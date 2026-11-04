const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { Supervisor } = require('../src/supervisor.js');

const HOOK = path.join(__dirname, '../src/hook.js');
const fx = (n) => path.join(__dirname, 'fixtures', n);

// Runs `node ...args` under a supervisor that resumes every pause.
async function run(args, { jsd = true } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'jsd-test-'));
  const sup = new Supervisor(dir);
  const events = { process: [], paused: [] };
  sup.on('process', (p) => events.process.push(p));
  sup.on('paused', (p) => { events.paused.push(p); sup.resume(p.pid); });
  sup.start();
  const env = { ...process.env, NODE_OPTIONS: `--require ${HOOK} --inspect-publish-uid=http` };
  if (jsd) env.JSD_DIR = dir; else delete env.JSD_DIR;
  const t0 = Date.now();
  const child = spawn(process.execPath, args, { env });
  let stdout = '', stderr = '';
  child.stdout.on('data', (d) => (stdout += d));
  child.stderr.on('data', (d) => (stderr += d));
  const code = await new Promise((r) => child.on('exit', r));
  const ms = Date.now() - t0;
  sup.stop();
  fs.rmSync(dir, { recursive: true, force: true });
  return { code, stdout, stderr, ms, pid: child.pid, ...events };
}

test('pauses on debugger', async () => {
  const r = await run([fx('pause.js')]);
  assert.equal(r.code, 0);
  assert.equal(r.stdout, 'done\n');
  assert.equal(r.paused.length, 1);
  assert.equal(r.paused[0].location.line, 2);
  assert.match(r.paused[0].location.url, /pause\.js$/);
});

test('follows children', async () => {
  const r = await run([fx('spawn-child.js')]);
  assert.equal(r.code, 0);
  assert.equal(r.process.length, 2);
  assert.equal(r.paused.length, 1);
  assert.notEqual(r.paused[0].pid, r.pid);
});

test('exits promptly', async () => {
  const r = await run([fx('exit-fast.js')]);
  assert.equal(r.code, 0);
  assert.ok(r.ms < 2000, `took ${r.ms}ms`);
  assert.doesNotMatch(r.stderr, /Waiting for the debugger/);
});

test('ignores worker threads', async () => {
  const r = await run([fx('worker.js')]);
  assert.equal(r.code, 0);
  assert.equal(r.process.length, 1);
  assert.equal(r.stdout, 'worker 1\n');
});

test('reuses an already-open inspector', async () => {
  const r = await run(['--inspect=0', fx('pause.js')]);
  assert.equal(r.code, 0);
  assert.equal(r.paused.length, 1);
});

test('no-op without JSD_DIR', async () => {
  const r = await run([fx('pause.js')], { jsd: false });
  assert.equal(r.code, 0);
  assert.equal(r.stdout, 'done\n');
  assert.equal(r.stderr, '');
});
