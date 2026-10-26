---
name: brain-spec
description: "How to add to or change this second brain so it stays cohesive and cheap for agents to read: the core, the skills library and the knowledge library's shelves; whether something is a skill or knowledge; cards and tags; the indexes and scripts; tasks and hand-offs; what to save; writing notes; skills, lessons and routines; and checks before you push. Use before making or moving any note, task, decision, idea, skill or routine, or when unsure where something goes."
---

# The brain spec
Where each kind of thing goes in the brain, and what shape it takes. It comes from Matt's brain, which this one was started from, where it was written so that everything "it's all cohesive... in line with you know it being efficient for an agent to use" (Matt, 18 Oct 2026). The rules themselves, the owner's defaults and the gates, are in the core ([CLAUDE.md](../../CLAUDE.md)); this is how to apply them. Any agent can follow it; it's a plain file.

## The shape
```
CLAUDE.md       the core: read by every agent, about a page
skills/         the skills library: how to do things
knowledge/      the knowledge library: what's true
```
Beside them: `README.md` (the owner's front door), `.github/` (the Actions), `.obsidian/` (Obsidian's shared settings) and `.claude/` (Claude Code's own settings). Nothing else goes at the top level.

**Skill or knowledge?** Know-how that works for any project, the same from job to job, is a skill. How one project does things, and anything true about the owner, their projects, people, systems or decisions, is knowledge, kept with that project or on its shelf. So "how to run an ad campaign" is a skill, and "the shop's ads may spend $50 a week" is knowledge.

**Links run one way.** Notes may point at skills, but skills don't point at notes, so skills stay general. The exceptions are the skills that run the brain's own machinery (brain-spec, brain-audit, getting-started, guide-mode, my-pc), the skills list itself, and a skill citing the decision it comes from. `library.py check` reports any other.

## The shelves
| Shelf | What goes there |
|---|---|
| `knowledge/tasks/` | What's in flight, who holds it, what waits on the owner. One note per task. |
| `knowledge/ventures/` | Things with a goal: businesses, projects, client work. A note each, or a folder once it has several notes. |
| `knowledge/areas/` | Ongoing things with no end: the brain itself (`the-brain/`), later money, health, home. |
| `knowledge/decisions/` | What the owner decided, standing rules included, on a sub-shelf per project or area. |
| `knowledge/people/` | The owner, customers, suppliers, contacts. One note per person. |
| `knowledge/systems/` | Accounts, the PC, routines, Obsidian, the brain graph. |
| `knowledge/ideas/` | Not started yet, the friction log included. |
| `knowledge/subjects/` | The open library, one note or folder per field, kept when facts took effort to get. |

- **A note's folder says what kind of thing it is; its tags say what it's about.** A tag is the name of a project, area or subject: its folder or file name (`the-brain`, `my-shop`).
- **The working shelves are fixed. Subjects grow,** and so does everything inside a shelf. A new subject, project or area starts as one note, and becomes a folder with its own `README.md` once it has several.
- **Every folder in `knowledge/` has a `README.md`:** its card, a few hand-written lines, and the index between `<!-- index:start -->` and `<!-- index:end -->`, which the script fills.
- **Old history goes in a `history/` sub-shelf** of the project or area it's about, marked `status: done`. Obsidian hides every `history/` folder. Current notes don't link into `history/`: say where a retired note is in words.
- **A new project** is a note (later a folder) in `ventures/`: what it is, its goal in the owner's words, where it stands, its code repo and its look; decisions, tasks and people about it are tagged with its name.

## Cards
Every note starts with a card in its front matter, which Obsidian shows as the note's properties:
```
---
about: "What the shop's supplier charges and their rules. Read before ordering stock or quoting a price."
tags: [my-shop]
status: current
updated: {KIT_DATE}
---
```
| Field | What it says |
|---|---|
| `about` | One line, under 250 characters: what's in the note and **when you'd read it**. It's the line an agent picks by. Always in double quotes, with no double quotes or backslashes inside. |
| `tags` | The projects, areas or subjects it's about, by their names. Optional. |
| `status` | Tasks: `open`, `doing`, `waiting`, `done` or `dropped`. Decisions: `current` or `superseded`. Ideas: `raw`, `researching`, `parked`, `graduated` or `dropped` (turned down). Ventures: `current`, `parked` or `done`. Anything else: `current` (the default) or `done`. |
| `updated` | When someone last made sure the note and its card are true, like `{KIT_DATE}`. |
| `holder` | Tasks only: `owner`, `open`, or the session link of the agent holding it. |
| `parent` | Tasks only, optional: the file name of the task it came from. |
| `due` | Optional: a date. |

The file name is the note's name, in lower-case words with hyphens. A decision's file name starts with its date (`{KIT_ISO}-...`). The body is free: a `# Title`, then dated, sourced writing.

## The indexes and the scripts
All in this folder, plain Python 3 with nothing to install:
- **`library.py build`** fills each `README.md`'s index from the cards in its folder; tasks are grouped under "Waiting on the owner", "Doing", "Waiting" and "Open", and finished notes are counted, not listed. A GitHub Action ([library.yml](../../.github/workflows/library.yml)) runs it on every push and commits the indexes, so never edit an index by hand.
- **`library.py find`** answers questions from the cards: `find --tag my-shop`, `find --shelf tasks --holder owner`, `find --text "supplier"`; add `--all` for finished notes.
- **`library.py check`** reports missing cards and fields, bad statuses, unknown tags, folders with no `README.md`, an index past about 60 entries, the core or the skills list over 6 KB, skills linking into notes, brain skills over 500 lines, skills with no line in a topic list, a source's commit line outside `skills/lists/sources.md`, and `LESSONS.md` files their skill doesn't link. `--strict` exits 1 if there's anything.
- **`library.py audit --since <date>`**, for the weekly tidy-up: notes changed a lot since their card was checked, tasks finished since then, and skills with lessons.
- **`check_links.py`**: broken links, notes nothing links to, big or binary files, and the core's and indexes' sizes.
- **`move.py MAP`** moves files and folders and fixes every link to them (`--dry-run` first). Paths in plain text aren't links: backticked paths, workflows, script defaults and comments are listed in its report, for fixing by hand.
- **`reminders.py`** prints the reminders that are due; the session-start hook runs it. A Claude Code hook only runs in a new session started in a clone of this repo, never for other agents, so whatever a hook does is also written in the notes (here, the core says to run it) to be done by hand.
- **`skill_updates.py`** checks copied skills against their sources ([find-skills](../find-skills/SKILL.md)).
- **`brain_update.py`** applies brain updates from AnIdeaLab and sends their reports ([below](#brain-updates)).
- `test_library.py` tests `library.py`.

## Tasks and hand-offs
- **A task note** is for work that will outlive the session, waits on someone, or is handed on. A job finished in one go needs none: git has the change, and anything learned goes to the library.
- **Whoever hands a task out makes the note,** and closes it when the work comes back. The agent doing the work can add dated lines under `## Progress`.
- **Something only the owner can do** is a task with `holder: owner`. Ask them in your thread as well.
- **When a task closes,** set its status to `done` or `dropped`, add a dated line, and save what was learned that should outlive it.
- **One note per task** keeps git conflicts rare.

## Saving knowledge
- **The test:** would an agent starting cold next month need this, and would it be hard to get again? If yes, save it.
- **Don't save** what's already in code or git history, what a quick search would find again, or chatter.
- **Update before you add.** Check the shelf's index first (or `library.py find`). If a card already covers it, update that note.
- **One note per thing:** one person, one decision, one project.
- **When:** save the owner's decisions straight away, so a dropped session can't lose them. Save everything else when a task closes, and whenever the owner says "remember this".
- **A decision** gets its own note: its card, then "**Decided** <date>, by <who, where>", the decision with the owner's words in quotes, and what it means in practice. When it changes, write the new note and mark the old one `status: superseded` with a line linking the new one. Never delete a decision. A rule every agent must follow also gets one line in the core.
- **An idea** gets its own note: what it is, why it might be worth it and what it would take, its status and where it came from.
- **A blocker that slowed you down** is one row in the [friction log](../../knowledge/ideas/friction-log.md).

## Writing notes
- **Date every fact and say where it came from:** who said it and when, or which file. Mark guesses as guesses. Dates are written like "{KIT_DATE}".
- **When something changes,** update the note and mark the old entry superseded rather than deleting it.
- **Plain English,** short full sentences. Use the owner's own words for what they want.
- **Link notes with relative Markdown links,** like the ones in this note, so they work for agents, on GitHub and in Obsidian's graph. To link a section, use `note.md#heading`, in lower case with hyphens for spaces. Renaming a heading breaks those links, so search for the old anchor first; `check_links.py` reports any left.
- **Whatever a note points to, any agent can get:** save it in this repo, a project's repo or on the PC under `C:\AI-Brain-Link\`, and say where. Never make a Claude artifact, or anything else only one AI app's account can open ([the starting rules](../../knowledge/decisions/the-brain/{KIT_ISO}-starting-rules.md)). A page for the owner is an HTML file saved in one of those places.
- **Big or binary files** (images, video, zips) don't go in the brain: keep them on the PC under `C:\AI-Brain-Link\`, or in a separate private repo for files if the owner makes one, and link to where they are. Keys go in neither.
- **Code** for a project lives in the project's own repo, with its own `CLAUDE.md`.

## A skill
- **Look for one before writing one:** [find-skills](../find-skills/SKILL.md) says where, and how to copy one in.
- **A folder,** `skills/<name>/`, in lower-case words with hyphens, holding `SKILL.md` and any files it needs. A script that finds the repo from its own place counts folders up to the root, so moving it to another depth breaks that count: fix it and run it.
- **A line saying when to use it, in a list by topic** in `skills/lists/`, for every skill, the brain's own and copied: one line per skill, in the list for the job it serves most, or in a new list linked from the [skills list](../README.md) under "The lists by topic". The brain's own come first in a list, under a "The brain's own" heading, and the copied ones follow under "Copied". Why: the brain's own were written for this brain, so read them before a copied one on the same job, and they're changed freely while a copied one stays as it came. The skills list itself names only the few most jobs need, and stays short because every agent reads it: `library.py check` flags it past 6 KB.
- **Which skills are copied is in [lists/sources.md](../lists/sources.md),** the record: a heading per source, its "From" line with the commit, and its skills. A skill with a line in it is copied (a link in its prose doesn't count), and any other is the brain's own. The scripts read it, not the lists' headings, to know which skills to leave as they came (the link check), which to hold to the brain's own rules (`library.py check`) and which to check for updates (`skill_updates.py`). So a copied skill has a line in a topic list and one under its source in `sources.md`, and a source's commit is only ever in `sources.md`. `library.py check` reports a skill with no line in a topic list, and a commit line anywhere else.
- **Front matter** has `name` and `description`, in double quotes. The description is all an agent sees before opening the skill, so say exactly when to use it.
- **Know-how only.** Jobs, customers and state go in the knowledge library.
- **Under 500 lines.** Past that, move detail into a file in the skill's folder and link it ([skill-creator](../skill-creator/SKILL.md) helps write and test one).

### How skills learn
- **A lesson** is one dated line, saved when a skill let you down (a step that was wrong, missing or out of date) or when the owner corrected work done with it. Say what happened and what to do instead, kept general like the skill.
- **`LESSONS.md`, in the skill's folder,** holds them, newest at the top. It exists once the skill has a lesson, and starts like this:
  ```
  # Lessons: <skill name>
  *What agents learned using this skill in the brain, one dated line each, newest at the top.*

  - **{KIT_DATE}:** what happened, and what to do instead.
  ```
- **The skill links it,** near the top of the brain's own skills, and in an `## In this brain` section at the very end of a copied skill, with this line:
  ```
  Lessons from using this skill in the brain: [LESSONS.md](LESSONS.md).
  ```
- **The weekly tidy-up** ([brain-audit](../brain-audit/SKILL.md)) folds a brain skill's lessons into its steps and keeps a copied skill's lessons short.

## A routine
Anything that runs or falls due on a beat gets a row in [routines](../../knowledge/systems/routines.md). The job is a script or skill in the repo; the trigger only says when and where. A reminder costs nothing until the owner says yes to it in a session; a scheduled AI job uses their plan by itself, so it needs their yes first.

## Brain updates
Matt, who made the starter kit this brain was started from, sends updates to brains like it from AnIdeaLab: fixes, new rules and new parts, through the public repo [AnIdeaLab-brain-friends-kit](https://github.com/mjohnsonchung/AnIdeaLab-brain-friends-kit). **The owner decides each one:** read them its summary, and apply it only if they say go. A check runs at the start of a session, asking the kit repo at most once a day (`reminders.py` runs `brain_update.py notice`), and it's silent unless an update is waiting; when one is, tell the owner in your first reply and ask whether they'd like to hear it. The weekly tidy-up checks too, and so does any agent the owner asks to. Which update this brain has, which the owner skipped, and a report of each, are in [brain updates](../../knowledge/systems/brain-updates/README.md).

**What an update is for: it brings this brain to the kit as it is now.** Matt, 26 Oct 2026, after the first updates: "I feel like their brains are set up in the right way now. I don't want to let any changes that originally happened with them messing around with it in its early stages to carry through now that we have the right update applied to it." So, once the owner says go:
- **The owner's own stuff stays:** everything in the knowledge library, skills and lists they added, their own tools and scripts, their PC's folders and names, their Obsidian settings, and lines they wrote into a kit file about their own setup (a skill's licence note, a link to their own list).
- **This brain's own fixes to kit parts give way.** Where this brain fixed or worked around something in a file the kit gave it (a script, a workflow, a check, a skill the kit wrote, the core's machinery), and the update brings the kit's own fix, keep the kit's, even if the brain's worked. A brain that keeps its own fixes drifts from the kit: every drift is a clash in a later update, which costs the owner's usage and leaves a judgement call to whichever agent applies it, and Matt tries each update on a brain like the kit, so a drifted brain gets one nobody tried.
- **Unsure which a line is:** keep it if it's about the owner, their projects or their PC; let it go if it's about how the brain's machinery works. Say in the report what you let go.

1. `python3 skills/brain-spec/brain_update.py check` lists the updates this brain hasn't had, oldest first, each with its summary for the owner.
2. Take them one at a time, oldest first. Give the owner the summary in a few plain lines, and ask whether to go ahead.
   - **Go:** `python3 skills/brain-spec/brain_update.py apply <number>`. It merges the update's files into the brain, records the update, starts its report (`knowledge/systems/brain-updates/<number>-report.md`) with what it did, and prints the update's message. Where the brain and the update changed the same lines, the update's lines go in, except in Obsidian's settings files, where the owner's stay. It prints both sides of each such place: git takes the whole clashing stretch, so lines next to the change go too. Put back what's the owner's own, by the rule above, and leave out the brain's old fixes. Then do what the message says. It gives its reasons; follow it, unless it would lose the owner's own stuff, and then say so in the report.
   - **No:** `python3 skills/brain-spec/brain_update.py skip <number>`, so it doesn't come up again. The owner can still have it later: `apply <number>`.
   - **Not now:** leave it, and it comes up again at the next day's first session, and at the next tidy-up.
3. **Check the brain against the kit:** `python3 skills/brain-spec/brain_update.py compare`. It compares this brain with the exemplar, the kit's brain as it is at the update this brain is on (`https://github.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/tree/<the update's commit>/brain`; the script prints the link). Files that should match the kit (the scripts, workflows, the kit's own skills, the copied skills, the brain graph) are listed where they differ: keep the kit's copy, unless it holds the owner's own, by the rule above. Files the owner fills in (the core, the front door, the skills list and lists, the knowledge library) are checked for their shape, not their words: the kit's headings are there, each shelf's index has its markers, and every skill has one line in a topic list, under "The brain's own" if `lists/sources.md` has no line for it. Fix what it finds. Why: an update changes only the files it touches, so a brain that drifted elsewhere stays drifted; the exemplar is the whole setup the kit's agent should end with, and `finish` puts the comparison in the report, so Matt sees how close each brain is.
4. **Fill in the report.** The script wrote what it did; each section still in italics is yours: the owner's answer, each of the message's steps and what you did, each clash and what you kept and why, what broke or puzzled you (with the exact error), code you changed beyond the update and why, and how big a job it was. Matt reads it without seeing this brain, so write enough for him to tell what happened. Leave the owner's own projects, people and notes out: write "one of the owner's notes", not its name or what's in it.
5. `python3 skills/brain-spec/brain_update.py finish <number>` runs `library.py build`, `library.py check`, `check_links.py`, `test_library.py` and `compare`, and adds their results to the report. It won't finish while a section is still empty. Fix what the checks find, and run it again.
6. Commit each update as one commit, "Brain update <number> from AnIdeaLab: <what>", and push. Pushing sends the report to AnIdeaLab's inbox (the "Send brain update reports" workflow), so the kit gets better.
7. Tell the owner in a line: "Brain update from AnIdeaLab applied." Say more only if something's out of whack and they really need to know, and don't offer to undo it.

## Before you push
1. `git pull --rebase`.
2. `git add` your new files, then run `python3 skills/brain-spec/library.py build` and `python3 skills/brain-spec/library.py check`: no missing cards, bad fields or unknown tags. `git add` again after the build, so the indexes it rewrote go in your commit; one left out lands in a later commit and races the index Action's push of the same rebuild.
3. Run `python3 skills/brain-spec/check_links.py`: no broken links, nothing unlinked.
4. If you changed code, run it or its tests (`python3 skills/brain-spec/test_library.py` for the library).
5. Make small commits with plain messages saying what changed, and push to `main`. Never force-push.
