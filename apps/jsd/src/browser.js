// DevTools windows: one private Chromium per jsd run; each paused process gets an
// app window (no browser chrome) on the DevTools frontend Chromium serves on its debug port.
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { connect } = require('./cdp.js');

function findBrowser(env = process.env) {
  if (!env.WAYLAND_DISPLAY && !env.DISPLAY) {
    throw new Error('jsd: no display (WAYLAND_DISPLAY and DISPLAY are unset); DevTools windows need one');
  }
  const exe = env.JSD_BROWSER || env.JSD_CHROMIUM;
  if (!exe) throw new Error('jsd: Chromium is needed (set JSD_BROWSER)');
  return exe;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function openBrowser(exe) {
  const udd = fs.mkdtempSync(path.join(os.tmpdir(), 'jsd-chromium-'));
  const base = [`--user-data-dir=${udd}`, '--ozone-platform-hint=auto'];
  const windows = new Map(); // key -> targetId
  const opening = new Map(); // "host:port/uuid" -> key, until its target appears
  const closedFns = [];
  let started, chromium;

  async function start() {
    chromium = spawn(exe, [...base, '--remote-debugging-port=0', '--no-first-run',
      '--no-default-browser-check', '--no-startup-window'], { stdio: 'ignore' });
    const portFile = path.join(udd, 'DevToolsActivePort');
    let lines = [];
    for (let i = 0; i < 300 && lines.length < 2; i++) {
      await sleep(50);
      try { lines = fs.readFileSync(portFile, 'utf8').trim().split('\n'); } catch {}
    }
    if (lines.length < 2) throw new Error(`couldn't start ${exe}`);
    const cdp = await connect(`ws://127.0.0.1:${lines[0]}${lines[1]}`);
    const claim = ({ targetId, url }) => {
      for (const [ws, key] of opening) {
        if (url.includes(`ws=${ws}`)) { opening.delete(ws); windows.set(key, targetId); }
      }
    };
    cdp.on('Target.targetCreated', ({ targetInfo }) => claim(targetInfo));
    cdp.on('Target.targetInfoChanged', ({ targetInfo }) => claim(targetInfo));
    cdp.on('Target.targetDestroyed', ({ targetId }) => {
      for (const [key, id] of windows) {
        if (id === targetId) { windows.delete(key); closedFns.forEach((fn) => fn(key)); }
      }
    });
    await cdp.send('Target.setDiscoverTargets', { discover: true });
    return { cdp, port: lines[0] };
  }

  return {
    async open(wsUrl, key) {
      started ??= start();
      const { cdp, port } = await started;
      if (windows.has(key)) return cdp.send('Target.activateTarget', { targetId: windows.get(key) });
      const ws = wsUrl.replace(/^ws:\/\//, '');
      if ([...opening.values()].includes(key)) return;
      opening.set(ws, key);
      // A second launch on the same profile hands the URL to the running instance and exits.
      spawn(exe, [...base, `--app=http://127.0.0.1:${port}/devtools/js_app.html?ws=${ws}`], { stdio: 'ignore' });
    },
    async closeWindow(key) {
      const id = windows.get(key);
      if (!id || !started) return;
      windows.delete(key);
      await (await started).cdp.send('Target.closeTarget', { targetId: id });
    },
    onClosed(fn) { closedFns.push(fn); },
    async close() {
      if (chromium && chromium.exitCode === null) {
        const exited = new Promise((r) => chromium.on('exit', r));
        chromium.kill();
        await Promise.race([exited, sleep(3000)]);
      }
      fs.rmSync(udd, { recursive: true, force: true });
    },
  };
}

module.exports = { findBrowser, openBrowser };
