#!/usr/bin/env python3
"""Tell the agent, at the start of a session, which reminders in knowledge/systems/routines.md are due.

Matt, 18 Oct 2026: work that needs an AI or Matt can be a reminder instead of a
scheduled AI job. When he starts a session after one is due and it hasn't been done,
the agent tells him, and he decides whether to run it. Each reminder is a row in the
table in knowledge/systems/routines.md whose Kind is "Reminder":
- its When cell gives a weekday and a time in NZ time, like "Saturdays 05:00", and can
  add "from 24 Oct 2026" for the first time it's due;
- its Log cell links to a note with one heading per run (or skipped week), newest
  first, starting "## <day> <month> <year>", like the audit log.

A reminder counts as done when its log has a heading dated on or after the UTC date of
the latest due time that has passed. For a morning in NZ that UTC date is the day
before, so a run logged late the evening before counts. A heading dated after tomorrow
is ignored, so a typo can't switch a reminder off for weeks.

Any agent can run it: python3 skills/brain-spec/reminders.py. Claude Code runs it at the start of a
session through a SessionStart hook in .claude/settings.json, and what it prints goes
into the session. It prints nothing when nothing is due. It reads only this repo and
needs nothing outside Python's standard library.
Try it: python3 skills/brain-spec/reminders.py --now 2026-10-24T03:00Z
"""
import os
import re
import sys
from datetime import date, datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))  # skills/brain-spec/ is two folders down
ROUTINES = os.path.join(ROOT, "knowledge", "systems", "routines.md")
ROUTINES_DIR = os.path.dirname(ROUTINES)  # the Log links are relative to routines.md
UTC = timezone.utc
DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]  # weekday() counts Monday as 0
MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
DATE = r"(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{4})"
HEADING = re.compile(r"^##\s+" + DATE, re.M)
WHEN = re.compile(r"\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\s+(\d{1,2}):(\d{2})", re.I)
FROM = re.compile(r"\bfrom\s+" + DATE, re.I)
LINK = re.compile(r"\[([^\]]*)\]\(([^)\s#]*)[^)]*\)")

try:
    from zoneinfo import ZoneInfo
    NZ = ZoneInfo("Pacific/Auckland")
except Exception:  # no time zone database (some Windows installs)
    NZ = None


def to_date(day, month, year):
    try:
        return date(int(year), MONTHS.index(month.lower()) + 1, int(day))
    except ValueError:
        return None


def nz_offset(utc):
    """NZ's offset from UTC in hours at a UTC time, by the daylight saving rule.

    Only used when Python has no time zone database. Daylight time starts on the last
    Sunday in September at 02:00 NZST and ends on the first Sunday in April at 03:00
    NZDT; both are Saturday 14:00 UTC.
    """
    y = utc.year
    last_sun_sep = 30 - (date(y, 9, 30).weekday() + 1) % 7
    first_sun_apr = 1 + (6 - date(y, 4, 1).weekday()) % 7
    starts = datetime(y, 9, last_sun_sep, 14, tzinfo=UTC) - timedelta(days=1)
    ends = datetime(y, 4, first_sun_apr, 14, tzinfo=UTC) - timedelta(days=1)
    return 12 if ends <= utc < starts else 13


def nz_wall(utc):
    """The NZ clock time at a UTC time, without a time zone."""
    if NZ is not None:
        return utc.astimezone(NZ).replace(tzinfo=None)
    return (utc + timedelta(hours=nz_offset(utc))).replace(tzinfo=None)


def nz_to_utc(wall):
    """The UTC time when NZ clocks show a given time."""
    if NZ is not None:
        return wall.replace(tzinfo=NZ).astimezone(UTC)
    for hours in (13, 12):
        utc = wall.replace(tzinfo=UTC) - timedelta(hours=hours)
        if nz_offset(utc) == hours:
            return utc
    return wall.replace(tzinfo=UTC) - timedelta(hours=12)  # an hour the clocks skip


def latest_due(now, weekday, hour, minute):
    """The latest time at or before now when NZ clocks show that weekday and time, in UTC."""
    local = nz_wall(now)
    due = (local - timedelta(days=(local.weekday() - weekday) % 7)).replace(
        hour=hour, minute=minute, second=0, microsecond=0)
    if due > local:
        due -= timedelta(days=7)
    return nz_to_utc(due)


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
        when = WHEN.search(cells[cols["when"]])
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
            "weekday": DAYS.index(when.group(1).lower()[:3]),
            "hour": int(when.group(2)),
            "minute": int(when.group(3)),
            "start": to_date(*start.groups()) if start else None,
            "log": os.path.normpath(os.path.join(ROUTINES_DIR, log.group(2))),
        })
    return rows, problems


def main(argv):
    now = datetime.now(UTC)
    if len(argv) == 3 and argv[1] == "--now":
        now = datetime.fromisoformat(argv[2].replace("Z", "+00:00")).astimezone(UTC)
    rows, problems = read_reminders()
    due_lines = []
    for r in rows:
        due = latest_due(now, r["weekday"], r["hour"], r["minute"])
        nz = nz_wall(due)
        if r["start"] is not None and nz.date() < r["start"]:
            continue
        last = last_logged(r["log"], now.date())
        if last is not None and last >= due.date():
            continue
        log = os.path.relpath(r["log"], ROOT).replace(os.sep, "/")
        newest = "it has no entries yet" if last is None else (
            f"its newest entry is dated {last.day} {last:%b %Y}")
        due_lines.append(
            f"- {r['name']} ({r['owner']}): due {nz:%A} {nz.day} {nz:%b %Y}, {nz:%H:%M} NZ time "
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
    for p in problems:
        print("skills/brain-spec/reminders.py: " + p)


if __name__ == "__main__":
    main(sys.argv)
