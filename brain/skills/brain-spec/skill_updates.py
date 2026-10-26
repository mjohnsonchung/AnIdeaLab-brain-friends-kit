#!/usr/bin/env python3
"""Check which copied skills have changed where they came from, since the brain copied them.

Matt, 20 Oct 2026: "how are you checking that these skills are out of date or not? Is
there like an easy script to check?" This is it. Every set of copied skills has a heading
in skills/lists/sources.md, the record of copied skills (26 Oct 2026; before, these lines
were spread through the topic lists), with a line like

    From [obra/superpowers](https://github.com/obra/superpowers), commit `bb92a77`, copied 19 Oct 2026.

followed by its skills, one "- [name](../name/SKILL.md)" line each. The script reads
those lines, finds each skill's folder in the source repo at that commit, and then asks
git whether that folder has changed between the copied commit and the repo's newest
commit. It compares the source with itself, so the brain's own changes to its copies
(the folder name, the name: line, links) never show up as differences.

    python3 skills/brain-spec/skill_updates.py map            # match each copied skill to its folder upstream
    python3 skills/brain-spec/skill_updates.py check          # which ones changed upstream since they were copied
    python3 skills/brain-spec/skill_updates.py diff NAME      # what changed upstream in one skill
    python3 skills/brain-spec/skill_updates.py update --source obra/superpowers   # or --all; --dry-run first
    python3 skills/brain-spec/skill_updates.py check --source obra/superpowers

`update` puts each upstream change into the brain's copy with a three-way merge
(git merge-file), so the brain's own changes stay. A skill whose file changed in the
same place on both sides is left as it was and reported, to merge by hand. When every
changed skill from a source is in, it moves the source's commit on in sources.md and adds "updated
<date>". Read the result with git diff before committing.

`map` writes skills/sources/upstream.json, so `check` needn't redo the matching; run it
again after copying in or updating a set (and after editing a commit in sources.md). `check`
also compares the Anthropic skills copied on 18 Oct 2026, which have no commit, with
Anthropic's current copies when the machine has them (/mnt/skills/ and
~/.claude/skills/synced/ in a claude.ai/code session).

It needs git and network access to github.com, and nothing outside Python's standard
library. Source repos are kept as small partial clones (history without file contents)
in ~/.cache/brain-skill-updates, so a check takes seconds once they exist.
"""
import argparse
import difflib
import json
import os
import re
import subprocess
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
SKILLS = os.path.dirname(HERE)  # skills/brain-spec/ sits inside skills/
ROOT = os.path.dirname(SKILLS)
MANIFEST = os.path.join(SKILLS, "sources", "upstream.json")
SOURCES = os.path.join(SKILLS, "lists", "sources.md")  # the record of copied skills and their commits
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "brain-skill-updates")
LOCAL_ANTHROPIC = ["/mnt/skills/public", "/mnt/skills/examples", os.path.expanduser("~/.claude/skills/synced/*")]

FROM = re.compile(r"From \[[^\]]+\]\(https://github\.com/([\w.-]+/[\w.-]+?)/?\), commit `([0-9a-f]{7,40})`, copied ([^.,;]+)")
ITEM = re.compile(r"^- \[([a-z0-9][a-z0-9-]*)\]\((?:\.\./)?\1/SKILL\.md\)")
HEADING = re.compile(r"^#{1,6} ")


def git(repo, *args, stdin=None, check=True):
    """Run git in a cached clone; return stdout."""
    r = subprocess.run(["git", "-C", repo, *args], input=stdin, capture_output=True, text=True, errors="replace")
    if check and r.returncode:
        raise RuntimeError(f"git {' '.join(args[:3])}: {r.stderr.strip()[:300]}")
    return r.stdout


def clone(repo):
    """Make or refresh a partial clone of github.com/<repo> and return (path, newest commit)."""
    path = os.path.join(CACHE, repo.replace("/", "__") + ".git")
    url = f"https://github.com/{repo}"
    if not os.path.isdir(path):
        os.makedirs(CACHE, exist_ok=True)
        r = subprocess.run(["git", "clone", "-q", "--bare", "--filter=blob:none", url, path], capture_output=True, text=True)
        if r.returncode:
            raise RuntimeError(f"clone {repo}: {r.stderr.strip()[:300]}")
    git(path, "fetch", "-q", "--filter=blob:none", "origin", "HEAD")
    return path, git(path, "rev-parse", "FETCH_HEAD").strip()


def newest(repo):
    """The source's newest commit, without cloning."""
    r = subprocess.run(["git", "ls-remote", f"https://github.com/{repo}", "HEAD"], capture_output=True, text=True)
    if r.returncode or not r.stdout:
        raise RuntimeError(f"ls-remote {repo}: {r.stderr.strip()[:300] or 'no HEAD'}")
    return r.stdout.split()[0]


def skill_dirs(path, commit):
    """{folder: blob id of its SKILL.md} for every skill in the repo at a commit."""
    out = {}
    for line in git(path, "ls-tree", "-r", commit).splitlines():
        meta, p = line.split("\t", 1)
        if os.path.basename(p).lower() == "skill.md":
            out[os.path.dirname(p)] = meta.split()[2]
    return out


def read_blobs(path, oids):
    """Fetch file contents in one request, then read them."""
    oids = sorted(set(oids))
    git(path, "-c", "fetch.negotiationAlgorithm=noop", "fetch", "-q", "--no-tags", "--no-write-fetch-head",
        "--recurse-submodules=no", "--filter=blob:none", "--stdin", "origin", stdin="\n".join(oids) + "\n", check=False)
    return {o: git(path, "cat-file", "blob", o, check=False) for o in oids}


def frontmatter(text):
    """(name, description) from a SKILL.md's front matter, whitespace and quotes tidied."""
    m = re.match(r"﻿?---\s*\n(.*?)\n---", text.replace("\r\n", "\n"), re.S)
    head = m.group(1) if m else ""
    fields = {}
    key = None
    for line in head.splitlines():
        km = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if km:
            key = km.group(1).lower()
            fields[key] = km.group(2)
        elif key and line.startswith((" ", "\t")):
            fields[key] += " " + line.strip()
    tidy = lambda s: re.sub(r"\s+", " ", (s or "").strip().strip("\"'>|-").strip()).lower()
    return tidy(fields.get("name")), tidy(fields.get("description"))


def body(text):
    """A SKILL.md without its name: line, which the brain changes."""
    return re.sub(r"(?m)^name:.*$", "", text.replace("\r\n", "\n"))


def read_sections():
    """Every "From [owner/repo](...), commit `x`" line in skills/lists/sources.md, with the skills listed under it."""
    files = [f for f in [SOURCES] if os.path.isfile(f)]
    sections, current = [], None
    for f in files:
        for line in open(f, encoding="utf-8"):
            if HEADING.match(line):
                current = None
            m = FROM.search(line)
            if m:
                current = {"repo": m.group(1), "commit": m.group(2), "copied": m.group(3).strip(),
                           "list": os.path.relpath(f, ROOT), "skills": []}
                sections.append(current)
                continue
            im = ITEM.match(line)
            if im and current is not None:
                current["skills"].append(im.group(1))
    return sections


def match(brain_names, upstream, texts):
    """Pair each brain skill with its upstream folder: same description first, then the name."""
    info = {d: frontmatter(texts.get(oid, "")) for d, oid in upstream.items()}
    by_desc = {}
    for d, (_, desc) in info.items():
        if desc:
            by_desc.setdefault(desc, []).append(d)
    found, missing = {}, []
    for name in brain_names:
        p = os.path.join(SKILLS, name, "SKILL.md")
        _, desc = frontmatter(open(p, encoding="utf-8").read()) if os.path.isfile(p) else ("", "")
        cands = by_desc.get(desc, []) if desc else []
        if len(cands) != 1:  # no description match, or several: fall back on the name
            pool = cands or list(upstream)
            def named(d):
                n = info[d][0] or os.path.basename(d)
                return {n, os.path.basename(d)}
            cands = [d for d in pool if name in named(d)] or \
                    [d for d in pool if any(name.endswith("-" + n) for n in named(d) if n)]
        if len(cands) > 1:  # the same skill in several folders upstream: take the one most like the brain's copy
            mine = body(open(p, encoding="utf-8").read())
            cands.sort(key=lambda d: (-difflib.SequenceMatcher(None, body(texts.get(upstream[d], "")), mine,
                                                                autojunk=False).ratio(), len(d)))
        if cands:
            found[name] = cands[0]
        else:
            missing.append(name)
    return found, missing


def do_map(args):
    sources = {}
    for s in read_sections():
        key = f"{s['repo']}@{s['commit']}"
        src = sources.setdefault(key, {"repo": s["repo"], "commit": s["commit"], "copied": s["copied"], "lists": [], "names": []})
        if s["list"] not in src["lists"]:
            src["lists"].append(s["list"])
        src["names"] += [n for n in s["skills"] if n not in src["names"]]
    out, problems = [], 0
    for key, src in sorted(sources.items()):
        if args.source and src["repo"] != args.source:
            continue
        try:
            path, _ = clone(src["repo"])
            full = git(path, "rev-parse", "--verify", src["commit"] + "^{commit}").strip()
            upstream = skill_dirs(path, full)
            texts = read_blobs(path, upstream.values())
            found, missing = match(src["names"], upstream, texts)
        except RuntimeError as e:
            print(f"{key}: {e}")
            problems += 1
            continue
        out.append({"repo": src["repo"], "commit": full, "copied": src["copied"], "lists": src["lists"],
                    "skills": dict(sorted(found.items())), "not_found": missing})
        note = f", not found upstream: {', '.join(missing)}" if missing else ""
        print(f"{src['repo']} @ {src['commit']}: {len(found)} of {len(src['names'])} matched{note}")
        problems += bool(missing)
    if args.source and os.path.isfile(MANIFEST):  # keep the other sources as they were
        old = json.load(open(MANIFEST, encoding="utf-8"))["sources"]
        out = [s for s in old if s["repo"] != args.source] + out
        out.sort(key=lambda s: s["repo"])
    json.dump({"made": date.today().isoformat(), "how": "python3 skills/brain-spec/skill_updates.py map",
               "sources": out}, open(MANIFEST, "w", encoding="utf-8"), indent=1)
    open(MANIFEST, "a").write("\n")
    print(f"Wrote {os.path.relpath(MANIFEST, ROOT)}: {sum(len(s['skills']) for s in out)} skills from {len(out)} sources.")
    return 1 if problems else 0


def load():
    if not os.path.isfile(MANIFEST):
        sys.exit("No skills/sources/upstream.json yet: run `python3 skills/brain-spec/skill_updates.py map` first.")
    return json.load(open(MANIFEST, encoding="utf-8"))["sources"]


def check_source(src):
    """What changed upstream in this source's copied skills."""
    head = newest(src["repo"])
    if head == src["commit"]:
        return head, 0, {}, {}, []
    path, head = clone(src["repo"])
    behind = int(git(path, "rev-list", "--count", f"{src['commit']}..{head}").strip() or 0)
    changed_files = git(path, "diff", "--name-only", src["commit"], head).splitlines()
    now = skill_dirs(path, head)
    changed, gone = {}, {}
    for name, d in src["skills"].items():
        if d not in now:  # say which commit took it away, whose message usually says where it went
            gone[name] = git(path, "log", "-1", "--format=%h %s", f"{src['commit']}..{head}", "--", d).strip()
            continue
        files = [f for f in changed_files if f.startswith(d + "/")]
        if files:
            changed[name] = files
    then = skill_dirs(path, src["commit"])
    new = sorted(d for d in now if d not in then)
    return head, behind, changed, gone, new


def check_local():
    """The 18 Oct 2026 Anthropic copies against the copies on this machine, if it has them."""
    import glob
    dirs = [d for pattern in LOCAL_ANTHROPIC for d in glob.glob(pattern) if os.path.isdir(d)]
    if not dirs:
        return None
    def norm(p, skill_md):
        try:
            t = open(p, encoding="utf-8").read().replace("\r\n", "\n")
        except (UnicodeDecodeError, OSError):
            return open(p, "rb").read()
        if skill_md:  # the brain changes the name: line and may add an "In this brain" section
            t = re.sub(r"(?m)^name:.*\n", "", t, count=1)
            t = re.split(r"(?m)^#+ In this brain", t)[0]
        return t.rstrip()
    report = []
    for base in dirs:
        for name in sorted(os.listdir(base)):
            theirs, ours = os.path.join(base, name), os.path.join(SKILLS, name)
            if not os.path.isfile(os.path.join(theirs, "SKILL.md")):
                continue
            if not os.path.isdir(ours):
                report.append((name, "not in the brain"))
                continue
            diff = []
            for dp, _, fs in os.walk(theirs):
                for f in fs:
                    rel = os.path.relpath(os.path.join(dp, f), theirs)
                    mine = os.path.join(ours, rel)
                    if not os.path.isfile(mine):
                        diff.append(rel + " (missing)")
                    elif norm(os.path.join(dp, f), rel == "SKILL.md") != norm(mine, rel == "SKILL.md"):
                        diff.append(rel)
            if diff:
                report.append((name, "differs: " + ", ".join(sorted(diff))))
    return dirs, report


def do_check(args):
    sources = [s for s in load() if not args.source or s["repo"] == args.source]
    stale = 0
    for src in sources:
        try:
            head, behind, changed, gone, new = check_source(src)
        except RuntimeError as e:
            print(f"? {src['repo']}: couldn't check ({e})")
            continue
        label = f"{src['repo']} (copied {src['copied']}, in {', '.join(src['lists'])})"
        if not (changed or gone):
            extra = f"; {behind} newer commits, none in the copied skills" if behind else ""
            extra += f"; new upstream since: {', '.join(new)}" if new and args.verbose else ""
            if args.verbose or new:
                print(f"ok {label}{extra}" + (f"; {len(new)} new skills upstream" if new and not args.verbose else ""))
            continue
        stale += len(changed) + len(gone)
        print(f"\n{label}: {behind} newer commits, now {head[:7]}")
        for name, files in sorted(changed.items()):
            print(f"  changed  {name}  ({len(files)} files: {', '.join(files[:4])}{' ...' if len(files) > 4 else ''})")
        for name, why in sorted(gone.items()):
            print(f"  removed  {name}  (its folder {src['skills'][name]} is gone upstream, in {why or 'a newer commit'})")
        if new:
            print(f"  new upstream since the copy: {', '.join(new)}")
    if not args.source:
        local = check_local()
        if local:
            dirs, report = local
            if report:
                print(f"\nAnthropic copies on this machine ({', '.join(dirs)}):")
                for name, what in report:
                    print(f"  {name}: {what}")
                stale += sum(1 for _, w in report if w.startswith("differs"))
            else:
                print(f"\nAnthropic's 18 Oct copies match this machine's ({', '.join(dirs)}).")
    print(f"\n{stale} copied skills differ from their source." if stale else "\nEvery copied skill matches its source.")
    return 0


def tree(path, commit, d):
    """{path inside the skill folder: blob id} at a commit."""
    out = {}
    for line in git(path, "ls-tree", "-r", commit, "--", d + "/").splitlines():
        meta, p = line.split("\t", 1)
        out[os.path.relpath(p, d)] = meta.split()[2]
    return out


def merge3(mine, base, theirs):
    """Put the upstream change (base to theirs) into the brain's copy; None if the two clash."""
    import tempfile
    with tempfile.TemporaryDirectory() as t:
        paths = []
        for label, text in (("mine", mine), ("base", base), ("theirs", theirs)):
            paths.append(os.path.join(t, label))
            open(paths[-1], "wb").write(text)
        r = subprocess.run(["git", "merge-file", "-p", *paths], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def update_source(src, today, dry_run):
    """Bring every changed skill from one source up to date. Returns (updated, needs_hand, gone)."""
    head, behind, changed, gone, _ = check_source(src)
    if not changed:
        return head, [], [], gone
    path, head = clone(src["repo"])
    # Upstream links between sibling skills use upstream folder names; the brain's copies use brain names.
    renames = {os.path.basename(d): n for n, d in src["skills"].items() if os.path.basename(d) != n}
    def brainify(rel, text, name):
        if rel.lower() == "skill.md":
            text = re.sub(rb"(?m)^name:.*$", b"name: " + name.encode(), text, count=1)
        for up, mine in renames.items():
            text = text.replace(b"../" + up.encode() + b"/", b"../" + mine.encode() + b"/")
        return text
    updated, by_hand = [], []
    for name in sorted(changed):
        d = src["skills"][name]
        old, new = tree(path, src["commit"], d), tree(path, head, d)
        blobs = read_blobs(path, list(old.values()) + list(new.values()))
        raw = lambda oid: subprocess.run(["git", "-C", path, "cat-file", "blob", oid], capture_output=True).stdout
        writes, clashes = {}, []
        for rel in sorted(set(old) | set(new)):
            if old.get(rel) == new.get(rel):
                continue
            o = brainify(rel, raw(old[rel]), name) if rel in old else None
            n = brainify(rel, raw(new[rel]), name) if rel in new else None
            mine_path = os.path.join(SKILLS, name, rel)
            b = open(mine_path, "rb").read() if os.path.isfile(mine_path) else None
            if n is None:  # deleted upstream
                if b is not None and b != o:
                    clashes.append(f"{rel} (deleted upstream, changed in the brain)")
                elif b is not None:
                    writes[rel] = None
            elif b is None:
                if o is None:
                    writes[rel] = n  # new upstream
                else:
                    clashes.append(f"{rel} (changed upstream, not in the brain's copy)")
            elif b in (o, n):
                if b != n:
                    writes[rel] = n
            else:
                merged = merge3(b, o, n) if o is not None and b"\0" not in b + o + n else None
                if merged is None:
                    clashes.append(f"{rel} (changed upstream and in the brain, in the same place)")
                elif merged != b:
                    writes[rel] = merged
        if clashes:
            by_hand.append((name, clashes))
            continue  # leave the whole skill as it was
        for rel, data in writes.items():
            target = os.path.join(SKILLS, name, rel)
            if dry_run:
                continue
            if data is None:
                os.remove(target)
            else:
                os.makedirs(os.path.dirname(target), exist_ok=True)
                open(target, "wb").write(data)
        updated.append((name, sorted(writes)))
    if not by_hand and not dry_run:  # every changed skill is in: move the list's commit on
        for lst in src["lists"]:
            p = os.path.join(ROOT, lst)
            text = open(p, encoding="utf-8").read()
            pat = re.compile(r"(From \[[^\]]+\]\(https://github\.com/" + re.escape(src["repo"]) + r"/?\), commit `)"
                             + src["commit"][:7] + r"[0-9a-f]*(`, copied [^.,;]+?)(, updated [^.,;]+)?(?=[.,;])")
            text = pat.sub(lambda m: m.group(1) + head[:7] + m.group(2) + f", updated {today}", text)
            open(p, "w", encoding="utf-8").write(text)
    return head, updated, by_hand, gone


def do_update(args):
    if not args.source and not args.all:
        sys.exit("Say which: --source owner/repo, or --all.")
    d = date.today()
    today = f"{d.day} {d:%b %Y}"
    moved = []
    for src in load():
        if args.source and src["repo"] != args.source:
            continue
        try:
            head, updated, by_hand, gone = update_source(src, today, args.dry_run)
        except RuntimeError as e:
            print(f"? {src['repo']}: couldn't update ({e})")
            continue
        if not (updated or by_hand or gone):
            continue
        print(f"\n{src['repo']}: {src['commit'][:7]} -> {head[:7]}{' (dry run, nothing written)' if args.dry_run else ''}")
        for name, files in updated:
            print(f"  updated  {name}  ({', '.join(files) or 'no change needed'})")
        for name, clashes in by_hand:
            print(f"  by hand  {name}: {'; '.join(clashes)}. See `skill_updates.py diff {name}`.")
        for name, why in sorted(gone.items()):
            print(f"  removed upstream  {name}  ({why}): decide whether to delete it or follow it to its new home.")
        if updated and not by_hand and not args.dry_run:
            moved.append(src["repo"])
    for repo in moved:  # match the skills again at the new commit
        do_map(argparse.Namespace(source=repo))
    if moved:
        print("\nRead what changed (git diff) before committing: an update can add new steps, tools or network calls.")
    return 0


def do_diff(args):
    for src in load():
        if args.name in src["skills"]:
            d = src["skills"][args.name]
            path, head = clone(src["repo"])
            print(f"{src['repo']} {d}: {src['commit'][:7]}..{head[:7]}\n")
            sys.stdout.write(git(path, "diff", "--stat", "-p", src["commit"], head, "--", d))
            return 0
    sys.exit(f"{args.name} isn't in skills/sources/upstream.json (run `map`, or it has no source commit).")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for cmd in ("map", "check"):
        p = sub.add_parser(cmd)
        p.add_argument("--source", help="only this owner/repo")
        p.add_argument("-v", "--verbose", action="store_true", help="also list sources that are up to date")
    sub.add_parser("diff").add_argument("name", help="a copied skill's folder name")
    p = sub.add_parser("update")
    p.add_argument("--source", help="only this owner/repo")
    p.add_argument("--all", action="store_true", help="every source")
    p.add_argument("--dry-run", action="store_true", help="say what would change, write nothing")
    args = ap.parse_args()
    return {"map": do_map, "check": do_check, "diff": do_diff, "update": do_update}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
