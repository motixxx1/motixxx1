import { existsSync, mkdirSync, readFileSync, renameSync, readdirSync, unlinkSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

// SQLite database (built into Node, nothing to install). One table per collection
// (market_jobs, market_pros, ...), one row per record: id, the record as JSON, and when it
// last changed. Writes go in a single transaction a moment after each change, and only
// the records that actually changed are written. Views (jobs, pros, clients, payments)
// make the data easy to read with any SQLite tool.
//
// On first start, data from the older JSON file (state.json) is imported automatically.
export function createDbStore(file, parts, { delayMs = 200, legacyJson = null, backups = true } = {}) {
  mkdirSync(dirname(file), { recursive: true });
  let timer = null;
  const db = new DatabaseSync(file);
  db.exec('PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA busy_timeout = 5000;');
  db.exec('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)');

  const safe = (s) => s.replace(/[^a-z0-9_]/gi, '_').toLowerCase();
  const tables = new Set();
  const ensure = (t) => {
    if (tables.has(t)) return;
    db.exec(`CREATE TABLE IF NOT EXISTS "${t}" (id TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at INTEGER NOT NULL)`);
    tables.add(t);
  };
  for (const r of db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT IN ('meta')").all()) tables.add(r.name);

  // A part's snapshot is either a list of records or an object of lists. Lists whose items
  // all have an id get a row per item; anything else is kept as one row.
  const collections = (name, snap) => {
    const out = [];
    const add = (table, value) => {
      if (Array.isArray(value) && value.every((x) => x && typeof x.id === 'string')) out.push({ table, rows: value, list: true });
      else out.push({ table, rows: [{ id: '*', value }], list: false });
    };
    if (Array.isArray(snap)) add(safe(name), snap);
    else for (const [k, v] of Object.entries(snap ?? {})) add(safe(`${name}_${k}`), v);
    return out;
  };

  // ---- load
  const load = () => {
    for (const [name, part] of Object.entries(parts)) {
      const shape = part.snapshot();
      const read = (table, list) => {
        if (!tables.has(table)) return undefined;
        const rows = db.prepare(`SELECT id, data FROM "${table}" ORDER BY rowid`).all();
        if (!rows.length) return undefined;
        if (list) return rows.map((r) => JSON.parse(r.data));
        return JSON.parse(rows[0].data);
      };
      let data;
      if (Array.isArray(shape)) data = read(safe(name), true);
      else {
        data = {};
        let any = false;
        for (const k of Object.keys(shape ?? {})) {
          const table = safe(`${name}_${k}`);
          // lists of records were stored per row; other values as a single '*' row
          const hasStar = tables.has(table) && db.prepare(`SELECT 1 FROM "${table}" WHERE id = '*'`).get();
          const v = read(table, !hasStar);
          if (v !== undefined) { data[k] = v; any = true; }
        }
        if (!any) data = undefined;
      }
      if (data !== undefined) part.restore(data);
    }
  };

  const empty = () => ![...tables].some((t) => db.prepare(`SELECT 1 FROM "${t}" LIMIT 1`).get());

  // ---- save (only what changed)
  const known = new Map(); // `${table}\u0000${id}` -> json
  const flush = () => {
    timer = null;
    const now = Date.now();
    const seen = new Set();
    db.exec('BEGIN');
    try {
      for (const [name, part] of Object.entries(parts)) {
        for (const { table, rows, list } of collections(name, part.snapshot())) {
          ensure(table);
          const up = db.prepare(`INSERT INTO "${table}" (id, data, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`);
          for (const r of rows) {
            const id = r.id;
            const json = JSON.stringify(list ? r : r.value);
            const key = `${table}\u0000${id}`;
            seen.add(key);
            if (known.get(key) === json) continue;
            up.run(id, json, now);
            known.set(key, json);
          }
        }
      }
      // records that disappeared (e.g. deleted media)
      for (const key of [...known.keys()]) {
        if (seen.has(key)) continue;
        const [table, id] = key.split('\u0000');
        db.prepare(`DELETE FROM "${table}" WHERE id = ?`).run(id);
        known.delete(key);
      }
      db.exec('COMMIT');
    } catch (e) {
      db.exec('ROLLBACK');
      console.error('[db] save failed', e);
    }
  };

  // ---- start: load, or import the old JSON file once
  if (!empty()) {
    load();
    console.log(`[db] loaded ${file}`);
  } else if (legacyJson && existsSync(legacyJson)) {
    const data = JSON.parse(readFileSync(legacyJson, 'utf8'));
    for (const [name, part] of Object.entries(parts)) if (data[name]) part.restore(data[name]);
    flush();
    renameSync(legacyJson, `${legacyJson}.imported`);
    console.log(`[db] imported ${legacyJson} into ${file}`);
  } else {
    console.log(`[db] new database ${file}`);
  }
  // fill the change cache with what is stored now, so the first save writes nothing new
  for (const [name, part] of Object.entries(parts)) {
    for (const { table, rows, list } of collections(name, part.snapshot())) {
      for (const r of rows) known.set(`${table}\u0000${r.id}`, JSON.stringify(list ? r : r.value));
    }
  }

  // Views for reading the data with any SQLite tool (DB Browser for SQLite, sqlite3, ...)
  const view = (name, table, cols) => {
    if (!tables.has(table)) ensure(table);
    db.exec(`DROP VIEW IF EXISTS ${name}`);
    db.exec(`CREATE VIEW ${name} AS SELECT id, ${cols.map(([c, p]) => `json_extract(data, '$.${p}') AS ${c}`).join(', ')}, updated_at FROM "${table}"`);
  };
  try {
    view('jobs', 'market_jobs', [['status', 'status'], ['category', 'categoryId'], ['mode', 'mode'], ['client_id', 'clientId'],
      ['pro_id', 'assignedProId'], ['client_price', 'clientPrice'], ['urgency', 'urgency'], ['address', 'address'], ['description', 'description'], ['created_at', 'createdAt']]);
    view('pros', 'market_pros', [['name', 'name'], ['phone', 'phone'], ['available', 'available'], ['balance', 'balance'],
      ['radius_km', 'radiusKm'], ['completed_jobs', 'completedJobs'], ['created_at', 'createdAt']]);
    view('clients', 'market_clients', [['name', 'name'], ['phone', 'phone']]);
    view('payments', 'market_ledger', [['pro_id', 'proId'], ['type', 'type'], ['amount', 'amount'], ['at', 'at']]);
  } catch (e) {
    console.warn('[db] views', e.message);
  }

  // Daily copy of the database, last 7 kept (data/backups/zariz-YYYY-MM-DD.db).
  const backup = () => {
    try {
      const dir = join(dirname(file), 'backups');
      mkdirSync(dir, { recursive: true });
      const day = new Date().toISOString().slice(0, 10);
      const out = join(dir, `zariz-${day}.db`);
      if (!existsSync(out)) {
        flush();
        db.exec(`VACUUM INTO '${out.replace(/'/g, "''")}'`);
        console.log(`[db] backup ${out}`);
      }
      const old = readdirSync(dir).filter((f) => /^zariz-\d{4}-\d\d-\d\d\.db$/.test(f)).sort().slice(0, -7);
      for (const f of old) unlinkSync(join(dir, f));
    } catch (e) {
      console.warn('[db] backup failed', e.message);
    }
  };
  let backupTimer = null;
  if (backups) {
    setTimeout(backup, 60_000).unref();
    backupTimer = setInterval(backup, 6 * 3600_000);
    backupTimer.unref();
  }

  return {
    db,
    save() { if (!timer) timer = setTimeout(flush, delayMs); },
    flush() { clearTimeout(timer); flush(); return Promise.resolve(); },
    close() { clearTimeout(timer); clearInterval(backupTimer); flush(); db.close(); },
  };
}
