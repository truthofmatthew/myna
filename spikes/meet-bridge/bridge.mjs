// Spike bridge: phone camera + mic over HTTP for the Myna Chrome extension.
// Uses scrcpy's phone-side server over adb as a stand-in for the Myna Android app.
//   GET /video?camera=front|back  -> scrcpy video stream (H.264)
//   GET /audio                    -> scrcpy audio stream (raw 48 kHz stereo PCM)
// Wireless: connect adb over Wi-Fi and start with ANDROID_SERIAL=<phone-ip>:5555.
import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import { execFileSync, spawn } from 'node:child_process';

const PORT = 8737;
const SERVER_JAR = process.env.SCRCPY_SERVER || '/opt/homebrew/share/scrcpy/scrcpy-server';
const SERVER_VERSION = process.env.SCRCPY_VERSION || '5.0.1';
const here = new URL('.', import.meta.url).pathname;
const CAMERAS = { front: '1', back: '0' }; // S24 FE camera ids
// Clockwise rotation applied on the phone: 0, 90, 180, 270, or flip0…flip270 to also mirror.
// 180 = landscape with the top on the right, for both cameras.
// shortcut: fixed per run; the Android app will follow the phone's rotation instead.
const ORIENTATION = process.env.MYNA_ORIENTATION || '180';

const adb = (...args) => execFileSync('adb', args, { encoding: 'utf8' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let nextPort = 27200;

function startServer(args) {
  const scid = (Math.random() * 0x7fffffff >>> 0).toString(16).padStart(8, '0');
  const port = nextPort++;
  adb('push', SERVER_JAR, '/data/local/tmp/myna-scrcpy.jar');
  adb('forward', `tcp:${port}`, `localabstract:scrcpy_${scid}`);
  const proc = spawn('adb', ['shell', `CLASSPATH=/data/local/tmp/myna-scrcpy.jar app_process / com.genymobile.scrcpy.Server ${SERVER_VERSION}`,
    `scid=${scid}`, 'log_level=info', 'tunnel_forward=true', 'control=false', 'send_device_meta=false', ...args]);
  proc.stdout.on('data', (d) => process.stdout.write(`[phone] ${d}`));
  proc.stderr.on('data', (d) => process.stdout.write(`[phone] ${d}`));
  const stop = () => { proc.kill(); try { adb('forward', '--remove', `tcp:${port}`); } catch {} };
  return { port, stop };
}

// The forwarded port accepts before the phone server listens, so retry until the dummy byte arrives.
async function connect(port) {
  for (let i = 0; i < 50; i++) {
    const sock = await new Promise((res) => {
      const s = net.connect(port, '127.0.0.1');
      // Pause so nothing flows (and gets lost) before the response attaches its listener.
      s.once('data', (b) => { s.pause(); if (b.length > 1) s.unshift(b.subarray(1)); res(s); });
      s.once('close', () => res(null));
      s.once('error', () => res(null));
    });
    if (sock) return sock;
    await sleep(100);
  }
  throw new Error('phone server did not start');
}

const files = { '/': 'test.html', '/myna.js': '../../chrome/myna.js' };

http.createServer(async (req, res) => {
  // Meet on https may call this loopback server; Chrome needs CORS and Private Network Access headers.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Private-Network', 'true');
  if (req.method === 'OPTIONS') return res.end();
  const url = new URL(req.url, 'http://x');
  if (files[url.pathname]) {
    res.setHeader('Content-Type', url.pathname.endsWith('.js') ? 'text/javascript' : 'text/html');
    return res.end(fs.readFileSync(here + files[url.pathname]));
  }

  let args;
  if (url.pathname === '/video') {
    const camera = CAMERAS[url.searchParams.get('camera') || 'front'];
    if (!camera) { res.statusCode = 400; return res.end('camera must be front or back'); }
    args = ['audio=false', 'video_source=camera', `camera_id=${camera}`, `capture_orientation=${ORIENTATION}`,
      'camera_size=1280x720', 'camera_fps=30', 'video_codec=h264', 'video_bit_rate=4000000'];
  } else if (url.pathname === '/audio') {
    args = ['video=false', 'audio_source=mic', 'audio_codec=raw'];
  } else { res.statusCode = 404; return res.end(); }

  console.log(`${req.url}: starting`);
  let server, sock;
  try {
    server = startServer(args);
    sock = await connect(server.port);
  } catch (e) {
    console.error(e.message); server?.stop(); res.statusCode = 503; return res.end(e.message);
  }
  res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Cache-Control': 'no-store' });
  sock.pipe(res);
  req.on('close', () => { sock.destroy(); server.stop(); console.log(`${req.url}: stopped`); });
}).listen(PORT, '127.0.0.1', () => console.log(`Myna bridge on http://127.0.0.1:${PORT} (rotation ${ORIENTATION})`));
