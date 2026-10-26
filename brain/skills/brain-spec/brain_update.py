#!/usr/bin/env python3
"""Apply brain updates from AnIdeaLab, and send their reports to AnIdeaLab's inbox.

This brain was started from a starter kit made from Matt's brain. Matt sends updates to it
(fixes, new rules, new parts) through the public repo AnIdeaLab-brain-friends-kit:
- brain/ holds the kit's brain as a fresh one would get it, with its two date placeholders
  left in for each brain's own start date;
- updates/NNNN-<words>.md is each update's message: a summary for the owner, what changed and
  why, and anything to do beyond the files. The commit that added it holds brain/ as of that update.

The owner decides each update: the agent reads them its summary, and applies it only if they say go.

    python3 skills/brain-spec/brain_update.py check        # updates this brain hasn't had, with each one's summary
    python3 skills/brain-spec/brain_update.py apply 3      # the owner said go: bring update 3's files in, start its report, print its message
    python3 skills/brain-spec/brain_update.py skip 3       # the owner said no: note it, so it doesn't come up again
    python3 skills/brain-spec/brain_update.py finish 3     # after doing the message: run the checks, add them to the report
    python3 skills/brain-spec/brain_update.py send         # the "Send brain update reports" workflow runs this

`apply` takes each file the update changed in brain/ and puts the change into this brain with a
three-way merge (git merge-file), so the brain's own changes elsewhere in a file stay. Where both
changed the same lines, the update's lines go in, and it prints both sides of each such place: git
takes the whole clashing stretch, so a paragraph the brain added next to a line the update changed
goes too, and the agent puts back what's the owner's own (but not the brain's own old fixes to kit parts,
which give way to the kit's: the brain spec's "Brain updates" says why). Obsidian's settings files
are the exception: there the brain's own lines stay, since the owner set them (two friends' brains,
26 Oct 2026). A file the update adds is written, one it changed that this brain no longer has is
written again, and one it deleted is deleted. Then it records the
update in knowledge/systems/brain-updates/README.md and starts knowledge/systems/brain-updates/NNNN-report.md
with what it did and a section for each thing the agent must say. `finish` runs the brain's checks, adds
them to the report, and won't finish while a section is still empty, so every report says enough. A skipped update can still be applied later, if the owner asks. The rest, and when to
use it: the brain spec's "Brain updates" section.

It needs git and network access to github.com, and nothing outside Python's standard library.
The kit repo is kept as a small partial clone in ~/.cache/brain-updates.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from datetime import date

GITHUB_REPO = "mjohnsonchung/AnIdeaLab-brain-friends-kit"
SOURCE = os.environ.get("BRAIN_KIT_URL") or f"https://github.com/{GITHUB_REPO}"  # another copy, for testing an update
AUDIENCE = "anidealab-brain-reports"  # the inbox only takes GitHub sign-in tokens made for it
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))  # skills/brain-spec/ is two folders down
FOLDER = "knowledge/systems/brain-updates"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "brain-updates", "kit.git")
ON = re.compile(r"\*\*On kit update:\*\* ([^\n]*)")
SKIPPED = re.compile(r"\*\*Skipped:\*\* ([^\n]*)")
UPDATE = re.compile(r"^updates/(\d{4})-[a-z0-9-]+\.md$")
REPORT = re.compile(r"^\d{4}-report\.md$")
# The kit repo's date placeholders, spelt in two parts so the kit's build doesn't fill them in here.
DATE_MARK, ISO_MARK = ("{" + "KIT_DATE}").encode(), ("{" + "KIT_ISO}").encode()
MARK = 15  # conflict markers this long can't be mistaken for a Markdown line of seven = signs
SHOW = 40  # lines of each side of a clash to print


def owner_setting(rel):
    """Obsidian's settings files, which the owner changes in Obsidian; a plugin's manifest is the plugin's own."""
    return rel.startswith(".obsidian/") and rel.endswith(".json") and not rel.endswith("/manifest.json")


def git(*args, repo=CACHE, check=True, text=True):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=text)
    if check and r.returncode:
        err = r.stderr if text else r.stderr.decode(errors="replace")
        sys.exit(f"brain_update: git {' '.join(args[:2])} failed: {err.strip()[:300]}")
    return r.stdout


def fetch():
    """Make or refresh the partial clone of the kit repo; return its newest commit on main."""
    if not os.path.isdir(CACHE):
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        r = subprocess.run(["git", "clone", "-q", "--bare", "--filter=blob:none", SOURCE, CACHE],
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"brain_update: couldn't reach {SOURCE}: {r.stderr.strip()[:300]}")
    git("fetch", "-q", "--filter=blob:none", "origin", "main")
    return git("rev-parse", "FETCH_HEAD").strip()


def updates(head):
    """Every update in the kit repo: {number: (file, commit, date)}, from the newest commit that added each."""
    out = git("log", "--diff-filter=A", "--no-renames", "--format=@%H %cs", "--name-only", head, "--", "updates/")
    found, commit, day = {}, None, None
    for line in out.splitlines():
        if line.startswith("@"):
            commit, day = line[1:].split()
        elif UPDATE.match(line):
            found.setdefault(int(UPDATE.match(line).group(1)), (line, commit, day))
    there = set(git("ls-tree", "--name-only", head, "updates/").split())
    return {n: f for n, f in found.items() if f[0] in there}  # one deleted from the kit since is withdrawn


def kit_start():
    """The day this brain was started from the kit, from its starting-rules note's name."""
    folder = os.path.join(ROOT, "knowledge", "decisions", "the-brain")
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        m = re.match(r"(\d{4}-\d{2}-\d{2})-starting-rules\.md$", name)
        if m:
            return date.fromisoformat(m.group(1))
    sys.exit("brain_update: can't find knowledge/decisions/the-brain/<date>-starting-rules.md, so can't tell when this brain started.")


def current(found):
    """The last update this brain has. Before its first one, it's the last update sent before the kit it started from."""
    readme = os.path.join(ROOT, FOLDER, "README.md")
    if os.path.isfile(readme):
        m = ON.search(open(readme, encoding="utf-8").read())
        if m and m.group(1)[:1].isdigit():
            return int(m.group(1).split()[0])
    start = kit_start().isoformat()
    return max([n for n, (_, _, day) in found.items() if day < start], default=0)


def skipped():
    """The updates the owner said no to."""
    readme = os.path.join(ROOT, FOLDER, "README.md")
    m = SKIPPED.search(open(readme, encoding="utf-8").read()) if os.path.isfile(readme) else None
    return {int(x) for x in re.findall(r"\d+", m.group(1))} if m else set()


def message(head, found, n):
    """An update's message as the kit has it now, so a fix to its wording reaches every brain."""
    path, target, _ = found[n]
    return (blob(head, path) or blob(target, path)).decode("utf-8", errors="replace")


def summary(text):
    """The message's "Summary for the owner" section, or its first paragraph if it has none."""
    m = re.search(r"(?ms)^## Summary for the owner\n+(.*?)(?=^## |\Z)", text)
    if m:
        return m.group(1).strip()
    paras = [p.strip() for p in text.split("\n\n") if p.strip() and not p.startswith("#")]
    return paras[0] if paras else ""


def fill(data, start):
    return data.replace(DATE_MARK, f"{start.day} {start:%b %Y}".encode()).replace(ISO_MARK, start.isoformat().encode())


def blob(commit, path):
    r = subprocess.run(["git", "-C", CACHE, "show", f"{commit}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def merge3(mine, base, theirs, keep="theirs"):
    """Three-way merge with git merge-file. Where both changed the same lines, the update's lines win
    (or this brain's, with keep="ours"). Returns the merged file and each clash as (brain's lines, update's lines)."""
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for name, data in (("mine", mine), ("base", base), ("theirs", theirs)):
            p = os.path.join(tmp, name)
            open(p, "wb").write(data)
            paths.append(p)
        r = subprocess.run(["git", "merge-file", "-p", f"--{keep}", *paths], capture_output=True)
        if r.returncode:
            sys.exit(f"brain_update: git merge-file failed: {r.stderr.decode(errors='replace')[:300]}")
        marked = subprocess.run(["git", "merge-file", "-p", "--diff3", f"--marker-size={MARK}", *paths], capture_output=True)
        return r.stdout, clashes(marked.stdout) if marked.returncode > 0 else []


def clashes(marked):
    """The clashing places in a merge written with conflict markers: (this brain's lines, the update's lines)."""
    found, side, ours, theirs = [], None, [], []
    for line in marked.decode("utf-8", errors="replace").splitlines():
        if line.startswith("<" * MARK):
            side, ours, theirs = "ours", [], []
        elif line.startswith("|" * MARK) and side == "ours":
            side = "base"
        elif line.startswith("=" * MARK) and side in ("ours", "base"):
            side = "theirs"
        elif line.startswith(">" * MARK) and side == "theirs":
            found.append((ours, theirs))
            side = None
        elif side == "ours":
            ours.append(line)
        elif side == "theirs":
            theirs.append(line)
    return found


def show(lines):
    if not lines:
        return "    (nothing)"
    out = ["    | " + line for line in lines[:SHOW]]
    if len(lines) > SHOW:
        out.append(f"    ... and {len(lines) - SHOW} more lines")
    return "\n".join(out)


def do_check(_args):
    head = fetch()
    found = updates(head)
    on = current(found)
    new = sorted(n for n in found if n > on)
    if not new:
        print(f"Up to date: this brain has kit update {on}, the newest." if found else "The kit hasn't sent any updates yet.")
        return
    print(f"This brain has kit update {on}. New, oldest first:\n")
    for n in new:
        path, _, day = found[n]
        text = message(head, found, n)
        print(f"Update {n}, sent {day}: {text.splitlines()[0].lstrip('# ')}\n\nSummary for the owner:\n{summary(text)}\n")
    print(f"Read the owner update {new[0]}'s summary, and ask whether to go ahead. Go: brain_update.py apply {new[0]}. No: brain_update.py skip {new[0]}.")


def do_apply(args):
    head = fetch()
    found = updates(head)
    n = args.number
    if n not in found:
        sys.exit(f"brain_update: the kit has no update {n}.")
    on = current(found)
    if n != on + 1 and n not in skipped():
        sys.exit(f"brain_update: this brain has update {on}, so {on + 1} comes next." if n > on
                 else f"brain_update: this brain already has update {n}.")
    path, target, day = found[n]
    base = found[n - 1][1] if n - 1 in found else git("rev-list", "--max-parents=0", head).split()[0]
    start = kit_start()
    changes = git("diff", "--name-status", "--no-renames", base, target, "--", "brain/").splitlines()
    done = {"added": [], "merged": [], "clashed": [], "kept": [], "restored": [], "deleted": [], "same": []}
    places = []  # (file, how, [(brain's lines, update's lines)])
    for line in changes:
        status, kit_path = line.split("\t", 1)
        rel = fill(kit_path[len("brain/"):].encode(), start).decode()
        if rel == f"{FOLDER}/README.md" and os.path.isfile(os.path.join(ROOT, rel)):
            continue  # this brain's own record of its updates; kept below
        dest = os.path.join(ROOT, rel)
        mine = open(dest, "rb").read() if os.path.isfile(dest) else None
        if status == "D":
            if mine is not None:
                os.remove(dest)
                done["deleted"].append(rel)
            continue
        theirs = fill(blob(target, kit_path), start)
        old = blob(base, kit_path) if status == "M" else None
        if mine == theirs:
            done["same"].append(rel)
            continue
        setting = owner_setting(rel)
        if mine is None:
            new = theirs
            done["added" if status == "A" else "restored"].append(rel)
        elif old is None or b"\0" in theirs or b"\0" in mine:
            new = mine if setting else theirs
            done["kept" if setting else "clashed"].append(rel)
            places.append((rel, "whole", []))
        else:
            new, hunks = merge3(mine, fill(old, start), theirs, keep="ours" if setting else "theirs")
            done[("kept" if setting else "clashed") if hunks else "merged"].append(rel)
            if hunks:
                places.append((rel, "ours" if setting else "theirs", hunks))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        open(dest, "wb").write(new)

    before = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip() or "unknown"
    record(n, "applied")
    report = start_report(n, path, day, done, on, start, before, places)
    text = message(head, found, n)
    print(f"Update {n} ({day}): {len(done['added'])} added, {len(done['merged'])} merged, {len(done['clashed'])} with the update's lines "
          f"over this brain's, {len(done['kept'])} Obsidian settings kept as this brain had them, {len(done['restored'])} brought back, "
          f"{len(done['deleted'])} deleted, {len(done['same'])} already the same.")
    if places:
        print_places(places)
    print(f"Report started: {report}\n\nThe update's message, to do now:\n\n{text}\n\n"
          f"Then fill in the report's sections in italics, and run: python3 skills/brain-spec/brain_update.py finish {n}")


def print_places(places):
    """Both sides of each place where this brain and the update changed the same lines."""
    print("\nWhere this brain and the update changed the same lines. Git takes the whole clashing stretch, so read each one.\n"
          "If this brain's side is the owner's own (their notes, a skill or list they added, their PC's folders, a line\n"
          "about their own setup), put it back beside the update's lines. If it's this brain's own earlier fix or\n"
          "workaround for a kit part, leave it out: the kit's version is the one to keep (the brain spec's \"Brain updates\"\n"
          "says why). Say in the report what you kept and what you let go, without the owner's own words.")
    for rel, how, found in places:
        if how == "whole":
            print(f"\n{rel}: no earlier kit version to merge against, or not a text file, so "
                  + ("this brain's copy was kept." if owner_setting(rel) else "the update's copy replaced this brain's.")
                  + f" git diff HEAD -- {rel} shows the difference.")
            continue
        for i, (ours, theirs) in enumerate(found, 1):
            print(f"\n{rel}, place {i} of {len(found)}"
                  + (": this brain's lines were kept, since the owner sets these in Obsidian." if how == "ours" else ":"))
            print("  This brain had:\n" + show(ours))
            print(("  The update had:\n" if how == "ours" else "  The update put in:\n") + show(theirs))


def do_skip(args):
    head = fetch()
    found = updates(head)
    n = args.number
    on = current(found)
    if n not in found or n != on + 1:
        sys.exit(f"brain_update: update {on + 1} is the next one to apply or skip." if n in found else f"brain_update: the kit has no update {n}.")
    record(n, "skipped")
    print(f"Update {n} skipped: noted in {FOLDER}/README.md. Commit that, and say so to the owner in a line. "
          f"They can still have it later: brain_update.py apply {n}.")


def record(n, how):
    """Say in this brain's brain-updates note which update it has, and which the owner skipped."""
    readme = os.path.join(ROOT, FOLDER, "README.md")
    if not os.path.isfile(readme):
        os.makedirs(os.path.dirname(readme), exist_ok=True)
        open(readme, "w", encoding="utf-8").write(
            '---\nabout: "Brain updates from AnIdeaLab: which one this brain has, and a report of each."\n'
            f"tags: [the-brain]\nupdated: {date.today().day} {date.today():%b %Y}\n---\n# Brain updates\n")
    skips = skipped()
    text = open(readme, encoding="utf-8").read()
    today = f"{date.today().day} {date.today():%b %Y}"
    m = ON.search(text)
    has = int(m.group(1).split()[0]) if m and m.group(1)[:1].isdigit() else None
    if has is None or n >= has:  # an older skipped update applied later leaves this line as it is
        line = f"**On kit update:** {n} ({how} {today})"
        text = ON.sub(lambda _: line, text, count=1) if m else text.rstrip() + f"\n\n{line}\n"
    text = re.sub(r"(?m)^updated: .*$", f"updated: {today}", text, count=1)  # the card's date: the note changed today
    skips = skips | {n} if how == "skipped" else skips - {n}
    line = "**Skipped:** " + (", ".join(str(x) for x in sorted(skips)) or "none")
    if SKIPPED.search(text):
        text = SKIPPED.sub(lambda _: line, text, count=1)
    elif skips:
        text = ON.sub(lambda m: m.group(0) + "\n\n" + line, text, count=1)
    open(readme, "w", encoding="utf-8").write(text)


SECTIONS = [  # what the agent must say in every report, and the line that stands in until it does
    ("The owner's answer", "*Did the owner say go after hearing the summary, or ask for it some other way? Their words, if they said more.*"),
    ("The message's steps", "*Each step in the message's \"What to do beyond the files\", and what you did for it.*"),
    ("Clashes", "*For each clash listed above: what this brain's side had and what the update's had, in a few words, and what you kept, put back or let go, and why. \"None\" if there were none.*"),
    ("What broke or puzzled you", "*Errors with their exact text, checks that failed and how you fixed them, and anything in the update that was unclear or seemed wrong. \"Nothing\" if nothing did.*"),
    ("Code you changed", "*Any file you changed beyond what the script did, and why. \"None\" if none.*"),
    ("How big a job", "*Quick, small, medium or big, and roughly how long it took.*"),
]
OLD_PLACEHOLDER = re.compile(r"^\*The agent that applied it fills this in[^\n]*\*$", re.M)  # reports started before update 2
KIT_PATHS = ("skills/", ".github/", ".obsidian/", "CLAUDE.md", "README.md", f"{FOLDER}/")  # problems here aren't the owner's notes


def start_report(n, path, day, done, on, start, before, places):
    today = f"{date.today().day} {date.today():%b %Y}"
    sent = date.fromisoformat(day)
    sent = f"{sent.day} {sent:%b %Y}"
    lines = ["---",
             f'about: "How brain update {n} from AnIdeaLab went in this brain: what went in, what clashed, what broke. Sent to AnIdeaLab\'s inbox."',
             "tags: [the-brain]", f"updated: {today}", "---",
             f"# Brain update {n}: how it went", "",
             f"Applied {today}, after update {on}. The update was sent on {sent} ([its message](https://github.com/{GITHUB_REPO}/blob/main/{path})). "
             f"This brain was started from the kit of {start.day} {start:%b %Y}, and was at commit `{before}` before the update.", "",
             "## What the script did",
             f"{sum(len(v) for k, v in done.items() if k != 'same')} files changed: " + ", ".join(
                 f"{len(done[k])} {label}" for k, label in (("added", "added"), ("merged", "merged"), ("clashed", "with the update's lines over this brain's"),
                                                           ("kept", "Obsidian settings kept as the owner had them"), ("restored", "brought back"), ("deleted", "deleted"))
                 if done[k]) + f"; {len(done['same'])} already the same.", ""]
    names = {"added": "New files", "merged": "Merged with this brain's own changes",
             "clashed": "The update's lines over this brain's, where both changed the same place",
             "kept": "This brain's Obsidian settings kept over the update's, where both changed the same place",
             "restored": "Brought back (the update changed them, and this brain had deleted them)", "deleted": "Deleted"}
    for key, label in names.items():
        if done[key]:
            lines.append(f"- **{label}:** " + ", ".join(f"`{p}`" for p in done[key]))
    if not any(done[k] for k in names):
        lines.append("- Nothing: every file was already the same.")
    if places:
        lines += ["", "Where both changed the same lines (how many lines each side had there; what each said is in the section below, in the agent's words):"]
        for rel, how, hunks in places:
            if how == "whole":
                lines.append(f"- `{rel}`: the whole file, " + ("this brain's kept" if owner_setting(rel) else "the update's put in") + " (no earlier kit version to merge against, or not text)")
            else:
                sizes = "; ".join(f"{len(ours)} of this brain's against {len(theirs)} of the update's" for ours, theirs in hunks)
                lines.append(f"- `{rel}`: {len(hunks)} place{'s' if len(hunks) > 1 else ''} ({sizes}), " + ("this brain's lines kept" if how == "ours" else "the update's lines put in"))
    for title, placeholder in SECTIONS:
        lines += ["", f"## {title}", placeholder]
    lines.append("")
    report = os.path.join(FOLDER, f"{n:04d}-report.md")
    open(os.path.join(ROOT, report), "w", encoding="utf-8").write("\n".join(lines))
    return report


def do_finish(args):
    """After the message is done: make sure every section is filled in, run the checks, and add them to the report."""
    n = args.number
    rel = os.path.join(FOLDER, f"{n:04d}-report.md")
    report = os.path.join(ROOT, rel)
    if not os.path.isfile(report):
        sys.exit(f"brain_update: there's no {rel}. Apply the update first: brain_update.py apply {n}.")
    text = open(report, encoding="utf-8").read()
    # A report started by an older copy of this script: drop its single empty section, add the ones it lacks.
    text = re.sub(r"(?ms)^## How it went\n+" + OLD_PLACEHOLDER.pattern[1:-1] + r"\n*(?=^## |\Z)", "", text)
    text = re.sub(r"(?ms)^## Checks\b.*?(?=^## |\Z)", "", text).rstrip() + "\n"
    for title, placeholder in SECTIONS:
        if not re.search(r"(?m)^## " + re.escape(title) + r"\s*$", text):
            text += f"\n## {title}\n{placeholder}\n"
    open(report, "w", encoding="utf-8").write(text)
    empty = [title for title, placeholder in SECTIONS if placeholder in text] + (["How it went"] if OLD_PLACEHOLDER.search(text) else [])
    if empty:
        sys.exit(f"brain_update: {rel} still needs these sections filled in: " + "; ".join(empty) +
                 ". Replace each line in italics with what happened, then run this again.")
    checks = []
    for script, cmd in (("library.py build", ["library.py", "build"]), ("library.py check", ["library.py", "check"]),
                        ("check_links.py", ["check_links.py"]), ("test_library.py", ["test_library.py"])):
        r = subprocess.run([sys.executable, os.path.join(HERE, cmd[0]), *cmd[1:]], cwd=ROOT, capture_output=True, text=True)
        out = (r.stdout + r.stderr).strip().splitlines()
        if script == "test_library.py":
            summary = [l for l in out if l.startswith(("Ran ", "OK", "FAILED"))]
            checks.append(f"- **{script}:** " + (" ".join(summary) or f"exit {r.returncode}"))
            continue
        first = out[0] if out else f"exit {r.returncode}"
        detail = [l[2:] for l in out[1:] if re.match(r"^  \S", l)]  # a problem line; the link check's size list is indented further
        mine = [l for l in detail if re.sub(r"^[a-z ]+: ", "", l).startswith(KIT_PATHS)]
        line = f"- **{script}:** {first}"
        if script != "library.py build":
            if mine:
                line += " " + "; ".join(f"`{l}`" for l in mine[:15])
            if len(detail) > len(mine):
                line += f" (and {len(detail) - len(mine)} in the owner's own notes, not listed)"
        checks.append(line)
    diff = subprocess.run(["git", "-C", ROOT, "diff", "--shortstat", "HEAD"], capture_output=True, text=True).stdout.strip()
    today = f"{date.today().day} {date.today():%b %Y}"
    text = text.rstrip() + f"\n\n## Checks\nRun by `brain_update.py finish` on {today}, before committing" + (f" ({diff})" if diff else "") + ":\n" + "\n".join(checks) + "\n"
    text = re.sub(r"(?m)^updated: .*$", f"updated: {today}", text, count=1)
    open(report, "w", encoding="utf-8").write(text)
    print(f"Report finished: {rel}\n" + "\n".join(checks) +
          f"\n\nIf a check found a problem in the brain's files, fix it and run this again. Then commit everything as one commit, "
          f"\"Brain update {n} from AnIdeaLab: <what>\", and push: that sends the report.")


def do_send(_args):
    """Send reports to the inbox. On a push, the ones the push added or changed; run by hand, all of them."""
    folder = os.path.join(ROOT, FOLDER)
    if os.environ.get("GITHUB_EVENT_NAME") == "push":
        event = json.load(open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8"))
        paths = {p for c in event.get("commits", []) for p in c.get("added", []) + c.get("modified", [])}
        names = sorted({os.path.basename(p) for p in paths if os.path.dirname(p) == FOLDER})
    else:
        names = sorted(os.listdir(folder)) if os.path.isdir(folder) else []
    names = [n for n in names if REPORT.match(n) and os.path.isfile(os.path.join(folder, n))]
    if not names:
        print("No reports to send.")
        return
    raw = f"https://raw.githubusercontent.com/{GITHUB_REPO}/main/inbox/address.txt"
    try:
        address = urllib.request.urlopen(raw, timeout=30).read().decode().strip()
    except Exception as e:
        address = ""
        print(f"Couldn't read the inbox's address ({e}).")
    if not address:
        print("AnIdeaLab's inbox isn't open yet, so the reports stay in this brain. Run this workflow by hand later to send them all.")
        return
    req = urllib.request.Request(os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + f"&audience={AUDIENCE}",
                                 headers={"Authorization": "bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]})
    token = json.load(urllib.request.urlopen(req, timeout=30))["value"]
    for name in names:
        text = open(os.path.join(folder, name), encoding="utf-8").read()
        body = json.dumps({"name": name, "text": text}).encode()
        req = urllib.request.Request(address, data=body, method="POST",
                                     headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
        try:
            answer = urllib.request.urlopen(req, timeout=60).read().decode()
            print(f"Sent {name}: {answer}")
        except urllib.error.HTTPError as e:
            print(f"The inbox didn't take {name} ({e.code}): {e.read().decode(errors='replace')[:300]}")


def main():
    import argparse
    p = argparse.ArgumentParser(description="Apply brain updates from AnIdeaLab, and send their reports.")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check", help="which updates this brain hasn't had")
    a = sub.add_parser("apply", help="the owner said go: bring an update's files in, start its report and print its message")
    a.add_argument("number", type=int)
    k = sub.add_parser("skip", help="the owner said no: note the update as skipped, so it doesn't come up again")
    k.add_argument("number", type=int)
    f = sub.add_parser("finish", help="after doing the message: check the report is filled in, run the checks, add them to it")
    f.add_argument("number", type=int)
    sub.add_parser("send", help="send update reports to AnIdeaLab's inbox (the workflow runs this)")
    args = p.parse_args()
    {"check": do_check, "apply": do_apply, "skip": do_skip, "finish": do_finish, "send": do_send}[args.cmd](args)


if __name__ == "__main__":
    main()
