const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const JSD = path.join(__dirname, '../src/jsd.js');
const fx = (n) => path.join(__dirname, 'fixtures', n);

function jsd(args, { env = {}, cwd } = {}) {
  return new Promise((resolve) => {
    const t0 = Date.now();
    const e = { ...process.env, JSD_HEADLESS: '1', ...env };
    delete e.NODE_TEST_CONTEXT; // else a nested `node --test` thinks it's inside ours
    const child = spawn(process.execPath, [JSD, ...args], { cwd, env: e });
    let stdout = '', stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('exit', (code) => resolve({ code, stdout, stderr, ms: Date.now() - t0 }));
  });
}

test('runs a file', async () => {
  const r = await jsd([fx('pause.js')]);
  assert.equal(r.code, 0);
  assert.equal(r.stdout, 'done\n');
  assert.match(r.stderr, /jsd: paused pid=\d+ .*pause\.js:2/);
});

test('wraps node --test', async () => {
  const r = await jsd(['--', 'node', '--test', fx('node-test/a.test.js')]);
  assert.equal(r.code, 0);
  assert.equal(r.stderr.match(/jsd: paused pid=\d+ .*a\.test\.js:3/g)?.length, 1, r.stderr);
});

test('passes the exit code', async () => {
  const r = await jsd(['--', 'node', '-e', 'process.exit(7)']);
  assert.equal(r.code, 7);
});

test('keeps existing NODE_OPTIONS', async () => {
  const r = await jsd(['--', 'node', '-e', 'console.log(process.env.NODE_OPTIONS)'],
    { env: { NODE_OPTIONS: '--max-old-space-size=123' } });
  assert.match(r.stdout, /--max-old-space-size=123/);
  assert.match(r.stdout, /hook\.js/);
});

test('exits with the command when a child outlives it, and the child runs', async () => {
  const r = await jsd(['--', 'node', '-e',
    "const c=require('child_process').spawn(process.execPath,['-e','setTimeout(()=>{},300)'],{detached:true,stdio:'ignore'}); c.unref(); console.log(c.pid)"]);
  assert.equal(r.code, 0);
  assert.ok(r.ms < 2000, `took ${r.ms}ms`);
  const pid = Number(r.stdout.trim());
  await new Promise((res) => setTimeout(res, 1500));
  assert.throws(() => process.kill(pid, 0), undefined, `grandchild ${pid} is still alive (stuck waiting for the debugger)`);
});

test('prints the driver note', { skip: spawnSync('npm', ['--version']).status !== 0 && 'no npm' }, async () => {
  const r = await jsd(['--', 'npm', 'test'], { cwd: fx('node-test/pkg'), env: { npm_config_offline: 'true' } });
  assert.match(r.stderr, /jsd: script "test" isn't a plain vitest command; no driver flags added/);
});

test('usage', async () => {
  const r = await jsd([]);
  assert.equal(r.code, 0);
  assert.match(r.stdout, /^usage: jsd/);
});

test('missing command: exit 127, temp dir removed', async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'jsd-tmpdir-'));
  const r = await jsd(['--', 'no-such-command-jsd'], { env: { TMPDIR: tmp } });
  assert.equal(r.code, 127);
  assert.match(r.stderr, /jsd: spawn no-such-command-jsd ENOENT/);
  assert.deepEqual(fs.readdirSync(tmp), []);
  fs.rmSync(tmp, { recursive: true });
});

test('SIGTERM to jsd reaches the command', async () => {
  const e = { ...process.env, JSD_HEADLESS: '1' };
  delete e.NODE_TEST_CONTEXT;
  const child = spawn(process.execPath, [JSD, '--', 'node', '-e', 'setInterval(()=>{},1000); console.log(process.pid)'], { env: e });
  const inner = Number(await new Promise((r) => child.stdout.once('data', r)));
  child.kill('SIGTERM');
  const code = await Promise.race([
    new Promise((r) => child.on('exit', (c) => r(c))),
    new Promise((r) => setTimeout(() => r('timeout'), 2000)),
  ]);
  if (code === 'timeout') { child.kill('SIGKILL'); try { process.kill(inner, 'SIGKILL'); } catch {} }
  assert.equal(code, 143);
});
