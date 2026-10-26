// A small stand-in for Obsidian and child_process, so the brain graph runs in a plain page.
(() => {
  class Plugin { constructor(app) { this.app = app; } async loadData() { return window.__data; } async saveData(d) { window.__saved = d; } registerView(t, f) { window.__factory = f; } addRibbonIcon() {} addCommand() {} }
  class ItemView {
    constructor(leaf) { this.leaf = leaf; this.app = leaf.app; this.contentEl = document.createElement('div'); this.contentEl.className = 'view-content'; document.body.appendChild(this.contentEl); }
    registerEvent() {} registerInterval(id) { return id; }
  }
  class Notice { constructor() {} }
  class TFile {}
  function spawn(bin, args) {
    const h = { out: {}, err: {}, self: {} };
    const on = (o) => ({ on: (ev, fn) => { o[ev] = fn; } });
    const child = { stdout: on(h.out), stderr: on(h.err), stdin: { on() {}, end(input) { child._in = input; } }, on: (ev, fn) => { h.self[ev] = fn; } };
    setTimeout(async () => {
      const inp = child._in == null ? null : typeof child._in === 'string' ? child._in : new TextDecoder().decode(child._in);
      const r = await window.__git(args, inp);
      const bin = atob(r.out), bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      if (bytes.length && h.out.data) h.out.data(bytes);
      if (r.err && h.err.data) h.err.data(new TextEncoder().encode(r.err));
      if (h.self.close) h.self.close(r.code);
    }, 0);
    return child;
  }
  window.process = { platform: 'linux', env: {} };
  window.require = (m) => (m === 'obsidian' ? { Plugin, ItemView, Notice, TFile } : m === 'child_process' ? { spawn } : null);
})();
