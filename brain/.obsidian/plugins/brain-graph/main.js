/*
 * Brain graph: an Obsidian plugin for the brain.
 *
 * It reads the vault's git history and replays it as bubbles: every folder with
 * more than one note is a circle, each note is a dot that appears when the note
 * was created, each link between notes is a line that forms when the link was
 * written, notes edited in a commit pulse, and a curve along the bottom shows how
 * busy each commit was. (Graph and Tree views were taken out on 20 Oct 2026.)
 *
 * Plain JavaScript with no build step, so agents can read and edit it here.
 * How to read the view, and the rules for changing it: knowledge/systems/brain-graph.md.
 */
'use strict';

const { Plugin, ItemView, Notice, TFile } = require('obsidian');

const VIEW_TYPE = 'brain-graph';
const BEATS_PER_SECOND = 2.4; // replay pace at 1x; one small commit is about one beat
const SETTLE = 2.4;           // beats after the last commit for its flashes to fade
const SPEEDS = [0.125, 0.25, 0.5, 1, 2, 4];
const speedLabel = (s) => ({ 0.125: '⅛', 0.25: '¼', 0.5: '½' }[s] || String(s)) + '×';
const POLL_MS = 15000;
const FRESH_START = /^fresh start\b/i; // a commit whose message starts like this is a fresh start
const STEADY_BEATS = 0.2;      // with One at a time on: beats between one new note, link or edit and the next
const GLOW_BEATS = 9;          // how long a written note keeps its accent tint

// Focus (added 17 Oct 2026, hq/brain-graph.md#focus). Hub notes are the ones nearly
// every note links to ("see the rules"); their links can be faded or hidden so the
// links that carry meaning stand out. Paths are from the vault root.
// Since the 19 Oct 2026 restructure the hubs are the core and the README. The old hubs keep their place
// under their retired paths, so a replay of the old layout stays readable.
const HUBS = new Set([
  'CLAUDE.md', 'README.md',
  'knowledge/areas/the-brain/history/connections.md', 'knowledge/areas/the-brain/history/structure.md',
  'knowledge/areas/the-brain/history/decisions-table-to-19-oct-2026.md', 'knowledge/areas/the-brain/history/hq-progress-to-19-oct-2026.md',
]);
// Folders of lists that link out to most of their library (Matt, 20 Oct 2026, of skills/lists: "no
// links coming from that folder specifically, just for visual", and that it "should be surrounding
// skills slash readme ... as like the second layer"). Their links show only on hover, or as a
// flash that fades when one is made or the list is edited ("I just want the on hover behavior"),
// and in Bubbles their notes sit as a ring in the middle of their parent folder.
const LIST_FOLDERS = new Set(['skills/lists']);
const inList = (p) => LIST_FOLDERS.has(p.slice(0, p.lastIndexOf('/')));
const MATT_EDIT = /^(?:Matt['’]s|My) edits in Obsidian/; // commits made by the Obsidian Git plugin on the owner's computers
const BOT_AUTHOR = /^farm-brain\b|github-actions|\[bot\]/i; // the repo's own Actions (links sync, legislation refresh)
const SWEEP_NOTES = 24;        // a commit touching more notes than this is a big sweep
const QUIET = 0.35;            // how bright a quiet commit's flashes are
const FADE_FLOOR = 0.3;        // how faint an old link gets
// A link between a skill and a knowledge note is a bridge: it shows only while you point at either end
// (Matt, 20 Oct 2026).
const isBridge = (pa, pb) => { const a = pa.split('/')[0], b = pb.split('/')[0]; return (a === 'skills' && b === 'knowledge') || (a === 'knowledge' && b === 'skills'); };
const EDIT_MATT = 1, EDIT_QUIET = 2; // flags on births, edits and links

const DEFAULT_SETTINGS = {
  theme: 'auto',      // auto (follow Obsidian), dark or light
  accent: 'violet',
  speed: 1,
  replayOnOpen: false,
  startFrom: 'fresh', // the latest fresh start, or the beginning
  steady: false,      // replay one thing at a time (a note, a link or an edit), each the same time apart
  physics: true,      // circles can be dragged and trail behind; off, they glide to their places
  hold: 0.04,         // physics: how strongly circles are pulled back to their places
  hubLinks: 'faint',  // links to the hub notes: show, faint or hide
  bridges: 'hover',   // links between skills and knowledge notes: only on hover, or always
  fadeDays: 14,       // a link fades once neither of its notes has been touched for this many days; 0 is off
  hideExcluded: true, // leave out notes Obsidian's Excluded files setting hides, such as the history/ folders
  markMatt: true,     // Matt's own edits light up in a second colour
  quiet: true,        // bot commits and big sweeps flash softly and leave no afterglow
};

const THEMES = {
  dark: { bg: '#09090b', fg: [244, 244, 245], edge: 0.13, node: 0.9, tipBg: 'rgba(24,24,27,0.86)' },
  light: { bg: '#fafaf9', fg: [16, 16, 18], edge: 0.13, node: 0.86, tipBg: 'rgba(255,255,255,0.9)' },
};

const ACCENTS = {
  violet: { name: 'Violet', dark: '#8f7dff', light: '#5b3df5' },
  cyan: { name: 'Cyan', dark: '#2ee0ff', light: '#0a8db6' },
  lime: { name: 'Lime', dark: '#c4f53a', light: '#4b9600' },
  coral: { name: 'Coral', dark: '#ff6b57', light: '#e0412b' },
};

/* ---------- small helpers ---------- */

const TAU = Math.PI * 2;
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);
const easeOutBack = (t) => 1 + 2.70158 * Math.pow(t - 1, 3) + 1.70158 * Math.pow(t - 1, 2);
const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
const hexRgb = (hex) => {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};
const decoder = new TextDecoder('utf-8');

// Index of the first element greater than v, in a sorted array of numbers.
function upper(arr, v) {
  let lo = 0, hi = arr.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (arr[mid] <= v) lo = mid + 1; else hi = mid;
  }
  return lo;
}

function concatBytes(chunks) {
  let n = 0;
  for (const c of chunks) n += c.length;
  const out = new Uint8Array(n);
  let o = 0;
  for (const c of chunks) { out.set(c, o); o += c.length; }
  return out;
}

function countLines(b) {
  if (!b || !b.length) return 0;
  let n = 0;
  for (let i = 0; i < b.length; i++) if (b[i] === 10) n++;
  return b[b.length - 1] === 10 ? n : n + 1;
}

/* ---------- what counts as a note, code, or settings ---------- */

const CODE_EXT = new Set(['js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'py', 'css', 'scss', 'html', 'sh', 'yml', 'yaml', 'toml', 'sql', 'lua', 'luau', 'rb', 'go', 'rs']);

// 'note', 'code', 'other' (counted as nothing, shown only if a note links to it),
// or null for Obsidian's settings and trash, which the brain graph leaves out.
function kindOf(path) {
  if (path.startsWith('.obsidian/')) {
    return /^\.obsidian\/(plugins\/[^/]+\/[^/]+\.(js|css)|snippets\/[^/]+\.css)$/.test(path) ? 'code' : null;
  }
  if (path.startsWith('.trash/')) return null;
  if (/\.md$/i.test(path)) return 'note';
  const dot = path.lastIndexOf('.');
  const ext = dot > path.lastIndexOf('/') ? path.slice(dot + 1).toLowerCase() : '';
  return CODE_EXT.has(ext) ? 'code' : 'other';
}
const countsLines = (k) => k === 'note' || k === 'code';

/* ---------- links written in notes ---------- */

// Link targets in a note: Markdown links [text](target) and wikilinks [[target]].
// Links inside code blocks and inline code don't count, as in Obsidian.
function extractLinks(text) {
  const clean = text
    .replace(/^(```|~~~)[^\n]*\n[\s\S]*?^\1[^\n]*$/gm, '')
    .replace(/`[^`\n]*`/g, '');
  const out = [];
  const scan = (part, mark) => {
    const md = /\[(?:[^\[\]\n]|\[[^\]\n]*\])*\]\(\s*(<[^>\n]+>|[^)\s]+)(?:\s+["'][^)\n]*)?\)/g;
    let m;
    while ((m = md.exec(part))) out.push(mark + 'md:' + m[1].replace(/^<|>$/g, ''));
    const wiki = /\[\[([^\]|#^\n]+)(?:[#^][^\]|\n]*)?(?:\|[^\]\n]*)?\]\]/g;
    while ((m = wiki.exec(part))) out.push(mark + 'wiki:' + m[1].trim());
  };
  scan(clean, '');
  return out;
}

// Obsidian's Excluded files: each entry is a path prefix, or a /regular expression/.
function excludedBy(filters, path) {
  return filters.some((f) => {
    if (typeof f !== 'string' || !f) return false;
    if (f.length > 2 && f.startsWith('/') && f.endsWith('/')) {
      try { return new RegExp(f.slice(1, -1)).test(path); } catch { return false; }
    }
    return path.startsWith(f);
  });
}

function joinPath(fromPath, target) {
  const parts = target.startsWith('/') ? [] : fromPath.split('/').slice(0, -1);
  for (const seg of target.split('/')) {
    if (!seg || seg === '.') continue;
    if (seg === '..') { if (!parts.length) return null; parts.pop(); } else parts.push(seg);
  }
  return parts.join('/');
}

function buildNameIndex(live) {
  const idx = new Map();
  for (const [path] of live) {
    const base = path.slice(path.lastIndexOf('/') + 1).toLowerCase();
    for (const key of [base, base.replace(/\.md$/, '')]) {
      if (!idx.has(key)) idx.set(key, []);
      idx.get(key).push(path);
    }
  }
  return idx;
}

// The live file a link points at, or null if it points outside the repo or nowhere.
function resolveLink(fromPath, spec, live, nameIndex) {
  if (spec.startsWith('md:')) {
    let t = spec.slice(3);
    if (/^[a-z][a-z0-9+.-]*:/i.test(t) || t.startsWith('#')) return null;
    t = t.split('#')[0].split('?')[0];
    if (!t) return null;
    try { t = decodeURIComponent(t); } catch { /* keep it as written */ }
    const p = joinPath(fromPath, t);
    if (p == null) return null;
    return live.get(p) || live.get(p + '.md') || null;
  }
  // Wikilink: a path from the vault root, or a note name found anywhere (nearest first).
  const name = spec.slice(5);
  const direct = live.get(name) || live.get(name + '.md');
  if (direct) return direct;
  const key = name.slice(name.lastIndexOf('/') + 1).toLowerCase();
  const hits = (nameIndex().get(key) || []).filter((p) => p.toLowerCase().endsWith(name.toLowerCase()) || p.toLowerCase().endsWith(name.toLowerCase() + '.md'));
  if (!hits.length) return null;
  const dir = fromPath.slice(0, fromPath.lastIndexOf('/') + 1);
  hits.sort((a, b) => (b.startsWith(dir) - a.startsWith(dir)) || a.length - b.length || (a < b ? -1 : 1));
  return live.get(hits[0]);
}

/* ---------- git ---------- */

class Git {
  // Finds a working git. Obsidian on a Mac often starts with a short PATH, so try the usual places.
  static async open(cwd) {
    const cp = require('child_process');
    const platform = typeof process !== 'undefined' ? process.platform : '';
    const candidates = ['git'];
    if (platform === 'darwin') candidates.push('/usr/bin/git', '/opt/homebrew/bin/git', '/usr/local/bin/git');
    else if (platform === 'win32') candidates.push('C:\\Program Files\\Git\\cmd\\git.exe', 'C:\\Program Files (x86)\\Git\\cmd\\git.exe');
    else candidates.push('/usr/bin/git', '/usr/local/bin/git');
    let lastError = null;
    for (const bin of candidates) {
      const git = new Git(cp, bin, cwd);
      try { await git.run(['--version']); return git; } catch (e) { lastError = e; }
    }
    throw new Error('Git wasn’t found on this computer' + (lastError ? ` (${lastError.message})` : '') + '.');
  }

  constructor(cp, bin, cwd) { this.cp = cp; this.bin = bin; this.cwd = cwd; }

  run(args, input) {
    return new Promise((resolve, reject) => {
      let child;
      const env = Object.assign({}, typeof process !== 'undefined' ? process.env : {}, { GIT_OPTIONAL_LOCKS: '0' });
      try {
        child = this.cp.spawn(this.bin, args, { cwd: this.cwd, env, windowsHide: true, stdio: [input == null ? 'ignore' : 'pipe', 'pipe', 'pipe'] });
      } catch (e) { reject(e); return; }
      const out = [], err = [];
      child.stdout.on('data', (d) => out.push(d));
      child.stderr.on('data', (d) => err.push(d));
      child.on('error', reject);
      child.on('close', (code) => {
        if (code === 0) resolve(concatBytes(out));
        else reject(new Error(decoder.decode(concatBytes(err)).trim() || `git exited with ${code}`));
      });
      if (input != null) { child.stdin.on('error', () => {}); child.stdin.end(input); }
    });
  }

  async text(args) { return decoder.decode(await this.run(args)); }
}

// One record per commit, oldest first: who, when, and every file it touched with
// the file's new blob, plus lines added and removed per file. Merges are compared
// with their first parent, and renames are followed so a moved note stays one dot.
function parseLog(text) {
  const commits = [];
  for (const chunk of text.split('\x1e')) {
    if (!chunk.trim()) continue;
    const z = chunk.indexOf('\0');
    const head = (z < 0 ? chunk : chunk.slice(0, z)).split('\x1f');
    const c = {
      sha: head[0].trim(),
      parents: (head[1] || '').split(' ').filter(Boolean),
      t: Number(head[2]) || 0,
      author: head[3] || '',
      subject: (head[4] || '').trim(),
      raw: [],
      num: [],
    };
    const tok = z < 0 ? [] : chunk.slice(z + 1).split('\0');
    for (let i = 0; i < tok.length; i++) {
      const x = tok[i].replace(/^\n+/, '');
      if (!x) continue;
      if (x[0] === ':') {
        const f = x.slice(1).split(' ');
        const status = f[4] || '';
        const e = { mode: f[1], sha: f[3], status: status[0] };
        if (status[0] === 'R' || status[0] === 'C') { e.src = tok[++i]; e.path = tok[++i]; } else e.path = tok[++i];
        if (e.path) c.raw.push(e);
      } else {
        const m = /^(\d+|-)\t(\d+|-)\t([\s\S]*)$/.exec(x);
        if (!m) continue;
        let path = m[3];
        if (!path) { i++; path = tok[++i]; } // renamed: old path, then new path
        c.num.push({ add: m[1] === '-' ? -1 : +m[1], del: m[2] === '-' ? -1 : +m[2], path });
      }
    }
    commits.push(c);
  }
  return commits;
}

async function readBlobs(git, shas) {
  const out = new Map();
  for (let i = 0; i < shas.length; i += 2000) {
    const bytes = await git.run(['cat-file', '--batch'], shas.slice(i, i + 2000).join('\n') + '\n');
    let p = 0;
    while (p < bytes.length) {
      const nl = bytes.indexOf(10, p);
      if (nl < 0) break;
      const header = decoder.decode(bytes.subarray(p, nl)).split(' ');
      p = nl + 1;
      if (header.length < 3 || header[1] === 'missing') continue;
      const size = Number(header[2]);
      out.set(header[0], bytes.subarray(p, p + size));
      p += size + 1;
    }
  }
  return out;
}

async function readModel(git, startFrom, steady) {
  const head = (await git.text(['rev-parse', 'HEAD'])).trim();
  const log = await git.run([
    '-c', 'core.quotepath=false', 'log', '--reverse', '--date-order', '--diff-merges=first-parent',
    '-M', '--raw', '--numstat', '-z', '--no-abbrev', '--format=%x1e%H%x1f%P%x1f%ct%x1f%an%x1f%s', head,
  ]);
  const commits = parseLog(decoder.decode(log));
  const want = new Set();
  for (const c of commits) {
    for (const e of c.raw) if (e.status !== 'D' && e.mode !== '160000' && countsLines(kindOf(e.path))) want.add(e.sha);
  }
  const blobs = await readBlobs(git, [...want]);
  let fresh = null;
  for (const c of commits) if (FRESH_START.test(c.subject)) fresh = c;
  const model = assemble(head, commits, blobs, startFrom === 'fresh' && fresh ? fresh.sha : null, steady);
  model.freshStart = fresh ? { sha: fresh.sha, t: fresh.t } : null;
  return model;
}

/* ---------- from commits to a replay ---------- */

// Pass 1 replays the commits to find, for each file, when it was born, edited and
// deleted, and for each pair of notes, when a link between them appeared or went.
// Pass 2 keeps the notes and the links between them, drops commits where
// nothing visible happened, and gives every event a time on the replay clock,
// measured in beats. Big commits get more beats, so 80 notes arriving at once
// grow in one by one instead of popping in together.
// From a fresh start, the commits before it are the starting picture: they happen
// well before the replay's zero, so their notes and links are already settled
// there, and the timeline begins with the fresh start commit.
function assemble(head, commits, blobs, startSha, steady) {
  const startAt = startSha ? commits.findIndex((c) => c.sha === startSha) : -1;
  const recs = [];
  const live = new Map();
  const deadByPath = new Map();
  const edgeRecs = new Map();
  let current = new Map();
  let nameIndex = null;
  const totals = { note: 0, code: 0 };
  const steps = [];

  commits.forEach((c, ci) => {
    const step = {
      sha: c.sha, t: c.t, author: c.author, subject: c.subject, merge: c.parents.length > 1,
      before: ci < startAt, start: ci === startAt,
      born: [], died: [], edited: [], linkAdd: [], linkDel: [],
      add: { note: 0, code: 0 }, del: { note: 0, code: 0 },
    };
    const bornSet = new Set();
    const edited = new Set();
    let filesChanged = false, linksChanged = false;

    for (const e of c.raw) {
      if (e.mode === '160000') continue;
      if (e.status === 'D') {
        const r = live.get(e.path);
        if (!r) continue;
        live.delete(e.path);
        deadByPath.set(e.path, r);
        if (countsLines(r.kind)) totals[r.kind] -= r.lines;
        if (r.links.length) linksChanged = true;
        step.died.push(r);
        filesChanged = true;
        continue;
      }
      let r = null;
      if (e.status === 'R' && live.has(e.src)) { r = live.get(e.src); live.delete(e.src); }
      if (!r) r = live.get(e.path) || null;
      if (!r) {
        r = deadByPath.get(e.path) || null;
        if (r) deadByPath.delete(e.path);
        else {
          r = { id: recs.length, path: e.path, paths: [], kind: null, lines: 0, sha: null, links: [] };
          recs.push(r);
        }
        step.born.push(r);
        bornSet.add(r);
        filesChanged = true;
      }
      if (r.path !== e.path || !r.paths.length) {
        if (r.paths.length) edited.add(r); // moved
        r.path = e.path;
        r.paths.push(e.path);
        filesChanged = true;
      }
      live.set(e.path, r);
      const kind = kindOf(e.path);
      if (r.sha !== e.sha || r.kind !== kind) {
        if (countsLines(r.kind)) totals[r.kind] -= r.lines;
        r.kind = kind;
        r.lines = countsLines(kind) ? countLines(blobs.get(e.sha)) : 0;
        if (countsLines(kind)) totals[kind] += r.lines;
        const links = kind === 'note' && blobs.has(e.sha) ? extractLinks(decoder.decode(blobs.get(e.sha))) : [];
        if (links.length || r.links.length) linksChanged = true;
        r.links = links;
        r.sha = e.sha;
        edited.add(r);
      }
    }
    step.edited = [...edited].filter((r) => !bornSet.has(r));

    if (!step.merge) {
      for (const n of c.num) {
        const k = kindOf(n.path);
        if (countsLines(k) && n.add >= 0) { step.add[k] += n.add; step.del[k] += n.del; }
      }
    }

    if (filesChanged || linksChanged) {
      if (filesChanged) nameIndex = null;
      const index = () => nameIndex || (nameIndex = buildNameIndex(live));
      const next = new Map();
      for (const r of live.values()) {
        if (r.kind !== 'note') continue;
        for (const spec of r.links) {
          const t = resolveLink(r.path, spec, live, index);
          if (!t || t === r) continue;
          const key = r.id < t.id ? r.id + ':' + t.id : t.id + ':' + r.id;
          if (!next.has(key)) next.set(key, r);
        }
      }
      for (const [key, src] of next) {
        if (current.has(key)) continue;
        let er = edgeRecs.get(key);
        if (!er) {
          const [a, b] = key.split(':').map(Number);
          er = { a: recs[a], b: recs[b], spans: [], key };
          edgeRecs.set(key, er);
        }
        step.linkAdd.push({ er, src });
      }
      for (const key of current.keys()) if (!next.has(key)) step.linkDel.push(edgeRecs.get(key));
      current = next;
    }
    step.totals = { note: totals.note, code: totals.code };
    steps.push(step);
  });

  // Pass 2. The dots: every note. Files that notes link to (scripts and other code) aren't drawn
  // since the Graph view went, but a commit that only changed one keeps its place on the timeline.
  const nodeRecs = recs.filter((r) => r.kind === 'note');
  const isNode = new Set(nodeRecs), linked = new Set(nodeRecs);
  for (const er of edgeRecs.values()) { linked.add(er.a); linked.add(er.b); }
  const between = (er) => isNode.has(er.a) && isNode.has(er.b);
  nodeRecs.forEach((r, i) => { r.node = i; r.bspans = []; r.bedits = []; r.eflags = []; r.etimes = []; });

  const visible = [];
  for (const s of steps) {
    const touched = [...s.born, ...s.died, ...s.edited].some((r) => linked.has(r));
    s.born = s.born.filter((r) => isNode.has(r));
    s.died = s.died.filter((r) => isNode.has(r));
    s.edited = s.edited.filter((r) => isNode.has(r));
    s.linkAdd = s.linkAdd.filter((l) => between(l.er));
    s.linkDel = s.linkDel.filter(between);
    const prev = visible[visible.length - 1];
    const lines = s.add.note + s.add.code + s.del.note + s.del.code;
    const totalsMoved = !prev || prev.totals.note !== s.totals.note || prev.totals.code !== s.totals.code;
    if (s.start || touched || s.linkAdd.length || s.linkDel.length || lines || totalsMoved) visible.push(s);
  }

  const unionDeg = new Map();
  for (const er of edgeRecs.values()) {
    if (!between(er)) continue;
    unionDeg.set(er.a, (unionDeg.get(er.a) || 0) + 1);
    unionDeg.set(er.b, (unionDeg.get(er.b) || 0) + 1);
  }
  const alive = new Set();
  let beat = 0, offset = 0, baseTotals = { note: 0, code: 0 };
  for (const s of visible) {
    if (s.before) baseTotals = s.totals;
    else if (startAt > 0 && !offset) { beat += GLOW_BEATS + 3; offset = beat; } // past every flash and glow
    s.b = beat;
    const order = birthOrder(s.born, s.linkAdd, alive, unionDeg);
    // One at a time (Matt, 20 Oct 2026: "only one file or folder or link happened at a time... a set
    // amount of time before the next one"): each edit, then each new note followed by the links it
    // can make now, gets its own slot, so a big commit takes as long as what's in it.
    let slot = null;
    if (steady) {
      slot = new Map();
      let k = 0;
      const up = new Set(alive), by = new Map();
      for (const l of s.linkAdd) for (const r of [l.er.a, l.er.b]) { if (!by.has(r)) by.set(r, []); by.get(r).push(l); }
      const ready = (ls) => { for (const l of ls || []) if (!slot.has(l) && up.has(l.er.a) && up.has(l.er.b)) slot.set(l, k++); };
      for (const r of s.edited) slot.set(r, k++);
      ready(s.linkAdd);
      for (const r of order) { slot.set(r, k++); up.add(r); ready(by.get(r)); }
      for (const l of s.linkAdd) if (!slot.has(l)) slot.set(l, k++);
      s.span = 1 + STEADY_BEATS * k;
    } else s.span = 1 + Math.min(14, 0.12 * s.born.length) + Math.min(2, 0.012 * s.linkAdd.length);
    const at = (x) => 0.1 + STEADY_BEATS * slot.get(x);
    beat += s.span;
    const touched = [...s.born, ...s.edited].filter((r) => r.kind === 'note').length;
    const flags = (MATT_EDIT.test(s.subject) ? EDIT_MATT : 0) | (BOT_AUTHOR.test(s.author) || touched > SWEEP_NOTES ? EDIT_QUIET : 0);

    const bornAt = new Map();
    order.forEach((r, k) => {
      const off = slot ? at(r) : 0.1 + (order.length > 1 ? (s.span - 1) * k / order.length : 0);
      bornAt.set(r, off);
      r.bspans.push({ b: s.b + off, d: Infinity, t: s.t, f: flags });
    });
    for (const r of s.born) alive.add(r);
    for (const r of s.edited) { r.bedits.push(s.b + (slot ? at(r) : 0.05)); r.eflags.push(flags); r.etimes.push(s.t); }
    s.linkAdd.forEach((l, k) => {
      const { er, src } = l, oa = bornAt.get(er.a), ob = bornAt.get(er.b);
      const off = slot ? at(l) : oa != null || ob != null
        ? Math.max(oa || 0, ob || 0) + 0.18
        : 0.12 + 0.45 * k / Math.max(1, s.linkAdd.length);
      er.spans.push({ b: s.b + off, d: Infinity, src: src.node, t: s.t, f: flags });
    });
    for (const er of s.linkDel) er.spans[er.spans.length - 1].d = s.b + 0.1;
    for (const r of s.died) { r.bspans[r.bspans.length - 1].d = s.b + 0.15; alive.delete(r); }
  }

  if (offset) {
    for (const s of visible) s.b -= offset;
    for (const r of nodeRecs) {
      for (const sp of r.bspans) { sp.b -= offset; sp.d -= offset; }
      r.bedits = r.bedits.map((b) => b - offset);
    }
    for (const er of edgeRecs.values()) for (const sp of er.spans) { sp.b -= offset; sp.d -= offset; }
    beat -= offset;
  }

  return {
    head,
    baseTotals,
    steps: visible.filter((s) => !s.before).map((s) => ({
      sha: s.sha, t: s.t, author: s.author, subject: s.subject, merge: s.merge,
      b: s.b, span: s.span, add: s.add, del: s.del, totals: s.totals,
    })),
    nodes: nodeRecs.map((r) => ({
      key: r.paths[0], path: r.path,
      spans: r.bspans, edits: r.bedits, eflags: r.eflags, etimes: r.etimes,
    })),
    edges: [...edgeRecs.values()].filter((er) => er.spans.length && between(er)).map((er) => ({
      a: er.a.node, b: er.b.node, spans: er.spans,
      hub: HUBS.has(er.a.path) || HUBS.has(er.b.path), bridge: isBridge(er.a.path, er.b.path),
      list: inList(er.a.path) ? er.a.node : inList(er.b.path) ? er.b.node : -1,
    })),
    endBeat: beat,
  };
}

// The order new notes appear in within one commit: first the ones that link to
// notes already there, then outwards along the commit's new links, breadth first.
function birthOrder(born, linkAdd, alive, deg) {
  if (!born.length) return [];
  const bornSet = new Set(born);
  const adj = new Map(born.map((r) => [r, []]));
  const anchored = new Set();
  const d = (r) => deg.get(r) || 0;
  for (const { er } of linkAdd) {
    const ia = bornSet.has(er.a), ib = bornSet.has(er.b);
    if (ia && ib) { adj.get(er.a).push(er.b); adj.get(er.b).push(er.a); continue; }
    const [n, o] = ia ? [er.a, er.b] : ib ? [er.b, er.a] : [null, null];
    if (n && alive.has(o)) anchored.add(n);
  }
  const byDeg = (x, y) => d(y) - d(x) || x.id - y.id;
  const out = [], seen = new Set(), queue = [];
  let head = 0;
  const visit = (r) => { seen.add(r); out.push(r); queue.push(r); };
  const drain = () => {
    while (head < queue.length) {
      const u = queue[head++];
      for (const v of adj.get(u).slice().sort(byDeg)) if (!seen.has(v)) visit(v);
    }
  };
  for (const r of born.filter((x) => anchored.has(x)).sort(byDeg)) visit(r);
  drain();
  for (const r of born.slice().sort(byDeg)) if (!seen.has(r)) { visit(r); drain(); }
  return out;
}

/* ---------- layout ---------- */

// A folder's own note (README.md, SKILL.md or index.md) sits in the middle of its circle.
const FOLDER_NOTE = /^(readme|skill|index)\.md$/i;
const BUNDLE_BETA = 0.85;     // how tightly links bundle: 0 straight, 1 along the branches
const PULSE_BEATS = 0.9;      // how long a pulse takes from the core to a note

// The points a bundled link runs through: up the branches from one note to the folder both
// share, then down to the other, pulled a little straight (BUNDLE_BETA). So links bundle
// (Holten's hierarchical edge bundling, 2006), and a thousand read as a few flows between folders.
function bundlePoints(T, a, b, ax, ay, bx, by) {
  const ca = T.chain[a], cb = T.chain[b];
  if (!ca || !cb) return [[ax, ay], [bx, by]];
  const inB = new Set(cb);
  let k = 0;
  while (k < ca.length && !inB.has(ca[k])) k++;
  const lca = ca[Math.min(k, ca.length - 1)];
  const pts = [[ax, ay]];
  for (let i = 0; i < k; i++) pts.push([ca[i].x, ca[i].y]);
  pts.push([lca.x, lca.y]);
  const j = cb.indexOf(lca);
  for (let i = (j < 0 ? cb.length : j) - 1; i >= 0; i--) pts.push([cb[i].x, cb[i].y]);
  pts.push([bx, by]);
  const m = pts.length - 1;
  for (let i = 1; i < m; i++) {
    const s = i / m;
    pts[i] = [BUNDLE_BETA * pts[i][0] + (1 - BUNDLE_BETA) * (ax + (bx - ax) * s), BUNDLE_BETA * pts[i][1] + (1 - BUNDLE_BETA) * (ay + (by - ay) * s)];
  }
  return pts;
}

// The bubbles view (Matt, 20 Oct 2026): the core in the middle, and every folder holding more
// than one note pops out as its own circle (a balloon tree). A folder's own note sits at its
// circle's centre, its other notes round its rim, and the folders inside it pop out beyond the
// rim. A one-note folder stays a dot on its parent's rim, and a folder holding nothing but one
// folder is drawn as one circle with it. So is a folder holding only its own note and one folder,
// such as a skill's SKILL.md and its references/: the SKILL.md in the middle and the references
// round the rim (Matt, 20 Oct 2026: "just surround the skill ring"). Sizes come from what's
// inside, so the scene grows as folders fill.
//
// Room comes from what's really there: each circle keeps the outline of everything beyond it,
// so its neighbours sit just clear of it and folders inside folders add up rather than double.
// That, and the two libraries each sitting their own distance from the core, came after 700
// skills arrived in an hour and the skills wheel pushed everything out (Matt, 20 Oct 2026).
// A crowded rim gets rows of notes ("maybe every second one sits low"); a folder with lots of
// circles fills rows of the small ones one at a time, inside out, with the big ones further out,
// "so it's got more space to expand ... while the other ones are like closer in"; and a folder's
// first circles sit at least twice as far out as its rim, so the rim reads as "a core layer, but
// ... it's like still got space".
const BUB_LEAF = 7;    // space between notes on a rim, in layout units
const BUB_ROW = 6;     // space between rows of notes on a crowded rim
const BUB_RIM = 200;   // a rim that would be bigger than this round gets rows, up to four
const BUB_GAP = 24;    // space between a rim and the circles that pop out of it
const BUB_PAD = 10;    // space around each circle
const BUB_RING = 2;    // a folder's first circles sit at least this many times its rim out
const BUB_FILL = 0.75; // how far round its folder a fan of circles may spread, leaving the way back clear
const BUB_CROWD = 40;  // a folder with this many circles or more puts them in rows,
const BUB_BIG = 80;    // with circles reaching further than this past their middle beyond the rows
const BUB_STEP = 1.25;  // the libraries' distances from the core go up in steps this many times apart
const BUB_NEAR = 8;    // in a crowded folder, the neighbours each circle keeps its room from
const BUB_POP = 0.7;   // beats a new circle takes to travel out from its parent's middle to its seat
const BUB_MOVE = 1.2;  // seconds a circle takes to travel to a new seat when the layout moves it
const BUB_LISTS = 0.9; // a ring of lists sits this far out, against where its folder's rim would be without it
const BUB_FIRST = 48;  // circles in a crowded folder's first row
const BUB_MORE = 14;   // and how many more each row out holds
// Bubbles physics, per 60th of a second (bubbleStep).
// Each is how much of the way a rule puts things right per step: low, so things drift, not snap.
const BUB_STEM = 0.12;    // a stem back to its length
const BUB_SPREAD = 0.06;  // a folder's circles back to the room they have in the layout, round it like a ring
const BUB_FAN = 0.03;     // a circle that's folded past its folder's fan, back towards it
const BUB_BUMP = 0.5;     // other circles whose rims nearly touch, apart
const BUB_SPACE = 0.25;   // the notes on a ring, evenly round it
const BUB_HOLD = 0.05;    // times Hold shape: everything, back to its place
const wrapAngle = (v) => v - TAU * Math.round(v / TAU);

function bubbleLayout(model, skip) {
  const nodes = model.nodes, n = nodes.length;
  const mk = (name, parent) => ({ name, parent, path: parent && parent.path ? parent.path + '/' + name : name, kids: new Map(), notes: [], self: -1, count: 0, first: Infinity, born: Infinity });
  const root = mk('', null);
  for (let i = 0; i < n; i++) {
    const nd = nodes[i];
    if (skip && skip[i]) continue;
    const parts = nd.path.split('/');
    const file = parts.pop(), born = nd.spans.length ? nd.spans[0].b : 0;
    let f = root;
    f.count++;
    for (const p of parts) {
      if (!f.kids.has(p)) f.kids.set(p, mk(p, f));
      f = f.kids.get(p);
      f.count++;
      // When the folder got its second note, so became a circle: its age in a crowded folder's rows.
      if (born < f.first) { f.born = f.first; f.first = born; } else if (born < f.born) f.born = born;
    }
    if (f !== root && f.self < 0 && FOLDER_NOTE.test(file)) f.self = i; else f.notes.push(i);
  }
  const name = (i) => nodes[i].path.toLowerCase();
  // The commit a moment of the replay is in.
  const steps = model.steps || [];
  const stepOf = (t) => { let lo = 0, hi = steps.length; while (lo < hi) { const m = (lo + hi) >> 1; if (steps[m].b <= t) lo = m + 1; else hi = m; } return lo - 1; };
  const bubble = (folder, parent) => ({ folder, parent, leaves: [], kids: [], self: -1, x: 0, y: 0, rim: 0, rows: 1, ext: 0, depth: parent ? parent.depth + 1 : 0 });
  const top = bubble(root, null);
  const centre = [];
  const gather = (f, b) => {
    for (const i of f.notes) (b === top && f === root ? centre : b.leaves).push(i);
    if (f.self >= 0) { if (b.folder === f) b.self = f.self; else b.leaves.push(f.self); }
    // Its own note and one folder, and nothing else: that folder's notes go round this rim.
    const lone = b !== top && b.folder === f && f.self >= 0 && !f.notes.length && f.kids.size === 1;
    for (let k of [...f.kids.values()].sort((a, c) => (a.name < c.name ? -1 : 1))) {
      if (LIST_FOLDERS.has(k.path)) { const g = bubble(k, b); gather(k, g); b.mid = [...(g.self >= 0 ? [g.self] : []), ...g.leaves]; continue; }
      if (k.count < 2) { gather(k, b); continue; }
      while (!k.notes.length && k.self < 0 && k.kids.size === 1) k = k.kids.values().next().value;
      if (lone) { gather(k, b); continue; }
      const c = bubble(k, b); b.kids.push(c); gather(k, c);
    }
  };
  gather(root, top);
  // A circle's footprint (fp) is a disc [x, y, r] for its rim and for each circle beyond it, seen
  // from its middle with its stem coming in from the left (-x).
  const reach = (c, f) => c.fp.reduce((s, d) => Math.max(s, f(d)), 0);
  // The angles a circle's footprint covers either side of its stem, with the stem L long.
  const wedge = (c, L) => {
    let lo = Infinity, hi = -Infinity;
    for (let i = 0; i < c.fp.length; i++) {
      const d = c.fp[i], X = L + d[0], a = Math.atan2(d[1], X), h = Math.asin(Math.min(1, (d[2] + BUB_PAD) / Math.max(1e-6, Math.hypot(X, d[1]))));
      if (a - h < lo) lo = a - h;
      if (a + h > hi) hi = a + h;
    }
    return [lo, hi];
  };
  // The least t (pushing circles further out) at which span(t) fits round a folder.
  const fit = (span, A = TAU * BUB_FILL) => {
    if (span(0) <= A) return 0;
    let lo = 0, hi = 16;
    while (span(hi) > A && hi < 1e7) { lo = hi; hi *= 2; }
    for (let i = 0; i < 10; i++) { const t = (lo + hi) / 2; if (span(t) > A) lo = t; else hi = t; }
    return hi;
  };
  // Only a footprint's outline matters to the circles round it, so it keeps the discs furthest
  // out in each of 32 directions.
  const outline = (fp) => {
    if (fp.length <= 32) return fp;
    const keep = new Set();
    for (let j = 0; j < 32; j++) {
      const ux = Math.cos((j * TAU) / 32), uy = Math.sin((j * TAU) / 32);
      let best = null, m = -Infinity;
      for (const d of fp) { const v = d[0] * ux + d[1] * uy + d[2]; if (v > m) { m = v; best = d; } }
      keep.add(best);
    }
    return [...keep];
  };
  // Side by side round a folder, in name order, each L(k) out: where each sits, and how far
  // round they go between them.
  const side = (b, ks, L) => {
    const ang = new Map();
    let a = 0;
    for (const k of ks) { const w = wedge(b.kids[k], L(k)); a -= w[0]; ang.set(k, a); a += w[1]; }
    return { ang, span: a };
  };
  // Where a folder's circles go: each stem's length and angle (from straight out for a folder,
  // from the right for the core), with the footprint that makes and how far it reaches.
  const arrange = (b) => {
    const kids = b.kids, nk = kids.length, all = kids.map((c, k) => k);
    const near = kids.map((c) => reach(c, (d) => d[2] - d[0])), far = kids.map((c) => reach(c, (d) => d[0] + d[2]));
    const core = Math.max(b.rim, b.midR || 0); // its rim, or its ring of lists
    const clear = near.map((v) => core + BUB_GAP + v); // the shortest stem that's clear of the rim
    // Lay a try out, and see how far it reaches.
    const lay = (c) => {
      const fp = [[0, 0, core]];
      kids.forEach((kid, k) => {
        const a = c.ang[k], L = c.len[k], cs = Math.cos(a), sn = Math.sin(a);
        for (const [x, y, r] of kid.fp) fp.push([L * cs + x * cs - y * sn, L * sn + x * sn + y * cs, r]);
      });
      return Object.assign(c, { fp, ext: fp.reduce((s, [x, y, r]) => Math.max(s, Math.hypot(x, y) + r), 0) });
    };
    if (b === top && nk <= 3) {
      // The libraries face each other, the biggest as close in as it can be in its own part of the
      // circle, and the others twice as far out as that, with room to grow (Matt, 20 Oct 2026: the
      // knowledge base "like double the distance that Claude and README are from the skills README").
      const len = all.map((k) => clear[k] + fit((t) => { const [lo, hi] = wedge(kids[k], clear[k] + t); return 2 * Math.max(-lo, hi) * nk * BUB_FILL; }));
      // Each library's own size sets how far out it sits, so one growing doesn't push the other away
      // (Matt, 20 Oct 2026: "each one in size dictates how far away they are from the core").
      const far = all.map((k) => Math.max(len[k], kids[k].ext));
      // In steps, so the libraries hold still while they grow, and jump out a step at a time (Matt,
      // 20 Oct 2026: "when the skills base gets to a certain size, then it jumps up to the next distance").
      const step = (L) => 100 * BUB_STEP ** Math.ceil(Math.log(Math.max(L, 100) / 100) / Math.log(BUB_STEP));
      return lay({ ang: all.map((k) => -Math.PI / 2 + (k * TAU) / nk), len: far.map(step) });
    }
    const first = Math.max(b.firstAt, ...clear);
    // All round one ring.
    const ring = () => {
      const t = fit((t) => side(b, all, () => first + t).span), s = side(b, all, () => first + t);
      const gap = b === top ? (TAU - s.span) / nk : Math.min((TAU - s.span) / nk, 0.12);
      const shift = b === top ? -Math.PI / 2 : -(s.span + gap * (nk - 1)) / 2;
      return { len: all.map(() => first + t), ang: all.map((k) => s.ang.get(k) + shift + k * gap) };
    };
    // Crowded (Matt, 20 Oct 2026: "building out a full row first and then another row outside of
    // that", filling "from say like 12 to 1 o'clock... and then everything else just gets pushed
    // closer and closer together... clockwise of it"). The small circles fill rows one at a time,
    // inside out, oldest first (by when each became a circle), BUB_FIRST in the first row and
    // BUB_MORE more in each row out, so which row a circle is in never depends on anything but its
    // age, and a full row doesn't change. Each row sits as close in as its circles fit. A row's
    // circles go all the way round it: the newest commit's where the stem comes in (12 o'clock on
    // the skills wheel), in the order they came, and the older ones on clockwise from there, closer
    // together each time some arrive. The big circles go round their own ring beyond the rows, the
    // same way. (Until 20 Oct 2026 the small circles were dealt into staggered rows in name order,
    // so each new one moved every circle after it to another row; then, for a few hours, a row held
    // as many as fitted, so a growing rim re-dealt the rows.)
    const rows = () => {
      const sm = all.filter((k) => far[k] <= BUB_BIG), bg = all.filter((k) => far[k] > BUB_BIG);
      const born = (k) => kids[k].folder.born, path = (k) => kids[k].folder.path;
      const width = (k, R) => { const w = wedge(kids[k], R); return w[1] - w[0]; };
      sm.sort((p, q) => born(p) - born(q) || (path(p) < path(q) ? -1 : 1));
      const rings = [];
      for (let j = 0, r = 0; j < sm.length; r++) {
        const ks = sm.slice(j, j + BUB_FIRST + r * BUB_MORE), prev = rings[r - 1];
        j += ks.length;
        const inner = prev ? prev.R + prev.out + BUB_PAD : core + BUB_GAP;
        const R0 = Math.max(inner + Math.max(...ks.map((k) => near[k])), prev ? 0 : b.firstAt);
        const R = R0 + fit((t) => ks.reduce((u, k) => u + width(k, R0 + t), 0), TAU);
        rings.push({ R, ks, out: Math.max(...ks.map((k) => far[k])) });
      }
      // All the way round, evenly, starting where the stem comes in and going clockwise.
      const newest = (p, q) => stepOf(born(q)) - stepOf(born(p)) || born(p) - born(q) || (path(p) < path(q) ? -1 : 1);
      const len = new Array(nk), ang = new Array(nk);
      const round = (ks, L) => {
        ks.sort(newest);
        const w = ks.map((k) => wedge(kids[k], L(k))), gap = (TAU - w.reduce((t, v) => t + v[1] - v[0], 0)) / ks.length;
        let a = Math.PI;
        ks.forEach((k, j) => { if (j) a += w[j - 1][1] + gap - w[j][0]; len[k] = L(k); ang[k] = a; });
      };
      for (const ring of rings) round(ring.ks, () => ring.R);
      if (bg.length) {
        const last = rings[rings.length - 1], edge = last ? last.R + last.out + BUB_PAD : 0;
        const L = (u) => (k) => Math.max(clear[k], edge + near[k]) + u;
        round(bg, L(fit((u) => side(b, bg, L(u)).span, TAU * 0.97)));
      }
      return { len, ang };
    };
    return lay(b !== top && nk >= BUB_CROWD ? rows() : ring());
  };
  const size = (b) => {
    b.leaves.sort((a, c) => (name(a) < name(c) ? -1 : 1));
    for (const c of b.kids) size(c);
    const m = b.leaves.length;
    b.rim = b === top ? 14 : Math.max(10, (m * BUB_LEAF) / TAU);
    while (b !== top && b.rim > BUB_RIM && b.rows < 4) { b.rows++; b.rim = (m * BUB_LEAF) / (TAU * b.rows) + (b.rows - 1) * BUB_ROW; }
    b.firstAt = b.rim * BUB_RING;
    if (b.mid) {
      // A folder of lists (skills): the lists in a ring a little inside where its rim would be, and
      // its rim, rows and all, out where the lists would be, so its notes have a little more room
      // round it; its circles stay where they'd be (Matt, 20 Oct 2026: the lists as "the inner
      // circle inside of the first skills row", the skills "slightly spaced out slightly", and "I
      // don't need it to be a single ring"). Until then the lists sat outside the rim.
      b.mid.sort((a, c) => (name(a) < name(c) ? -1 : 1));
      const out = Math.max(b.rim * 1.5, b.rim + BUB_GAP, (b.mid.length * BUB_LEAF) / TAU);
      b.midR = Math.max(20, b.rim * BUB_LISTS, (b.mid.length * BUB_LEAF) / TAU);
      b.rim = Math.max(out, b.midR + BUB_GAP + (b.rows - 1) * BUB_ROW);
    }
    b.lay = b.kids.length ? arrange(b) : { len: [], ang: [], fp: [[0, 0, b.midR || b.rim]], ext: b.midR || b.rim };
    b.fp = outline(b.lay.fp); b.ext = b.lay.ext;
  };
  size(top);
  const x = new Float64Array(n), y = new Float64Array(n), chain = new Array(n).fill(null), all = [];
  const place = (b, bx, by, out) => {
    b.x = bx; b.y = by; all.push(b);
    const up = [];
    for (let g = b; g; g = g.parent) up.push(g);
    const m = b.leaves.length;
    b.leaves.forEach((i, k) => {
      // Evenly round the rim; on a crowded one, every second note a row in.
      const a = out + Math.PI + ((k + 0.5) / m) * TAU, r = b.rim - (k % b.rows) * BUB_ROW;
      x[i] = bx + r * Math.cos(a); y[i] = by + r * Math.sin(a); chain[i] = up;
    });
    if (b.self >= 0) { x[b.self] = bx; y[b.self] = by; chain[b.self] = up; }
    if (b.mid) b.mid.forEach((i, k) => {
      const a = out + Math.PI + ((k + 0.5) / b.mid.length) * TAU;
      x[i] = bx + b.midR * Math.cos(a); y[i] = by + b.midR * Math.sin(a); chain[i] = up;
    });
    b.kids.forEach((c, k) => {
      const a = (b === top ? 0 : out) + b.lay.ang[k], L = b.lay.len[k];
      place(c, bx + L * Math.cos(a), by + L * Math.sin(a), a);
    });
  };
  place(top, 0, 0, -Math.PI / 2);
  centre.forEach((i, k) => { x[i] = 0; y[i] = k * 12; chain[i] = [top]; });
  // For the physics (bubbleStep): x and y are where a circle is now, hx and hy its place in the
  // layout, len its stem's length, fan how far round it sits from straight out along its parent's
  // stem, and it's as heavy as the notes it holds, out to its far circles.
  for (const b of all) {
    const p = b.parent, g = p && p.parent;
    b.key = b.folder.path; b.hx = b.x; b.hy = b.y; b.vx = 0; b.vy = 0; b.kin = new Set();
    b.len = p ? Math.hypot(b.x - p.x, b.y - p.y) : 0;
    b.fan = g ? wrapAngle(Math.atan2(b.y - p.y, b.x - p.x) - Math.atan2(p.y - g.y, p.x - g.x)) : 0;
    b.mass = Math.max(1, b.folder.count);
    b.fp = b.lay = null;
  }
  // The pairs in a folder that keep the room the layout gives them: every pair in a small folder,
  // each circle and its nearest few in a crowded one.
  const pairs = [];
  const pair = (a, c) => { if (a.kin.has(c)) return; a.kin.add(c); c.kin.add(a); pairs.push([a, c, Math.hypot(c.hx - a.hx, c.hy - a.hy)]); };
  for (const b of all) {
    const ks = b.kids;
    if (ks.length < BUB_CROWD) { for (let i = 0; i < ks.length; i++) for (let j = i + 1; j < ks.length; j++) pair(ks[i], ks[j]); continue; }
    // The nearest are among the dozen or so either side of it round the folder.
    const round = ks.map((c) => [c, Math.atan2(c.hy - b.hy, c.hx - b.hx)]).sort((p, q) => p[1] - q[1]).map((p) => p[0]), m = round.length;
    round.forEach((a, i) => {
      const by = [];
      for (let j = 1; j <= 12; j++) for (const c of [round[(i + j) % m], round[(i + m - j) % m]]) by.push([c, (c.hx - a.hx) ** 2 + (c.hy - a.hy) ** 2]);
      by.sort((p, q) => p[1] - q[1]);
      for (const [c] of by.slice(0, BUB_NEAR)) pair(a, c);
    });
  }
  return { x, y, chain, folders: all, pairs, root: top, folderOf: chain.map((c) => (c ? c[0] : null)) };
}

// A uniform cubic B-spline through the points (as d3's curveBasis draws it).
function traceBasis(ctx, pts) {
  const n = pts.length;
  ctx.moveTo(pts[0][0], pts[0][1]);
  if (n === 2) { ctx.lineTo(pts[1][0], pts[1][1]); return; }
  let [x0, y0] = pts[0], [x1, y1] = pts[1];
  ctx.lineTo((5 * x0 + x1) / 6, (5 * y0 + y1) / 6);
  for (let i = 2; i < n; i++) {
    const [x, y] = pts[i];
    ctx.bezierCurveTo((2 * x0 + x1) / 3, (2 * y0 + y1) / 3, (x0 + 2 * x1) / 3, (y0 + 2 * y1) / 3, (x0 + 4 * x1 + x) / 6, (y0 + 4 * y1 + y) / 6);
    x0 = x1; y0 = y1; x1 = x; y1 = y;
  }
  ctx.bezierCurveTo((2 * x0 + x1) / 3, (2 * y0 + y1) / 3, (x0 + 2 * x1) / 3, (y0 + 2 * y1) / 3, x1, y1);
}

/* ---------- the view ---------- */

const ICONS = {
  play: '<path d="M8 5.5v13a.6.6 0 0 0 .9.5l10.4-6.5a.6.6 0 0 0 0-1L8.9 5a.6.6 0 0 0-.9.5z" fill="currentColor" stroke="none"/>',
  pause: '<rect x="7" y="5.5" width="3.2" height="13" rx="1" fill="currentColor" stroke="none"/><rect x="13.8" y="5.5" width="3.2" height="13" rx="1" fill="currentColor" stroke="none"/>',
  replay: '<path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1"/><path d="M3.5 4v4.5H8"/>',
  fit: '<path d="M4 9V6a2 2 0 0 1 2-2h3M15 4h3a2 2 0 0 1 2 2v3M20 15v3a2 2 0 0 1-2 2h-3M9 20H6a2 2 0 0 1-2-2v-3"/>',
  settings: '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>',
  list: '<path d="M9 6.5h11M9 12h11M9 17.5h11"/><circle cx="4.75" cy="6.5" r="1.1" fill="currentColor" stroke="none"/><circle cx="4.75" cy="12" r="1.1" fill="currentColor" stroke="none"/><circle cx="4.75" cy="17.5" r="1.1" fill="currentColor" stroke="none"/>',
};

function el(parent, tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  if (parent) parent.appendChild(e);
  return e;
}

function setIconSvg(button, name) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('fill', 'none');
  svg.setAttribute('stroke', 'currentColor');
  svg.setAttribute('stroke-width', '1.7');
  svg.setAttribute('stroke-linecap', 'round');
  svg.setAttribute('stroke-linejoin', 'round');
  // Static markup from ICONS above, never from notes or git.
  svg.innerHTML = ICONS[name];
  while (button.firstChild) button.removeChild(button.firstChild);
  button.appendChild(svg);
}

function iconButton(parent, name, label, onClick) {
  const b = el(parent, 'button', 'bg-icon');
  b.setAttribute('aria-label', label);
  b.title = label;
  setIconSvg(b, name);
  b.addEventListener('click', (e) => { e.stopPropagation(); onClick(e); });
  return b;
}

const fmtNum = (n) => Math.round(n).toLocaleString();
const fmtShort = (n) => (n >= 10000 ? Math.round(n / 1000) + 'k' : n >= 1000 ? (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : String(n));
const fmtWhen = (t) => new Date(t * 1000).toLocaleString(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
const fmtStamp = (t) => new Date(t * 1000).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
const fmtDay = (t) => new Date(t * 1000).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
const noteName = (path) => path.replace(/\.md$/i, '');

// The error function (Abramowitz and Stegun 7.1.26), for blurring the activity curve.
function erf(x) {
  const s = x < 0 ? -1 : 1;
  x = Math.abs(x);
  const t = 1 / (1 + 0.3275911 * x);
  return s * (1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x));
}

// Activity along the replay, 0 to 1: each commit's lines touched (added plus
// removed), on a log scale so one huge commit doesn't flatten the rest, spread
// over the commit's stretch of the timeline and blurred into a smooth curve.
function activityCurve(steps, endBeat, samples) {
  const out = new Float32Array(samples);
  if (!endBeat) return out;
  const sigma = Math.max(0.7, endBeat * 0.018), k = 1 / (sigma * Math.SQRT2);
  for (const s of steps) {
    const v = s.merge ? 0 : Math.log1p(s.add.note + s.add.code + s.del.note + s.del.code);
    if (!v) continue;
    const a = s.b, b = s.b + s.span;
    const i0 = Math.max(0, Math.floor(((a - 4 * sigma) / endBeat) * (samples - 1)));
    const i1 = Math.min(samples - 1, Math.ceil(((b + 4 * sigma) / endBeat) * (samples - 1)));
    for (let i = i0; i <= i1; i++) {
      const x = (i / (samples - 1)) * endBeat;
      out[i] += v * 0.5 * (erf((b - x) * k) - erf((a - x) * k));
    }
  }
  let max = 0;
  for (const v of out) if (v > max) max = v;
  if (max > 0) for (let i = 0; i < samples; i++) out[i] /= max;
  return out;
}

class BrainView extends ItemView {
  constructor(leaf, plugin) {
    super(leaf);
    this.plugin = plugin;
    this.model = null;
    this.git = null;
    this.tau = 0;
    this.tauTarget = null;
    this.playing = false;
    this.cam = { x: 0, y: 0, k: 1 };
    this.autoCam = true;
    this.camReady = false;
    this.hover = -1;
    this.chartHover = -1;
    this.dragNode = -1;
    this.wheelAcc = 0;
    this.listOpen = false;
    this.raf = 0;
    this.lastNow = 0;
    this.size = { w: 0, h: 0 };
    this.chartSize = { w: 0, h: 0 };
    this.dpr = 1;
    this.hudCache = {};
  }

  getViewType() { return VIEW_TYPE; }
  getDisplayText() { return 'Brain graph'; }
  getIcon() { return 'brain-circuit'; }

  get settings() { return this.plugin.settings; }

  async onOpen() {
    this.buildDom();
    this.applyTheme();
    this.registerEvent(this.app.workspace.on('css-change', () => { this.applyTheme(); this.buildSettings(); this.requestFrame(); }));
    this.registerInterval(window.setInterval(() => this.checkForNewCommits(), POLL_MS));
    await this.load(true);
  }

  async onClose() {
    this.closed = true;
    if (this.raf) cancelAnimationFrame(this.raf);
    this.raf = 0;
    if (this.resizeObserver) this.resizeObserver.disconnect();
  }

  onResize() { this.resize(); }

  /* ----- loading ----- */

  async load(initial) {
    if (this.loading) return;
    this.loading = true;
    if (initial) this.setStatus('Reading the brain’s history…');
    try {
      if (!this.git) {
        const adapter = this.app.vault.adapter;
        if (!adapter || typeof adapter.getBasePath !== 'function') throw new Error('The brain graph needs Obsidian on a computer.');
        this.git = await Git.open(adapter.getBasePath());
        this.prefix = (await this.git.text(['rev-parse', '--show-prefix'])).trim();
      }
      const prev = this.model, prevSim = this.sim;
      this.excluded = await this.readExcluded();
      const model = await readModel(this.git, this.settings.startFrom, this.settings.steady);
      if (this.closed) return;
      const wasAtEnd = prev && this.tau >= prev.endBeat - 0.01;
      this.model = model;
      this.focus = this.focusFor(model);
      this.layoutSig = null;
      this.allocate();
      if (prev && prevSim) {
        // Dots keep where the physics had them.
        const old = new Map(prev.nodes.map((nd, i) => [nd.key, i]));
        model.nodes.forEach((nd, i) => {
          const j = old.get(nd.key);
          if (j == null) return;
          this.sim.x[i] = prevSim.x[j]; this.sim.y[i] = prevSim.y[j];
          this.sim.was[i] = prevSim.was[j];
        });
      }
      if (initial || !prev) {
        this.tau = this.settings.replayOnOpen ? 0 : model.endBeat + SETTLE;
        this.playing = this.settings.replayOnOpen;
        this.camReady = false;
      } else if (wasAtEnd && model.endBeat > prev.endBeat) {
        // New commits while watching the latest state: play them in.
        this.tau = Math.min(this.tau, prev.endBeat);
        this.playing = true;
      }
      this.tauTarget = null;
      this.hover = -1;
      this.dragNode = -1;
      this.curve = null;
      this.buildList();
      this.buildSettings();
      this.setStatus(model.steps.length ? null : 'No notes in the history yet.');
      this.updatePlayButton();
    } catch (e) {
      console.error('Brain graph:', e);
      if (!this.model) this.setStatus('Couldn’t read the brain’s git history. ' + (e && e.message ? e.message : e));
    } finally {
      this.loading = false;
    }
    this.requestFrame();
  }

  // Obsidian's Excluded files setting (Settings → Files and links), so the brain
  // graph can leave out the same notes as Obsidian's own graph.
  async readExcluded() {
    let f = null;
    try { f = this.app.vault.getConfig && this.app.vault.getConfig('userIgnoreFilters'); } catch { f = null; }
    if (!Array.isArray(f)) {
      try { f = JSON.parse(await this.app.vault.adapter.read((this.app.vault.configDir || '.obsidian') + '/app.json')).userIgnoreFilters; } catch { f = null; }
    }
    return Array.isArray(f) ? f : [];
  }

  // What the Focus settings mean for this model: which links are drawn all the time
  // (hidden hub links, skill links on hover and the lists' links aren't), and which
  // dots are left out.
  focusFor(model) {
    const set = this.settings, pre = this.prefix || '';
    const vaultPath = (p) => (pre && p.startsWith(pre) ? p.slice(pre.length) : p);
    return {
      shown: Uint8Array.from(model.edges, (e) => ((e.bridge && set.bridges === 'hover') || e.list >= 0 || (e.hub && set.hubLinks === 'hide') ? 0 : 1)),
      hidden: Uint8Array.from(model.nodes, (nd) => (set.hideExcluded && excludedBy(this.excluded || [], vaultPath(nd.path)) ? 1 : 0)),
    };
  }

  // A Focus setting changed: lay the circles out again for the notes now showing.
  applyFocus() {
    if (!this.model || !this.sim) return;
    this.focus = this.focusFor(this.model);
    this.layoutSig = null;
    this.autoCam = true;
    this.requestFrame();
  }

  async checkForNewCommits() {
    if (!this.git || !this.model || this.loading || this.closed) return;
    try {
      const head = (await this.git.text(['rev-parse', 'HEAD'])).trim();
      if (head !== this.model.head) await this.load(false);
    } catch { /* try again next time */ }
  }

  allocate() {
    const nodes = this.model.nodes, n = nodes.length, m = this.model.edges.length;
    this.ns = {
      on: new Uint8Array(n), s: new Float32Array(n), a: new Float32Array(n), born: new Float32Array(n),
      edit: new Float32Array(n), glow: new Float32Array(n), dying: new Uint8Array(n), deg: new Int32Array(n),
      sx: new Float32Array(n), sy: new Float32Array(n), r: new Float32Array(n),
      bornF: new Uint8Array(n), editF: new Uint8Array(n), glowF: new Uint8Array(n), touch: new Float64Array(n),
    };
    this.es = {
      p: new Float32Array(m), a: new Float32Array(m), flash: new Float32Array(m), src: new Int32Array(m), live: new Uint8Array(m),
      f: new Uint8Array(m), m: new Float32Array(m),
    };
    this.adj = nodes.map(() => []);
    this.model.edges.forEach((e, j) => { this.adj[e.a].push(j); this.adj[e.b].push(j); });
    // Where each dot actually is. It starts at its place in the layout, then physics and dragging move it.
    this.sim = { x: new Float64Array(n), y: new Float64Array(n), was: new Uint8Array(n), ride: new Uint8Array(n), fx: 0, fy: 0 };
  }

  /* ----- the DOM ----- */

  buildDom() {
    const root = this.contentEl;
    while (root.firstChild) root.removeChild(root.firstChild);
    root.classList.add('brain-graph');
    root.setAttribute('tabindex', '0');
    this.root = root;

    this.canvas = el(root, 'canvas', 'bg-canvas');
    this.ctx = this.canvas.getContext('2d');

    const hud = el(root, 'div', 'bg-hud');
    const stats = el(hud, 'div', 'bg-stats');
    this.statEls = {};
    for (const [key, label] of [['notes', 'Notes'], ['links', 'Links'], ['lines', 'Lines']]) {
      const s = el(stats, 'div', 'bg-stat');
      this.statEls[key] = el(s, 'div', 'bg-stat-value', '0');
      el(s, 'div', 'bg-stat-label', label);
    }

    const tools = el(root, 'div', 'bg-tools');
    this.gearBtn = iconButton(tools, 'settings', 'Options', () => this.toggleSettings());
    this.panel = el(root, 'div', 'bg-panel');
    this.buildSettings();

    this.tip = el(root, 'div', 'bg-tip');
    this.statusEl = el(root, 'div', 'bg-status');

    // The timeline box: the commit navigator (opens upwards), what's playing, and the activity curve.
    const dock = el(root, 'div', 'bg-dock');
    this.dock = dock;
    this.list = el(dock, 'div', 'bg-list');
    this.list.addEventListener('pointerenter', () => { this.listHovered = true; });
    this.list.addEventListener('pointerleave', () => { this.listHovered = false; });
    const bar = el(dock, 'div', 'bg-bar');
    this.playBtn = iconButton(bar, 'play', 'Play (space)', () => this.togglePlay());
    this.playBtn.classList.add('bg-play');
    const now = el(bar, 'div', 'bg-now');
    this.nowTitle = el(now, 'div', 'bg-now-title');
    this.nowMeta = el(now, 'div', 'bg-now-meta');
    // Recentre (Matt, 20 Oct 2026: "a button... on the navigator down bottom"): the camera follows the
    // brain again as it moves and grows. It's lit while the camera is following.
    this.fitBtn = iconButton(bar, 'fit', 'Recentre: follow the brain as it moves and grows (F)', () => { this.autoCam = true; this.requestFrame(); });
    this.listBtn = iconButton(bar, 'list', 'Commits', () => this.toggleList());
    this.speedBtn = el(bar, 'button', 'bg-speed');
    this.speedBtn.title = 'Replay speed';
    this.speedBtn.addEventListener('click', () => {
      const i = SPEEDS.indexOf(this.settings.speed);
      this.settings.speed = SPEEDS[(i + 1) % SPEEDS.length];
      this.saveSettings();
    });
    this.chartWrap = el(dock, 'div', 'bg-chart');
    this.chart = el(this.chartWrap, 'canvas', 'bg-chart-canvas');
    this.cctx = this.chart.getContext('2d');
    this.chartTip = el(dock, 'div', 'bg-tip bg-chart-tip');

    this.bindGraphEvents();
    this.bindChartEvents();
    root.addEventListener('keydown', (e) => this.onKey(e));
    root.addEventListener('pointerdown', (e) => {
      if (this.panel.classList.contains('is-open') && !this.panel.contains(e.target) && !this.gearBtn.contains(e.target)) this.toggleSettings(false);
    });
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(root);
    this.resize();
    this.updateSpeed();
  }

  buildSettings() {
    const p = this.panel, set = this.settings;
    while (p.firstChild) p.removeChild(p.firstChild);
    const section = (title) => el(p, 'div', 'bg-section', title);
    const row = (label) => { const r = el(p, 'div', 'bg-row'); el(r, 'div', 'bg-row-label', label); return el(r, 'div', 'bg-row-control'); };
    const segmented = (parent, options, value, onPick) => {
      const seg = el(parent, 'div', 'bg-seg');
      for (const [v, label] of options) {
        const b = el(seg, 'button', v === value ? 'is-on' : '', label);
        b.addEventListener('click', () => onPick(v));
      }
    };
    const toggle = (label, hint, key, after) => {
      const t = el(p, 'div', 'bg-toggle');
      const text = el(t, 'div', 'bg-toggle-text');
      el(text, 'div', 'bg-toggle-label', label);
      if (hint) el(text, 'div', 'bg-toggle-hint', hint);
      const sw = el(t, 'button', 'bg-switch' + (set[key] ? ' is-on' : ''));
      sw.setAttribute('role', 'switch');
      sw.setAttribute('aria-checked', String(!!set[key]));
      el(sw, 'span', 'bg-knob');
      t.addEventListener('click', () => { set[key] = !set[key]; if (after) after(); this.saveSettings(); });
    };
    const slider = (label, key, min, max, step) => {
      const r = el(p, 'div', 'bg-row bg-row-slider');
      el(r, 'div', 'bg-row-label', label);
      const input = el(r, 'input', 'bg-slider');
      Object.assign(input, { type: 'range', min, max, step, value: set[key] });
      input.addEventListener('input', () => { set[key] = Number(input.value); this.wake(); });
      input.addEventListener('change', () => this.plugin.saveSettings());
    };

    section('Look');
    segmented(row('Theme'), [['auto', 'Auto'], ['dark', 'Dark'], ['light', 'Light']], set.theme, (v) => { set.theme = v; this.saveSettings(); });
    const sw = el(row('Accent'), 'div', 'bg-swatches');
    for (const [key, acc] of Object.entries(ACCENTS)) {
      const b = el(sw, 'button', 'bg-accent' + (key === set.accent ? ' is-on' : ''));
      b.title = acc.name;
      b.setAttribute('aria-label', acc.name);
      b.style.setProperty('--swatch', this.isDark() ? acc.dark : acc.light);
      b.addEventListener('click', () => { set.accent = key; this.saveSettings(); });
    }

    section('Replay');
    segmented(row('Speed'), SPEEDS.map((s) => [s, speedLabel(s)]), set.speed, (v) => { set.speed = v; this.saveSettings(); });
    const fresh = this.model && this.model.freshStart;
    segmented(row('Start from'), [['fresh', fresh ? 'Fresh start, ' + fmtDay(fresh.t) : 'Fresh start'], ['beginning', 'The beginning']], set.startFrom, (v) => {
      if (v === set.startFrom) return;
      set.startFrom = v;
      this.saveSettings();
      this.load(true);
    });
    if (this.model && !fresh) el(p, 'div', 'bg-toggle-hint', 'No fresh start yet, so the replay starts at the beginning.');
    toggle('One at a time', 'Each new note, link and edit gets its own moment, the same time apart, so the brain grows steadily instead of in bursts. Big commits take as long as what’s in them; Speed sets the pace.', 'steady', () => this.load(true));
    toggle('Replay when opened', null, 'replayOnOpen');

    section('Focus');
    segmented(row('Hub links'), [['show', 'Show'], ['faint', 'Faint'], ['hide', 'Hide']], set.hubLinks, (v) => {
      if (v === set.hubLinks) return;
      set.hubLinks = v; this.applyFocus(); this.saveSettings();
    });
    el(p, 'div', 'bg-toggle-hint', 'Links to the notes nearly every note points at: the core (CLAUDE.md) and the README, and in a replay of the old layout, connections.md, the decisions table, the brain structure and HQ’s progress.');
    segmented(row('Skill links'), [['hover', 'On hover'], ['show', 'Always']], set.bridges, (v) => {
      if (v === set.bridges) return;
      set.bridges = v; this.applyFocus(); this.saveSettings();
    });
    el(p, 'div', 'bg-toggle-hint', 'Links between a skill and a knowledge note. On hover, they show only while you point at either end.');
    segmented(row('Fade old links'), [[0, 'Off'], [7, '1 wk'], [14, '2 wks'], [30, '1 mo']], set.fadeDays, (v) => { set.fadeDays = v; this.saveSettings(); });
    el(p, 'div', 'bg-toggle-hint', 'A link dims once neither of its notes has been edited for that long, and lights up again when one is.');
    toggle('Hide excluded notes', 'The notes Obsidian’s Excluded files setting hides from its own graph, such as the history/ folders.', 'hideExcluded', () => this.applyFocus());
    const mk = set.accent === 'cyan' ? 'coral' : 'cyan';
    toggle('Your edits in their own colour', 'Commits named “My edits in Obsidian” light up in ' + ACCENTS[mk].name.toLowerCase() + '.', 'markMatt');
    toggle('Quieter bots and big sweeps', 'Commits by the repo’s own Actions, and commits touching more than ' + SWEEP_NOTES + ' notes, flash softly, leave no afterglow, and don’t keep links from fading.', 'quiet');

    section('Bubbles');
    toggle('Physics', 'Drag a dot and its circle comes with it, and everything beyond trails behind on stems of set lengths; each folder’s notes stay evenly round its ring, and folders bump rather than overlap. Hold shape sets how strongly things go back to their places; at the lowest, they stay where you leave them. Off: circles glide to their places.', 'physics', () => {
      if (this.sim) { this.sim.ride.fill(0); this.wake(); }
    });
    if (set.physics) slider('Hold shape', 'hold', 0, 0.3, 0.005);
  }

  buildList() {
    const list = this.list;
    while (list.firstChild) list.removeChild(list.firstChild);
    this.rows = this.model.steps.map((s, i) => {
      const r = el(list, 'button', 'bg-commit');
      el(r, 'span', 'bg-commit-time', fmtStamp(s.t));
      el(r, 'span', 'bg-commit-subject', s.subject);
      el(r, 'span', 'bg-commit-lines', s.merge ? 'merge' : `+${fmtShort(s.add.note + s.add.code)} −${fmtShort(s.del.note + s.del.code)}`);
      r.title = `${s.author} · ${fmtWhen(s.t)}`;
      r.addEventListener('click', () => this.goToStep(i));
      r.addEventListener('pointerenter', () => { this.chartHover = i; this.requestFrame(); });
      r.addEventListener('pointerleave', () => { if (this.chartHover === i) { this.chartHover = -1; this.requestFrame(); } });
      return r;
    });
    this.listCurrent = -2;
  }

  toggleList(force) {
    this.listOpen = force != null ? force : !this.listOpen;
    this.dock.classList.toggle('is-list-open', this.listOpen);
    this.listBtn.classList.toggle('is-on', this.listOpen);
    if (this.listOpen) this.scrollListTo(this.stepIndexAt(this.tau), false);
  }

  scrollListTo(i, smooth) {
    const r = this.rows && this.rows[i];
    if (!r || !this.listOpen || this.listHovered) return;
    const top = r.offsetTop - this.list.clientHeight / 2 + r.offsetHeight / 2;
    this.list.scrollTo({ top: Math.max(0, top), behavior: smooth ? 'smooth' : 'auto' });
  }

  toggleSettings(force) {
    const open = force != null ? force : !this.panel.classList.contains('is-open');
    this.panel.classList.toggle('is-open', open);
    this.gearBtn.classList.toggle('is-on', open);
  }

  async saveSettings() {
    this.applyTheme();
    this.buildSettings();
    this.updateSpeed();
    this.wake();
    await this.plugin.saveSettings();
  }

  updateSpeed() {
    const s = this.settings.speed;
    this.speedBtn.textContent = speedLabel(s);
  }

  isDark() {
    const t = this.settings.theme;
    return t === 'auto' ? document.body.classList.contains('theme-dark') : t === 'dark';
  }

  applyTheme() {
    const dark = this.isDark();
    const th = THEMES[dark ? 'dark' : 'light'];
    const acc = ACCENTS[this.settings.accent] || ACCENTS.violet;
    const mattAcc = ACCENTS[this.settings.accent === 'cyan' ? 'coral' : 'cyan'];
    this.theme = Object.assign({ dark, accent: hexRgb(dark ? acc.dark : acc.light), matt: hexRgb(dark ? mattAcc.dark : mattAcc.light) }, th);
    const r = this.root.style;
    r.setProperty('--bg-bg', th.bg);
    r.setProperty('--bg-fg', rgba(th.fg, 1));
    r.setProperty('--bg-muted', rgba(th.fg, 0.52));
    r.setProperty('--bg-faint', rgba(th.fg, 0.1));
    r.setProperty('--bg-line', rgba(th.fg, 0.12));
    r.setProperty('--bg-hover', rgba(th.fg, 0.07));
    r.setProperty('--bg-tip-bg', th.tipBg);
    r.setProperty('--bg-accent', rgba(this.theme.accent, 1));
    r.setProperty('--bg-accent-soft', rgba(this.theme.accent, 0.16));
    this.root.classList.toggle('is-light', !dark);
    this.font = getComputedStyle(this.root).fontFamily || 'sans-serif';
  }

  setStatus(text) {
    this.statusEl.textContent = text || '';
    this.statusEl.classList.toggle('is-on', !!text);
  }

  resize() {
    if (!this.root) return;
    const dpr = window.devicePixelRatio || 1;
    const w = this.root.clientWidth, h = this.root.clientHeight;
    this.dpr = dpr;
    if (w !== this.size.w || h !== this.size.h) {
      this.size = { w, h };
      this.canvas.width = Math.max(1, Math.round(w * dpr));
      this.canvas.height = Math.max(1, Math.round(h * dpr));
      this.canvas.style.width = w + 'px';
      this.canvas.style.height = h + 'px';
    }
    // Room the box takes at the bottom, not counting the commit list, which floats over the graph.
    this.dockH = this.dock.offsetHeight - (this.listOpen ? this.list.offsetHeight : 0);
    const cw = this.chartWrap.clientWidth, ch = this.chartWrap.clientHeight;
    if (cw !== this.chartSize.w || ch !== this.chartSize.h) {
      this.chartSize = { w: cw, h: ch };
      this.chart.width = Math.max(1, Math.round(cw * dpr));
      this.chart.height = Math.max(1, Math.round(ch * dpr));
      this.chart.style.width = cw + 'px';
      this.chart.style.height = ch + 'px';
      this.curve = null;
    }
    this.requestFrame();
  }

  /* ----- playback and moving through commits ----- */

  togglePlay() {
    if (!this.model) return;
    if (this.playing) this.playing = false;
    else {
      if (this.tau >= this.model.endBeat - 0.01) { this.tau = 0; this.autoCam = true; }
      this.playing = true;
    }
    this.tauTarget = null;
    this.updatePlayButton();
    this.requestFrame();
  }

  updatePlayButton() {
    if (!this.playBtn) return;
    const atEnd = this.model && this.tau >= this.model.endBeat - 0.01;
    const icon = this.playing ? 'pause' : atEnd ? 'replay' : 'play';
    if (this.playBtn.dataset.icon !== icon) {
      setIconSvg(this.playBtn, icon);
      this.playBtn.dataset.icon = icon;
      const label = this.playing ? 'Pause (space)' : atEnd ? 'Replay from the first commit (space)' : 'Play (space)';
      this.playBtn.setAttribute('aria-label', label);
      this.playBtn.title = label;
    }
  }

  stepIndexAt(tau) {
    const steps = this.model.steps;
    let lo = 0, hi = steps.length;
    while (lo < hi) { const mid = (lo + hi) >> 1; if (steps[mid].b <= tau) lo = mid + 1; else hi = mid; }
    return lo - 1;
  }

  stepEnd(i) {
    const s = this.model.steps[i];
    return i === this.model.steps.length - 1 ? this.model.endBeat + SETTLE : s.b + s.span - 0.001;
  }

  // Glide the replay to a moment; the commits in between play out quickly on the way.
  glideTo(tau) {
    this.playing = false;
    this.tauTarget = clamp(tau, 0, this.model.endBeat + SETTLE);
    this.updatePlayButton();
    this.requestFrame();
  }

  goToStep(i) { if (this.model && this.model.steps[i]) this.glideTo(this.stepEnd(i)); }

  // One commit forwards or back, from wherever the replay is heading.
  stepBy(dir) {
    if (!this.model || !this.model.steps.length) return;
    const from = this.tauTarget != null ? this.tauTarget : this.tau, n = this.model.steps.length;
    if (dir > 0) {
      for (let i = 0; i < n; i++) if (this.stepEnd(i) > from + 1e-3) { this.goToStep(i); return; }
    } else {
      for (let i = n - 1; i >= 0; i--) if (this.stepEnd(i) < from - 1e-3) { this.goToStep(i); return; }
      this.glideTo(0);
    }
  }

  onKey(e) {
    if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
    const k = e.key;
    if (k === ' ') this.togglePlay();
    else if (k === 'ArrowRight' || k === 'ArrowDown') this.stepBy(1);
    else if (k === 'ArrowLeft' || k === 'ArrowUp') this.stepBy(-1);
    else if (k === 'Home') this.glideTo(0);
    else if (k === 'End') { if (this.model) this.glideTo(this.model.endBeat + SETTLE); }
    else if (k === 'f' || k === 'F') { this.autoCam = true; this.requestFrame(); }
    else if (k === 'Escape') { this.toggleSettings(false); this.toggleList(false); }
    else return;
    e.preventDefault();
  }

  requestFrame() {
    if (!this.raf && !this.closed) this.raf = requestAnimationFrame((t) => this.frame(t));
  }

  frame(now) {
    this.raf = 0;
    if (!this.model || !this.size.w) { this.drawEmpty(); return; }
    const dt = this.lastNow ? Math.min(0.1, (now - this.lastNow) / 1000) : 0;
    this.lastNow = now;
    this.clock = (this.clock || 0) + dt; // seconds the view has been running, for circles travelling to a new seat
    let busy = false;
    if (this.playing) {
      this.tau += dt * BEATS_PER_SECOND * this.settings.speed;
      if (this.tau >= this.model.endBeat + SETTLE) { this.tau = this.model.endBeat + SETTLE; this.playing = false; this.updatePlayButton(); }
      busy = true;
    } else if (this.tauTarget != null) {
      this.tau += (this.tauTarget - this.tau) * (1 - Math.exp(-dt * 9));
      if (Math.abs(this.tauTarget - this.tau) < 0.004) { this.tau = this.tauTarget; this.tauTarget = null; }
      busy = true;
    }
    this.evaluate(this.tau);
    this.followLayout();
    this.placeNewNodes();
    if (this.settings.physics ? this.bubbleTick(dt) : this.glideTick(dt)) busy = true;
    if (this.dragNode < 0 && this.updateCamera(dt)) busy = true;
    this.project();
    this.drawGraph();
    this.drawChart();
    this.updateHud();
    if (this.hover >= 0 && this.dragNode < 0) this.placeTip();
    if (busy) this.requestFrame(); else this.lastNow = 0;
  }

  /* ----- state at a moment of the replay ----- */

  evaluate(tau) {
    const { nodes, edges } = this.model;
    const N = this.ns, E = this.es, F = this.focus, set = this.settings, quiet = set.quiet;
    for (let i = 0; i < nodes.length; i++) {
      const nd = nodes[i];
      N.on[i] = 0; N.deg[i] = 0; N.born[i] = -1; N.edit[i] = -1; N.dying[i] = 0; N.glow[i] = 0;
      N.bornF[i] = 0; N.editF[i] = 0; N.glowF[i] = 0; N.touch[i] = 0;
      if (F.hidden[i]) continue;
      let sp = null;
      for (const s of nd.spans) { if (s.b <= tau) sp = s; else break; }
      if (!sp) continue;
      let scale = 1, alpha = 1;
      if (tau >= sp.d) {
        const dd = tau - sp.d;
        if (dd >= 0.8) continue;
        alpha = 1 - dd / 0.8; scale = 0.5 + 0.5 * alpha; N.dying[i] = 1;
      } else {
        const since = tau - sp.b;
        if (since < 0.55) scale = Math.max(0, easeOutBack(since / 0.55));
        if (since < 1.1) N.born[i] = since;
        N.bornF[i] = sp.f || 0;
        // The note's last touch: its newest edit, or its birth. With "Quieter" on,
        // quiet commits don't count for the afterglow or for its links' age.
        let last = sp.b, lastF = sp.f || 0, touchT = sp.t || 0;
        const ed = nd.edits;
        if (ed.length) {
          let j = upper(ed, tau) - 1;
          if (j >= 0 && ed[j] >= sp.b) {
            if (tau - ed[j] < 1.3) { N.edit[i] = tau - ed[j]; N.editF[i] = nd.eflags[j]; }
            if (quiet) while (j >= 0 && ed[j] >= sp.b && (nd.eflags[j] & EDIT_QUIET)) j--;
            if (j >= 0 && ed[j] >= sp.b) { last = ed[j]; lastF = nd.eflags[j]; touchT = nd.etimes[j]; }
          }
        }
        // Afterglow: a note stays tinted for a while after it's written, so the
        // latest activity shows even when the replay is paused.
        N.glow[i] = quiet && (lastF & EDIT_QUIET) ? 0 : clamp(1 - (tau - last) / GLOW_BEATS, 0, 1);
        N.glowF[i] = lastF;
        N.touch[i] = touchT;
      }
      N.on[i] = 1; N.s[i] = scale; N.a[i] = alpha;
    }
    // The replay's clock time (the commit it's on), for the links' age.
    const si = this.stepIndexAt(tau), now = this.model.steps.length ? this.model.steps[Math.max(0, si)].t : 0;
    const fadeS = set.fadeDays > 0 ? set.fadeDays * 86400 : 0;
    let links = 0;
    for (let j = 0; j < edges.length; j++) {
      const e = edges[j];
      E.p[j] = 0; E.live[j] = 0;
      if (!N.on[e.a] || !N.on[e.b]) continue;
      let sp = null;
      for (const s of e.spans) { if (s.b <= tau) sp = s; else break; }
      if (!sp) continue;
      const since = tau - sp.b;
      let alpha = 1;
      if (tau >= sp.d) {
        const dd = tau - sp.d;
        if (dd >= 0.6) continue;
        alpha = 1 - dd / 0.6;
      } else {
        E.live[j] = 1; links++;
        if (F.shown[j]) { N.deg[e.a]++; N.deg[e.b]++; }
      }
      if (!F.shown[j] && !(e.bridge && set.bridges === 'hover') && e.list < 0) continue; // a hidden hub link: counted, not drawn
      E.p[j] = Math.max(0.0001, Math.min(1, since / 0.45));
      E.a[j] = alpha * Math.min(N.a[e.a], N.a[e.b]);
      E.flash[j] = tau < sp.d && since < 2.2 ? since : -1;
      if (e.list >= 0 && E.flash[j] < 0 && N.edit[e.list] >= 0) E.flash[j] = N.edit[e.list]; // its list was just edited
      E.src[j] = sp.src === e.b ? e.b : e.a;
      E.f[j] = sp.f || 0;
      // How strongly it's drawn: hub links faint, old links faded.
      let m = 1;
      if (e.hub && set.hubLinks === 'faint') m *= 0.35;
      if (e.list >= 0) m *= E.flash[j] >= 0 ? 1 - E.flash[j] / 2.2 : 0; // a list's link fades out after its flash
      if (fadeS) {
        const age = now - Math.max(N.touch[e.a], N.touch[e.b], sp.t || 0);
        if (age > fadeS) m *= Math.max(FADE_FLOOR, 1 - ((age - fadeS) / fadeS) * (1 - FADE_FLOOR));
      }
      E.m[j] = m;
    }
    let notes = 0;
    for (let i = 0; i < nodes.length; i++) if (N.on[i] && !N.dying[i]) notes++;
    this.counts = { notes, links };
  }

  /* ----- where the dots are ----- */

  // A dot that has just appeared starts at its place on its circle, wherever the circle is now.
  // One just written grows out of the circle's middle from there (bubbleStep, glideTick).
  placeNewNodes() {
    const N = this.ns, S = this.sim, T = this.tree, n = this.model.nodes.length;
    for (let i = 0; i < n; i++) {
      if (N.on[i] && !S.was[i]) {
        const b = T.folderOf[i];
        S.x[i] = T.x[i] + (b ? b.x - b.hx : 0); S.y[i] = T.y[i] + (b ? b.y - b.hy : 0);
      }
      S.was[i] = N.on[i];
    }
  }

  // Wakes the physics after a change, so it runs again until things settle.
  wake() {
    this.bubAge = 0;
    this.requestFrame();
  }

  // Physics off: the circles and dots glide to their places slowly, not twitchily (Matt,
  // 20 Oct 2026: "more gradual"), and a new note grows out of its circle's middle.
  glideTick(dt) {
    const S = this.sim, N = this.ns, T = this.tree, n = this.model.nodes.length, ease = 1 - Math.exp(-dt * 2);
    let moving = false;
    for (const b of T.folders) {
      if (b.pop >= 0 && b.trip) { this.popTo(b); moving = true; } else { b.x += (b.hx - b.x) * ease; b.y += (b.hy - b.y) * ease; }
      b.vx = b.vy = 0;
      if (Math.abs(b.hx - b.x) + Math.abs(b.hy - b.y) > 0.1) moving = true;
    }
    for (let i = 0; i < n; i++) {
      if (!N.on[i]) continue;
      const tx = T.x[i], ty = T.y[i], f = T.folderOf[i];
      if (N.born[i] >= 0 && N.born[i] < 0.7 && f && f.parent) {
        const k = easeOutCubic(N.born[i] / 0.7);
        S.x[i] = f.x + (tx - f.x) * k; S.y[i] = f.y + (ty - f.y) * k;
        moving = true;
        continue;
      }
      const dx = tx - S.x[i], dy = ty - S.y[i];
      if (dx * dx + dy * dy > 0.02) { S.x[i] += dx * ease; S.y[i] += dy * ease; moving = true; } else { S.x[i] = tx; S.y[i] = ty; }
    }
    return moving;
  }

  // Physics on. Matt, 20 Oct 2026: "draggable, but also somehow still be able to
  // hold its shape", and then, of a first try that sprang every circle back to its place, that
  // things should trail like the old Graph view, nothing "too snappy", and "it shouldn't have to
  // snap back into a certain shape" on the lowest Hold shape. So circles carry on a little as
  // they move, heavily damped like the old Graph view, and a few gentle rules each put things a
  // little more right every step: each circle hangs off the one it popped out of on a stem of
  // its own length that's free to swing, so whatever you drag pulls the rest along behind it; a
  // folder's circles keep the room they have round it, like a ring; a folder's circles fan out
  // away from the stem it hangs on, so branches don't fold back; circles don't overlap; and the
  // notes on a ring space themselves evenly round it, so a folder stays a circle. Only Hold
  // shape pulls things back to their places, so at 0 they stay where you leave them. The layout
  // itself breaks no rule, so it's at rest. Steps run 60 times a second whatever the screen's
  // rate, and stop when nothing moves (or 15 seconds after the last drag, whatever happens).
  bubbleTick(dt) {
    this.stepAcc = Math.min(4 / 60, (this.stepAcc || 0) + (dt || 1 / 60));
    while (this.stepAcc >= 1 / 60) { this.stepAcc -= 1 / 60; this.bubMoving = this.bubbleStep(); }
    return this.bubMoving !== false || this.dragNode >= 0;
  }

  bubbleStep() {
    const S = this.sim, N = this.ns, T = this.tree, B = T.folders, n = this.model.nodes.length, d = this.dragNode;
    if (d >= 0 || this.playing || this.tauTarget != null) this.bubAge = 0;
    else if ((this.bubAge = (this.bubAge || 0) + 1) > 900) return false;
    const hold = this.settings.hold * BUB_HOLD, ride = S.ride;
    const held = d >= 0 && N.on[d] ? T.folderOf[d] : null;
    if (held && held.trip) { held.trip = null; held.pop = -1; }
    // Carry on a little, and drift back to its place as hard as Hold shape says. A circle popping
    // out goes its own way (popTo) and the rules leave it and its neighbours alone till it's there.
    for (const b of B) {
      b.px = b.x; b.py = b.y;
      if (b === held || b.pop >= 0) continue;
      b.x += b.vx * 0.6 + (b.hx - b.x) * hold; b.y += b.vy * 0.6 + (b.hy - b.y) * hold;
    }
    // The circle holding the dragged dot hangs from it, trailing behind as you move.
    if (held) {
      const ux = held.x - S.fx, uy = held.y - S.fy, u = Math.hypot(ux, uy), k = u > 1e-6 ? Math.hypot(T.x[d] - held.hx, T.y[d] - held.hy) / u : 0;
      held.x = S.fx + ux * k; held.y = S.fy + uy * k;
    }
    // How far a pair gives way: the lighter one further, the held one not at all.
    const share = (a, b) => (a === held ? 0 : b === held ? 1 : b.mass / (a.mass + b.mass));
    const give = (b) => (b === held ? 0 : 1 / b.mass);
    for (const c of B) {
      const p = c.parent;
      if (!p || c.pop >= 0 || p.pop >= 0) continue;
      // The stem, back towards its length.
      const dx = c.x - p.x, dy = c.y - p.y, l = Math.hypot(dx, dy) || 0.01, f = ((l - c.len) / l) * BUB_STEM, w = share(c, p);
      c.x -= dx * f * w; c.y -= dy * f * w; p.x += dx * f * (1 - w); p.y += dy * f * (1 - w);
      // Folded further round than its fan: the bend at its parent eased back. The circle, its parent
      // and the grandparent all give way a little, the heavier less, so nothing ends up twisted or
      // pushed along (a bend constraint, as in cloth and rope physics).
      const g = p.parent;
      if (!g || g.pop >= 0) continue;
      const ux = c.x - p.x, uy = c.y - p.y, vx = p.x - g.x, vy = p.y - g.y;
      const phi = wrapAngle(Math.atan2(uy, ux) - Math.atan2(vy, vx)), over = Math.abs(phi) - Math.abs(c.fan);
      if (over <= 0) continue;
      const u2 = ux * ux + uy * uy || 1e-6, v2 = vx * vx + vy * vy || 1e-6;
      const gux = -uy / u2, guy = ux / u2, gvx = -vy / v2, gvy = vx / v2, gpx = -gux - gvx, gpy = -guy - gvy;
      const wc = give(c), wp = give(p), wg = give(g);
      const den = wc * (gux * gux + guy * guy) + wp * (gpx * gpx + gpy * gpy) + wg * (gvx * gvx + gvy * gvy);
      if (!den) continue;
      const k = (over / den) * Math.sign(phi) * BUB_FAN;
      c.x -= k * wc * gux; c.y -= k * wc * guy;
      p.x -= k * wp * gpx; p.y -= k * wp * gpy;
      g.x -= k * wg * gvx; g.y -= k * wg * gvy;
    }
    // Too close: a folder's circles want the room the layout gives them round it (from their
    // nearest few, in a crowded folder); other circles just mustn't overlap. Only circles side by
    // side across the screen are checked for that, so hundreds of circles stay quick.
    const apart = (a, b, min, k) => {
      const dx = b.x - a.x, dy = b.y - a.y, d2 = dx * dx + dy * dy;
      if (d2 >= min * min || a.pop >= 0 || b.pop >= 0) return;
      const dist = Math.sqrt(d2) || 0.01, push = ((min - dist) / dist) * k, w = share(a, b);
      a.x -= dx * push * w; a.y -= dy * push * w;
      b.x += dx * push * (1 - w); b.y += dy * push * (1 - w);
    };
    for (const [a, b, home] of T.pairs) apart(a, b, home, BUB_SPREAD);
    const order = B.slice().sort((a, b) => a.x - a.rim - (b.x - b.rim));
    for (let i = 0; i < order.length; i++) {
      const a = order[i], right = a.x + a.rim + 2 * BUB_PAD;
      for (let j = i + 1; j < order.length; j++) {
        const b = order[j], touch = a.rim + b.rim + 2 * BUB_PAD;
        if (b.x - b.rim > right) break;
        if (a.kin.has(b) || Math.abs(b.y - a.y) >= touch) continue;
        apart(a, b, Math.min(Math.hypot(b.hx - a.hx, b.hy - a.hy), touch), BUB_BUMP);
      }
    }
    let moving = !!held;
    for (const b of B) {
      // A travelling circle goes its own way, and the circles beyond it come along with it.
      const p = b.parent;
      if (b.pop >= 0) { this.popTo(b); moving = true; b.cx = b.x - b.px; b.cy = b.y - b.py; } else if (p && (p.cx || p.cy)) { b.x += p.cx; b.y += p.cy; b.cx = p.cx; b.cy = p.cy; } else b.cx = b.cy = 0;
      b.vx = b.x - b.px; b.vy = b.y - b.py;
      if (Math.abs(b.vx) + Math.abs(b.vy) > 0.01) moving = true;
    }
    // The notes. One that's just appeared glides to its circle (or grows out of its middle), then
    // rides it at its distance from the middle, drifting back to its place on its circle as hard
    // as Hold shape says. (Until 20 Oct 2026 that was its place in the whole layout, which pulled
    // a ring's notes into a bunch on one side whenever the circle was away from its own place;
    // Matt: "they're all clumped together and not spread out around that circle".) The ring
    // holding the dragged dot turns with it, so its notes never pass each other.
    const ox = S.ox || (S.ox = new Float64Array(n)), oy = S.oy || (S.oy = new Float64Array(n));
    const spin = held ? wrapAngle(Math.atan2(S.fy - held.y, S.fx - held.x) - Math.atan2(S.y[d] - held.py, S.x[d] - held.px)) : 0;
    const cs = Math.cos(spin), sn = Math.sin(spin);
    for (let i = 0; i < n; i++) {
      ox[i] = S.x[i]; oy[i] = S.y[i];
      if (!N.on[i]) { ride[i] = 0; continue; }
      if (i === d) { S.x[i] = S.fx; S.y[i] = S.fy; ride[i] = 1; continue; }
      const b = T.folderOf[i];
      if (!b) continue;
      const qx = T.x[i] - b.hx, qy = T.y[i] - b.hy;
      if (N.born[i] >= 0 && N.born[i] < 0.7 && b.parent) {
        const k = easeOutCubic(N.born[i] / 0.7);
        S.x[i] = b.x + qx * k; S.y[i] = b.y + qy * k; ride[i] = 0; moving = true;
        continue;
      }
      if (!ride[i]) {
        const dx = b.x + qx - S.x[i], dy = b.y + qy - S.y[i];
        if (dx * dx + dy * dy > 0.25) { S.x[i] += dx * 0.15; S.y[i] += dy * 0.15; moving = true; continue; }
        ride[i] = 1;
      }
      let x = S.x[i] + b.vx + (b.x + qx - S.x[i]) * hold * 2.5, y = S.y[i] + b.vy + (b.y + qy - S.y[i]) * hold * 2.5;
      if (b === held) { const sx = x - b.x, sy = y - b.y; x = b.x + sx * cs - sy * sn; y = b.y + sx * sn + sy * cs; }
      const L = Math.hypot(qx, qy), rx = x - b.x, ry = y - b.y, r = Math.hypot(rx, ry);
      if (r > 1e-6) { x = b.x + (rx * L) / r; y = b.y + (ry * L) / r; } else { x = b.x + qx; y = b.y + qy; }
      S.x[i] = x; S.y[i] = y;
    }
    // Each ring's notes keep the gaps their seats have round it, in the order they're in now, once
    // they've all landed: evenly on a full ring, with room left for the ones the commit hasn't
    // added yet. If a drag has put them out of their seats' order, evenly.
    for (const b of B) {
      const ring = b.leaves.filter((i) => N.on[i]), m = ring.length;
      if (m < 2 || ring.some((i) => !ride[i])) continue;
      const ang = new Map(ring.map((i) => [i, Math.atan2(S.y[i] - b.y, S.x[i] - b.x)]));
      ring.sort((i, j) => ang.get(i) - ang.get(j));
      const a = ring.map((i) => ang.get(i)), seat = ring.map((i) => Math.atan2(T.y[i] - b.hy, T.x[i] - b.hx));
      const gap = seat.map((v, k) => { const g = (seat[(k + 1) % m] - v) % TAU; return g <= 0 ? g + TAU : g; });
      if (Math.abs(gap.reduce((t, g) => t + g, 0) - TAU) > 1e-3) gap.fill(TAU / m);
      ring.forEach((i, k) => {
        if (i === d) return;
        const c = ((wrapAngle(a[(k + 1) % m] - a[k] - gap[k]) + wrapAngle(a[(k + m - 1) % m] - a[k] + gap[(k + m - 1) % m])) / 2) * BUB_SPACE;
        if (Math.abs(c) < 1e-4) return;
        const r = Math.hypot(T.x[i] - b.hx, T.y[i] - b.hy); // its own row, on a crowded rim
        S.x[i] = b.x + r * Math.cos(a[k] + c); S.y[i] = b.y + r * Math.sin(a[k] + c);
      });
    }
    for (let i = 0; i < n && !moving; i++) if (N.on[i] && Math.abs(S.x[i] - ox[i]) + Math.abs(S.y[i] - oy[i]) > 0.01) moving = true;
    return moving;
  }

  // Lay out the commit the replay is on: the notes there now and the ones it will add, so a
  // big commit's notes drop into seats already there instead of each new one rearranging the
  // rest (Matt, 20 Oct 2026: the rows were "too twitchy... making and destroying those rows",
  // and a new row needs "enough room on that new row for more to spawn in"). It's done again
  // when the replay moves to another commit. Circles that were already there keep where the
  // physics had them, and a new one starts at its seat.
  followLayout() {
    const N = this.ns, nodes = this.model.nodes, n = nodes.length, hidden = this.focus.hidden;
    const si = this.stepIndexAt(this.tau), s = si >= 0 ? this.model.steps[si] : null;
    const t0 = s ? s.b : 0, t1 = s ? s.b + s.span : 0;
    const room = new Uint8Array(n);
    let h = 0, c = 0;
    for (let i = 0; i < n; i++) {
      if (hidden[i]) continue;
      let take = !s && N.on[i];
      if (s) for (const sp of nodes[i].spans) if (sp.b < t1 && sp.d > t0) { take = true; break; }
      if (take) { room[i] = 1; h = (Math.imul(h, 31) + i + 1) >>> 0; c++; }
    }
    const sig = c + ':' + h;
    if (sig !== this.layoutSig) {
      this.layoutSig = sig;
      const prev = this.tree ? new Map(this.tree.folders.map((b) => [b.key, b])) : null;
      this.tree = bubbleLayout(this.model, room.map((v) => 1 - v));
      this.bubAge = 0;
      for (const b of this.tree.folders) {
        const o = prev && prev.get(b.key), p = b.parent;
        b.live = 0; b.trip = null; b.pop = -1;
        if (o) Object.assign(b, { x: o.x, y: o.y, vx: o.vx, vy: o.vy, live: o.live, trip: o.trip });
        else if (p) { b.x = p.x + b.hx - p.hx; b.y = p.y + b.hy - p.hy; }
        // A circle the new layout gives another seat travels straight there, carrying its own circles,
        // rather than being pushed through the others, where it could get stuck (Matt, 20 Oct 2026: the
        // rows "get jumbled up and not go back to their correct place").
        if (o && p && o.parent && Math.hypot(b.hx - p.hx - (o.hx - o.parent.hx), b.hy - p.hy - (o.hy - o.parent.hy)) > 1) {
          b.trip = { fx: b.x - p.x, fy: b.y - p.y, start: this.clock || 0, len: BUB_MOVE, beats: false };
        }
      }
    }
    // A circle shows once a note in it does. One that shows because a note was just written pops
    // out of its parent's middle and travels to its seat (Matt: "they spawn all at the same point...
    // and then travel to their spot"), so a circle grows out of the one it belongs to.
    const T = this.tree;
    for (const b of T.folders) { b.now = 0; b.fresh = 0; }
    for (let i = 0; i < n; i++) {
      if (!N.on[i] || !T.chain[i]) continue;
      for (const b of T.chain[i]) { b.now = 1; if (N.born[i] >= 0) b.fresh = 1; }
    }
    for (const b of T.folders) {
      if (b.now && !b.live && b.fresh && b.parent) {
        b.trip = { fx: 0, fy: 0, start: this.tau, len: BUB_POP, beats: true };
        b.x = b.parent.x; b.y = b.parent.y; b.vx = b.vy = 0; this.bubAge = 0;
      }
      b.live = b.now;
      const age = b.trip ? (b.trip.beats ? this.tau : this.clock || 0) - b.trip.start : -1;
      if (age < 0 || (b.trip && age >= b.trip.len)) b.trip = null;
      b.pop = b.trip ? easeOutCubic(age / b.trip.len) : -1;
    }
  }

  // Where a travelling circle is: on its way from where it set out (its parent's middle, for one
  // popping out) to its seat, measured from its parent.
  popTo(b) {
    const p = b.parent, t = b.trip;
    b.x = p.x + t.fx + (b.hx - p.hx - t.fx) * b.pop; b.y = p.y + t.fy + (b.hy - p.hy - t.fy) * b.pop;
  }

  // Each folder's circle and stem, and the links, each a bundled curve along the branches. Faint until you point
  // at a note, then its own links light up and the rest step back.
  drawBundles(hov, incident, hoverOnly) {
    const ctx = this.ctx, th = this.theme, fg = th.fg, T = this.tree;
    const { edges } = this.model;
    const N = this.ns, E = this.es, c = this.cam, { ox, oy } = this.origin;
    if (!T) return;
    const sx = (x) => (x - c.x) * c.k + ox, sy = (y) => (y - c.y) * c.k + oy;
    ctx.lineWidth = 1;
    // Each folder's circle as a hairline, and a stem from the circle it popped out of, once a note
    // in it shows. (The circles the commit hasn't filled yet keep their room, unseen.)
    ctx.strokeStyle = rgba(fg, 0.07);
    ctx.beginPath();
    for (const b of T.folders) if (b.parent && b.live) { ctx.moveTo(sx(b.parent.x), sy(b.parent.y)); ctx.lineTo(sx(b.x), sy(b.y)); }
    ctx.stroke();
    ctx.strokeStyle = rgba(fg, 0.13);
    ctx.beginPath();
    for (const b of T.folders) if (b.live) { const r = b.rim * c.k; ctx.moveTo(sx(b.x) + r, sy(b.y)); ctx.arc(sx(b.x), sy(b.y), r, 0, TAU); }
    ctx.stroke();
    const line = (j) => {
      const e = edges[j];
      const pts = bundlePoints(T, e.a, e.b, this.sim.x[e.a], this.sim.y[e.a], this.sim.x[e.b], this.sim.y[e.b]);
      for (const p of pts) { p[0] = sx(p[0]); p[1] = sy(p[1]); }
      traceBasis(ctx, pts);
    };
    const base = (hov >= 0 ? 0.35 : 1) * th.edge * 0.6;
    const buckets = new Map(), lit = [], flashing = [];
    for (let j = 0; j < edges.length; j++) {
      if (!(E.p[j] > 0)) continue;
      const e = edges[j], inc = incident(e);
      if (hoverOnly(e, j) && !inc) continue;
      if (inc) { lit.push(j); continue; }
      if (E.flash[j] >= 0) flashing.push(j);
      const key = Math.round(Math.min(E.m[j] * E.a[j] * Math.min(1, E.p[j] * 1.5), 3) * 20);
      if (!key) continue;
      let list = buckets.get(key);
      if (!list) buckets.set(key, (list = []));
      list.push(j);
    }
    ctx.lineWidth = 1;
    for (const [key, list] of buckets) {
      ctx.beginPath();
      for (const j of list) line(j);
      ctx.strokeStyle = rgba(fg, Math.min(0.9, base * (key / 20)));
      ctx.stroke();
    }
    for (const j of flashing) {
      const f = E.flash[j], glow = (f < 0.45 ? 1 : 1 - (f - 0.45) / 1.75) * this.flagK(E.f[j]);
      ctx.lineWidth = 1.2;
      ctx.strokeStyle = rgba(this.flagColor(E.f[j]), 0.75 * glow * (hov >= 0 ? 0.4 : 1));
      ctx.beginPath(); line(j); ctx.stroke();
    }
    if (lit.length) {
      ctx.lineWidth = 1.25;
      ctx.strokeStyle = rgba(th.accent, 0.7);
      ctx.beginPath();
      for (const j of lit) line(j);
      ctx.stroke();
    }
    this.drawPulses(sx, sy);
  }

  // A note written or edited sends a pulse from the core out along its branches to it,
  // like a thought firing down a nerve.
  drawPulses(sx, sy) {
    const ctx = this.ctx, N = this.ns, T = this.tree, S = this.sim, n = this.model.nodes.length;
    for (let i = 0; i < n; i++) {
      if (!N.on[i] || !T.chain[i]) continue;
      const tb = N.born[i] >= 0 && N.born[i] < PULSE_BEATS ? N.born[i] : -1;
      const te = N.edit[i] >= 0 && N.edit[i] < PULSE_BEATS ? N.edit[i] : -1;
      const t = tb >= 0 ? tb : te;
      if (t < 0) continue;
      const flags = tb >= 0 ? N.bornF[i] : N.editF[i];
      const pts = [];
      for (let k = T.chain[i].length - 1; k >= 0; k--) pts.push([sx(T.chain[i][k].x), sy(T.chain[i][k].y)]);
      pts.push([sx(S.x[i]), sy(S.y[i])]);
      const lens = [0];
      for (let k = 1; k < pts.length; k++) lens.push(lens[k - 1] + Math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]));
      const total = lens[lens.length - 1];
      if (total < 1) continue;
      const at = (d) => {
        let k = 1;
        while (k < lens.length - 1 && lens[k] < d) k++;
        const s = (d - lens[k - 1]) / Math.max(1e-6, lens[k] - lens[k - 1]);
        return [pts[k - 1][0] + (pts[k][0] - pts[k - 1][0]) * s, pts[k - 1][1] + (pts[k][1] - pts[k - 1][1]) * s];
      };
      const f = easeOutCubic(Math.min(1, t / PULSE_BEATS)), d = f * total;
      const col = this.flagColor(flags), k = this.flagK(flags) * (1 - 0.6 * f);
      const [x0, y0] = at(Math.max(0, d - Math.min(60, total * 0.25))), [x1, y1] = at(d);
      const g = ctx.createLinearGradient(x0, y0, x1, y1);
      g.addColorStop(0, rgba(col, 0)); g.addColorStop(1, rgba(col, 0.8 * k));
      ctx.lineWidth = 1.6; ctx.strokeStyle = g;
      ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
      ctx.fillStyle = rgba(col, k);
      ctx.beginPath(); ctx.arc(x1, y1, 2, 0, TAU); ctx.fill();
    }
  }

  graphArea() {
    const top = 84, bottom = (this.dockH || 120) + 34;
    return { x: 24, y: top, w: Math.max(40, this.size.w - 48), h: Math.max(40, this.size.h - top - bottom) };
  }

  // The camera eases to fit the dots that are showing, so the brain fills the view
  // as it grows. Panning or zooming by hand turns that off until you press F.
  updateCamera(dt) {
    const N = this.ns, S = this.sim, n = this.model.nodes.length;
    if (!this.autoCam && this.camReady) return false;
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (let i = 0; i < n; i++) {
      if (!N.on[i]) continue;
      const x = S.x[i], y = S.y[i];
      if (x < x0) x0 = x; if (x > x1) x1 = x;
      if (y < y0) y0 = y; if (y > y1) y1 = y;
    }
    if (x0 === Infinity) { x0 = y0 = -1; x1 = y1 = 1; }
    const area = this.graphArea();
    const w = Math.max(x1 - x0, 220), h = Math.max(y1 - y0, 220);
    const target = { x: (x0 + x1) / 2, y: (y0 + y1) / 2, k: Math.min(area.w / (w + 40), area.h / (h + 40), 4) };
    if (!this.camReady) { this.cam = target; this.camReady = true; return false; }
    const s = 1 - Math.exp(-dt * 2.6), c = this.cam;
    c.x += (target.x - c.x) * s;
    c.y += (target.y - c.y) * s;
    c.k *= Math.pow(target.k / c.k, s);
    return Math.abs(target.x - c.x) * c.k > 0.3 || Math.abs(target.y - c.y) * c.k > 0.3 || Math.abs(Math.log(target.k / c.k)) > 0.002;
  }

  project() {
    const N = this.ns, S = this.sim, n = this.model.nodes.length, a = this.graphArea(), c = this.cam;
    const ox = a.x + a.w / 2, oy = a.y + a.h / 2;
    const zoomR = Math.pow(c.k, 0.55);
    for (let i = 0; i < n; i++) {
      if (!N.on[i]) continue;
      N.sx[i] = (S.x[i] - c.x) * c.k + ox;
      N.sy[i] = (S.y[i] - c.y) * c.k + oy;
      N.r[i] = Math.max(1.1, (0.9 + 0.4 * Math.sqrt(N.deg[i])) * zoomR) * N.s[i];
    }
    this.origin = { ox, oy };
  }

  toWorld(px, py) {
    const { ox, oy } = this.origin || { ox: 0, oy: 0 };
    return [(px - ox) / this.cam.k + this.cam.x, (py - oy) / this.cam.k + this.cam.y];
  }

  /* ----- drawing the graph ----- */

  drawEmpty() {
    if (!this.ctx || !this.size.w) return;
    const ctx = this.ctx;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.fillStyle = this.theme ? this.theme.bg : '#09090b';
    ctx.fillRect(0, 0, this.size.w, this.size.h);
  }

  drawGraph() {
    const ctx = this.ctx, th = this.theme, fg = th.fg, acc = th.accent;
    const { nodes, edges } = this.model;
    const N = this.ns, E = this.es;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.fillStyle = th.bg;
    ctx.fillRect(0, 0, this.size.w, this.size.h);
    const hov = this.hover >= 0 && N.on[this.hover] ? this.hover : -1;
    const near = hov >= 0 ? new Set([hov]) : null;
    if (near) for (const j of this.adj[hov]) if (E.p[j] > 0) { near.add(edges[j].a); near.add(edges[j].b); }
    const incident = (e) => hov >= 0 && (e.a === hov || e.b === hov);
    const hoverOnly = (e, j) => (e.bridge && this.settings.bridges === 'hover') || (e.list >= 0 && !(E.flash[j] >= 0));

    this.drawBundles(hov, incident, hoverOnly);

    // Notes: settled ones in one fill, the rest one at a time.
    const dimA = th.node * 0.22;
    ctx.beginPath();
    for (let i = 0; i < nodes.length; i++) {
      if (!N.on[i] || N.s[i] !== 1 || N.a[i] !== 1 || N.edit[i] >= 0 || N.glow[i] > 0 || (near && !near.has(i))) continue;
      ctx.moveTo(N.sx[i] + N.r[i], N.sy[i]);
      ctx.arc(N.sx[i], N.sy[i], N.r[i], 0, TAU);
    }
    ctx.fillStyle = rgba(fg, th.node);
    ctx.fill();
    for (let i = 0; i < nodes.length; i++) {
      if (!N.on[i]) continue;
      const dim = near && !near.has(i);
      const plain = N.s[i] === 1 && N.a[i] === 1 && N.edit[i] < 0 && N.glow[i] <= 0 && !dim;
      const r = N.r[i], x = N.sx[i], y = N.sy[i];
      if (!plain && r > 0) {
        const a = (dim ? dimA : th.node) * N.a[i];
        ctx.beginPath(); ctx.arc(x, y, r, 0, TAU);
        ctx.fillStyle = rgba(fg, a); ctx.fill();
        const flash = N.edit[i] >= 0 ? clamp(1 - N.edit[i] / 0.8, 0, 1) * this.flagK(N.editF[i]) : 0;
        const glow = 0.85 * easeOutCubic(N.glow[i]);
        const k = Math.max(flash, glow) * (dim ? 0.3 : 1);
        if (k > 0) {
          ctx.fillStyle = rgba(this.flagColor(flash >= glow ? N.editF[i] : N.glowF[i]), k * N.a[i]);
          ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill();
        }
      }
      // Rings: a new note sends out one wide ring; an edited note pulses.
      if (N.born[i] >= 0) {
        const k = N.born[i] / 1.1;
        ctx.lineWidth = 1.2;
        ctx.strokeStyle = rgba(this.flagColor(N.bornF[i]), 0.75 * (1 - k) * this.flagK(N.bornF[i]));
        ctx.beginPath(); ctx.arc(x, y, r + 2 + 16 * easeOutCubic(k), 0, TAU); ctx.stroke();
      }
      if (N.edit[i] >= 0) {
        const k = N.edit[i] / 1.3;
        ctx.lineWidth = 1.2;
        ctx.strokeStyle = rgba(this.flagColor(N.editF[i]), 0.7 * (1 - k) * this.flagK(N.editF[i]));
        ctx.beginPath(); ctx.arc(x, y, r + 1.5 + 10 * easeOutCubic(k), 0, TAU); ctx.stroke();
      }
    }
    if (hov >= 0) {
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = rgba(acc, 1);
      ctx.beginPath(); ctx.arc(N.sx[hov], N.sy[hov], N.r[hov] + 3, 0, TAU); ctx.stroke();
    }
  }

  // The colour and brightness of a birth, edit or link flash, from its commit's flags.
  flagColor(f) { return this.settings.markMatt && (f & EDIT_MATT) ? this.theme.matt : this.theme.accent; }
  flagK(f) { return this.settings.quiet && (f & EDIT_QUIET) ? QUIET : 1; }

  /* ----- the activity curve ----- */

  // The curve runs along the replay, not the clock: each commit gets the stretch of
  // timeline it takes to play, so every commit can be reached by dragging.
  chartGeom() {
    const W = this.chartSize.w, H = this.chartSize.h, end = this.model.endBeat || 1;
    const x0 = 2, x1 = W - 2, top = 3, base = H - 17;
    const tx = (b) => x0 + clamp(b / end, 0, 1) * (x1 - x0);
    const fromX = (x) => clamp((x - x0) / (x1 - x0), 0, 1) * end;
    return { W, H, x0, x1, top, base, end, tx, fromX };
  }

  drawChart() {
    const ctx = this.cctx, th = this.theme, fg = th.fg, acc = th.accent;
    const W = this.chartSize.w, H = this.chartSize.h, steps = this.model.steps;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    if (!steps.length || W < 10) return;
    const g = this.chartGeom();
    const K = Math.max(2, Math.round((g.x1 - g.x0) / 2));
    if (!this.curve || this.curve.length !== K) this.curve = activityCurve(steps, g.end, K);
    const pts = [];
    for (let i = 0; i < K; i++) pts.push([g.x0 + (i / (K - 1)) * (g.x1 - g.x0), g.base - this.curve[i] * (g.base - g.top)]);
    const atEnd = this.tau >= g.end - 0.01;
    const playX = g.tx(this.tau);

    const paint = (k) => {
      const grad = ctx.createLinearGradient(0, g.top, 0, g.base);
      grad.addColorStop(0, rgba(acc, 0.45 * k));
      grad.addColorStop(1, rgba(acc, 0.03 * k));
      ctx.beginPath();
      ctx.moveTo(g.x0, g.base);
      for (const [x, y] of pts) ctx.lineTo(x, y);
      ctx.lineTo(g.x1, g.base);
      ctx.closePath();
      ctx.fillStyle = grad;
      ctx.fill();
      ctx.beginPath();
      pts.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
      ctx.lineWidth = 1.5; ctx.lineJoin = 'round';
      ctx.strokeStyle = rgba(acc, 0.95 * k);
      ctx.stroke();
    };
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, playX, H); ctx.clip(); paint(1); ctx.restore();
    ctx.save(); ctx.beginPath(); ctx.rect(playX, 0, W - playX, H); ctx.clip(); paint(atEnd ? 1 : 0.3); ctx.restore();

    // One dot per commit along the baseline; the current one in the accent colour.
    const cur = this.stepIndexAt(this.tau);
    ctx.fillStyle = rgba(fg, 0.1);
    ctx.fillRect(g.x0, g.base, g.x1 - g.x0, 1 / this.dpr);
    for (let i = 0; i < steps.length; i++) {
      const x = g.tx(steps[i].b + steps[i].span / 2);
      const isCur = i === cur, isHover = i === this.chartHover;
      ctx.fillStyle = isCur ? rgba(acc, 1) : rgba(fg, isHover ? 0.9 : i < cur ? 0.5 : 0.18);
      ctx.beginPath(); ctx.arc(x, g.base + 5, isCur || isHover ? 2.2 : 1.3, 0, TAU); ctx.fill();
    }

    // Day labels where the date changes.
    ctx.font = '10px ' + this.font;
    ctx.textBaseline = 'alphabetic';
    let lastDay = '', lastRight = -Infinity;
    for (const s of steps) {
      const day = new Date(s.t * 1000).toDateString();
      if (day === lastDay) continue;
      lastDay = day;
      const label = fmtDay(s.t), w = ctx.measureText(label).width;
      const x = clamp(g.tx(s.b), 0, W - w);
      if (x < lastRight + 10) continue;
      ctx.fillStyle = rgba(fg, 0.38);
      ctx.fillText(label, x, H - 1);
      lastRight = x + w;
    }

    // The playhead, and the commit under the pointer.
    if (!atEnd) {
      const ci = clamp(Math.round(((playX - g.x0) / (g.x1 - g.x0)) * (K - 1)), 0, K - 1);
      ctx.fillStyle = rgba(fg, 0.45);
      ctx.fillRect(Math.round(playX), g.top, 1, g.base - g.top);
      ctx.beginPath(); ctx.arc(playX, pts[ci][1], 3.5, 0, TAU);
      ctx.fillStyle = rgba(acc, 1); ctx.fill();
      ctx.lineWidth = 2; ctx.strokeStyle = th.dark ? '#18181b' : '#ffffff'; ctx.stroke();
    }
    if (this.chartHover >= 0 && steps[this.chartHover]) {
      const s = steps[this.chartHover];
      ctx.fillStyle = rgba(fg, 0.07);
      ctx.fillRect(g.tx(s.b), g.top, Math.max(2, g.tx(s.b + s.span) - g.tx(s.b)), g.base - g.top);
    }
  }

  /* ----- words ----- */

  updateHud() {
    const m = this.model, i = Math.max(0, this.stepIndexAt(this.tau)), s = m.steps[i];
    const set = (key, value, elx) => { if (this.hudCache[key] !== value) { this.hudCache[key] = value; elx.textContent = value; } };
    set('notes', fmtNum(this.counts.notes), this.statEls.notes);
    set('links', fmtNum(this.counts.links), this.statEls.links);
    // Lines count up over a commit's beats, in step with its notes growing in.
    let lines = 0;
    if (s) {
      const prev = i > 0 ? m.steps[i - 1].totals : m.baseTotals;
      const f = easeOutCubic(clamp((this.tau - s.b) / (s.span * 0.9), 0, 1));
      lines = prev.note + prev.code + (s.totals.note + s.totals.code - prev.note - prev.code) * f;
    }
    set('lines', fmtNum(lines), this.statEls.lines);
    const atEnd = this.tau >= m.endBeat - 0.01;
    this.fitBtn.classList.toggle('is-following', this.autoCam);
    set('title', s ? s.subject : '', this.nowTitle);
    set('meta', s ? `${s.author} · ${fmtWhen(s.t)}${atEnd ? ' · latest' : ''}` : '', this.nowMeta);
    const cur = s ? i : -1;
    if (cur !== this.listCurrent && this.rows) {
      this.rows.forEach((r, k) => { r.classList.toggle('is-current', k === cur); r.classList.toggle('is-future', k > cur); });
      this.listCurrent = cur;
      this.scrollListTo(cur, true);
    }
    this.updatePlayButton();
  }

  showTip(tip, lines) {
    while (tip.firstChild) tip.removeChild(tip.firstChild);
    for (const [cls, text] of lines) el(tip, 'div', cls, text);
    tip.classList.add('is-on');
    tip.dataset.w = tip.offsetWidth;
    tip.dataset.h = tip.offsetHeight;
  }

  hideTip(tip) { tip.classList.remove('is-on'); }

  placeTip() {
    const i = this.hover, N = this.ns, tip = this.tip;
    if (!tip.classList.contains('is-on') || !N.on[i]) return;
    const w = +tip.dataset.w, h = +tip.dataset.h, x = N.sx[i], y = N.sy[i] - N.r[i];
    tip.style.left = clamp(x - w / 2, 8, this.size.w - w - 8) + 'px';
    tip.style.top = (y - h - 12 < 4 ? y + N.r[i] * 2 + 14 : y - h - 12) + 'px';
  }

  /* ----- pointing, dragging, panning, zooming ----- */

  nodeAt(px, py) {
    if (!this.model) return -1;
    const N = this.ns;
    let best = -1, bestD = Infinity;
    for (let i = 0; i < this.model.nodes.length; i++) {
      if (!N.on[i] || N.dying[i]) continue;
      const dx = N.sx[i] - px, dy = N.sy[i] - py, d = dx * dx + dy * dy, reach = Math.max(9, N.r[i] + 5);
      if (d < reach * reach && d < bestD) { best = i; bestD = d; }
    }
    return best;
  }

  bindGraphEvents() {
    const c = this.canvas;
    let drag = null;
    const local = (e) => { const r = c.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    c.addEventListener('pointerdown', (e) => {
      this.root.focus({ preventScroll: true });
      const [x, y] = local(e);
      drag = { x, y, cx: this.cam.x, cy: this.cam.y, moved: false, node: this.nodeAt(x, y) };
      c.setPointerCapture(e.pointerId);
    });
    c.addEventListener('pointermove', (e) => {
      const [x, y] = local(e);
      if (drag) {
        if (!drag.moved && Math.hypot(x - drag.x, y - drag.y) > 3) {
          drag.moved = true;
          if (drag.node >= 0 && this.settings.physics) {
            // Pick the dot up: it follows the pointer and its circle comes with it.
            this.dragNode = drag.node;
            this.hover = drag.node;
            this.hideTip(this.tip);
            this.wake();
            c.classList.add('is-dragging');
          } else {
            c.classList.add('is-panning');
            this.setHover(-1);
          }
        }
        if (drag.moved) {
          if (this.dragNode >= 0) {
            [this.sim.fx, this.sim.fy] = this.toWorld(x, y);
          } else {
            this.autoCam = false;
            this.cam.x = drag.cx - (x - drag.x) / this.cam.k;
            this.cam.y = drag.cy - (y - drag.y) / this.cam.k;
          }
          this.requestFrame();
        }
        return;
      }
      this.setHover(this.nodeAt(x, y));
    });
    const end = (e) => {
      if (!drag) return;
      const d = drag;
      drag = null;
      c.classList.remove('is-panning', 'is-dragging');
      if (this.dragNode >= 0) {
        this.dragNode = -1;
        this.requestFrame();
      }
      if (!d.moved && d.node >= 0 && e.type === 'pointerup') this.openNode(d.node, e.metaKey || e.ctrlKey);
    };
    c.addEventListener('pointerup', end);
    c.addEventListener('pointercancel', end);
    c.addEventListener('pointerleave', () => { if (!drag) this.setHover(-1); });
    c.addEventListener('dblclick', () => { this.autoCam = true; this.requestFrame(); });
    c.addEventListener('wheel', (e) => {
      e.preventDefault();
      if (!this.model) return;
      const [x, y] = local(e);
      const k = clamp(this.cam.k * Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0015)), 0.05, 12);
      const [wx, wy] = this.toWorld(x, y);
      const { ox, oy } = this.origin || { ox: 0, oy: 0 };
      this.cam.k = k;
      this.cam.x = wx - (x - ox) / k;
      this.cam.y = wy - (y - oy) / k;
      this.autoCam = false;
      this.camReady = true;
      this.setHover(-1);
      this.requestFrame();
    }, { passive: false });
  }

  setHover(i) {
    if (i === this.hover) return;
    this.hover = i;
    this.canvas.classList.toggle('is-node', i >= 0);
    if (i < 0) this.hideTip(this.tip); else {
      const nd = this.model.nodes[i], N = this.ns;
      const born = this.model.steps[Math.max(0, this.stepIndexAt(nd.spans[0].b))];
      const meta = `${N.deg[i]} link${N.deg[i] === 1 ? '' : 's'} · since ${fmtDay(born.t)}`;
      this.showTip(this.tip, [['bg-tip-title', noteName(nd.path)], ['bg-tip-meta', meta]]);
      this.placeTip();
    }
    this.requestFrame();
  }

  async openNode(i, newTab) {
    const nd = this.model.nodes[i];
    let path = nd.path;
    if (this.prefix) { if (!path.startsWith(this.prefix)) return; path = path.slice(this.prefix.length); }
    const file = this.app.vault.getAbstractFileByPath(path);
    if (!(file instanceof TFile)) { new Notice(`${path} isn’t in the vault now.`); return; }
    if (file.extension !== 'md') {
      if (typeof this.app.openWithDefaultApp === 'function') this.app.openWithDefaultApp(path); else new Notice(path);
      return;
    }
    const ws = this.app.workspace;
    let leaf = null;
    if (newTab) leaf = ws.getLeaf('tab');
    else {
      if (this.readLeaf && ws.getLeavesOfType('markdown').includes(this.readLeaf)) leaf = this.readLeaf;
      else leaf = this.readLeaf = ws.getLeaf('split', 'vertical');
    }
    await leaf.openFile(file, { active: false });
  }

  // The activity curve: drag along it to move through the replay, point at it for a
  // commit's details, and scroll over it to step one commit at a time.
  bindChartEvents() {
    const c = this.chart;
    let scrubbing = false;
    const local = (e) => { const r = c.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    const hoverAt = (x) => {
      const g = this.chartGeom();
      const i = clamp(this.stepIndexAt(g.fromX(x)), 0, this.model.steps.length - 1);
      if (i === this.chartHover) return;
      this.chartHover = i;
      const s = this.model.steps[i];
      const lines = s.merge ? 'Merge commit' : `+${fmtNum(s.add.note + s.add.code)}  −${fmtNum(s.del.note + s.del.code)} lines`;
      this.showTip(this.chartTip, [['bg-tip-meta', `${s.author} · ${fmtWhen(s.t)}`], ['bg-tip-title', s.subject], ['bg-tip-meta', lines]]);
      const w = +this.chartTip.dataset.w, h = +this.chartTip.dataset.h;
      const cx = this.chartWrap.offsetLeft + g.tx(s.b + s.span / 2);
      this.chartTip.style.left = clamp(cx - w / 2, 0, this.dock.clientWidth - w) + 'px';
      this.chartTip.style.top = -h - 10 + 'px';
      this.requestFrame();
    };
    c.addEventListener('pointerdown', (e) => {
      if (!this.model || !this.model.steps.length) return;
      this.root.focus({ preventScroll: true });
      scrubbing = true;
      c.setPointerCapture(e.pointerId);
      this.glideTo(this.chartGeom().fromX(local(e)[0]));
    });
    c.addEventListener('pointermove', (e) => {
      if (!this.model || !this.model.steps.length) return;
      const x = local(e)[0];
      if (scrubbing) this.glideTo(this.chartGeom().fromX(x));
      hoverAt(x);
    });
    const end = () => { scrubbing = false; };
    c.addEventListener('pointerup', end);
    c.addEventListener('pointercancel', end);
    c.addEventListener('pointerleave', () => { if (this.chartHover >= 0) { this.chartHover = -1; this.hideTip(this.chartTip); this.requestFrame(); } });
    c.addEventListener('wheel', (e) => {
      e.preventDefault();
      if (!this.model) return;
      const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
      if (e.deltaMode !== 0 || Math.abs(d) >= 50) { this.wheelAcc = 0; this.stepBy(Math.sign(d)); return; }
      this.wheelAcc += d;
      if (Math.abs(this.wheelAcc) >= 40) { this.stepBy(Math.sign(this.wheelAcc)); this.wheelAcc = 0; }
    }, { passive: false });
  }
}

/* ---------- the plugin ---------- */

class BrainGraphPlugin extends Plugin {
  async onload() {
    this.settings = Object.assign({}, DEFAULT_SETTINGS, await this.loadData());
    // Settings that went with the Graph and Tree views (20 Oct 2026) drop out of data.json next time it's saved.
    for (const k of Object.keys(this.settings)) if (!(k in DEFAULT_SETTINGS)) delete this.settings[k];
    this.registerView(VIEW_TYPE, (leaf) => new BrainView(leaf, this));
    this.addRibbonIcon('brain-circuit', 'Open brain graph', () => this.openView());
    this.addCommand({ id: 'open', name: 'Open brain graph', callback: () => this.openView() });
  }

  async saveSettings() { await this.saveData(this.settings); }

  async openView() {
    const ws = this.app.workspace;
    const existing = ws.getLeavesOfType(VIEW_TYPE)[0];
    if (existing) { ws.revealLeaf(existing); return; }
    const leaf = ws.getLeaf('tab');
    await leaf.setViewState({ type: VIEW_TYPE, active: true });
    ws.revealLeaf(leaf);
  }
}

module.exports = BrainGraphPlugin;
