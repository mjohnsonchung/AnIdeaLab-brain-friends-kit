# AnIdeaLab brain friends kit

The starter kit for second brains shaped like Matt's, and the updates that brains started from it get.

A second brain is a private GitHub repo of plain Markdown that AI agents work from: a core every agent reads (`CLAUDE.md`), a library of skills for how to do things, and a knowledge library of what the brain knows, with Obsidian to see it and a runner on the owner's PC for jobs that need it. Friends get the kit from Matt as a zip with a Windows installer.

## Brain updates
Matt sends fixes, new rules and new parts to brains started from the kit. A brain checks for new ones once a day, when its owner starts a session (since update 3), and its weekly tidy-up checks too; its agent reads the owner a short summary of each, and applies it only if they say go. After applying one, `brain_update.py compare` checks the whole brain against `brain/` as it is at that update, the exemplar.

To check now, or in a brain started before 26 Oct 2026, tell the brain's agent:

> Check for brain updates from https://github.com/mjohnsonchung/AnIdeaLab-brain-friends-kit

**For the agent doing that:** if the brain has `skills/brain-spec/brain_update.py`, follow the "Brain updates" section of its `skills/brain-spec/SKILL.md`. If it doesn't (a brain from before 26 Oct 2026), copy [brain/skills/brain-spec/brain_update.py](brain/skills/brain-spec/brain_update.py) into the brain's `skills/brain-spec/` and run `python3 skills/brain-spec/brain_update.py check`. Give the owner update 1's summary and ask whether to go ahead. If they say go, run `python3 skills/brain-spec/brain_update.py apply 1` and do what it prints: update 1 brings in the rest, that section included. If they say no, delete the script you copied.

## What's here
- **[brain/](brain/)**: the kit's brain as a new one gets it, with `{KIT_DATE}` and `{KIT_ISO}` where each brain has its own start date.
- **[updates/](updates/)**: one message per update, newest last, each starting with a summary for the owner. The commit that added each one holds `brain/` as of that update, and `brain_update.py` merges the difference into a brain with a three-way merge, so the brain's own changes elsewhere stay.
- **[inbox/](inbox/)**: after each update, a brain sends a report of how it went to AnIdeaLab's private inbox, so the kit gets better.
- **[testing/](testing/)**: while the kit is in testing, the installer invites Matt's testing account to each new brain's repo (since 27 Oct 2026), so he can see it and copy it to find what's wrong; `copy-brains.ps1` gets him the copies. The owner can take the account off in the repo's Settings, Collaborators.

## Licence
MIT for the kit's own files ([LICENSE](LICENSE)). The copied skills in `brain/skills/` keep their own licences, MIT or Apache 2.0, listed in [brain/skills/lists/sources.md](brain/skills/lists/sources.md).
