#!/usr/bin/env python3
"""Apply brain updates from AnIdeaLab, and send their reports to AnIdeaLab's inbox.

This brain was started from a starter kit made from Matt's brain. Matt sends updates to it
(fixes, new rules, new parts) through the public repo AnIdeaLab-brain-friends-kit:
- brain/ holds the kit's brain as a fresh one would get it, with its two date placeholders
  left in for each brain's own start date;
- updates/NNNN-<words>.md is each update's message: what changed, why, and anything to do
  beyond the files. The commit that added it holds brain/ as of that update.

    python3 skills/brain-spec/brain_update.py check        # which updates this brain hasn't had
    python3 skills/brain-spec/brain_update.py apply 3      # bring update 3's files in, start its report, print its message
    python3 skills/brain-spec/brain_update.py send         # the "Send brain update reports" workflow runs this

`apply` takes each file the update changed in brain/ and puts the change into this brain with a
three-way merge (git merge-file), so the brain's own changes elsewhere in a file stay. Where both
changed the same lines, the update's lines go in. A file the update adds is written, one it changed
that this brain no longer has is written again, and one it deleted is deleted. Then it records the
update in knowledge/systems/brain-updates/README.md and starts knowledge/systems/brain-updates/NNNN-report.md
with what it did. The rest, and when to use it: the brain spec's "Brain updates" section.

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
UPDATE = re.compile(r"^updates/(\d{4})-[a-z0-9-]+\.md$")
REPORT = re.compile(r"^\d{4}-report\.md$")
# The kit repo's date placeholders, spelt in two parts so the kit's build doesn't fill them in here.
DATE_MARK, ISO_MARK = ("{" + "KIT_DATE}").encode(), ("{" + "KIT_ISO}").encode()


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
    """Every update in the kit repo: {number: (file, commit, date)}, from the commits that added them."""
    out = git("log", "--diff-filter=A", "--format=@%H %cs", "--name-only", head, "--", "updates/")
    found, commit, day = {}, None, None
    for line in out.splitlines():
        if line.startswith("@"):
            commit, day = line[1:].split()
        elif UPDATE.match(line):
            found.setdefault(int(UPDATE.match(line).group(1)), (line, commit, day))
    return found


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


def fill(data, start):
    return data.replace(DATE_MARK, f"{start.day} {start:%b %Y}".encode()).replace(ISO_MARK, start.isoformat().encode())


def blob(commit, path):
    r = subprocess.run(["git", "-C", CACHE, "show", f"{commit}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def merge3(mine, base, theirs):
    """Three-way merge with git merge-file; where both changed the same lines, the update's lines win."""
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for name, data in (("mine", mine), ("base", base), ("theirs", theirs)):
            p = os.path.join(tmp, name)
            open(p, "wb").write(data)
            paths.append(p)
        r = subprocess.run(["git", "merge-file", "-p", "--theirs", *paths], capture_output=True)
        if r.returncode:
            sys.exit(f"brain_update: git merge-file failed: {r.stderr.decode(errors='replace')[:300]}")
        clashed = subprocess.run(["git", "merge-file", "-p", *paths], capture_output=True).returncode > 0
        return r.stdout, clashed


def do_check(_args):
    head = fetch()
    found = updates(head)
    on = current(found)
    new = sorted(n for n in found if n > on)
    if not new:
        print(f"Up to date: this brain has kit update {on}, the newest." if found else "The kit hasn't sent any updates yet.")
        return
    print(f"This brain has kit update {on}. New:")
    for n in new:
        path, _, day = found[n]
        print(f"  {n}  {day}  {path}")
    print(f"Apply them oldest first: python3 skills/brain-spec/brain_update.py apply {new[0]}")


def do_apply(args):
    head = fetch()
    found = updates(head)
    n = args.number
    if n not in found:
        sys.exit(f"brain_update: the kit has no update {n}.")
    on = current(found)
    if n != on + 1:
        sys.exit(f"brain_update: this brain has update {on}, so apply {on + 1} next." if n > on
                 else f"brain_update: this brain already has update {n}.")
    path, target, day = found[n]
    base = found[n - 1][1] if n - 1 in found else git("rev-list", "--max-parents=0", head).split()[0]
    start = kit_start()
    changes = git("diff", "--name-status", "--no-renames", base, target, "--", "brain/").splitlines()
    done = {"added": [], "merged": [], "clashed": [], "restored": [], "deleted": [], "same": []}
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
        if mine is None:
            new = theirs
            done["added" if status == "A" else "restored"].append(rel)
        elif old is None or b"\0" in theirs or b"\0" in mine:
            new = theirs
            done["clashed"].append(rel)
        else:
            new, clashed = merge3(mine, fill(old, start), theirs)
            done["clashed" if clashed else "merged"].append(rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        open(dest, "wb").write(new)

    record(n)
    report = start_report(n, path, day, done)
    message = blob(target, path).decode("utf-8", errors="replace")
    print(f"Update {n} ({day}): {len(done['added'])} added, {len(done['merged'])} merged, {len(done['clashed'])} with the update's lines "
          f"over this brain's, {len(done['restored'])} brought back, {len(done['deleted'])} deleted, {len(done['same'])} already the same.")
    print(f"Report started: {report}\n\nThe update's message, to do now:\n\n{message}")


def record(n):
    """Say in this brain's brain-updates note which update it has."""
    readme = os.path.join(ROOT, FOLDER, "README.md")
    if not os.path.isfile(readme):
        os.makedirs(os.path.dirname(readme), exist_ok=True)
        open(readme, "w", encoding="utf-8").write(
            '---\nabout: "Brain updates from AnIdeaLab: which one this brain has, and a report of each."\n'
            f"tags: [the-brain]\nupdated: {date.today().day} {date.today():%b %Y}\n---\n# Brain updates\n")
    text = open(readme, encoding="utf-8").read()
    line = f"**On kit update:** {n} (applied {date.today().day} {date.today():%b %Y})"
    text = ON.sub(line, text, count=1) if ON.search(text) else text.rstrip() + f"\n\n{line}\n"
    open(readme, "w", encoding="utf-8").write(text)


def start_report(n, path, day, done):
    today = f"{date.today().day} {date.today():%b %Y}"
    sent = date.fromisoformat(day)
    sent = f"{sent.day} {sent:%b %Y}"
    lines = ["---",
             f'about: "How brain update {n} from AnIdeaLab went in this brain: what went in, what clashed, what broke. Sent to AnIdeaLab\'s inbox."',
             "tags: [the-brain]", f"updated: {today}", "---",
             f"# Brain update {n}: how it went", "",
             f"Applied {today}. The update was sent on {sent} ([its message](https://github.com/{GITHUB_REPO}/blob/main/{path})).", "",
             "## What the script did"]
    names = {"added": "New files", "merged": "Merged with this brain's own changes",
             "clashed": "The update's lines over this brain's, where both changed the same place",
             "restored": "Brought back (the update changed them, and this brain had deleted them)", "deleted": "Deleted"}
    for key, label in names.items():
        if done[key]:
            lines.append(f"- **{label}:** " + ", ".join(f"`{p}`" for p in done[key]))
    if not any(done[k] for k in names):
        lines.append("- Nothing: every file was already the same.")
    lines += ["", "## How it went", "*The agent that applied it fills this in.*", ""]
    report = os.path.join(FOLDER, f"{n:04d}-report.md")
    open(os.path.join(ROOT, report), "w", encoding="utf-8").write("\n".join(lines))
    return report


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
    a = sub.add_parser("apply", help="bring an update's files in, start its report and print its message")
    a.add_argument("number", type=int)
    sub.add_parser("send", help="send update reports to AnIdeaLab's inbox (the workflow runs this)")
    args = p.parse_args()
    {"check": do_check, "apply": do_apply, "send": do_send}[args.cmd](args)


if __name__ == "__main__":
    main()
