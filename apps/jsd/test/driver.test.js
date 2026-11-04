const test = require('node:test');
const assert = require('node:assert/strict');
const { applyDriver } = require('../src/driver.js');

const T = '--testTimeout=2147483647';

test('vitest gets forks pool and no timeout', () => {
  assert.deepEqual(applyDriver(['vitest', 'run']).argv, ['vitest', 'run', '--pool=forks', T]);
});
test('npx launcher is stripped', () => {
  assert.deepEqual(applyDriver(['npx', 'vitest']).argv, ['npx', 'vitest', '--pool=forks', T]);
});
test('pnpm bin call', () => {
  assert.deepEqual(applyDriver(['pnpm', 'vitest']).argv, ['pnpm', 'vitest', '--pool=forks', T]);
});
test('jest by path', () => {
  assert.deepEqual(applyDriver(['./node_modules/.bin/jest']).argv, ['./node_modules/.bin/jest', T]);
});
test('mocha via pnpm exec', () => {
  assert.deepEqual(applyDriver(['pnpm', 'exec', 'mocha']).argv, ['pnpm', 'exec', 'mocha', '--no-timeout']);
});
test('node --test unchanged', () => {
  assert.deepEqual(applyDriver(['node', '--test', 'a.test.ts']).argv, ['node', '--test', 'a.test.ts']);
});
test('npm test script gets flags after --', () => {
  assert.deepEqual(applyDriver(['npm', 'test'], { scripts: { test: 'vitest run --coverage' } }).argv,
    ['npm', 'test', '--', '--pool=forks', T]);
});
test('pnpm run script gets flags directly', () => {
  assert.deepEqual(applyDriver(['pnpm', 'run', 'unit'], { scripts: { unit: 'jest --ci' } }).argv,
    ['pnpm', 'run', 'unit', T]);
});
test('compound script: unchanged with note', () => {
  const c = applyDriver(['npm', 'test'], { scripts: { test: 'tsc && vitest' } });
  assert.deepEqual(c.argv, ['npm', 'test']);
  assert.equal(c.note, 'jsd: script "test" isn\'t a plain vitest command; no driver flags added');
});
test('non-runner script unchanged, no note', () => {
  assert.deepEqual(applyDriver(['npm', 'run', 'dev'], { scripts: { dev: 'tsx watch src/main.ts' } }), { argv: ['npm', 'run', 'dev'] });
});
test('missing script unchanged', () => {
  assert.deepEqual(applyDriver(['npm', 'test'], {}), { argv: ['npm', 'test'] });
});
test('bare yarn (install) unchanged', () => {
  assert.deepEqual(applyDriver(['yarn']), { argv: ['yarn'] });
});
test('npm script with user args after -- keeps one separator', () => {
  assert.deepEqual(applyDriver(['npm', 'test', '--', 'foo.test.ts'], { scripts: { test: 'vitest run' } }).argv,
    ['npm', 'test', '--', 'foo.test.ts', '--pool=forks', T]);
});
