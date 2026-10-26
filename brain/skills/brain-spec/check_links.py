#!/usr/bin/env python3
"""Check the brain's notes for problems a script can find, for the weekly brain audit.

It reports:
- links in notes that point at files that don't exist,
- links to a section (note.md#heading) whose heading isn't in that note,
- notes that no other note links to (a finished library note is fine: its index counts it),
- big or binary files in the repo (they belong on the PC or in a files repo),
- the core and the longest indexes (README.md files in knowledge/), which agents read first.

Skills copied in unchanged from another provider (the folders linked under "Copied
skills" in skills/README.md, 18 Oct 2026, and in the lists it links in skills/lists/,
19 Oct 2026) are kept as they came, so their own links, notes and asset files are
counted in one line, not listed. The lists themselves are the brain's, and checked. A list
linked under "Copied skills" stays a list of copied skills even if "The brain's own" links it
too, say in a line on where its own skills came from (a friend's brain, 26 Oct 2026).

Run it from anywhere: python3 skills/brain-spec/check_links.py
It exits with 1 if any link is broken, so it can also run as a check.
How the audit uses it: skills/brain-audit/SKILL.md.
"""
import collections
import os
import re
import subprocess
import sys
from urllib.parse import unquote

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # skills/brain-spec/ is two folders down
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
FENCE = re.compile(r"```.*?```", re.S)
TEXT = {".md", ".py", ".js", ".mjs", ".cjs", ".css", ".json", ".yml", ".yaml", ".txt", ".html", ".gitignore", ".sh", ".ps1", ".gyroflow", ".xml", ".xsd", ".dtd", ".ent"}
SKILLS = "skills/"
LISTS = "lists/"  # inside skills/: one list per big copied set, linked from its README
TEMPLATES = ("skills/brain-starter/kit/",)  # a friend's brain in the making; its links point inside it, and make_starter.py checks them there
BIG = 1_000_000  # bytes; text files over this are flagged too
LONG = 12_000    # bytes; the core or an index over this is flagged
HEADING = re.compile(r"^#{1,6}\s+(.+?)\s*#*\s*$", re.M)
ANCHOR = re.compile(r'<a\s+(?:id|name)="([^"]+)"')


def anchors(path, cache={}):
    """The section links a note offers, as GitHub makes them from its headings."""
    if path not in cache:
        with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
            text = FENCE.sub("", fh.read())
        seen, found = collections.Counter(), set(ANCHOR.findall(text))
        for heading in HEADING.findall(text):
            plain = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading)
            slug = re.sub(r"[^\w\- ]", "", plain.lower()).replace(" ", "-")
            found.add(slug if not seen[slug] else f"{slug}-{seen[slug]}")
            seen[slug] += 1
        cache[path] = found
    return cache[path]


def copied_skills():
    """The skill folders linked under "Copied skills" in skills/README.md, and in the
    lists in skills/lists/ that it links to, minus the brain's own."""
    path = os.path.join(ROOT, SKILLS, "README.md")
    if not os.path.exists(path):
        return ()
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    def links(heading, skip=()):
        """The links under a heading, and in the lists linked there (but not the lists in skip)."""
        part = re.search(r"^## " + heading + r".*?(?=^## |\Z)", text, re.M | re.S)
        found = LINK.findall(part.group(0)) if part else []
        for target in [t for t in found if t.startswith(LISTS) and t.split("#")[0].endswith(".md") and t.split("#")[0] not in skip]:
            with open(os.path.join(ROOT, SKILLS, target.split("#")[0]), encoding="utf-8") as fh:
                found += [os.path.normpath(os.path.join(LISTS, t)) for t in LINK.findall(fh.read()) if not re.match(r"^[a-z]+:", t)]
        return found
    def folders(targets):
        return {t.split("/")[0] for t in targets if re.match(r"^[\w-]+/", t)}
    copied = links("Copied")
    copied_lists = {t.split("#")[0] for t in copied if t.startswith(LISTS)}
    return tuple(SKILLS + f + "/" for f in folders(copied) - folders(links("The brain's own", copied_lists)) - {LISTS.rstrip("/")})


def finished(path):
    """True for a library note whose card marks it finished: its shelf's index counts it
    and `library.py find --all` lists it, so no other note needs to link it."""
    if not path.startswith("knowledge/"):
        return False
    with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
        head = fh.read(2000).split("\n")
    if not head or head[0].strip() != "---":
        return False
    for line in head[1:]:
        if line.strip() == "---":
            return False
        if re.match(r"^status:\s*(done|dropped|superseded|graduated)\s*$", line.strip()):
            return True
    return False


def tracked():
    """The repo's files: tracked ones, and new ones not yet added that git doesn't ignore.

    New ones count too, so a check before `git add` doesn't miss new notes (a friend's brain, Oct 2026)."""
    out = subprocess.check_output(["git", "-C", ROOT, "ls-files", "-z", "--cached", "--others", "--exclude-standard"])
    return sorted({p for p in out.decode("utf-8").split("\0") if p and os.path.isfile(os.path.join(ROOT, p))})


def main():
    files = tracked()
    copied = copied_skills()
    kept = [p for p in files if copied and p.startswith(copied)]
    files = [p for p in files if not (copied and p.startswith(copied)) and not p.startswith(TEMPLATES)]
    notes = [p for p in files if p.endswith(".md")]
    broken, sections, inbound = [], [], collections.Counter()
    for note in notes:
        with open(os.path.join(ROOT, note), encoding="utf-8") as fh:
            text = FENCE.sub("", fh.read())
        for target in LINK.findall(text):
            if re.match(r"^[a-z]+:", target):
                continue
            file, _, section = unquote(target).partition("#")
            path = os.path.normpath(os.path.join(os.path.dirname(note), file)) if file else note
            if not os.path.exists(os.path.join(ROOT, path)):
                broken.append((note, target))
                continue
            if file:
                inbound[path] += 1
            if section and path.endswith(".md") and section.lower() not in anchors(path):
                sections.append((note, target))

    orphans = [n for n in notes if not inbound[n] and n not in ("README.md", "CLAUDE.md") and not finished(n)]
    binary = []
    for p in files:
        ext = os.path.splitext(p)[1].lower() or os.path.basename(p)
        size = os.path.getsize(os.path.join(ROOT, p))
        if ext not in TEXT or size > BIG:
            binary.append((p, size))
    long_notes = sorted(
        ((p, os.path.getsize(os.path.join(ROOT, p))) for p in notes
         if p == "CLAUDE.md" or (p.startswith("knowledge/") and os.path.basename(p) == "README.md")),
        key=lambda x: -x[1],
    )

    print(f"{len(notes)} notes. Broken links: {len(broken)}. Broken section links: {len(sections)}. Notes nothing links to: {len(orphans)}.")
    for note, target in broken:
        print(f"  broken: {note} -> {target}")
    for note, target in sections:
        print(f"  no such section: {note} -> {target}")
    for note in orphans:
        print(f"  no links in: {note}")
    if binary:
        total = sum(s for _, s in binary)
        print(f"Big or binary files in the repo: {len(binary)}, {total / 1e6:.1f} MB (they belong on the PC or in a files repo unless a decision says otherwise).")
        for p, s in sorted(binary, key=lambda x: -x[1])[:10]:
            print(f"  {s / 1e6:6.2f} MB  {p}")
    print("The core and the longest indexes (agents read these first):")
    for p, s in long_notes[:6]:
        flag = "  <- over 12 KB" if s > LONG else ""
        print(f"  {s / 1000:5.1f} KB  {p}{flag}")
    if kept:
        size = sum(os.path.getsize(os.path.join(ROOT, p)) for p in kept)
        print(f"Copied skills, kept as they came: {len(copied)} folders, {len(kept)} files, {size / 1e6:.1f} MB ({SKILLS}README.md).")
    return 1 if broken or sections else 0


if __name__ == "__main__":
    sys.exit(main())
