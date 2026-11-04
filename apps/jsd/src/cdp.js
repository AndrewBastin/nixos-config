// Minimal Chrome DevTools Protocol client over Node's global WebSocket.
'use strict';

function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const pending = new Map();
    const listeners = new Map();
    const closers = [];
    let id = 0;
    ws.onmessage = ({ data }) => {
      const msg = JSON.parse(data);
      if (msg.id !== undefined) {
        const p = pending.get(msg.id);
        pending.delete(msg.id);
        if (p) msg.error ? p.reject(new Error(msg.error.message)) : p.resolve(msg.result);
      } else {
        for (const fn of listeners.get(msg.method) ?? []) fn(msg.params);
      }
    };
    ws.onclose = () => {
      for (const p of pending.values()) p.reject(new Error('cdp: socket closed'));
      pending.clear();
      closers.forEach((fn) => fn());
    };
    ws.onerror = (e) => reject(e.error ?? new Error(`cdp: can't connect to ${url}`));
    ws.onopen = () => resolve({
      send(method, params) {
        return new Promise((res, rej) => {
          pending.set(++id, { resolve: res, reject: rej });
          ws.send(JSON.stringify({ id, method, params }));
        });
      },
      on(event, fn) {
        listeners.set(event, [...(listeners.get(event) ?? []), fn]);
      },
      onClose(fn) { closers.push(fn); },
      close() { ws.close(); },
    });
  });
}

module.exports = { connect };
