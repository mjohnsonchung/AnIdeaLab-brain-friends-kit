#!/usr/bin/env python3
"""Build, search and check the knowledge library's indexes from the notes' cards.

Written for the brain restructure (19 Oct 2026). The design is in the brain-spec skill
(skills/brain-spec/SKILL.md); in short, every note in knowledge/ starts with a card:

    ---
    about: "One line: what's in the note and when you'd read it."
    tags: [drivermods, money]
    status: current
    updated: 19 Oct 2026
    ---

Tasks also have `holder` (owner, open, or a session link), and may have `parent` and
`due`. Every folder in knowledge/ is a shelf, and its README.md is its index.

Usage: python3 skills/brain-spec/library.py COMMAND [options]
  build                     fill each README.md's list, between the index marks
  find [--shelf PATH] [--tag T] [--status S,S] [--holder H] [--text WORDS] [--all]
                            one line per matching note, as path: about
  check [--strict]          report problems; exit 1 with --strict if there are any
  audit --since DATE        notes changed a lot since their card was checked, tasks
                            finished since DATE, every skill with a LESSONS.md, and
                            later decisions pointing at an earlier one that doesn't
                            point back (for the weekly audit)
Any command takes --root PATH to work on another copy of the repo (the tests do).

It uses Python 3.8 or later and the standard library only, so it runs anywhere.
"""
import argparse
import os
import re
import subprocess
import sys
from datetime import date, datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))  # skills/brain-spec/ is two folders down
SCRIPT = "python3 skills/brain-spec/library.py"
START, END = "<!-- index:start -->", "<!-- index:end -->"
MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
FINISHED = {"done", "dropped", "superseded", "graduated"}
STATUSES = {
    "tasks": {"open", "doing", "waiting", "done", "dropped"},
    "decisions": {"current", "superseded"},
    "ideas": {"raw", "researching", "parked", "graduated", "dropped"},
    "ventures": {"current", "parked", "done"},
}
OTHER_STATUSES = {"current", "done"}
TAG_SHELVES = ("ventures", "areas", "subjects")
MACHINERY = {"brain-spec", "brain-audit", "getting-started", "guide-mode", "my-pc"}  # skills that run the brain's own machinery, so may link into notes
TASK_GROUPS = [("Waiting on the owner", None), ("Doing", "doing"), ("Waiting", "waiting"), ("Open", "open")]
MAX_ABOUT = 250
MAX_INDEX = 60   # entries in an index
MAX_CORE = 6 * 1024
MAX_SKILL_LINES = 500  # Anthropic's skill-creator: "Keep SKILL.md under 500 lines"
MAX_LESSONS = 20  # in a skill's LESSONS.md, before the audit must merge them
LESSONS_LINK = re.compile(r"\]\((?:\./)?LESSONS\.md\)")
IN_MATTS_BRAIN = re.compile(r"^#+ In this brain", re.M)  # skill_updates.py ignores this section of a copied skill
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
FENCE = re.compile(r"```.*?```", re.S)
DATED = re.compile(r"^(\d{4}-\d{2}-\d{2})-")
CHECKED_LINKS = "skills/brain-spec/checked_links.txt"  # one-way decision links an audit read and found to be plain references


# Cards ------------------------------------------------------------------------

def parse_value(raw):
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] == '"':
        return raw[1:-1].replace('\\"', '"')
    if raw.startswith("[") and raw.endswith("]"):
        return [v.strip().strip('"') for v in raw[1:-1].split(",") if v.strip()]
    return raw


def read_card(path):
    """The note's card as a dict, or None if it has none."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except (OSError, UnicodeDecodeError):
        return None
    if not lines or lines[0].strip() != "---":
        return None
    card = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return card
        m = re.match(r"^([A-Za-z][\w-]*):\s?(.*)$", line)
        if m:
            card[m.group(1)] = parse_value(m.group(2))
    return None  # no closing line


def to_date(text):
    """A date written the brain's way ("19 Oct 2026") or as 2026-10-19, or None."""
    if not isinstance(text, str):
        return None
    text = text.strip()
    m = re.match(r"^(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{4})$", text)
    try:
        if m:
            return date(int(m.group(3)), MONTHS.index(m.group(2).lower()) + 1, int(m.group(1)))
        return datetime.strptime(text, "%Y-%m-%d").date()
    except ValueError:
        return None


def tags_of(card):
    tags = card.get("tags") or []
    return [tags] if isinstance(tags, str) else tags


# The library ------------------------------------------------------------------

class Library:
    def __init__(self, root):
        self.root = os.path.abspath(root)
        self.know = os.path.join(self.root, "knowledge")

    def rel(self, path):
        return os.path.relpath(path, self.root).replace(os.sep, "/")

    def shelves(self):
        """Every folder in knowledge/, the library's own folder first."""
        out = []
        for dirpath, dirnames, _ in os.walk(self.know):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
            out.append(dirpath)
        return out

    def notes_in(self, shelf):
        return sorted(os.path.join(shelf, f) for f in os.listdir(shelf)
                      if f.endswith(".md") and f != "README.md" and os.path.isfile(os.path.join(shelf, f)))

    def subshelves(self, shelf):
        return sorted(os.path.join(shelf, d) for d in os.listdir(shelf)
                      if os.path.isdir(os.path.join(shelf, d)) and not d.startswith("."))

    def top(self, path):
        """The working shelf a path is on (tasks, decisions...), or "" for the library itself."""
        parts = os.path.relpath(path, self.know).replace(os.sep, "/").split("/")
        return "" if parts[0] in (".", "README.md") else parts[0]

    def all_notes(self):
        """Every .md file in the library, READMEs included, with its card."""
        out = []
        for shelf in self.shelves():
            readme = os.path.join(shelf, "README.md")
            if os.path.exists(readme) and shelf != self.know:
                out.append((readme, read_card(readme) or {}))
            for n in self.notes_in(shelf):
                out.append((n, read_card(n) or {}))
        return out

    def known_tags(self):
        tags = set()
        for shelf in TAG_SHELVES:
            base = os.path.join(self.know, shelf)
            if not os.path.isdir(base):
                continue
            for name in os.listdir(base):
                if name in ("README.md", "history"):
                    continue
                if name.endswith(".md"):
                    tags.add(name[:-3])
                elif os.path.isdir(os.path.join(base, name)):
                    tags.add(name)
                    if shelf == "ventures":
                        # a project inside a venture (anidealab/rosie/) is a tag too
                        for sub in os.listdir(os.path.join(base, name)):
                            if sub != "history" and os.path.isfile(os.path.join(base, name, sub, "README.md")):
                                tags.add(sub)
        return tags


# build ------------------------------------------------------------------------

def line_for(lib, shelf, path, card, is_shelf=False):
    name = os.path.basename(os.path.dirname(path)) + "/" if is_shelf else os.path.basename(path)[:-3]
    link = os.path.relpath(path, shelf).replace(os.sep, "/")
    about = card.get("about") or "*(no card yet)*"
    extra = ""
    status = card.get("status", "")
    if lib.top(path) == "tasks" and not is_shelf:
        if card.get("due"):
            extra += f" Due {card['due']}."
    elif status and status not in ("current",) and status not in FINISHED:
        extra += f" *({status})*"
    tags = tags_of(card)
    return f"- [{name}]({link}): {about}{extra}" + (f" [{', '.join(tags)}]" if tags else "")


def index_for(lib, shelf):
    lines = []
    subs = []
    for sub in lib.subshelves(shelf):
        readme = os.path.join(sub, "README.md")
        subs.append(line_for(lib, shelf, readme, read_card(readme) or {}, is_shelf=True))
    notes = [(n, read_card(n) or {}) for n in lib.notes_in(shelf)]
    live = [(n, c) for n, c in notes if c.get("status") not in FINISHED]
    finished = len(notes) - len(live)
    top = lib.top(os.path.join(shelf, "x"))
    if subs:
        lines += subs
    if top == "tasks":
        for title, status in TASK_GROUPS:
            group = [(n, c) for n, c in live if (c.get("holder") == "owner") == (status is None)
                     and (status is None or c.get("status") == status)]
            group.sort(key=lambda nc: (to_date(nc[1].get("due")) or date.max, nc[0]))
            if group:
                lines += ["", f"### {title}"] + [line_for(lib, shelf, n, c) for n, c in group]
        if not live and not subs:
            lines.append("*No open tasks.*")
    else:
        dated = [nc for nc in live if re.match(r"^\d{4}-\d{2}-\d{2}", os.path.basename(nc[0]))]
        live = sorted(dated, key=lambda nc: os.path.basename(nc[0]), reverse=True) + [nc for nc in live if nc not in dated]
        if live:
            if subs:
                lines.append("")
            lines += [line_for(lib, shelf, n, c) for n, c in live]
        if not live and not subs:
            lines.append("*Nothing here yet.*")
    if finished:
        rel = lib.rel(shelf)
        lines += ["", f"Finished, and not listed: {finished}. `{SCRIPT} find --shelf {rel} --all` lists them."]
    return "\n".join(lines).strip("\n")


def build(lib, quiet=False):
    changed = []
    for shelf in lib.shelves():
        readme = os.path.join(shelf, "README.md")
        if not os.path.exists(readme):
            continue
        with open(readme, encoding="utf-8") as fh:
            text = fh.read()
        if START not in text or END not in text or text.index(START) > text.index(END):
            continue
        head, rest = text.split(START, 1)
        _, tail = rest.split(END, 1)
        new = head + START + "\n" + index_for(lib, shelf) + "\n" + END + tail
        if new != text:
            with open(readme, "w", encoding="utf-8") as fh:
                fh.write(new)
            changed.append(lib.rel(readme))
    if not quiet:
        print(f"Indexes rebuilt: {len(changed)}" + "".join(f"\n  {c}" for c in changed))
    return changed


# find -------------------------------------------------------------------------

def find(lib, shelf=None, tag=None, status=None, holder=None, text=None, show_all=False):
    base = lib.know
    if shelf:
        shelf = shelf.strip("/")
        if shelf.startswith("knowledge"):
            shelf = shelf[len("knowledge"):].strip("/")
        base = os.path.join(lib.know, shelf)
    statuses = set(status.split(",")) if status else None
    words = text.lower().split() if text else []
    hits = []
    for path, card in lib.all_notes():
        if not (path == base or path.startswith(base.rstrip(os.sep) + os.sep)):
            continue
        st = card.get("status", "")
        if statuses is not None and st not in statuses:
            continue
        if statuses is None and not show_all and st in FINISHED:
            continue
        if tag and tag not in tags_of(card) and not (
                os.path.basename(path) == "README.md" and os.path.basename(os.path.dirname(path)) == tag):
            continue
        if holder and card.get("holder") != holder:
            continue
        if words:
            hay = " ".join([lib.rel(path), str(card.get("about", "")), " ".join(tags_of(card))]).lower()
            if not all(w in hay for w in words):
                continue
        hits.append(f"{lib.rel(path)}: {card.get('about', '(no card)')}")
    return hits


# check ------------------------------------------------------------------------

def check(lib):
    problems = []
    if not os.path.isdir(lib.know):
        return ["there's no knowledge/ folder"]
    tags = lib.known_tags()
    for shelf in lib.shelves():
        readme = os.path.join(shelf, "README.md")
        if not os.path.exists(readme):
            problems.append(f"{lib.rel(shelf)}/: no README.md")
            continue
        with open(readme, encoding="utf-8") as fh:
            text = fh.read()
        if START in text and END in text:
            block = text.split(START, 1)[1].split(END, 1)[0]
            n = sum(1 for line in block.split("\n") if line.startswith("- "))  # entries, not headings
            if n > MAX_INDEX:
                what = "close stale tasks" if lib.top(readme) == "tasks" else "give it sub-shelves"
                problems.append(f"{lib.rel(readme)}: the index lists {n} entries, past about {MAX_INDEX}; time to {what}")
    for path, card in lib.all_notes():
        rel = lib.rel(path)
        readme = os.path.basename(path) == "README.md"
        top = lib.top(path)
        if not card:
            problems.append(f"{rel}: no card")
            continue
        if not card.get("about"):
            problems.append(f"{rel}: no about line")
        elif len(card["about"]) > MAX_ABOUT:
            problems.append(f"{rel}: the about line is {len(card['about'])} characters, over {MAX_ABOUT}")
        if "\\" in str(card.get("about", "")):
            problems.append(f"{rel}: the about line has a backslash, which YAML reads as an escape; reword it")
        if not card.get("updated"):
            problems.append(f"{rel}: no updated date")
        for key in ("updated", "due"):
            if card.get(key) and not to_date(card[key]):
                problems.append(f'{rel}: {key} "{card[key]}" isn\'t a date like 19 Oct 2026')
        st = card.get("status")
        allowed = STATUSES.get(top, OTHER_STATUSES) | ({"current"} if readme else set())
        if st and st not in allowed:
            problems.append(f'{rel}: status "{st}" isn\'t one the {top or "library"} shelf uses ({", ".join(sorted(allowed))})')
        for t in tags_of(card):
            if t not in tags:
                problems.append(f'{rel}: the tag "{t}" isn\'t the name of a venture, area or subject')
        if top == "tasks" and not readme:
            h = card.get("holder", "")
            if not (h in ("owner", "open") or re.match(r"^https?://\S+$", str(h))):
                problems.append(f'{rel}: holder "{h}" should be owner, open or a session link')
    core = os.path.join(lib.root, "CLAUDE.md")
    if os.path.exists(core) and os.path.getsize(core) > MAX_CORE:
        problems.append(f"CLAUDE.md: the core is {os.path.getsize(core) / 1024:.1f} KB, over {MAX_CORE // 1024} KB")
    problems += skill_links(lib)
    problems += skill_shape(lib)
    problems += history_links(lib)
    return problems


def skill_links(lib):
    """Skills linking into knowledge/, apart from the machinery skills and cited decisions."""
    out = []
    skills = os.path.join(lib.root, "skills")
    if not os.path.isdir(skills):
        return out
    for dirpath, _, files in os.walk(skills):
        name = os.path.relpath(dirpath, skills).split(os.sep)[0]
        if name in MACHINERY or name == ".":  # the skills list itself is the brain's own
            continue
        for f in files:
            if not f.endswith(".md"):
                continue
            path = os.path.join(dirpath, f)
            try:
                with open(path, encoding="utf-8") as fh:
                    text = FENCE.sub("", fh.read())
            except UnicodeDecodeError:
                continue
            for target in LINK.findall(text):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
                    continue
                dest = os.path.normpath(os.path.join(dirpath, target.split("#")[0]))
                inside = os.path.relpath(dest, lib.know)
                if inside.startswith("..") or inside.startswith("decisions"):
                    continue
                out.append(f"{lib.rel(path)}: a skill links into the notes ({target}); skills stay general")
    return out


def own_skills(lib):
    """The brain's own skills: the folders linked under "The brain's own" in skills/README.md,
    and in the lists in skills/lists/ linked there (22 Oct 2026)."""
    path = os.path.join(lib.root, "skills", "README.md")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as fh:
        m = re.search(r"^## The brain's own\n(.*?)(?=^## |\Z)", fh.read(), re.M | re.S)
    if not m:
        return []
    text = m.group(1)
    for name in re.findall(r"\]\(lists/([\w-]+\.md)\)", text):
        listed = os.path.join(lib.root, "skills", "lists", name)
        if os.path.exists(listed):
            with open(listed, encoding="utf-8") as fh:
                text += "\n" + fh.read().replace("](../", "](")
    return list(dict.fromkeys(re.findall(r"\]\(([a-z0-9-]+)/SKILL\.md\)", text)))


def skill_text(lib, name, file="SKILL.md"):
    path = os.path.join(lib.root, "skills", name, file)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def all_skills(lib):
    """Every folder in skills/ with a SKILL.md, the brain's own and the copied ones."""
    skills = os.path.join(lib.root, "skills")
    if not os.path.isdir(skills):
        return []
    return sorted(n for n in os.listdir(skills) if os.path.isfile(os.path.join(skills, n, "SKILL.md")))


def count_lessons(text):
    return sum(1 for line in text.split("\n") if line.startswith("- "))


def skill_shape(lib):
    """The brain's own skills stay under MAX_SKILL_LINES, and every LESSONS.md is linked from its skill and kept short."""
    out, own = [], set(own_skills(lib))
    for name in all_skills(lib):
        text = skill_text(lib, name)
        lessons_md = skill_text(lib, name, "LESSONS.md")
        rel = f"skills/{name}/SKILL.md"
        lines = text.count("\n")
        if name in own and lines > MAX_SKILL_LINES:
            out.append(f"{rel}: {lines} lines, over {MAX_SKILL_LINES}; fold its lessons tighter, or move detail into a file it links")
        plain = FENCE.sub("", text)
        link = LESSONS_LINK.search(plain)
        if lessons_md is None:
            if link:
                out.append(f"{rel}: links LESSONS.md, but there isn't one; drop the link")
            continue
        if not link:
            out.append(f"skills/{name}/LESSONS.md: {rel} doesn't link it; add the line the brain spec gives")
        elif name not in own:
            section = IN_MATTS_BRAIN.search(plain)
            if not section or link.start() < section.start():
                out.append(f"{rel}: a copied skill links LESSONS.md outside an \"In this brain\" section at its end, so it shows as changed")
        n = count_lessons(lessons_md)
        if n > MAX_LESSONS:
            out.append(f"skills/{name}/LESSONS.md: {n} lessons, past {MAX_LESSONS}; merge them, or fold them in")
    return out


def lessons(lib):
    """Every skill with a LESSONS.md: the brain's own to fold in, then the copied ones to keep short."""
    own = set(own_skills(lib))
    rows = []
    for name in all_skills(lib):
        text = skill_text(lib, name, "LESSONS.md")
        if text is None:
            continue
        n = count_lessons(text)
        what = "fold in" if name in own else "copied, keep short"
        rows.append((name not in own, f"skills/{name}/LESSONS.md: {n} lesson{'s' if n != 1 else ''} ({what})"))
    return [r for _, r in sorted(rows)]


def history_links(lib):
    """Live notes linking to a retired note in a history/ folder (Matt, 20 Oct 2026).

    Retired notes keep their own links, and an index may list its history/ shelf, but
    nothing current should send an agent to a superseded note: say where it is in words.
    """
    out = []
    marks = re.compile(re.escape(START) + r".*?" + re.escape(END), re.S)
    for top in (lib.root,):
        for dirpath, dirs, files in os.walk(top):
            dirs[:] = [d for d in dirs if d not in (".git", ".obsidian", "history")]
            for f in files:
                if not f.endswith(".md"):
                    continue
                path = os.path.join(dirpath, f)
                try:
                    with open(path, encoding="utf-8") as fh:
                        text = marks.sub("", FENCE.sub("", fh.read()))
                except UnicodeDecodeError:
                    continue
                for target in LINK.findall(text):
                    if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
                        continue
                    dest = os.path.relpath(os.path.normpath(os.path.join(dirpath, target.split("#")[0])), lib.root)
                    parts = dest.split(os.sep)
                    if "history" in parts[:-1] and parts[-1] != "README.md":
                        out.append(f"{lib.rel(path)}: links to a retired note ({target}); say where it is in words instead")
    return out


def one_way_decisions(lib):
    """Pairs (later, earlier) of current decisions where the later links to the earlier, not back.

    Added 25 Oct 2026, after the flat-copy test: agents stopped at the 22 Oct "no editing
    rules" note, which said nothing of the six effects the 24 Oct note took off the table.
    The 24 Oct note linked to the 22 Oct one, but not the other way. A later decision that
    changes, narrows or adds to an earlier one should be named in it, so an agent who finds
    the earlier one first isn't misled. Pairs read and found to be plain references are
    listed in checked_links.txt as `later -> earlier`, and not reported again.
    """
    checked = set()
    listed = os.path.join(lib.root, CHECKED_LINKS)
    if os.path.exists(listed):
        with open(listed, encoding="utf-8") as fh:
            for line in fh:
                line = line.split("#")[0].strip()
                if " -> " in line:
                    checked.add(tuple(part.strip() for part in line.split(" -> ", 1)))
    current = {}
    for path, card in lib.all_notes():
        name = os.path.basename(path)
        if lib.top(path) == "decisions" and card.get("status") == "current" and DATED.match(name):
            current[os.path.normpath(path)] = DATED.match(name).group(1)
    links = {}
    for path in current:
        with open(path, encoding="utf-8") as fh:
            text = FENCE.sub("", fh.read())
        links[path] = {os.path.normpath(os.path.join(os.path.dirname(path), t.split("#")[0]))
                       for t in LINK.findall(text) if not re.match(r"^[a-z][a-z0-9+.-]*:", t, re.I)}
    out = []
    for later, day in sorted(current.items()):
        for earlier in sorted(links[later]):
            if earlier in current and current[earlier] < day and later not in links[earlier]:
                pair = (lib.rel(later), lib.rel(earlier))
                if pair not in checked:
                    out.append(pair)
    return out


# audit ------------------------------------------------------------------------

def git(lib, *args):
    try:
        return subprocess.check_output(["git", "-C", lib.root, *args], stderr=subprocess.DEVNULL).decode("utf-8", "replace")
    except (OSError, subprocess.CalledProcessError):
        return ""


def audit(lib, since):
    """Notes changed by more than about 20 lines since their card's date, and tasks finished since `since`."""
    if git(lib, "rev-parse", "--is-shallow-repository").strip() == "true":
        # A shallow clone's oldest commit adds every file, so every note looks changed (24 Oct 2026 audit: 151 instead of 2).
        sys.exit("This clone is shallow, so every note would look changed. Run `git fetch --unshallow origin main` first.")
    changed, finished = [], []
    for path, card in lib.all_notes():
        rel = lib.rel(path)
        checked = to_date(card.get("updated"))
        if checked:
            log = git(lib, "log", "--follow", "--numstat", "--format=@%an",
                      f"--since={(checked + timedelta(days=1)).isoformat()}T00:00:00Z", "--", rel)
            lines, bot = 0, False
            for row in log.splitlines():
                if row.startswith("@"):
                    bot = row[1:].startswith(("farm-brain", "github-actions"))  # the repo's own Actions
                    continue
                parts = row.split("\t")
                if not bot and len(parts) == 3 and parts[0].isdigit():
                    lines += int(parts[0]) + int(parts[1])
            if lines > 20:
                changed.append(f"{rel}: {lines} lines changed since its card was checked ({card.get('updated')})")
        if lib.top(path) == "tasks" and card.get("status") in FINISHED:
            diff = git(lib, "log", "--follow", "-p", "--format=", f"--since={since.isoformat()}T00:00:00Z", "--", rel)
            if re.search(r"^\+status:\s*(" + "|".join(FINISHED) + r")\s*$", diff, re.M):
                finished.append(f"{rel}: {card.get('status')}: {card.get('about', '')}")
    return changed, finished


# The command line -------------------------------------------------------------

def main(argv=None):
    p = argparse.ArgumentParser(description="Build, search and check the knowledge library.")
    p.add_argument("--root", default=REPO, help="the repo to work on (default: this one)")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("build")
    f = sub.add_parser("find")
    f.add_argument("--shelf")
    f.add_argument("--tag")
    f.add_argument("--status")
    f.add_argument("--holder")
    f.add_argument("--text")
    f.add_argument("--all", action="store_true")
    c = sub.add_parser("check")
    c.add_argument("--strict", action="store_true")
    a = sub.add_parser("audit")
    a.add_argument("--since", required=True)
    args = p.parse_args(argv)
    lib = Library(args.root)

    if args.cmd == "build":
        build(lib)
    elif args.cmd == "find":
        hits = find(lib, args.shelf, args.tag, args.status, args.holder, args.text, args.all)
        print("\n".join(hits) if hits else "Nothing matches.")
    elif args.cmd == "check":
        problems = check(lib)
        print(f"Library check: {len(problems)} problem{'s' if len(problems) != 1 else ''}.")
        for pr in problems:
            print("  " + pr)
        return 1 if problems and args.strict else 0
    elif args.cmd == "audit":
        since = to_date(args.since)
        if not since:
            sys.exit(f'--since "{args.since}" isn\'t a date like 17 Oct 2026')
        changed, finished = audit(lib, since)
        print(f"Notes changed a lot since their card was checked: {len(changed)}")
        for c_ in changed:
            print("  " + c_)
        print(f"Tasks finished since {since.day} {since:%b %Y}: {len(finished)}")
        for f_ in finished:
            print("  " + f_)
        waiting = lessons(lib)
        print(f"Skills with lessons: {len(waiting)}")
        for w in waiting:
            print("  " + w)
        pairs = one_way_decisions(lib)
        print(f"Later decisions linking to an earlier one that doesn't link back: {len(pairs)}")
        for later, earlier in pairs:
            print(f"  {later} -> {earlier}")
        if pairs:
            print(f"  If the later one changes or adds to the earlier, say so in the earlier; if it only refers to it, add the pair to {CHECKED_LINKS}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
