// Isolated-world helper: hands stream requests from myna.js (page world) to the hidden relay frame.
let relay;

function relayFrame() {
  relay ??= new Promise((resolve) => {
    const frame = document.createElement('iframe');
    frame.src = chrome.runtime.getURL('relay.html');
    frame.hidden = true;
    frame.setAttribute('aria-hidden', 'true');
    frame.onload = () => resolve(frame);
    document.documentElement.appendChild(frame);
  });
  return relay;
}

addEventListener('message', async (event) => {
  if (event.source !== window || event.data?.myna !== 'open' || !event.ports[0]) return;
  const frame = await relayFrame();
  frame.contentWindow.postMessage({ path: event.data.path }, new URL(frame.src).origin, [event.ports[0]]);
});
