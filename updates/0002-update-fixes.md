# Brain update 2 from AnIdeaLab: fixes from the first updates

Sent 26 Oct 2026. Fixes from the first two reports on update 1, from two friends' brains. It changes how brain updates handle a clash, and one check.

## Summary for the owner
Small fixes from the first brains to get update 1:
- When an update and your brain changed the same lines, your agent now sees both sides, so nothing of yours goes missing unseen.
- Your Obsidian settings, like the brain graph's speed, stay as you set them when an update changes them too.
- The link check no longer counts copied skills as the brain's own.

Nothing runs on your PC.

## What changed, and why
- **Clashes show both sides** (`skills/brain-spec/brain_update.py`). Where the brain and an update changed the same lines, the update's lines go in, as before. But git takes the whole clashing stretch, so in update 1 a paragraph of a brain's own, sitting next to a sentence the update changed, went too, and only an agent reading the diff saw it (both reports). Now `apply` prints the brain's side and the update's side of each clash, and the brain spec's "Brain updates" section says to put back what the update didn't mean to replace.
- **Obsidian's settings stay the owner's** (`brain_update.py`). In `.obsidian/` settings files (the JSON ones, but not a plugin's `manifest.json`), where both changed the same lines, the brain's own lines stay. In update 1 a brain's graph speed, set by its owner, was put back to the kit's.
- **The brain-updates note gets today's date** when an update is applied or skipped (`brain_update.py`). It kept the brain's start date.
- **The link check** (`skills/brain-spec/check_links.py`): a list of skills linked under "Copied skills" stays a list of copied skills, even when "The brain's own" links it too, say in a line on where its own skills came from. In one brain that line made every skill in the list count as its own, and the check reported 32 broken links and 157 unlinked notes inside copied skills.
- **The brain's copy on the PC** (`skills/my-pc/SKILL.md`): the commands that name `C:\AI-Brain-Link\<repo name>` now say a brain cloned somewhere else uses the folder in its PC note.

## What to do beyond the files
1. If update 1 dropped lines of this brain's own in a clash and they weren't put back then, put them back now. Both reports so far had already done it.
2. If this brain worked around the link check its own way after update 1 (one pointed a line in its skills list at the "Copied skills" section instead of the list), it can stay as it is: the check now gives the same answer either way.
3. Nothing needs to run on the PC.
