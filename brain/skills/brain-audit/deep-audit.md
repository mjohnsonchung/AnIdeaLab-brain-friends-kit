# The monthly deep audit

The brain has two levels of audit. The [weekly tidy-up](SKILL.md) is cheap: scripts and cards, not notes. This monthly one reads notes in full and asks a fresh agent questions about the brain, to catch what only reading does: rules that clash without linking, a removed rule surviving in other words, and cards that no longer say what's in their note. It uses more of the owner's plan, so it comes once a month.

**When:** the first Saturday of each month, as a reminder, like the tidy-up: nothing runs until the owner says yes in a session ([routines](../../knowledge/systems/routines.md)). Do the weekly tidy-up first if it's due the same morning.

**Budget:** more of the owner's plan than the tidy-up, on purpose, but keep it in proportion. A young brain's decisions read in a few minutes; once they pass about 100 KB, read a shelf at a time and save as you go, so a usage limit doesn't lose the work. One or two agents at once, as the core says.

## 1. The clash sweep
1. **Read the core and every current decision in full,** a shelf at a time (`python3 skills/brain-spec/library.py find --shelf knowledge/decisions`). For each, ask:
   - Does a later decision change, narrow or remove it, without this one saying so?
   - Does another current note say the opposite?
   - Does the core still say what the decisions say?
2. **Hunt down removed rules.** For each rule removed or replaced since the last deep audit, search the knowledge library and the brain's own skills for its wording, and for its idea in other words ("signs off", "approves every", "must", "never"). Fix what survived.
3. **Fix the clear cases:** mark a replaced decision `status: superseded`, with a line at its top linking the newer one; add a dated pointer line to an older note a newer one changes; reword a skill line that states a removed rule. When it isn't clear which of two notes stands, ask the owner, quoting both, and leave them until they answer. Never guess for them.
4. **Leave copied skills as they came,** apart from folding in their lessons, as the tidy-up does.

## 2. The quiz
A fresh agent answers questions about the brain. An answer that comes back wrong shows a note that misled it, or a place it stopped too soon.
1. **Add 3 to 6 questions** to [quiz.json](quiz.json) from decisions made or changed since the last deep audit. Pick ones where an older note says otherwise, or where the answer sits in a note a search wouldn't reach first. Each has the question (`prompt`), the words a right answer must contain (`expect`), any that mark a stale answer (`not`), the source note, the date added and why. Keep the old ones: they're the standing traps.
2. **Ask each question of a fresh agent,** one with no memory of this session, working in the brain's folder: a subagent, or `claude -p "<question> Use only the files in this folder, don't open skills/brain-audit/quiz.json, and name the notes you got it from."` from the brain's root. Any other agent tool does the same job.
3. **Check each answer** against `expect` and `not`. For each one that's wrong or half right: which note did it stop at, or what misled it? Fix the brain, not the question (a pointer in the note it stopped at, a card that says what the note holds, or a superseded mark), then ask that question again to see the fix work. If a fine answer was marked wrong, fix the question's words instead.

## 3. Cards that drifted
The tidy-up rechecks the cards of notes that changed. Here, open 10 current notes that haven't changed in a while (the 5 most linked-to and 5 at random), and fix any card that doesn't say what its note holds.

## 4. Log it and tell the owner
- Add a heading to the top of [the deep audit log](../../knowledge/areas/the-brain/deep-audit-log.md), with today's UTC date, like `## 7 Nov 2026: deep audit`, and two or three lines under it: what was fixed, the quiz score (right of asked), and what waits on the owner. That heading turns the reminder off until next month.
- Commit in small commits with plain messages, and push.
- Tell the owner the short version in the thread.
