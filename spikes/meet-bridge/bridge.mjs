// Spike bridge: phone camera + mic -> http://127.0.0.1:8737/av for the Myna Chrome extension.
// Uses scrcpy's phone-side server over adb as a stand-in for the Myna Android app.
// Stream format on /av: repeated [channel u8 (0 video, 1 audio)][length u32 BE][scrcpy stream bytes].
import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import { execFileSync, spawn } from 'node:child_process';

const PORT = 8737, ADB_PORT = 27199;
const SERVER_JAR = process.env.SCRCPY_SERVER || '/opt/homebrew/share/scrcpy/scrcpy-server';
const SERVER_VERSION = process.env.SCRCPY_VERSION || '5.0.1';
const here = new URL('.', import.meta.url).pathname;
const CAMERA = process.env.MYNA_CAMERA || '1'; // 1 = front on the S24 FE
// Clockwise rotation applied on the phone: 0, 90, 180, 270, or flip0…flip270 to also mirror.
// shortcut: fixed per run; the Android app will follow the phone's rotation instead.
const ORIENTATION = process.env.MYNA_ORIENTATION || '0';

const adb = (...args) => execFileSync('adb', args, { encoding: 'utf8' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function startServer() {
  const scid = (Math.random() * 0x7fffffff >>> 0).toString(16).padStart(8, '0');
  adb('push', SERVER_JAR, '/data/local/tmp/myna-scrcpy.jar');
  adb('forward', `tcp:${ADB_PORT}`, `localabstract:scrcpy_${scid}`);
  const proc = spawn('adb', ['shell', `CLASSPATH=/data/local/tmp/myna-scrcpy.jar app_process / com.genymobile.scrcpy.Server ${SERVER_VERSION}`,
    `scid=${scid}`, 'log_level=info', 'tunnel_forward=true', 'control=false', 'send_device_meta=false',
    'video_source=camera', `camera_id=${CAMERA}`, `capture_orientation=${ORIENTATION}`, 'camera_size=1280x720', 'camera_fps=30', 'video_codec=h264',
    'video_bit_rate=4000000', 'audio_source=mic', 'audio_codec=raw']);
  proc.stdout.on('data', (d) => process.stdout.write(`[phone] ${d}`));
  proc.stderr.on('data', (d) => process.stdout.write(`[phone] ${d}`));
  return proc;
}

// The forwarded port accepts before the phone server listens, so retry until the dummy byte arrives.
async function connectFirst() {
  for (let i = 0; i < 50; i++) {
    const sock = await new Promise((res) => {
      const s = net.connect(ADB_PORT, '127.0.0.1');
      // Pause so nothing flows (and gets lost) before the forwarder attaches its listener.
      s.once('data', (b) => { s.pause(); if (b.length > 1) s.unshift(b.subarray(1)); res(s); });
      s.once('close', () => res(null));
      s.once('error', () => res(null));
    });
    if (sock) return sock;
    await sleep(100);
  }
  throw new Error('phone server did not start');
}

const connect = () => new Promise((res, rej) => {
  const s = net.connect(ADB_PORT, '127.0.0.1', () => res(s));
  s.once('error', rej);
});

function frame(channel, data) {
  const head = Buffer.alloc(5);
  head[0] = channel; head.writeUInt32BE(data.length, 1);
  return Buffer.concat([head, data]);
}

const files = { '/': 'test.html', '/myna.js': '../../chrome/myna.js' };

http.createServer(async (req, res) => {
  // Meet on https may call this loopback server; Chrome needs CORS and Private Network Access headers.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Private-Network', 'true');
  if (req.method === 'OPTIONS') return res.end();
  if (files[req.url]) {
    res.setHeader('Content-Type', req.url.endsWith('.js') ? 'text/javascript' : 'text/html');
    return res.end(fs.readFileSync(here + files[req.url]));
  }
  if (req.url !== '/av') { res.statusCode = 404; return res.end(); }

  console.log('client connected, starting phone camera');
  let proc, video, audio;
  try {
    proc = startServer();
    video = await connectFirst();
    audio = await connect();
  } catch (e) {
    console.error(e.message); proc?.kill(); res.statusCode = 503; return res.end(e.message);
  }
  res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Cache-Control': 'no-store' });
  video.on('data', (d) => res.write(frame(0, d))).resume();
  audio.on('data', (d) => res.write(frame(1, d)));
  const stop = () => { video.destroy(); audio.destroy(); proc.kill(); console.log('client gone, camera stopped'); };
  req.on('close', stop);
  video.on('close', () => res.end());
}).listen(PORT, '127.0.0.1', () => console.log(`Myna bridge on http://127.0.0.1:${PORT}`));
