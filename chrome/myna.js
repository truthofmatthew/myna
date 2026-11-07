// Adds the phone's cameras and mic to the page's device list and serves them from the Myna bridge.
// Runs in the page's own world so Meet sees the patched navigator.mediaDevices.
(() => {
  const GROUP = 'myna-phone';
  const DEVICES = {
    'myna-camera-front': { kind: 'videoinput', label: 'Myna Front Camera (phone)', path: '/video?camera=front' },
    'myna-camera-back': { kind: 'videoinput', label: 'Myna Back Camera (phone)', path: '/video?camera=back' },
    'myna-mic': { kind: 'audioinput', label: 'Myna Mic (phone)', path: '/audio' },
  };
  const md = navigator.mediaDevices;
  const realGetUserMedia = md.getUserMedia.bind(md);
  const realEnumerate = md.enumerateDevices.bind(md);
  const ours = new WeakMap(); // track -> deviceId
  const streams = {}; // deviceId -> open phone stream, shared by every track handed out for it
  window.mynaStats = {}; // read from the console when debugging

  // One phone stream: scrcpy 5 framing (4-byte codec id, then 12-byte packet headers) into a track generator.
  function openStream(id) {
    const device = DEVICES[id], isVideo = device.kind === 'videoinput';
    const gen = new MediaStreamTrackGenerator({ kind: isVideo ? 'video' : 'audio' });
    const out = gen.writable.getWriter();
    const abort = new AbortController();
    const stats = window.mynaStats[id] = { packets: 0, decoded: 0, codec: '', error: '' };
    const s = { gen, users: 0, ended: false, close: () => abort.abort() };

    let onPacket, rotation = 0, codec = '';
    if (isVideo) {
      let config = null;
      const decoder = new VideoDecoder({
        output: (f) => {
          stats.decoded++;
          const frame = turn(f, rotation);
          out.write(frame).catch(() => frame.close());
        },
        error: (e) => { stats.error = e.message; console.warn('[myna] video decode', e); },
      });
      onPacket = (isConfig, isKey, pts, data) => {
        if (isConfig) { // SPS/PPS
          config = data;
          const sps = findNal(data, 7);
          stats.codec = 'avc1.' + [...sps.subarray(1, 4)].map((b) => b.toString(16).padStart(2, '0')).join('');
          decoder.configure({ codec: stats.codec, optimizeForLatency: true }); // no description = Annex B input
          return;
        }
        if (decoder.state !== 'configured') return;
        if (isKey && config) data = concat(config, data);
        decoder.decode(new EncodedVideoChunk({ type: isKey ? 'key' : 'delta', timestamp: pts, data }));
      };
    } else {
      let decoder;
      onPacket = (isConfig, isKey, pts, data) => {
        if (isConfig) return;
        if (codec === 'opus') { // Myna app: 20 ms Opus packets, 48 kHz mono
          decoder ??= new AudioDecoder({
            output: (a) => { stats.decoded++; out.write(a).catch(() => a.close()); },
            error: (e) => { stats.error = e.message; console.warn('[myna] audio decode', e); },
          });
          if (decoder.state === 'unconfigured') decoder.configure({ codec: 'opus', sampleRate: 48000, numberOfChannels: 1 });
          decoder.decode(new EncodedAudioChunk({ type: 'key', timestamp: pts, data }));
          return;
        }
        // Interleaved s16le, 48 kHz: mono for 'pcm1', stereo from scrcpy ('raw').
        const channels = codec === 'pcm1' ? 1 : 2;
        out.write(new AudioData({ format: 's16', sampleRate: 48000, numberOfChannels: channels,
          numberOfFrames: data.byteLength / (2 * channels), timestamp: pts, data })).catch(() => {});
      };
    }

    (async () => {
      try {
        const reader = openBridge(device.path, abort.signal);
        let buf = new Uint8Array(0), header = 4;
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          buf = concat(buf, value);
          if (header) {
            if (buf.length < header) continue;
            codec = String.fromCharCode(...buf.subarray(0, 4));
            stats.codec ||= codec;
            buf = buf.subarray(header); header = 0;
          }
          while (buf.length >= 12) {
            const v = new DataView(buf.buffer, buf.byteOffset);
            const hi = v.getUint32(0), lo = v.getUint32(4);
            // Session packet, no payload: rotation in the low bits (Myna app), then width and height.
            if (hi >>> 31) { rotation = hi & 0x1ff; buf = buf.subarray(12); continue; }
            const size = v.getUint32(8);
            if (buf.length < 12 + size) break;
            stats.packets++;
            // bit 62 = config, bit 61 = key frame, pts in the low 61 bits
            onPacket(!!(hi & 0x40000000), !!(hi & 0x20000000), (hi & 0x1fffffff) * 2 ** 32 + lo, buf.slice(12, 12 + size));
            buf = buf.subarray(12 + size);
          }
        }
      } catch (e) {
        if (e.name !== 'AbortError') console.warn('[myna] phone stream stopped:', e.message);
      }
      s.ended = true; gen.stop();
      if (streams[id] === s) delete streams[id];
    })();
    return s;
  }

  // The bytes come through the extension's relay frame (host.js, relay.js), which fetches with the
  // extension's own permission; the Mac app turns web pages away.
  function openBridge(path, signal) {
    const { port1, port2 } = new MessageChannel();
    const queue = [];
    let ended = false, failure = null, wake = null;
    port1.onmessage = ({ data }) => {
      if (data.chunk) queue.push(new Uint8Array(data.chunk));
      if (data.end) { ended = true; failure = data.error ? new Error(data.error) : null; }
      wake?.();
    };
    signal.addEventListener('abort', () => { port1.postMessage({ stop: true }); port1.close(); ended = true; wake?.(); });
    window.postMessage({ myna: 'open', path }, location.origin, [port2]);
    return {
      async read() {
        while (!queue.length && !ended) await new Promise((r) => (wake = r));
        if (queue.length) return { value: queue.shift(), done: false };
        if (failure) throw failure;
        return { done: true };
      },
    };
  }

  // The phone sends frames as the sensor sees them; turn them upright here.
  let canvas, draw;
  function turn(frame, degrees) {
    if (!degrees) return frame;
    const w = frame.displayWidth, h = frame.displayHeight, sideways = degrees % 180 !== 0;
    canvas ??= new OffscreenCanvas(1, 1);
    const cw = sideways ? h : w, ch = sideways ? w : h;
    if (canvas.width !== cw || canvas.height !== ch) { canvas.width = cw; canvas.height = ch; }
    draw ??= canvas.getContext('2d');
    draw.setTransform(1, 0, 0, 1, cw / 2, ch / 2);
    draw.rotate(degrees * Math.PI / 180);
    draw.drawImage(frame, -w / 2, -h / 2);
    const turned = new VideoFrame(canvas, { timestamp: frame.timestamp });
    frame.close();
    return turned;
  }

  function findNal(annexB, type) {
    for (let i = 0; i + 3 < annexB.length; i++) {
      if (annexB[i] === 0 && annexB[i + 1] === 0 && annexB[i + 2] === 1 && (annexB[i + 3] & 0x1f) === type) return annexB.subarray(i + 3);
    }
    throw new Error('no SPS in config packet');
  }

  function concat(a, b) {
    if (!a.length) return b;
    const out = new Uint8Array(a.length + b.length); out.set(a); out.set(b, a.length); return out;
  }

  // Meet passes deviceId as a string, an array, or {exact|ideal: ...}. Returns our id if it asked for one.
  function requested(c) {
    if (!c || typeof c !== 'object' || !c.deviceId) return null;
    const d = c.deviceId;
    const v = typeof d === 'object' && !Array.isArray(d) ? (d.exact ?? d.ideal) : d;
    return [v].flat().find((x) => x in DEVICES) ?? null;
  }

  // Hand out a clone; the phone stream closes when the last clone is stopped, which frees the camera.
  function track(id) {
    let s = streams[id];
    if (!s || s.ended) s = streams[id] = openStream(id);
    const t = s.gen.clone();
    ours.set(t, id);
    s.users++;
    const stop = t.stop.bind(t);
    let stopped = false;
    t.stop = () => {
      stop();
      if (stopped) return;
      stopped = true;
      if (--s.users === 0) s.close();
    };
    return t;
  }

  md.getUserMedia = async (constraints = {}) => {
    const cam = requested(constraints.video), mic = requested(constraints.audio);
    if (!cam && !mic) return realGetUserMedia(constraints);
    const rest = { video: cam ? false : constraints.video || false, audio: mic ? false : constraints.audio || false };
    const stream = rest.video || rest.audio ? await realGetUserMedia(rest) : new MediaStream();
    if (cam) stream.addTrack(track(cam));
    if (mic) stream.addTrack(track(mic));
    return stream;
  };

  function fakeDevice(deviceId) {
    const { kind, label } = DEVICES[deviceId];
    return Object.create(MediaDeviceInfo.prototype, {
      deviceId: { value: deviceId, enumerable: true }, kind: { value: kind, enumerable: true },
      label: { value: label, enumerable: true }, groupId: { value: GROUP, enumerable: true },
      toJSON: { value: () => ({ deviceId, kind, label, groupId: GROUP }) },
    });
  }

  md.enumerateDevices = async () => [...await realEnumerate(), ...Object.keys(DEVICES).map(fakeDevice)];

  // Meet matches tracks to devices by label and settings.deviceId.
  const proto = MediaStreamTrack.prototype;
  const realSettings = proto.getSettings, realLabel = Object.getOwnPropertyDescriptor(proto, 'label').get;
  proto.getSettings = function () {
    const id = ours.get(this), s = realSettings.call(this);
    if (!id) return s;
    const extra = DEVICES[id].kind === 'videoinput' ? { width: 1280, height: 720, frameRate: 30 } : { sampleRate: 48000, channelCount: 1 };
    return { ...s, deviceId: id, groupId: GROUP, ...extra };
  };
  Object.defineProperty(proto, 'label', { get() { return DEVICES[ours.get(this)]?.label ?? realLabel.call(this); } });
})();
