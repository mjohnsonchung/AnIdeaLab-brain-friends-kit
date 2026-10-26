# Brain update 1 from AnIdeaLab: catch-up

Sent 26 Oct 2026. It brings a brain started from the 22 Oct 2026 kit up to today's kit, and adds brain updates themselves. A brain started from a later kit already has most of it, and its files merge as no change.

## Summary for the owner
A catch-up to today's starter kit:
- Outside messages sign off "Assistant built by AnIdeaLab.com", with no business name, and never on replies to you.
- Three new defaults you can change: no Claude artifacts, best guess with light checks, and one agent at a time.
- Fixes from the first real install: the PC runner's setup, a workflow to delete branches, and a few scripts.
- Brain updates: from now on your brain checks for them in its weekly tidy-up and asks you before applying one, like this. After each one it sends a short report of how it went to AnIdeaLab, to make the kit better.
- Two copied skills brought up to date.

Nothing runs on your PC.

## What changed, and why
- **The sign-off** is now "Assistant built by AnIdeaLab.com" on every agent message to the outside, for the owner or any of their projects, with no business name. Replies to the owner never carry it. Cold outreach drops the link: "Assistant built by AnIdeaLab". It replaces "AI assistant for {business}, made with love by AnIdeaLab.com" (Matt, 23 and 26 Oct 2026). In the core and the starting rules.
- **Three new defaults** in the core and the starting rules, which the owner can change like any other:
  - **No Claude artifacts:** whatever the brain saves or points to lives where any agent can get it, never only in one AI app's page (24 Oct).
  - **Best guess, light checks:** a job in one pass and a fix-up pass, with only the checks it needs; the owner checks it when they try it (24 Oct).
  - **One agent at a time:** never agents side by side, to save the owner's usage (24 Oct).
- **Brain updates:** this brain now checks for updates in its weekly tidy-up, reads the owner each one's summary, and applies it only if they say go (`brain_update.py`, the brain spec's "Brain updates" section, `knowledge/systems/brain-updates/`). It sends a report of each to AnIdeaLab's inbox through a new workflow, "Send brain update reports", which runs on GitHub's machines.
- **Fixes from the first real install** (Karl's, 22 Oct):
  - the runner setup (`skills/my-pc/setup-runner.ps1`) no longer stops at the script-policy step, puts Git on the PC's PATH, and says it's done only once GitHub sees the runner online;
  - the setup check lists the script policy at every scope, checks Git is on the PATH, and with `-Send` puts its report in the repo;
  - a new workflow, "Delete branches" (`delete-branch.yml`), deletes branches a cloud session can't, on GitHub's machines;
  - the index workflow (`library.yml`) rebuilds and tries again when its push loses a race, instead of going red;
  - `check_links.py` counts new files that aren't added yet;
  - the my-pc skill has the runner lessons: tools installed after the runner, winget and FFmpeg in a job, and more.
- **Copied skills** brought up to date from their sources: impeccable and superpowers-brainstorming.

## What to do beyond the files
1. Look for the old sign-off anywhere else in the brain, such as notes or skills of the owner's own that quote it, and change it to the new line.
2. Nothing needs to run on the PC for this update. The runner fixes only matter when setting a runner up; if this brain's runner has trouble, the my-pc skill has them.
3. If this brain already fixed something here its own way (a runner fix, its own diagnose script), keep what works and say what you kept in the report.
