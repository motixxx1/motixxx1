import { randomUUID } from 'node:crypto';
import { createWriteStream, createReadStream, mkdirSync, statSync } from 'node:fs';
import { unlink } from 'node:fs/promises';
import { once } from 'node:events';
import { join } from 'node:path';
import { MarketplaceError } from './marketplace.js';

const fail = (code, msg) => { throw new MarketplaceError(code, msg); };
// Only formats phones produce. No SVG/HTML: they could run scripts when opened.
const TYPES = {
  'image/jpeg': ['image', 'jpg'], 'image/png': ['image', 'png'], 'image/webp': ['image', 'webp'], 'image/gif': ['image', 'gif'],
  'image/heic': ['image', 'heic'], 'video/mp4': ['video', 'mp4'], 'video/webm': ['video', 'webm'], 'video/quicktime': ['video', 'mov'],
};
export const MAX_IMAGES = 8;
export const MAX_VIDEOS = 1;

// Photos and videos attached to requests, stored as files next to the data.
// Files get an unguessable id and are served by id (like a share link).
export class Media {
  constructor(dir, { maxImageBytes = 15 * 1048576, maxVideoBytes = 100 * 1048576 } = {}) {
    Object.assign(this, { dir, maxImageBytes, maxVideoBytes });
    this.files = new Map();
    mkdirSync(dir, { recursive: true });
  }
  snapshot() { return [...this.files.values()]; }
  restore(list = []) { this.files = new Map(list.map((f) => [f.id, f])); }
  #path(f) { return join(this.dir, `${f.id}.${f.ext}`); }

  async save(req, owner) {
    const type = String(req.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
    const [kind, ext] = TYPES[type] ?? fail('bad_type', 'סוג הקובץ לא נתמך (תמונה או סרטון בלבד)');
    const max = kind === 'image' ? this.maxImageBytes : this.maxVideoBytes;
    const declared = Number(req.headers['content-length']);
    if (declared > max) fail('too_large', `הקובץ גדול מדי (עד ${Math.round(max / 1048576)}MB)`);
    const f = { id: randomUUID(), owner, kind, ext, type, size: 0, at: Date.now() };
    const path = this.#path(f);
    const out = createWriteStream(path);
    try {
      for await (const chunk of req) {
        f.size += chunk.length;
        if (f.size > max) fail('too_large', `הקובץ גדול מדי (עד ${Math.round(max / 1048576)}MB)`);
        if (!out.write(chunk)) await once(out, 'drain');
      }
      if (!f.size) fail('empty', 'קובץ ריק');
      out.end(); await once(out, 'finish');
    } catch (e) { out.destroy(); await unlink(path).catch(() => {}); throw e; }
    this.files.set(f.id, f);
    return { id: f.id, kind, url: `/media/${f.id}` };
  }

  // Deletes every file a user uploaded (account deletion).
  async removeOwner(owner) {
    for (const f of [...this.files.values()].filter((x) => x.owner === owner)) {
      this.files.delete(f.id);
      await unlink(this.#path(f)).catch(() => {});
    }
  }

  // Turns ids sent by a client into media entries, only if the client uploaded them.
  attach(ids = [], owner) {
    if (!Array.isArray(ids)) fail('bad_media', 'media must be a list');
    const out = ids.map((id) => {
      const f = this.files.get(id);
      if (!f || f.owner !== owner) fail('bad_media', 'קובץ לא נמצא – העלה אותו שוב');
      return { id: f.id, kind: f.kind, url: `/media/${f.id}` };
    });
    if (out.filter((m) => m.kind === 'image').length > MAX_IMAGES) fail('too_many', `עד ${MAX_IMAGES} תמונות`);
    if (out.filter((m) => m.kind === 'video').length > MAX_VIDEOS) fail('too_many', 'סרטון אחד לקריאה');
    return out;
  }

  // GET /media/:id with Range support (phones and Safari need it to play video).
  serve(req, res, id) {
    const f = this.files.get(id);
    if (!f) { res.writeHead(404); return res.end(); }
    const path = this.#path(f);
    let size; try { size = statSync(path).size; } catch { res.writeHead(404); return res.end(); }
    const headers = { 'content-type': f.type, 'accept-ranges': 'bytes', 'cache-control': 'private, max-age=86400',
      'x-content-type-options': 'nosniff', 'content-disposition': 'inline' };
    const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range ?? '');
    if (m && (m[1] || m[2])) {
      let start = m[1] ? Number(m[1]) : size - Number(m[2]);
      let end = m[1] && m[2] ? Number(m[2]) : size - 1;
      end = Math.min(end, size - 1); start = Math.max(start, 0);
      if (start > end) { res.writeHead(416, { 'content-range': `bytes */${size}` }); return res.end(); }
      res.writeHead(206, { ...headers, 'content-range': `bytes ${start}-${end}/${size}`, 'content-length': end - start + 1 });
      return createReadStream(path, { start, end }).pipe(res);
    }
    res.writeHead(200, { ...headers, 'content-length': size });
    createReadStream(path).pipe(res);
  }
}
