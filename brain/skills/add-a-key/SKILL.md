---
name: add-a-key
description: "How to get a key or token that only the owner can make (a service's API key, a GitHub token) into the one place it lives with a single command they paste: the page that makes it opened for them, the key read in hidden and handed straight to this brain's GitHub Actions secrets or a site host's secret settings, then a check that it works. Use whenever a job needs a new key."
---

# Getting a key from the owner in one command
From Matt's brain, where it started on 26 Oct 2026, after a key went in this way: "That was a very streamlined way of doing it... It might not be just for Vercel, just in general, that was quite useful. Being able to add a GitHub token that way. And whatever else, wherever else." He brought it to this kit on 31 Oct 2026 ([the starting rules](../../knowledge/decisions/the-brain/{KIT_ISO}-starting-rules.md)).

The secrets gate in the core still holds: a key never goes in a file, a commit or a message, and never in a chat, and the owner is the one who adds it. This keeps to that and costs them one paste. It's the "give the owner a command" default for keys: no clicking through GitHub's settings.

## A service's API key for the brain's jobs
[add-api-keys.ps1](add-api-keys.ps1), beside this skill, does it for each service named. Give the owner this to paste into PowerShell, with the services they need:
```
powershell -ExecutionPolicy Bypass -File "C:\AI-Brain-Link\<repo name>\skills\add-a-key\add-api-keys.ps1" -Services openai
```
`C:\AI-Brain-Link\<repo name>` is where the installer put the brain's copy; a brain cloned somewhere else has its folder in [the PC's note](../../knowledge/systems/my-pc.md). For each service, the script opens the page that makes the key and says what to press, reads the key hidden, checks it by its start and with the service (only an answer that means a bad key stops it), and saves it in the GitHub Actions secrets of the repo that folder syncs with, under the service's usual name (`OPENAI_API_KEY`). It signs `gh` in first if it has to, and it's safe to run again: a key already there is replaced.
- **The services it knows:** `elevenlabs`, `openai` and `gemini`, comma-separated for more than one. Matt keeps the list in his brain, and new ones come with brain updates. For another service, use the same shape (below), or add it to the script's `$known` table: its name, the secret's name, how its keys start, the page that makes them, what to press there, and a call that checks a key.
- **If PowerShell says the file isn't there,** the owner's copy hasn't caught up with GitHub (Obsidian Git syncs it while Obsidian is open): have them open Obsidian for a minute, or give them `git -C "C:\AI-Brain-Link\<repo name>" pull`.
- **Not through the PC runner:** the sign-ins and the key's page need the owner's browser, and a job can't read what they type.
- Then add the key's row to [keys and accounts](../../knowledge/systems/keys-and-accounts.md): its name, the service, the date and what it's for, never the value. Jobs that run through GitHub Actions, the PC runner's included, can use it from then on.

## Any other key, the same way
When a job needs a key the script doesn't cover (a GitHub token, a site's key, a service without a row), write a short script that does everything except what only a person can do, in this order:
1. **Install what it needs** if it's missing (`winget install -e --id GitHub.cli` and the like), and sign in to the service the first time, with its own tool's browser sign-in.
2. **Open the page that makes the key, pre-filled** where it can be (below), with `Start-Process <url>`, and print the one or two choices the link can't make, plainly: "Under Repository access, choose Only select repositories and pick X."
3. **Read the key hidden:** `Read-Host -AsSecureString`, turned into text only in memory, trimmed, and checked by how it starts (`github_pat_` for a fine-grained GitHub token), so a wrong paste stops with a plain message.
4. **Hand it straight to where it lives** (below), then clear the variable. Never a file, the clipboard, a log, the screen or chat.
5. **Check it works** without printing it: the service answers, a test call goes through. Then say what to tell the agent.
6. **Make it safe to run again:** it replaces an old key rather than stopping at "already exists", so a failed try is fixed by pasting the same command again.

Save it in the brain beside the job it's for, push it, and give the owner the same kind of command, with the path in their copy. Write it for Windows PowerShell 5.1, in plain ASCII, and call `npx.cmd` and the like, not `npx`, so the script policy can't block them; its traps are in the [windows-powershell skill](../windows-powershell/SKILL.md). Before handing it over, parse it on the owner's PC with a job through the runner (`[Management.Automation.Language.Parser]::ParseFile`, the [my-pc skill](../my-pc/SKILL.md)).

## Pre-filled pages
- **A GitHub fine-grained token:** `https://github.com/settings/personal-access-tokens/new?name=...&description=...&expires_in=none&contents=write`. From GitHub's docs ("Managing your personal access tokens", checked 26 Oct 2026), every parameter is optional:
  - `name`, up to 40 characters, and `description`, up to 1,024; URL-encoded, with `+` for spaces;
  - `target_name`: the owner, a user or an organisation; the signed-in account if it's left out;
  - `expires_in`: 1 to 366 days, or `none`; 30 days if it's left out;
  - any permission, by its name, set to `read`, `write` or `admin`, joined with `&`: `contents=write&pull_requests=read`. `write` includes `read`.
  - **Which repositories it reaches can't be pre-filled,** so the script says which one to pick. Give a token the fewest repos and permissions it needs.
- **Another service:** look for a documented pre-fill link before relying on one. Without one, open the exact page for making the key and say which buttons to press.

## Where it goes
- **A key for the brain's own jobs** goes in this repo's GitHub Actions secrets: `gh secret set NAME --repo <owner>/<repo> --body $key`. `gh` is a real program, so the key reaches GitHub exactly.
- **A live site's runtime key** goes in its host's secret settings, through the host's own tool, but never with the key on a command line: on Windows, `npx.cmd`, `vercel.cmd` and the like run through cmd.exe, which changes `^ & | < > %` in an argument without a word (a password reached a site changed that way in Matt's brain, 30 Oct 2026). On Vercel, use [set-vercel-env.mjs](set-vercel-env.mjs), beside this skill, with the key in an environment variable: `$env:ENV_VALUE = $key; node set-vercel-env.mjs <project> <NAME>`, then `Remove-Item Env:ENV_VALUE`. Then deploy again so the site picks it up.
- **A key a Claude session needs directly** (rare: jobs use the Actions secret): the owner adds it to the session's environment settings with the same name, as [keys and accounts](../../knowledge/systems/keys-and-accounts.md) says.

## When it goes wrong
- **When a step says it failed,** check what it changed before running it again: a set-up step in Matt's brain set a key, then failed while tidying up and said the key hadn't gone in.
- **A token for a second GitHub account:** `gh auth login --web` signs in whatever account the browser is on, and git on the PC follows `gh`. Open the sign-in in a private window (`$env:GH_BROWSER = 'cmd /c start msedge --inprivate'`), check whose token it got with `gh api user`, and end with `gh auth switch` back to the owner's main account.
