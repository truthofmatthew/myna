// Adds "Myna Camera" and "Myna Mic" to the page's device list and serves them from the phone stream.
// Runs in the page's own world so Meet sees the patched navigator.mediaDevices.
(() => {
  const AV_URL = 'http://127.0.0.1:8737/av';
  const CAM = 'myna-camera', MIC = 'myna-mic', GROUP = 'myna-phone';
  const labels = { [CAM]: 'Myna Camera (phone)', [MIC]: 'Myna Mic (phone)' };
  const md = navigator.mediaDevices;
  const realGetUserMedia = md.getUserMedia.bind(md);
  const realEnumerate = md.enumerateDevices.bind(md);
  const ours = new WeakMap(); // track -> deviceId

  let session = null; // one phone stream shared by every getUserMedia call

  function openSession() {
    const video = new MediaStreamTrackGenerator({ kind: 'video' });
    const audio = new MediaStreamTrackGenerator({ kind: 'audio' });
    const videoOut = video.writable.getWriter(), audioOut = audio.writable.getWriter();
    const s = { video, audio, ended: false, stats: { video: 0, audio: 0, decoded: 0, codec: '', error: '' } };
    window.mynaStats = s.stats; // read from the console when debugging

    let config = null;
    const decoder = new VideoDecoder({
      output: (f) => { s.stats.decoded++; videoOut.write(f).catch(() => f.close()); },
      error: (e) => { s.stats.error = e.message; console.warn('[myna] video decode', e); },
    });

    // Each channel carries scrcpy 5's stream: a 4-byte codec id, then 12-byte packet headers.
    // A header whose top bit is set is a session packet (width, height) with no payload;
    // otherwise it's [flags + pts u64][size u32] followed by the payload.
    const channels = [
      { buf: new Uint8Array(0), header: 4, onPacket: onVideo },
      { buf: new Uint8Array(0), header: 4, onPacket: onAudio },
    ];

    function onVideo(flags, pts, data) {
      s.stats.video++;
      if (flags & 2) { // config packet: SPS/PPS
        config = data;
        const sps = findNal(data, 7);
        const codec = s.stats.codec = 'avc1.' + [...sps.subarray(1, 4)].map((b) => b.toString(16).padStart(2, '0')).join('');
        decoder.configure({ codec, optimizeForLatency: true }); // no description = Annex B input
        return;
      }
      if (decoder.state !== 'configured') return;
      const key = !!(flags & 1);
      if (key && config) data = concat(config, data);
      decoder.decode(new EncodedVideoChunk({ type: key ? 'key' : 'delta', timestamp: pts, data }));
    }

    function onAudio(flags, pts, data) {
      s.stats.audio++;
      if (flags & 2) return;
      // raw = interleaved s16le, 48 kHz, stereo
      audioOut.write(new AudioData({ format: 's16', sampleRate: 48000, numberOfChannels: 2,
        numberOfFrames: data.byteLength / 4, timestamp: pts, data })).catch(() => {});
    }

    function feed(ch, bytes) {
      ch.buf = concat(ch.buf, bytes);
      if (ch.header) {
        if (ch.buf.length < ch.header) return;
        ch.buf = ch.buf.subarray(ch.header); ch.header = 0;
      }
      while (ch.buf.length >= 12) {
        const v = new DataView(ch.buf.buffer, ch.buf.byteOffset);
        const hi = v.getUint32(0), lo = v.getUint32(4);
        if (hi >>> 31) { ch.buf = ch.buf.subarray(12); continue; } // session packet
        const size = v.getUint32(8);
        if (ch.buf.length < 12 + size) return;
        const flags = ((hi >>> 30) & 1) << 1 | ((hi >>> 29) & 1); // bit 62 = config, bit 61 = key frame
        const pts = (hi & 0x1fffffff) * 2 ** 32 + lo;
        ch.onPacket(flags, pts, ch.buf.slice(12, 12 + size));
        ch.buf = ch.buf.subarray(12 + size);
      }
    }

    (async () => {
      try {
        const res = await fetch(AV_URL, { cache: 'no-store' });
        if (!res.ok) throw new Error(`bridge answered ${res.status}`);
        const reader = res.body.getReader();
        let pending = new Uint8Array(0);
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          pending = concat(pending, value);
          while (pending.length >= 5) {
            const len = new DataView(pending.buffer, pending.byteOffset).getUint32(1);
            if (pending.length < 5 + len) break;
            feed(channels[pending[0]], pending.subarray(5, 5 + len));
            pending = pending.subarray(5 + len);
          }
        }
      } catch (e) {
        console.warn('[myna] phone stream stopped:', e.message);
      }
      s.ended = true; video.stop(); audio.stop();
      if (session === s) session = null;
    })();
    return s;
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

  // Meet passes deviceId as a string, an array, or {exact|ideal: ...}.
  function wants(c, id) {
    if (!c || typeof c !== 'object') return false;
    const d = c.deviceId; if (!d) return false;
    const v = typeof d === 'object' && !Array.isArray(d) ? (d.exact ?? d.ideal) : d;
    return Array.isArray(v) ? v.includes(id) : v === id;
  }

  function track(kind, id) {
    if (!session || session.ended) session = openSession();
    const t = session[kind].clone();
    ours.set(t, id);
    return t;
  }

  md.getUserMedia = async (constraints = {}) => {
    const cam = wants(constraints.video, CAM), mic = wants(constraints.audio, MIC);
    if (!cam && !mic) return realGetUserMedia(constraints);
    const rest = { video: cam ? false : constraints.video || false, audio: mic ? false : constraints.audio || false };
    const real = rest.video || rest.audio ? await realGetUserMedia(rest) : new MediaStream();
    if (cam) real.addTrack(track('video', CAM));
    if (mic) real.addTrack(track('audio', MIC));
    return real;
  };

  function fakeDevice(deviceId, kind) {
    const label = labels[deviceId];
    return Object.create(MediaDeviceInfo.prototype, {
      deviceId: { value: deviceId, enumerable: true }, kind: { value: kind, enumerable: true },
      label: { value: label, enumerable: true }, groupId: { value: GROUP, enumerable: true },
      toJSON: { value: () => ({ deviceId, kind, label, groupId: GROUP }) },
    });
  }

  md.enumerateDevices = async () => [...await realEnumerate(), fakeDevice(CAM, 'videoinput'), fakeDevice(MIC, 'audioinput')];

  // Meet matches tracks to devices by label and settings.deviceId.
  const proto = MediaStreamTrack.prototype;
  const realSettings = proto.getSettings, realLabel = Object.getOwnPropertyDescriptor(proto, 'label').get;
  proto.getSettings = function () {
    const id = ours.get(this), s = realSettings.call(this);
    return id ? { ...s, deviceId: id, groupId: GROUP, ...(id === CAM ? { width: 1280, height: 720, frameRate: 30 } : { sampleRate: 48000, channelCount: 2 }) } : s;
  };
  Object.defineProperty(proto, 'label', { get() { return labels[ours.get(this)] ?? realLabel.call(this); } });
})();
