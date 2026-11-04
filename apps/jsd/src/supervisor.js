// Holds one quiet CDP session per reported Node process and reports pauses.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const { connect } = require('./cdp.js');

class Supervisor extends EventEmitter {
  constructor(dir) {
    super();
    this.dir = dir;
    this.sessions = new Map(); // pid -> cdp session
    this.seen = new Set();
    this.inflight = new Set(); // attach() calls not yet past runIfWaitingForDebugger
  }

  start() {
    const pick = (name) => {
      if (!name?.endsWith('.json') || this.seen.has(name)) return;
      let proc;
      try { proc = JSON.parse(fs.readFileSync(path.join(this.dir, name), 'utf8')); } catch { return; }
      this.seen.add(name);
      this.attach(proc);
    };
    // Polling, not fs.watch: inotify watches run out on busy machines (watchman, editors),
    // and a missed report leaves that process blocked forever.
    this.scan = () => { try { fs.readdirSync(this.dir).forEach(pick); } catch {} };
    this.timer = setInterval(this.scan, 20);
    this.scan();
  }

  // Shutdown: move the dir aside so late reporters fail to write (the hook then lets
  // them run on), then release everyone who already reported. Returns the moved dir.
  async drain() {
    clearInterval(this.timer);
    const closing = `${this.dir}.closing`;
    try { fs.renameSync(this.dir, closing); this.dir = closing; } catch {}
    this.scan?.();
    await Promise.race([Promise.allSettled(this.inflight), new Promise((r) => setTimeout(r, 1000))]);
    return this.dir;
  }

  stop() {
    clearInterval(this.timer);
    for (const s of this.sessions.values()) s.close();
    this.sessions.clear();
  }

  attach(proc) {
    const p = this.#attach(proc);
    this.inflight.add(p);
    return p.finally(() => this.inflight.delete(p));
  }

  async #attach(proc) {
    let s;
    try { s = await connect(proc.url); } catch { return; } // process already gone
    this.sessions.set(proc.pid, s);
    this.emit('process', proc);
    let mainContext;
    s.on('Runtime.executionContextCreated', ({ context }) => { mainContext ??= context.id; });
    // Only the main context ending means exit; vm contexts (vitest, jest) come and go.
    s.on('Runtime.executionContextDestroyed', ({ executionContextId }) => {
      if (executionContextId === mainContext) s.close();
    });
    const scripts = new Map(); // scriptId -> url (Node leaves callFrame.url empty)
    s.on('Debugger.scriptParsed', ({ scriptId, url }) => scripts.set(scriptId, url));
    s.on('Debugger.paused', ({ callFrames: [top] }) => {
      const url = top.url || scripts.get(top.location.scriptId) || '';
      this.emit('paused', { ...proc, location: { url, line: top.location.lineNumber + 1 } });
    });
    s.on('Debugger.resumed', () => this.emit('resumed', proc.pid));
    s.onClose(() => {
      if (this.sessions.get(proc.pid) !== s) return;
      this.sessions.delete(proc.pid);
      this.emit('exit', proc.pid);
    });
    try {
      await s.send('Runtime.enable');
      await s.send('Debugger.enable');
      await s.send('Runtime.runIfWaitingForDebugger');
    } catch {} // exited while we were attaching
  }

  resume(pid) {
    return this.sessions.get(pid)?.send('Debugger.resume').catch(() => {});
  }
}

module.exports = { Supervisor };
