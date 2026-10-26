---
name: brain-audit
description: "The weekly tidy-up of this second brain: run the library and link checks, fix what they find, a light quality pass on the cards (duplicates, notes doing two jobs, knowledge left in finished tasks, old decisions), turn friction-log blockers into skills, fold in skills' lessons, then a short report for the owner. Use when the owner says yes to the weekly tidy-up reminder, or asks for a brain cleanup."
---

# The weekly tidy-up
Matt's brain, which this one was started from, has a weekly audit (Matt, 18 Oct 2026: "an audit and like a, like a weekly report for me and for you to go in and clean up"). This is a lighter version. It's a reminder, not a scheduled job: `reminders.py` says when it's due, the agent tells the owner, and it runs only if they say yes. What past ones found is in [the audit log](../../knowledge/areas/the-brain/audit-log.md).

**Keep it light.** It uses the owner's plan. Read cards, not notes: the shelves' indexes and `library.py find` show every card; open a note only when a card or a script points at a problem. For "what happened this week", read commit messages, not the notes themselves.

## 1. Clean up
1. **Brain updates first.** Pull, and if the session can reach github.com, run `python3 skills/brain-spec/brain_update.py check`. For each new update, read the owner its summary and apply it if they say go ([brain updates](../brain-spec/SKILL.md#brain-updates)).
2. Run `python3 skills/brain-spec/library.py check`, `python3 skills/brain-spec/check_links.py` and `python3 skills/brain-spec/library.py audit --since <the last tidy-up's date>`. Fix what they report. The audit stops on a shallow clone, where every note would look changed; `git fetch --unshallow origin main` fixes that.
3. Reread the notes the audit lists as changed a lot since their card's `updated` date; fix any card that no longer matches, and set `updated` to today.
4. Two cards that say nearly the same thing: merge the notes, and mark the merged-away one `dropped` or `superseded` with a link to the one that stays. Split a note doing two jobs.
5. For each task finished since the last tidy-up, save anything learned that never became a note ([brain spec](../brain-spec/SKILL.md#saving-knowledge)).
6. A decision a newer one contradicts gets `status: superseded` and a link to the newer one, and the old rule mustn't survive in the core or other notes.
7. Ideas and parked projects nobody has touched for months go to the owner as "keep or drop?".
8. Every folder in `skills/` has a line in the [skills list](../README.md). If the session can reach github.com, run `python3 skills/brain-spec/skill_updates.py check` and bring changed sets up to date ([find-skills](../find-skills/SKILL.md#keeping-them-up-to-date)).

## 2. The friction log
For each open row in the [friction log](../../knowledge/ideas/friction-log.md) added since the last tidy-up: would know-how that stays the same from job to job have saved the trouble? If yes, find or write a skill for it ([find-skills](../find-skills/SKILL.md)), and move the row to "Solved" naming the skill. If it needs the owner (an account, a key, a payment), a tool nobody has built, or something outside the brain's control, it stays open.

## 3. Skill lessons
`library.py audit` lists every skill with a `LESSONS.md`. For the brain's own skills, fold each lesson into the step it belongs to by rewording that step, delete it from `LESSONS.md`, and delete the file and its link once it's empty; at most 4 changes to one skill a week. A copied skill's text stays as it came: merge its repeated lessons and delete ones an update has fixed.

## 4. The report
1. Add an entry at the top of [the audit log](../../knowledge/areas/the-brain/audit-log.md), with a heading starting with today's UTC date, like `## 24 Oct 2026: tidy-up`: what was fixed, what waits on the owner, and two or three suggestions marked as the agent's own. That heading is what turns the reminder off until next week.
2. Commit in small commits with plain messages, and push.
3. Tell the owner the short version in the thread: what changed, what waits on them, and the suggestions.

## Don't
- Don't rewrite a project's plans, or decide for it.
- Don't change links just to make the map look tidier; agents use them to find their way.
- Don't touch the brain graph's code (`.obsidian/plugins/brain-graph/`) unless the owner asks.
