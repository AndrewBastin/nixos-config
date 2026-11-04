const test = require('node:test');
const assert = require('node:assert/strict');
const { findBrowser } = require('../src/browser.js');

test('JSD_BROWSER wins', () => {
  assert.equal(findBrowser({ WAYLAND_DISPLAY: 'w', JSD_BROWSER: '/x', JSD_CHROMIUM: '/c' }), '/x');
});
test('falls back to the baked chromium', () => {
  assert.equal(findBrowser({ DISPLAY: ':0', JSD_CHROMIUM: '/c' }), '/c');
});
test('no display is an error', () => {
  assert.throws(() => findBrowser({ JSD_CHROMIUM: '/c' }),
    { message: 'jsd: no display (WAYLAND_DISPLAY and DISPLAY are unset); DevTools windows need one' });
});
