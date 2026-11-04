const { spawnSync } = require('node:child_process');
const r = spawnSync(process.execPath, [require('node:path').join(__dirname, 'pause.js')], { stdio: 'inherit' });
process.exit(r.status);
