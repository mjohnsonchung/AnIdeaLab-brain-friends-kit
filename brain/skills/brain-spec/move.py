#!/usr/bin/env python3
"""Move files and folders in the brain without breaking the links to them.

Written for the brain restructure (19 Oct 2026), and kept for any later move.

Usage: python3 skills/brain-spec/move.py MAP [--dry-run]

MAP is a text file with one move per line, as old<TAB>new, paths from the repo root.
A line whose old path ends in "/" moves a folder and everything in it. Blank lines
and lines starting "#" are skipped. A file's own line wins over its folder's line,
and a longer folder wins over a shorter one.

What it does, in order:
1. Links. For every tracked .md file, it rewrites each relative Markdown link, so it
   points at the same file after the move, from the linking file's new place. A
   "#heading" after the path is kept. Links in code blocks, http: and mailto: links,
   and links to a "#heading" alone are left as they are. A link whose words are the
   old path, like [hq/routines.md](...), gets the new path as its words too (without
   "knowledge/" in front). A file whose links don't change isn't touched, so copied
   skills stay as they came.
2. Moving. It moves the files with git mv, making folders as needed, and removes
   folders the move leaves empty.
3. Report. Last, it prints every remaining plain-text mention of an old path, as
   file:line, for fixing by hand (paths in backticks, scripts, workflows, comments).

With --dry-run it prints what it would change and the report, and changes nothing.
It uses Python's standard library only.
"""
import os
import re
import subprocess
import sys
from urllib.parse import quote, unquote

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.exists(os.path.join(ROOT, ".git")) and os.path.dirname(ROOT) != ROOT:
    ROOT = os.path.dirname(ROOT)
LINK = re.compile(r"(\[([^\]]*)\]\()([^)\s]+)(\))")
FENCE = re.compile(r"```.*?```", re.S)  # as check_links.py reads code blocks
TEXT = {".md", ".py", ".js", ".mjs", ".css", ".json", ".yml", ".yaml", ".txt", ".html", ".sh", ".ps1"}


def git(*args):
    return subprocess.check_output(["git", "-C", ROOT, *args]).decode("utf-8")


def tracked():
    return [p for p in git("ls-files", "-z").split("\0") if p]


def read_map(path):
    files, folders = {}, []
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                sys.exit(f"{path}:{n}: expected old<TAB>new, got {line!r}")
            old, new = (p.strip() for p in parts)
            if old.endswith("/"):
                folders.append((old, new.rstrip("/") + "/"))
            else:
                files[old] = new
    folders.sort(key=lambda f: -len(f[0]))
    return files, folders


def mover(files, folders):
    """A function from an old repo path (file or folder) to its new path."""
    def new_path(old, is_dir=False):
        if old in files:
            return files[old]
        probe = old.rstrip("/") + "/" if is_dir else old
        for src, dst in folders:
            if probe.startswith(src):
                return (dst + probe[len(src):]).rstrip("/") if is_dir else dst + probe[len(src):]
        return old
    return new_path


def split_fences(text):
    """The text in pieces, each marked True if it's inside a fenced code block."""
    pieces, last = [], 0
    for m in FENCE.finditer(text):
        pieces.append((text[last:m.start()], False))
        pieces.append((m.group(0), True))
        last = m.end()
    pieces.append((text[last:], False))
    return pieces


def relink(note, new_note, text, new_path):
    """The note's text with its links fixed for the move, and how many changed."""
    old_dir, new_dir = os.path.dirname(note), os.path.dirname(new_note)
    changed = 0

    def fix(m):
        nonlocal changed
        words, target = m.group(2), m.group(3)
        if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I) or target.startswith("#"):
            return m.group(0)
        raw, hash_, section = target.partition("#")
        path = unquote(raw)
        old_target = os.path.normpath(os.path.join(old_dir, path))
        if old_target.startswith(".."):
            return m.group(0)
        full = os.path.join(ROOT, old_target)
        if not os.path.exists(full):
            return m.group(0)
        is_dir = os.path.isdir(full)
        new_target = new_path(old_target, is_dir)
        if new_target == old_target and new_dir == old_dir:
            return m.group(0)
        rel = os.path.relpath(new_target, new_dir or ".").replace(os.sep, "/")
        if is_dir and raw.endswith("/"):
            rel += "/"
        if "%" in raw:
            rel = quote(rel)
        if os.path.normpath(rel) == os.path.normpath(path):
            return m.group(0)
        changed += 1
        bare = words.strip("`").rstrip("/")
        if bare and bare in (old_target, path.rstrip("/")) and new_target != old_target:
            label = new_target[len("knowledge/"):] if new_target.startswith("knowledge/") else new_target
            label += "/" if words.strip("`").endswith("/") else ""
            words = words.replace(words.strip("`"), label)
        return "[" + words + "](" + rel + hash_ + section + m.group(4)

    out = []
    for piece, fenced in split_fences(text):
        out.append(piece if fenced else LINK.sub(fix, piece))
    return "".join(out), changed


def mention_pattern(old):
    """A pattern for a plain-text mention of an old path."""
    if old.endswith("/"):  # a folder: only its name with the slash, so plain words don't match
        return re.compile(r"(?<![\w.-])" + re.escape(old))
    return re.compile(r"(?<![\w.-])" + re.escape(old) + r"(?![\w-])")


def report(paths, olds):
    patterns = [(o, mention_pattern(o)) for o in olds]
    hits = []
    for p in paths:
        ext = os.path.splitext(p)[1].lower()
        full = os.path.join(ROOT, p)
        if ext not in TEXT or not os.path.isfile(full):
            continue
        try:
            with open(full, encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except UnicodeDecodeError:
            continue
        for n, line in enumerate(lines, 1):
            plain = LINK.sub(lambda m: m.group(1) + m.group(4), line) if ext == ".md" else line
            for old, pat in patterns:
                if pat.search(plain):
                    hits.append(f"{p}:{n}: {old}: {line.strip()[:160]}")
                    break
    return hits


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in argv
    if len(args) != 1:
        sys.exit(__doc__)
    files, folders = read_map(args[0])
    new_path = mover(files, folders)
    all_files = tracked()

    moves = []
    for p in all_files:
        q = new_path(p)
        if q != p:
            moves.append((p, q))
    for old in list(files) + [f for f, _ in folders]:
        if not any(p == old or p.startswith(old) for p, _ in moves) and not any(p == old for p in all_files):
            print(f"warning: nothing tracked at {old}")
    targets = [q for _, q in moves]
    staying = set(all_files) - {p for p, _ in moves}
    clash = [q for q in targets if q in staying or os.path.exists(os.path.join(ROOT, q))] + \
            [q for q in set(targets) if targets.count(q) > 1]
    if clash:
        sys.exit("These new paths are taken already: " + ", ".join(sorted(set(clash))))

    edits = []
    for note in all_files:
        if not note.endswith(".md"):
            continue
        with open(os.path.join(ROOT, note), encoding="utf-8") as fh:
            text = fh.read()
        new_text, changed = relink(note, new_path(note), text, new_path)
        if changed:
            edits.append((note, new_text, changed))

    print(f"{len(moves)} files to move, {sum(c for *_, c in edits)} links to fix in {len(edits)} notes.")
    for note, _, changed in edits:
        print(f"  links: {note} ({changed})")
    if dry:
        for p, q in moves[:40]:
            print(f"  move: {p} -> {q}")
        if len(moves) > 40:
            print(f"  ... and {len(moves) - 40} more moves")
    else:
        for note, new_text, _ in edits:
            with open(os.path.join(ROOT, note), "w", encoding="utf-8") as fh:
                fh.write(new_text)
        for p, q in moves:
            os.makedirs(os.path.join(ROOT, os.path.dirname(q)), exist_ok=True)
            git("mv", p, q)
        for p, _ in moves:
            d = os.path.dirname(os.path.join(ROOT, p))
            while d != ROOT and os.path.isdir(d) and not os.listdir(d):
                os.rmdir(d)
                d = os.path.dirname(d)

    olds = list(files) + [f for f, _ in folders]
    after = [q for q in (new_path(p) for p in all_files)] if not dry else all_files
    hits = report(after, olds)
    print(f"Plain-text mentions of old paths left to fix by hand: {len(hits)}")
    for h in hits:
        print("  " + h)


if __name__ == "__main__":
    main(sys.argv)
