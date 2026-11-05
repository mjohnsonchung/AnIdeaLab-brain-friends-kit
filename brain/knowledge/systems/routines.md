---
about: "Every routine in the brain (reminders, timers, scheduled jobs) and the rules for them. Read before adding, changing or checking a routine."
tags: [the-brain]
updated: {KIT_DATE}
---
# Routines

Anything that runs, or falls due, on a beat.

## The rules
1. **Keep three things apart:** what the job is (a script or skill in the repo), when it runs (its beat, in the owner's time zone, set on the Time zone line under "The owner's own", which `reminders.py` reads), and where it runs (GitHub Actions, the PC runner, or a session the owner starts).
2. **Pick the kind:**
   - **Reminder,** for work that needs an AI or the owner. Nothing runs until the owner says yes in a session, so it uses none of their plan until then. `reminders.py` tells the agent when one is due.
   - **Code on a timer,** for work a script can do alone (a GitHub Actions `schedule:`, or a Windows task on the PC). It uses no AI.
   - **Scheduled AI job,** which uses the owner's plan by itself, only with their yes for that routine.
3. **Every routine has a row** in one of the two tables below: the brain's own, which brain updates from the kit add to, in "Running now", and the owner's in "The owner's own", so an update's new rows never meet theirs.

## Running now
| Routine | Owner | Kind | When (the owner's time) | What runs | Where it runs | Log |
|---|---|---|---|---|---|---|
| Brain update check | The brain | Code on a timer | Once a day, at the day's first session | `brain_update.py notice`, run by `reminders.py`: asks the kit repo, and says so only if an update is waiting | A session the owner starts (Claude Code's session-start hook) | [brain updates](brain-updates/README.md) |
| Upload point check | The brain | Code on a timer | Every session the owner starts | `reminders.py` reads [the upload point's list](upload-point.md), and says so only if something's waiting | A session the owner starts (Claude Code's session-start hook) | [the upload point](upload-point.md) |

## The owner's own
**Time zone:** not set yet. Getting-started asks the owner where they live and puts their time zone's name here, like Pacific/Auckland or Europe/London; `reminders.py` reads every reminder's time in it.

<!-- The owner's routines go in this table, at its end. A reminder row looks like this (the weekly tidy-up, once the owner says yes to it):
| Weekly tidy-up | The brain | Reminder | Saturdays 09:00, from 24 Oct 2026 | the brain-audit skill | A session the owner starts | [audit-log.md](../areas/the-brain/audit-log.md) |
And the monthly deep audit, once the owner says yes to it (reminders.py reads beats that are weekly, or the first of a weekday in each month):
| Monthly deep audit | The brain | Reminder | First Saturday of each month, 10:00, from 5 Dec 2026 | the deep audit in the brain-audit skill (deep-audit.md) | A session the owner starts | [deep-audit-log.md](../areas/the-brain/deep-audit-log.md) |
-->
| Routine | Owner | Kind | When (the owner's time) | What runs | Where it runs | Log |
|---|---|---|---|---|---|---|
