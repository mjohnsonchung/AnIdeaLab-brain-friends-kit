---
name: brain-audit
description: "The weekly tidy-up of this second brain: run the library and link checks, fix what they find, a light quality pass on the cards (duplicates, notes doing two jobs, knowledge left in finished tasks, old decisions, stale tasks closed and finished ones moved to history, hand-offs folded in and tidied), turn friction-log blockers into skills, fold in skills' lessons, rewrite where each active project and area stands, then a short report for the owner. Also the monthly deep audit (deep-audit.md): every current decision read for clashes, removed rules hunted down, and a quiz of a fresh agent on the brain. Use when the owner says yes to the weekly tidy-up or monthly deep audit reminder, or asks for a brain cleanup or a deeper check."
---

# The weekly tidy-up
Once a week, the agent cleans the brain up and gives the owner a short report, so the brain stays tidy and true as it grows. It's light on purpose, and a reminder, not a scheduled job: `reminders.py` says when it's due, the agent tells the owner, and it runs only if they say yes. What past ones found is in [the audit log](../../knowledge/areas/the-brain/audit-log.md).

**Two levels.** This weekly one is cheap. Once a month, [the deep audit](deep-audit.md) reads every current decision in full and quizzes a fresh agent on the brain, to catch what only reading does.

**Keep it light.** It uses the owner's plan. Read cards, not notes: the shelves' indexes and `library.py find` show every card; open a note only when a card or a script points at a problem. For "what happened this week", read commit messages, not the notes themselves.

## 1. Clean up
1. **Brain updates first.** Pull, and if the session can reach github.com, run `python3 skills/brain-spec/brain_update.py check`. For each new update, read the owner its summary and apply it if they say go ([brain updates](../brain-spec/SKILL.md#brain-updates)).
2. Run `python3 skills/brain-spec/library.py check`, `python3 skills/brain-spec/check_links.py` and `python3 skills/brain-spec/library.py audit --since <the last tidy-up's date>`. Fix what they report. The audit stops on a shallow clone, where every note would look changed; `git fetch --unshallow origin main` fixes that.
3. Reread the notes the audit lists as changed a lot since their card's `updated` date; fix any card that no longer matches, and set `updated` to today.
4. Two cards that say nearly the same thing: merge the notes, and mark the merged-away one `dropped` or `superseded` with a link to the one that stays. Split a note doing two jobs.
5. For each task finished since the last tidy-up, save anything learned that never became a note ([brain spec](../brain-spec/SKILL.md#saving-knowledge)).
6. **Stale tasks.** The tasks shelf should hold only what's still to do. A task closes only when the agent working on it closes it, so unfinished ones pile up, many unchanged for weeks.
   - List every open, doing or waiting task whose note hasn't changed in two weeks (`git log -1 --format=%cs -- <task>`), and open each. Check the commits and the notes it names to see where it really stands.
   - Close what's finished or overtaken: mark it `done` (saving what was learned, as in step 5) or `dropped`, with a dated line under `## Progress` saying why. Merge two tasks that are the same job. Never mark the owner's part done on a guess: a task they hold that you can't settle goes to them as "keep or drop?".
   - Move every `done` or `dropped` task that hasn't changed in two weeks to `knowledge/tasks/history/` with `python3 skills/brain-spec/move.py`, then reword any live note's link to it into words, as the brain spec says for history; make the folder's `README.md` if it isn't there yet.
7. **Hand-offs.** They pile up too, and what's lasting in them belongs in the brain's notes, so the tidy-up folds them in and cuts them down. Read the [hand-offs shelf's](../../knowledge/handoffs/README.md) index, the board, and list the done ones not yet in `history/` with `python3 skills/brain-spec/library.py find --shelf handoffs --status done`. For each done one, save what's lasting in it that never became a note (decisions, facts, lessons and tasks, by the brain spec's test), then move it unchanged to `knowledge/handoffs/history/` with `move.py`, kept as the raw record, and reword any live link to it into words; make the folder's `README.md` if it isn't there yet. An open or picked-up one that hasn't changed in a week: check the commits for where its work stands, mark it `done` with a dated line if the job is finished or a newer hand-off carries it on, and cut down one that has grown past what's still true (git keeps the original).
8. A decision a newer one contradicts gets `status: superseded` and a link to the newer one, and the old rule mustn't survive in the core or other notes.
9. Ideas and parked projects nobody has touched for months go to the owner as "keep or drop?".
10. Every folder in `skills/` has a line in a list by topic (`library.py check` names any that hasn't), no line names a skill that's gone, and every copied skill has its line under its source in [lists/sources.md](../lists/sources.md), the record the scripts read to tell copied from the brain's own. If the session can reach github.com, run `python3 skills/brain-spec/skill_updates.py check` and bring changed sets up to date ([find-skills](../find-skills/SKILL.md#keeping-them-up-to-date)).

## 2. The friction log
For each open row in the [friction log](../../knowledge/ideas/friction-log.md) added since the last tidy-up: would know-how that stays the same from job to job have saved the trouble? If yes, find or write a skill for it ([find-skills](../find-skills/SKILL.md)), and move the row to "Solved" naming the skill. If it needs the owner (an account, a key, a payment), a tool nobody has built, or something outside the brain's control, it stays open.

## 3. Skill lessons
`library.py audit` lists every skill with a `LESSONS.md`. Fold each skill's lessons in, the brain's own, the kit's own and copied ones alike: put each lesson into the step it belongs to by rewording that step, delete it from `LESSONS.md`, and delete the file and its link once it's empty; at most 4 changes to one skill a week. Folded in, a lesson changes how the skill is done, rather than sitting in a list beside it that agents may not read. A brain update merges its changes around the folded lines, and where both changed the same place, the brain spec's "Brain updates" says to put the owner's lesson back.

## 4. The report
1. **Where each project and area stands:** a summary of the week and where everything is, as short as it can be without losing the detail that's needed. For each project in `knowledge/ventures/`, and each area in `knowledge/areas/` (the brain itself, and any the owner adds), whose notes, tasks or code changed since the last tidy-up, rewrite the "Where it stands" part of its note (one that has none gets one, under its opening lines) from the week's commits (`git log --since="<the last tidy-up's date>" --format="%ad %s" --date=short`) and its tasks (`python3 skills/brain-spec/library.py find --tag <name> --shelf tasks`). Rewrite it, don't add to it: date it with today, and say what's true now (what's built or live, what's being worked on, what waits on the owner or anyone else, the numbers that matter). Drop what's only history, since the commits and the notes keep it, and keep every fact still true. Keep it short, each line linking the note or task that holds the detail, so it's a map over the notes, not a second copy that drifts. A project or area that didn't move keeps its paragraph and its date.
2. Add an entry at the top of [the audit log](../../knowledge/areas/the-brain/audit-log.md), with a heading starting with today's UTC date, like `## 24 Oct 2026: tidy-up`: what was fixed, what waits on the owner, and two or three suggestions marked as the agent's own. That heading is what turns the reminder off until next week.
3. Commit in small commits with plain messages, and push.
4. Tell the owner the short version in the thread: what changed, what waits on them, and the suggestions.

## Don't
- Don't rewrite a project's plans, or decide for it: Part 4's first step rewrites only where it stands.
- Don't change links just to make the map look tidier; agents use them to find their way.
- Don't touch the brain graph's code (`.obsidian/plugins/brain-graph/`) unless the owner asks.
