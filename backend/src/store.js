import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { writeFile, rename } from 'node:fs/promises';
import { dirname } from 'node:path';

// Saves the in-memory state to a JSON file after every change (debounced, atomic
// rename) and loads it on start, so a single server survives restarts.
// Good for a first deployment; move to Postgres before real scale.
export function createFileStore(file, parts, { delayMs = 300 } = {}) {
  if (existsSync(file)) {
    const data = JSON.parse(readFileSync(file, 'utf8'));
    for (const [name, part] of Object.entries(parts)) if (data[name]) part.restore(data[name]);
    console.log(`[store] loaded ${file}`);
  } else {
    mkdirSync(dirname(file), { recursive: true });
  }
  let timer = null;
  let writing = Promise.resolve();
  const flush = () => {
    timer = null;
    const data = JSON.stringify(Object.fromEntries(Object.entries(parts).map(([n, p]) => [n, p.snapshot()])));
    writing = writing.then(async () => {
      await writeFile(file + '.tmp', data);
      await rename(file + '.tmp', file);
    }).catch((e) => console.error('[store] save failed', e));
    return writing;
  };
  return {
    save() { if (!timer) timer = setTimeout(flush, delayMs); },
    flush() { clearTimeout(timer); return flush(); },
  };
}
