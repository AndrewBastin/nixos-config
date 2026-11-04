#!/usr/bin/env node
// jsd: run Node programs and tests with DevTools opening on `debugger` statements.
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');
const { applyDriver } = require('./driver.js');
const { Supervisor } = require('./supervisor.js');

const USAGE = `usage: jsd <file> [args]       run a Node file under the debugger
       jsd -- <command…>        run any command (npm, vitest, jest, node --test…)
       jsd attach <pid>         debug an already-running Node process
`;
const HEADLESS = process.env.JSD_HEADLESS === '1';

function die(msg, code = 1) {
  process.stderr.write(`${msg}\n`);
  process.exit(code);
}

// Wires supervisor pauses to DevTools windows (or, headless, to a stderr line + resume).
async function connectUi(sup) {
  if (HEADLESS) {
    sup.on('paused', (p) => {
      process.stderr.write(`jsd: paused pid=${p.pid} ${p.location.url}:${p.location.line}\n`);
      sup.resume(p.pid);
    });
    return { close: async () => {} };
  }
  const { findBrowser, openBrowser } = require('./browser.js');
  let exe;
  try { exe = findBrowser(); } catch (e) { die(e.message); }
  const browser = openBrowser(exe);
  sup.on('paused', (p) => browser.open(p.url, p.pid).catch((e) => process.stderr.write(`jsd: ${e.message}\n`)));
  sup.on('exit', (pid) => browser.closeWindow(pid).catch(() => {}));
  browser.onClosed((pid) => sup.resume(pid));
  return browser;
}

async function run(argv) {
  let pkg;
  try { pkg = JSON.parse(fs.readFileSync('package.json', 'utf8')); } catch {}
  const { argv: cmd, note } = applyDriver(argv, pkg);
  if (note) process.stderr.write(`${note}\n`);

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'jsd-'));
  const sup = new Supervisor(dir);
  const ui = await connectUi(sup);
  sup.start();

  const hook = path.join(__dirname, 'hook.js');
  const env = {
    ...process.env,
    JSD_DIR: dir,
    NODE_OPTIONS: `${process.env.NODE_OPTIONS ?? ''} --require ${JSON.stringify(hook)} --inspect-publish-uid=http`.trim(),
  };
  delete env.JSD_HEADLESS;
  const child = spawn(cmd[0], cmd.slice(1), { stdio: 'inherit', env });
  // The terminal's Ctrl-C reaches the whole process group; let the command decide.
  process.on('SIGINT', () => {});
  // A kill aimed at jsd alone is passed on, so the command can shut down.
  for (const sig of ['SIGTERM', 'SIGHUP']) process.on(sig, () => child.kill(sig));
  const [code, signal] = await new Promise((r) => {
    child.on('exit', (c, s) => r([c, s]));
    child.on('error', (e) => { process.stderr.write(`jsd: ${e.message}\n`); r([127, null]); });
  });

  const left = await sup.drain();
  sup.stop();
  await ui.close();
  fs.rmSync(left, { recursive: true, force: true });
  process.exit(signal ? 128 + os.constants.signals[signal] : code);
}

async function attach(pidArg) {
  const pid = Number(pidArg);
  let command;
  try { command = execFileSync('ps', ['-o', 'command=', '-p', String(pid)], { encoding: 'utf8' }); } catch {}
  if (!Number.isInteger(pid) || !command) die(`jsd: no such process ${pidArg}`);
  const port = Number(command.match(/--inspect(?:-brk)?=(?:[^\s:]+:)?(\d+)/)?.[1] ?? 9229);

  const list = async () => {
    try { return await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); } catch { return undefined; }
  };
  let targets = await list();
  if (!targets) {
    process.kill(pid, 'SIGUSR1');
    for (let i = 0; i < 30 && !targets; i++) {
      await new Promise((r) => setTimeout(r, 100));
      targets = await list();
    }
  }
  const url = targets?.[0]?.webSocketDebuggerUrl;
  if (!url) die(`jsd: couldn't reach the inspector of ${pid} on port ${port}`);

  const sup = new Supervisor(null);
  const ui = await connectUi(sup);
  const done = new Promise((r) => sup.on('exit', r));
  const detach = async () => { sup.stop(); await ui.close(); process.exit(0); };
  process.on('SIGINT', detach);
  process.on('SIGTERM', detach);
  await sup.attach({ pid, argv: command.trim().split(/\s+/), url });
  await done;
  await detach();
}

const [first, ...rest] = process.argv.slice(2);
if (!first || first === '-h' || first === '--help') {
  process.stdout.write(USAGE);
} else if (first === '--') {
  if (!rest.length) die(USAGE.trimEnd(), 2);
  run(rest);
} else if (first === 'attach') {
  if (rest.length !== 1) die(USAGE.trimEnd(), 2);
  attach(rest[0]);
} else if (first.startsWith('-')) {
  die(USAGE.trimEnd(), 2);
} else {
  run(['node', first, ...rest]);
}
