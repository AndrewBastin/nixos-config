// Test-runner drivers: rewrite a command so its tests run in debuggable processes
// and a test paused in the debugger isn't killed by the runner's timeout.
'use strict';
const path = require('node:path');

const TIMEOUT = 2147483647; // largest setTimeout delay
const FLAGS = {
  vitest: ['--pool=forks', `--testTimeout=${TIMEOUT}`], // default threads pool has no per-test inspector
  jest: [`--testTimeout=${TIMEOUT}`],
  mocha: ['--no-timeout'],
};
const PMS = ['npm', 'pnpm', 'yarn', 'bun'];

const runnerOf = (word) => {
  const name = word && path.basename(word);
  return FLAGS[name] ? name : undefined;
};

// Returns the tool name (from a direct/launcher call) or the script name (from `<pm> run x`/`<pm> test`).
function classify(argv) {
  const [cmd, sub, third] = argv;
  const base = cmd && path.basename(cmd);
  if (base === 'npx' || base === 'bunx') return { tool: argv.slice(1).find((a) => !a.startsWith('-')) };
  if (PMS.includes(base)) {
    if (sub === 'run' || sub === 'run-script') return { script: third };
    if (sub === 'test' || sub === 't') return { script: 'test' };
    if (sub === 'exec' || sub === 'x' || sub === 'dlx') return { tool: argv.slice(2).find((a) => a !== '--' && !a.startsWith('-')) };
    return { tool: sub }; // `pnpm vitest`; unknown subcommands just won't match a runner
  }
  return { tool: cmd };
}

function applyDriver(argv, pkg) {
  const { tool, script } = classify(argv);
  if (script === undefined) {
    const runner = runnerOf(tool);
    return { argv: runner ? [...argv, ...FLAGS[runner]] : argv };
  }
  const body = pkg?.scripts?.[script];
  if (!body) return { argv };
  // ponytail: whitespace split, no shell-quote parsing; compound scripts get no flags
  const words = body.trim().split(/\s+/);
  if (/&&|\|\||;|\|/.test(body)) {
    const found = words.map(runnerOf).find(Boolean);
    return found
      ? { argv, note: `jsd: script "${script}" isn't a plain ${found} command; no driver flags added` }
      : { argv };
  }
  const runner = runnerOf(words[0] === 'npx' ? words[1] : words[0]);
  if (!runner) return { argv };
  const sep = path.basename(argv[0]) === 'npm' && !argv.includes('--') ? ['--'] : [];
  return { argv: [...argv, ...sep, ...FLAGS[runner]] };
}

module.exports = { applyDriver, TIMEOUT };
