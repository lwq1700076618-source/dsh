// 拉取手机当前界面的 UI 树（uiautomator，经 su 2000 降权），并可点按文字。
// 用法：
//   node phone-ui.mjs                 → 列出可点元素（文字 + 中心坐标）
//   node phone-ui.mjs --tap 首页      → 按文字精确/包含匹配后点击
//   node phone-ui.mjs --raw           → 输出原始 XML
import fs from 'node:fs';
import crypto from 'node:crypto';

const DIR = 'C:/Users/Liwq/phone-bridge';
const TOPIC = fs.readFileSync(`${DIR}/topic.txt`, 'utf8').trim();
const KEY = fs.readFileSync(`${DIR}/hmac.key`, 'utf8').trim();
const BASE = 'https://ntfy.sh';
const TIMEOUT_MS = 60000;

const argv = process.argv.slice(2);
const wantTap = argv.includes('--tap') ? argv[argv.indexOf('--tap') + 1] : '';
const wantRaw = argv.includes('--raw');

const id = crypto.randomBytes(4).toString('hex');
const inner = JSON.stringify({ id, tool: 'ui_dump', args: {}, ts: Math.floor(Date.now() / 1000) });
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
  body: JSON.stringify({ p: payload, sig }),
});

let xml = '';
let attachUrl = '';
const deadline = Date.now() + TIMEOUT_MS;
while (Date.now() < deadline) {
  const { value, done } = await reader.read();
  if (done) break;
  buf += dec.decode(value, { stream: true });
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i); buf = buf.slice(i + 1);
    if (!line.trim()) continue;
    let j; try { j = JSON.parse(line); } catch { continue; }
    if (j.event !== 'message') continue;
    if (j.attachment?.url && String(j.message || '').startsWith(id + '|')) { attachUrl = j.attachment.url; continue; }
    if (String(j.message || '').startsWith(id + '|')) {
      const text = j.message.slice(id.length + 1);
      if (!text.startsWith('shot') && !text.startsWith('ui')) {
        // 真正的结果消息
        if (attachUrl) {
          xml = await (await fetch(attachUrl)).text();
        }
        if (xml) break;
        console.log(text);
        if (!attachUrl) process.exit(0);
      }
    }
  }
  if (xml) break;
}
clearTimeout(timer);
try { await reader.cancel(); } catch {}

if (!xml) { console.log('没拿到 UI 树（手机没回 / 或 uiautomator 失败）'); process.exit(1); }
if (wantRaw) { console.log(xml); process.exit(0); }

const nodes = [...xml.matchAll(/<node\b[^>]*>/g)].map((m) => m[0]);
const items = [];
for (const n of nodes) {
  const text = (n.match(/text="([^"]*)"/) || [])[1] || '';
  const desc = (n.match(/content-desc="([^"]*)"/) || [])[1] || '';
  const cls = (n.match(/class="([^"]*)"/) || [])[1] || '';
  const bounds = (n.match(/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/) || []);
  if (!bounds.length) continue;
  const label = (text || desc).trim();
  if (!label) continue;
  const [x1, y1, x2, y2] = bounds.slice(1).map(Number);
  items.push({ label, cls: cls.split('.').pop(), x: Math.round((x1 + x2) / 2), y: Math.round((y1 + y2) / 2) });
}

if (wantTap) {
  const hit = items.find((it) => it.label === wantTap) || items.find((it) => it.label.includes(wantTap));
  if (!hit) { console.log('没找到「' + wantTap + '」，当前可点：'); console.log(items.slice(0, 40).map((i) => i.label).join(' / ')); process.exit(1); }
  const { execFileSync } = await import('node:child_process');
  execFileSync(process.execPath, [`${DIR}/phone.mjs`, 'tap', `x=${hit.x}`, `y=${hit.y}`], { stdio: 'inherit' });
  console.log(`已点击「${hit.label}」(${hit.x},${hit.y})`);
  process.exit(0);
}

console.log('可点元素：');
for (const it of items.slice(0, 60)) console.log(`- ${it.label}  [${it.cls}]  (${it.x},${it.y})`);
