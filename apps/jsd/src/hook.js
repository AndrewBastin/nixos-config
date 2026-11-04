// Preloaded into every Node process under `jsd` (via NODE_OPTIONS). Opens the inspector,
// reports it to the supervisor, and waits until the supervisor is attached, so even a
// `debugger` on the first line pauses. Must never throw or print.
// ponytail: Node itself prints "Debugger attached." once per process; no JS-side way to silence it.
'use strict';
try {
  const dir = process.env.JSD_DIR;
  if (dir && require('node:worker_threads').isMainThread) {
    const fs = require('node:fs');
    const path = require('node:path');
    const inspector = require('node:inspector');
    if (!inspector.url()) inspector.open(0);
    const url = inspector.url();
    const file = path.join(dir, String(process.pid));
    fs.writeFileSync(`${file}.tmp`, JSON.stringify({ pid: process.pid, argv: process.argv, url }));
    fs.renameSync(`${file}.tmp`, `${file}.json`);
    // Closing on exit drops our sessions, so Node doesn't wait for them to disconnect.
    process.on('exit', () => inspector.close());
    inspector.waitForDebugger();
  }
} catch {}
