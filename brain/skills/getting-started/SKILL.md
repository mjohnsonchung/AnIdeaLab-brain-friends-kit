---
name: getting-started
description: "The first session in a new brain: welcome the owner, learn who they are and what they want the brain for, write their first notes, test the PC runner and record what their PC has, show them Obsidian, skills and where keys go, offer the weekly tidy-up, then mark the brain set up. Use when the core says the brain is new, or when the owner asks to redo their setup."
---

# Getting started
This brain was started on {KIT_DATE} from a starter kit made from Matt's brain. On the owner's Windows PC, the installer has already:
- made this private GitHub repo and put the brain in it;
- put a copy in `C:\AI-Brain-Link\<repo name>` and opened it in Obsidian, with the Obsidian Git plugin syncing it;
- set up the PC runner (a GitHub Actions self-hosted runner with the label `my-pc`, running as a Windows service under the owner's account), unless they skipped it.

This skill is the first session: about 15 minutes of the owner's time. Guide mode applies, so keep each message short, and ask everything you need in as few messages as you can.

## 1. Say hello, and what this is
In a few lines, in plain words:
- This repo is their second brain: plain notes that any AI agent can read. The core (`CLAUDE.md`) is the page every agent reads first. The skills library is how to do things (60 to start, and more whenever a job needs one). The knowledge library is what the brain knows about them and their projects, and it fills up as they use it.
- Obsidian on their PC shows the brain as a map, and the brain graph replays how it grew. Their edits there sync here, and agents' work syncs there.
- The PC runner lets agents run jobs on their PC whenever it's on.
- Guide mode: agents check a plan with them before bigger jobs, because their plan's usage runs out.

## 2. Ask, in one message
- Their first name.
- What they'd like the brain to help with: projects, a business, study, life admin, learning to build things. A few words is fine.
- Any business or project names, for the sign-off on messages agents send for them (the core explains it).
- Their Claude plan (Pro, Max or another), and whether agents should check a plan with them before every job or only bigger ones (guide mode's default is bigger ones).

## 3. Write it down
- `knowledge/people/<first-name>.md`: the owner's note, with a card ([brain spec](../brain-spec/SKILL.md#cards)), what they said in their words, their plan, and the date.
- In the core, change "A second brain" at the top to "<Name>'s second brain".
- One short note per project or business they named, `knowledge/ventures/<name>.md`: what it is and their goal, in their words. They grow into folders when work starts.
- Anything they said about how agents should work goes in a decision note, `knowledge/decisions/the-brain/<date>-<what>.md`.
- Run `python3 skills/brain-spec/library.py build`, then the checks in the brain spec's "Before you push", and commit and push.

## 4. Test the PC runner
Find the repo's owner and name from `git remote get-url origin` (the part after `github.com/` or `/git/`). Start the workflow `pc-run.yml` ("Run on my PC") on `main` with the GitHub tool's run-workflow method, with `workdir` left as it is and this `command`:
```
# Hello from the brain: what this PC has
$os = Get-CimInstance Win32_OperatingSystem
"PC: $env:COMPUTERNAME, $($os.Caption) $($os.Version), running as $(whoami)"
"CPU: $((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)"
"RAM: {0:N0} GB" -f ($os.TotalVisibleMemorySize / 1MB)
Get-CimInstance Win32_VideoController | ForEach-Object { "GPU: $($_.Name)" }
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { "Disk {0} {1:N0} GB free of {2:N0} GB" -f $_.DeviceID, ($_.FreeSpace / 1GB), ($_.Size / 1GB) }
foreach ($t in 'git','gh','python','py','node','winget','ffmpeg','nvidia-smi') { $c = Get-Command $t -ErrorAction SilentlyContinue; "{0}: {1}" -f $t, $(if ($c) { $c.Source } else { 'not found' }) }
```
Wait until the run shows as completed, then read its job log. Put what it found in [the PC's note](../../knowledge/systems/my-pc.md) under "What's on the PC", dated, and tell the owner in two lines, with a note that the live jobs window on their desktop showed it running.

- **It sat in "queued" for more than a few minutes:** the runner isn't up. Go through "If the runner stops picking up jobs" in the [my-pc skill](../my-pc/SKILL.md).
- **They skipped the runner** when installing: say they can set it up any time with one command, and give them the one in the my-pc skill's "Setting it up again".
- **No GitHub tool in this session** to start a workflow: say so, and that the owner can connect GitHub to Claude (claude.ai/code shows how) and start a new session; carry on with the rest.

## 5. Show them around, briefly
- **Obsidian:** Ctrl+G opens the map; the bookmarks panel has "Start here"; the brain icon on the left opens the brain graph (the first time, Ctrl+P, then "Reload app without saving"). [Obsidian setup](../../knowledge/systems/obsidian-setup.md) has the rest.
- **What waits on them:** the [tasks index](../../knowledge/tasks/README.md), "Waiting on the owner" at the top.
- **More skills:** they can ask "find me a skill for X" ([find-skills](../find-skills/SKILL.md)).
- **Keys** (API keys for services, later): never pasted into a chat. When a job needs one, the agent says the name to use, and the owner adds it on GitHub: the repo, then Settings, then Secrets and variables, then Actions, then New repository secret. The full how is in [keys and accounts](../../knowledge/systems/keys-and-accounts.md).
- **When a site is blocked** in a Claude session, the agent will say which; the owner can allow it in the session's environment settings (the environment menu in the session's title bar, then Edit, then Network access).

## 6. Offer the weekly tidy-up
The [brain-audit skill](../brain-audit/SKILL.md) tidies the brain once a week. It's a reminder, not a scheduled job: nothing runs, and none of their plan is used, until they say yes to it in a session. Ask if they'd like it. If yes, add its row to [routines](../../knowledge/systems/routines.md) as the comment in that note shows, starting from the next Saturday, and commit.

## 7. Finish
- Take the "A new brain" paragraph out of the core, so this skill doesn't run again.
- Run the checks, commit ("Set up <Name>'s brain") and push.
- Tell the owner in three lines what's set up, and suggest one small first job that fits what they said they want, sized the guide-mode way.
