const { Worker } = require('node:worker_threads');
const w = new Worker('debugger; require("node:worker_threads").parentPort.postMessage(1)', { eval: true });
w.on('message', (m) => console.log('worker', m));
