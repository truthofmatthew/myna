// Runs in a hidden extension frame inside Meet. Fetches a Myna stream from the Mac app with the
// extension's own permission (no local network prompt for meet.google.com) and passes the bytes on.
const BRIDGE = 'http://127.0.0.1:8737';
const ALLOWED = /^\/(video\?camera=(front|back)|audio)$/;

addEventListener('message', async (event) => {
  const port = event.ports[0];
  if (!port || event.origin !== 'https://meet.google.com' || !ALLOWED.test(event.data?.path)) return;
  const abort = new AbortController();
  port.onmessage = (m) => { if (m.data?.stop) abort.abort(); };
  try {
    const res = await fetch(BRIDGE + event.data.path, { cache: 'no-store', signal: abort.signal });
    if (!res.ok) throw new Error(`Myna on the Mac answered ${res.status}`);
    const reader = res.body.getReader();
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      const own = value.byteOffset === 0 && value.byteLength === value.buffer.byteLength ? value : value.slice();
      port.postMessage({ chunk: own.buffer }, [own.buffer]);
    }
    port.postMessage({ end: true });
  } catch (e) {
    if (e.name !== 'AbortError') port.postMessage({ end: true, error: e.message === 'Failed to fetch' ? 'Myna isn\'t running on this Mac' : e.message });
  }
});
