// 手机桥 v2：签名指令（sha256(payload+KEY)）→ ntfy → 手机 Termux agent → 回执
// 用法：node phone.mjs <tool> [key=value ...]
import fs from 'node:fs';
import crypto from 'node:crypto';

const DIR = 'C:/Users/Liwq/phone-bridge';
const TOPIC = fs.readFileSync(`${DIR}/topic.txt`, 'utf8').trim();
const KEY = fs.readFileSync(`${DIR}/hmac.key`, 'utf8').trim();
const BASE = 'https://ntfy.sh';
const TIMEOUT_MS = 60000;

const [tool, ...pairs] = process.argv.slice(2);
if (!tool) {
  console.error('用法: node phone.mjs <tool> [key=value ...]');
  process.exit(2);
}
const args = {};
for (const p of pairs) {
  const i = p.indexOf('=');
  if (i < 0) continue;
  const k = p.slice(0, i);
  const v = p.slice(i + 1);
  args[k] = /^-?\d+(\.\d+)?$/.test(v) ? Number(v) : v;
}

const id = crypto.randomBytes(4).toString('hex');
if (tool === 'nav' && typeof args.q === 'string') args.q_enc = encodeURIComponent(args.q);
const inner = JSON.stringify({ id, tool, args, ts: Math.floor(Date.now() / 1000) });
const payload = Buffer.from(inner, 'utf8').toString('base64');
const sig = crypto.createHash('sha256').update(payload + KEY, 'utf8').digest('hex');

const ctrl = new AbortController();
const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);

const sub = await fetch(`${BASE}/${TOPIC}-res/json`, { signal: ctrl.signal });
const reader = sub.body.getReader();
const dec = new TextDecoder();
let buf = '';

await fetch(`${BASE}/${TOPIC}-cmd`, {
  method: 'POST',
  headers: { 'X-Title': 'dsh-cmd' },
  body: JSON.stringify({ p: payload, sig, id }),
});

const deadline = Date.now() + TIMEOUT_MS;
try {
  while (Date.now() < deadline) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i);
      buf = buf.slice(i + 1);
      if (!line.trim()) continue;
      let j;
      try { j = JSON.parse(line); } catch { continue; }
      if (j.event !== 'message' || !j.message) continue;
      if (j.message.startsWith(id + '|')) {
        console.log(j.message.slice(id.length + 1));
        process.exit(0);
      }
    }
  }
  console.log('TIMEOUT（手机没回执）');
  process.exit(1);
} finally {
  clearTimeout(timer);
  try { await reader.cancel(); } catch {}
}
