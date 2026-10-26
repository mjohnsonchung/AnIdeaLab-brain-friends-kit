// Runs the brain graph in Chromium with a stand-in for Obsidian (stub.js) and this
// repo's real git history, then takes a screenshot per scenario. For agents in cloud
// threads, where Obsidian can't run (hq/brain-graph.md, "Testing").
//
//   node .obsidian/plugins/brain-graph/test/run.mjs <main.js> <out folder> 'name={"settings":{...}}' ...
//
// A scenario is a name, optionally followed by = and JSON: "settings" are laid over the
// test defaults, "at" jumps to the first commit whose message starts with that text
// ("after" beats into it), "wait" is how long to let it run in ms, "panel" also shoots
// the settings panel open. It prints load numbers and, after the frames, how many links
// are drawn, hub, business and faded. Set BG_REPO to test against another clone.
// Screenshots and output stay out of the repo: write them to a scratch folder.
import { createRequire } from 'module';
const req = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = req('playwright')); } catch { ({ chromium } = createRequire('/opt/node22/lib/node_modules/')('playwright')); }
import fs from 'fs';
import { spawnSync } from 'child_process';
const [mainPath, out, ...scenarios] = process.argv.slice(2);
const repo = process.env.BG_REPO || new URL('../../../../', import.meta.url).pathname.replace(/\/$/, '');
const dir = new URL('.', import.meta.url).pathname;
fs.mkdirSync(out, { recursive: true });
const src = fs.readFileSync(mainPath, 'utf8');
const css = fs.readFileSync(repo + '/.obsidian/plugins/brain-graph/styles.css', 'utf8');
const appjson = JSON.parse(fs.readFileSync(repo + '/.obsidian/app.json', 'utf8'));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1400, height: 900 }, deviceScaleFactor: 1 });
page.on('pageerror', (e) => console.log('PAGE ERROR', e.message));
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.log('console', m.type(), m.text()); });
await page.exposeFunction('__git', (args, input) => {
  const r = spawnSync('git', args, { cwd: repo, input: input == null ? undefined : input, maxBuffer: 1 << 30 });
  return { code: r.status, out: r.stdout.toString('base64'), err: r.stderr.toString() };
});
await page.exposeFunction('__readFile', (p) => fs.readFileSync(repo + '/' + p, 'utf8'));
await page.setContent(`<html><head><style>${css} html,body{margin:0;height:100%;background:#09090b} .view-content{position:fixed;inset:0}</style></head><body class="theme-dark"></body></html>`);
await page.addScriptTag({ path: dir + 'stub.js' });
await page.addScriptTag({ content: `window.__appjson = ${JSON.stringify(appjson)}; const module = { exports: {} }; (function (require, module, exports) {\n${src}\n})(window.require, module, module.exports); window.BrainGraphPlugin = module.exports;` });
const base = { theme: 'dark', accent: 'coral', speed: 1, replayOnOpen: false, physics: true, hold: 0.04 };
for (const sc of scenarios) {
  const eq = sc.indexOf('='), name = eq < 0 ? sc : sc.slice(0, eq), json = eq < 0 ? '' : sc.slice(eq + 1);
  const extra = json ? JSON.parse(json) : {};
  const t0 = Date.now();
  const info = await page.evaluate(async ({ settings, tauSubject, tauAfter }) => {
    document.querySelectorAll('.view-content').forEach((n) => n.remove());
    window.__data = settings;
    const app = { vault: { adapter: { getBasePath: () => '/vault', read: (p) => window.__readFile(p) }, configDir: '.obsidian', getConfig: (k) => window.__appjson[k] }, workspace: { on: () => ({}), getLeavesOfType: () => [], revealLeaf() {} } };
    const plugin = new window.BrainGraphPlugin(app);
    await plugin.onload();
    const view = window.__factory({ app });
    window.view = view;
    const t = performance.now();
    await view.onOpen();
    const loadMs = performance.now() - t;
    if (tauSubject) {
      const s = view.model.steps.find((x) => x.subject.startsWith(tauSubject));
      if (s) { view.tau = s.b + (tauAfter || 0.4); view.playing = false; }
    }
    view.requestFrame();
    const m = view.model;
    return { loadMs: Math.round(loadMs), nodes: m.nodes.length, edges: m.edges.length, hub: m.edges.filter((e) => e.hub && !e.business).length, business: m.edges.filter((e) => e.business).length, hidden: view.focus ? [...view.focus.hidden].filter(Boolean).length : null, steps: m.steps.length, quietEdits: m.nodes.reduce((t, nd) => t + nd.eflags.filter((f) => f & 2).length, 0), mattEdits: m.nodes.reduce((t, nd) => t + nd.eflags.filter((f) => f & 1).length, 0), faded: view.es ? [...view.es.m].filter((v, j) => view.es.p[j] > 0 && v < 0.99 && !view.model.edges[j].hub).length : null };
  }, { settings: Object.assign({}, base, extra.settings || {}), tauSubject: extra.at, tauAfter: extra.after });
  await page.waitForTimeout(extra.wait || 4500);
  if (extra.then) { await page.evaluate(extra.then); await page.waitForTimeout(2500); }
  await page.screenshot({ path: `${out}/${name}.png` });
  console.log(name, 'after frames', JSON.stringify(await page.evaluate(() => { const v = window.view, E = v.es, ed = v.model.edges; let faded = 0, drawn = 0, hubDrawn = 0, biz = 0; for (let j = 0; j < ed.length; j++) { if (!(E.p[j] > 0)) continue; drawn++; if (ed[j].hub && !ed[j].business) hubDrawn++; if (ed[j].business) biz++; if (E.m[j] < (ed[j].business ? 2.39 : ed[j].hub ? 0.349 : 0.999)) faded++; } return { drawn, hubDrawn, biz, faded }; })));
  if (extra.panel) { await page.evaluate(() => window.view.toggleSettings(true)); await page.waitForTimeout(400); await page.screenshot({ path: `${out}/${name}-panel.png` }); await page.evaluate(() => window.view.toggleSettings(false)); }
  console.log(name, JSON.stringify(info), 'total', Date.now() - t0, 'ms');
}
await browser.close();
