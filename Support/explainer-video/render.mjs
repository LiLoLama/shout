// Rendert die Erklär-Animation Resources/Explainers/scratchpad.html deterministisch zu MP4.
//
//   node render.mjs --lang de                 → out/scratchpad-de.mp4 (1600 × 1000, 30 fps, mit Ton)
//   node render.mjs --lang en --fps 60        → mit 60 Bildern je Sekunde
//   node render.mjs --stills 1,7,15 --lang en → Einzelbilder als JPEG nach ./stills
//   --keys "⌃⌥S,⌃⌥E"                          → andere Tasten anzeigen (wie in der App)
//
// Braucht ffmpeg im PATH und ein Chromium: entweder CHROME=/pfad/zum/binary
// oder das von Playwright zwischengespeicherte unter ~/Library/Caches/ms-playwright.
import { chromium } from 'playwright-core';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const opt = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const lang = opt('--lang') === 'en' ? 'en' : 'de';
const fps = Number(opt('--fps') ?? 30);
const stills = opt('--stills');
const keys = opt('--keys');
const name = opt('--name') ?? 'scratchpad';
const html = resolve(here, '../../Resources/Explainers', `${name}.html`);

function findChrome() {
  if (process.env.CHROME) return process.env.CHROME;
  const cache = join(homedir(), 'Library/Caches/ms-playwright');
  if (!existsSync(cache)) return undefined;
  const dirs = readdirSync(cache).filter(d => /^chromium-\d+$/.test(d)).sort().reverse();
  for (const d of dirs) {
    for (const arch of ['chrome-mac-arm64', 'chrome-mac']) {
      const p = join(cache, d, arch, 'Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing');
      if (existsSync(p)) return p;
    }
  }
  return undefined;
}

const browser = await chromium.launch({ executablePath: findChrome(), args: ['--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1 });
let pageErrors = 0;
page.on('pageerror', e => { pageErrors++; console.error('Seitenfehler:', e.message); });
page.on('console', m => { if (m.type() === 'error') { pageErrors++; console.error('Konsole:', m.text()); } });
let url = pathToFileURL(html).href + `?export&lang=${lang}&muted=0`;
if (keys) url += `&keys=${encodeURIComponent(keys)}`;
await page.goto(url);
await page.waitForFunction(() => window.explainer && window.explainer.ready, null, { timeout: 30000 });
const duration = await page.evaluate(() => window.explainer.duration);

if (stills) {
  const dir = join(here, 'stills');
  mkdirSync(dir, { recursive: true });
  for (const s of stills.split(',').map(Number)) {
    const b64 = await page.evaluate(x => window.explainer.frame(x, 0.9), s);
    const file = join(dir, `${name}-${lang}-t${s.toFixed(2).padStart(5, '0')}.jpg`);
    writeFileSync(file, Buffer.from(b64, 'base64'));
    console.log(file);
  }
  await browser.close();
  process.exit(pageErrors ? 1 : 0);
}

const outDir = join(here, 'out');
mkdirSync(outDir, { recursive: true });
const out = join(outDir, `${name}-${lang}.mp4`);

console.log(`Ton wird gerendert (${duration.toFixed(1)} s) …`);
const wav = join(outDir, `${name}-${lang}.wav`);
writeFileSync(wav, Buffer.from(await page.evaluate(() => window.explainer.renderAudio()), 'base64'));

// Lautheit messen und mit fester Verstärkung auf etwa -20 LUFS bringen (höchstens
// +12 dB) — ruhiger als ein Launch-Film, die Klicks bleiben Klicks.
const meas = spawnSync('ffmpeg', ['-hide_banner', '-i', wav, '-af', 'ebur128', '-f', 'null', '-'], { encoding: 'utf8' }).stderr;
const lufs = Number((meas.match(/I:\s+(-?[\d.]+) LUFS\s*\n\s*Threshold/) || [])[1] ?? -20);
const gain = Math.max(-6, Math.min(12, -20 - lufs)).toFixed(2);
console.log(`Lautheit ${lufs} LUFS → ${gain} dB`);

const frames = Math.ceil(duration * fps);
console.log(`${frames} Bilder mit ${fps} fps …`);
const ff = spawn('ffmpeg', [
  '-y', '-loglevel', 'error',
  '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
  '-i', wav,
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p', '-profile:v', 'high',
  '-af', `volume=${gain}dB,alimiter=limit=0.89:attack=2:release=60:level=disabled`,
  '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart', out
], { stdio: ['pipe', 'inherit', 'inherit'] });
const done = new Promise((res, rej) => ff.on('close', c => c === 0 ? res() : rej(new Error('ffmpeg ' + c))));

const started = Date.now();
for (let f = 0; f < frames; f++) {
  const b64 = await page.evaluate(x => window.explainer.frame(x, 0.95), f / fps);
  if (!ff.stdin.write(Buffer.from(b64, 'base64'))) await new Promise(r => ff.stdin.once('drain', r));
  if (f % fps === 0) {
    const el = (Date.now() - started) / 1000;
    process.stdout.write(`\r${(f / fps).toFixed(0).padStart(3)} s / ${duration.toFixed(0)} s  ·  ${(f / Math.max(el, 0.01)).toFixed(1)} Bilder/s`);
  }
}
ff.stdin.end();
await done;
await browser.close();
rmSync(wav, { force: true });
console.log(`\nFertig: ${out}`);
if (pageErrors) { console.error(`${pageErrors} Fehler auf der Seite`); process.exit(1); }
