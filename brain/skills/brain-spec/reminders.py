#!/usr/bin/env python3
"""Tell the agent, at the start of a session, which reminders in knowledge/systems/routines.md are due.

Work that needs an AI or the owner can be a reminder instead of a scheduled AI job.
When the owner starts a session after one is due and it hasn't been done, the agent
tells them, and they decide whether to run it. Each reminder is a row in the
table in knowledge/systems/routines.md whose Kind is "Reminder":
- its When cell gives a weekday and a time in the owner's time zone, like "Saturdays 05:00",
  or the first of a weekday in each month, like "First Saturday of each month, 06:00" (for
  the monthly deep audit), and can add "from 24 Oct 2026" for the first time it's due;
- its Log cell links to a note with one heading per run (or skipped week), newest
  first, starting "## <day> <month> <year>", like the audit log.

The owner's time zone is the "**Time zone:**" line in routines.md, under "The owner's own":
a time zone's name, like Pacific/Auckland or Europe/London, which getting-started asks for.
Until it's set, or where Python can't read it (no time zone database, on some Windows
installs), times are read in this computer's own time zone, which in a cloud session is UTC,
and the agent is told to ask the owner where they live.

A reminder counts as done when its log has a heading dated on or after the UTC date of
the latest due time that has passed. For a morning in a time zone ahead of UTC that UTC
date can be the day before, so a run logged late the evening before counts. A heading
dated after tomorrow is ignored, so a typo can't switch a reminder off for weeks.

Any agent can run it: python3 skills/brain-spec/reminders.py. Claude Code runs it at the start of a
session through a SessionStart hook in .claude/settings.json, and what it prints goes
into the session. It prints nothing when nothing is due. It reads only this repo and
needs nothing outside Python's standard library. In a brain started from the AnIdeaLab brain
kit, it also runs brain_update.py notice beside it, which asks the kit repo at most once a day
whether AnIdeaLab has sent an update, and prints only when one is waiting, so a day with no
update costs the session nothing. In a kit brain it also says how many
things are waiting at the upload point and since when (knowledge/systems/upload-point.md, which the
owner's Upload point window writes; 31 Oct 2026), so the agent asks the owner what to do with them.
It's silent when nothing's waiting, and in a brain without the note.
Try it: python3 skills/brain-spec/reminders.py --now 2026-10-24T03:00Z
"""
import os
import re
import subprocess
import sys
import time
from datetime import date, datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))  # skills/brain-spec/ is two folders down
ROUTINES = os.path.join(ROOT, "knowledge", "systems", "routines.md")
ROUTINES_DIR = os.path.dirname(ROUTINES)  # the Log links are relative to routines.md
UPLOAD_POINT = os.path.join(ROOT, "knowledge", "systems", "upload-point.md")  # kit brains only
UTC = timezone.utc
DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]  # weekday() counts Monday as 0
MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
DATE = r"(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{4})"
HEADING = re.compile(r"^##\s+" + DATE, re.M)
WHEN = re.compile(r"\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\s+(\d{1,2}):(\d{2})", re.I)
MONTHLY = re.compile(r"\bfirst\s+(mon|tue|wed|thu|fri|sat|sun)[a-z]*\b.*?(\d{1,2}):(\d{2})", re.I)
FROM = re.compile(r"\bfrom\s+" + DATE, re.I)
LINK = re.compile(r"\[([^\]]*)\]\(([^)\s#]*)[^)]*\)")
WAITING = re.compile(r"(?ms)^##\s+Waiting\s*$(.*?)(?=^#{1,2}\s|\Z)")
ITEM = re.compile(r"(?m)^\s*[-*]\s+(`+)\s?(.+?)\s?\1(?!`)(.*)$")  # - `<path>`: <kind>, <size>, added <when>
ADDED = re.compile(r"\badded\s+" + DATE + r"(?:\s+(\d{1,2}):(\d{2}))?", re.I)
# The owner's time zone: a name from the time zone database (Area/City, like Pacific/Auckland), or UTC.
# The kit's line says "not set yet" until getting-started fills it in, which this doesn't match.
ZONE_LINE = re.compile(r"(?m)^\*\*Time zone:\*\*[ \t]*([A-Za-z][A-Za-z_]*(?:/[A-Za-z0-9_+-]+)+|UTC)\b")


def owner_zone():
    """The owner's time zone from routines.md: (its name, or None if not set; the zone, or None if Python can't read it)."""
    try:
        with open(ROUTINES, encoding="utf-8") as fh:
            m = ZONE_LINE.search(fh.read())
    except OSError:
        m = None
    if not m:
        return None, None
    try:
        from zoneinfo import ZoneInfo
        return m.group(1), ZoneInfo(m.group(1))
    except Exception:  # no time zone database (some Windows installs), or not a zone's name
        return m.group(1), None


ZONE_NAME, ZONE = owner_zone()


def to_date(day, month, year):
    try:
        return date(int(year), MONTHS.index(month.lower()) + 1, int(day))
    except ValueError:
        return None


def owner_wall(utc):
    """The owner's clock time at a UTC time, without a time zone (this computer's, if theirs can't be read)."""
    if ZONE is not None:
        return utc.astimezone(ZONE).replace(tzinfo=None)
    return utc.astimezone().replace(tzinfo=None)


def owner_to_utc(wall):
    """The UTC time when the owner's clocks show a given time (this computer's, if theirs can't be read)."""
    if ZONE is not None:
        return wall.replace(tzinfo=ZONE).astimezone(UTC)
    return datetime.fromtimestamp(time.mktime(wall.timetuple()), UTC)


def latest_due(now, weekday, hour, minute):
    """The latest time at or before now when the owner's clocks show that weekday and time, in UTC."""
    local = owner_wall(now)
    due = (local - timedelta(days=(local.weekday() - weekday) % 7)).replace(
        hour=hour, minute=minute, second=0, microsecond=0)
    if due > local:
        due -= timedelta(days=7)
    return owner_to_utc(due)


def latest_due_monthly(now, weekday, hour, minute):
    """The latest time at or before now when the owner's clocks show the first of that weekday in a month, in UTC."""
    local = owner_wall(now)
    year, month = local.year, local.month
    for _ in range(2):
        first = date(year, month, 1)
        day = first + timedelta(days=(weekday - first.weekday()) % 7)
        due = datetime(day.year, day.month, day.day, hour, minute)
        if due <= local:
            return owner_to_utc(due)
        year, month = (year, month - 1) if month > 1 else (year - 1, 12)
    return owner_to_utc(due)


def last_logged(path, today):
    """The newest date heading in a log note up to tomorrow (UTC), or None."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    dates = [d for d in (to_date(*m) for m in HEADING.findall(text))
             if d is not None and d <= today + timedelta(days=1)]
    return max(dates) if dates else None


def plain(cell):
    """A table cell as plain text: links become their words, bold marks go."""
    return LINK.sub(r"\1", cell).replace("**", "").replace("`", "").strip()


def read_reminders():
    """The reminder rows in knowledge/systems/routines.md, and a note of any it couldn't read."""
    try:
        with open(ROUTINES, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return [], ["knowledge/systems/routines.md is missing, so no reminders were checked."]
    rows, problems, cols = [], [], None
    for line in lines:
        if not line.lstrip().startswith("|"):
            cols = None
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cols is None:
            names = [plain(c).lower() for c in cells]
            found = {key: next((i for i, n in enumerate(names) if n.startswith(key)), None)
                     for key in ("routine", "owner", "kind", "when", "what", "log")}
            if None not in found.values():
                cols = found
            continue
        if len(cells) <= max(cols.values()) or plain(cells[cols["kind"]]).lower() != "reminder":
            continue
        name = plain(cells[cols["routine"]])
        monthly = MONTHLY.search(cells[cols["when"]])
        when = monthly or WHEN.search(cells[cols["when"]])
        start = FROM.search(cells[cols["when"]])
        log = LINK.search(cells[cols["log"]])
        if not when or not log or not log.group(2):
            problems.append(f'in knowledge/systems/routines.md, the reminder row "{name}" needs a weekday and time in When '
                            '(like "Saturdays 05:00") and a link to its log in Log. Fix the row.')
            continue
        rows.append({
            "name": name,
            "owner": plain(cells[cols["owner"]]),
            "what": plain(cells[cols["what"]]),
            "monthly": bool(monthly),
            "weekday": DAYS.index(when.group(1).lower()[:3]),
            "hour": int(when.group(2)),
            "minute": int(when.group(3)),
            "start": to_date(*start.groups()) if start else None,
            "log": os.path.normpath(os.path.join(ROUTINES_DIR, log.group(2))),
        })
    return rows, problems


def upload_point():
    """A line for the agent when something's waiting at the upload point, or None."""
    try:
        with open(UPLOAD_POINT, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    waiting = WAITING.search(text)
    items = ITEM.findall(waiting.group(1)) if waiting else []
    if not items:
        return None
    added = []
    for *_, rest in items:
        m = ADDED.search(rest)
        day = to_date(*m.group(1, 2, 3)) if m else None
        if day:
            added.append((day, f"{int(m.group(4)):02d}:{m.group(5)}" if m.group(4) else ""))
    since = ""
    if added:
        day, time = min(added)
        since = f", the oldest since {day.day} {day:%b %Y}" + (f" {time}" if time else "")
    n = len(items)
    return (f"Upload point: {n} thing{'s' if n != 1 else ''} waiting{since}, in knowledge/systems/upload-point.md "
            "(the owner's Upload point window writes it on GitHub, so pull first). In your first reply, tell the owner "
            "in one line and ask what they'd like done with them, unless they've already said; then sort them with the "
            "upload-point skill. Ignore this if the owner didn't start this session.")


def main(argv):
    now = datetime.now(UTC)
    if len(argv) == 3 and argv[1] == "--now":
        now = datetime.fromisoformat(argv[2].replace("Z", "+00:00")).astimezone(UTC)
    rows, problems = read_reminders()
    due_lines = []
    zone = f"{ZONE_NAME} time" if ZONE is not None else "this computer's time"
    for r in rows:
        due = (latest_due_monthly if r["monthly"] else latest_due)(now, r["weekday"], r["hour"], r["minute"])
        local = owner_wall(due)
        if r["start"] is not None and local.date() < r["start"]:
            continue
        last = last_logged(r["log"], now.date())
        if last is not None and last >= due.date():
            continue
        log = os.path.relpath(r["log"], ROOT).replace(os.sep, "/")
        newest = "it has no entries yet" if last is None else (
            f"its newest entry is dated {last.day} {last:%b %Y}")
        due_lines.append(
            f"- {r['name']} ({r['owner']}): due {local:%A} {local.day} {local:%b %Y}, {local:%H:%M} {zone} "
            f"[UTC date {due.day} {due:%b %Y}]. What runs: {r['what']}. "
            f"Log: {log}; {newest}.")
    if due_lines:
        print(
            "Reminders due, from knowledge/systems/routines.md. The brain's rule: a reminder is not a "
            "scheduled AI job. When the owner starts a session after one is due and it hasn't been "
            "done, tell them, and they decide whether to run it.\n" + "\n".join(due_lines) + "\n"
            "In your first reply, tell the owner in one line each what's due and ask whether they want "
            "to run it. Then carry on with what they asked, and don't run a reminder unless they say "
            "so. If they say to skip it this time, add a heading to its log dated today (UTC), like "
            '"## 25 Oct 2026: skipped (owner)", so it stays quiet until it is next due. Ignore '
            "this if the owner didn't start this session (a scheduled run or another agent's session), "
            "or if, after you pull, the log has an entry dated on or after the UTC date given."
        )
    if rows and ZONE is None:
        problems.append(
            ("the owner's time zone isn't set" if ZONE_NAME is None else
             f"Python couldn't read the time zone {ZONE_NAME} (not a time zone's name, or no time zone database here: "
             "on Windows, py -m pip install tzdata adds one)")
            + ", so reminders were read in this computer's time, which in a cloud session is UTC. Ask the owner where "
            "they live, in a line, and put their time zone's name on the \"Time zone\" line under \"The owner's own\" "
            "in knowledge/systems/routines.md (like **Time zone:** Europe/London), then commit.")
    for p in problems:
        print("skills/brain-spec/reminders.py: " + p)
    waiting = upload_point()
    if waiting:
        print(waiting)
    update = os.path.join(HERE, "brain_update.py")
    if os.path.isfile(update) and len(argv) == 1:  # a brain started from the kit: is a brain update waiting?
        try:
            r = subprocess.run([sys.executable, update, "notice"], capture_output=True, text=True, timeout=8)
            if r.returncode == 0 and r.stdout.strip():
                print(r.stdout.strip())
        except (OSError, subprocess.SubprocessError):
            pass  # silent: it asks again at the next session


if __name__ == "__main__":
    main(sys.argv)
