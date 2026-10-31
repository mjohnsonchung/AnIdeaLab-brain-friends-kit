---
name: upload-point
description: "The upload point: the small Upload point window on the owner's Windows PC, and My brain in File Explorer's Send to menu, where they drop files and folders for the brain, listed by path in knowledge/systems/upload-point.md on GitHub. How the owner uses it, how to set it up again, and how to sort what's waiting: files moved into the brain or onto the PC, code repos learned where they are, the list cleared. Use when the owner mentions the upload point or files they dropped, or the session start says something's waiting."
---

# The upload point
Matt, 31 Oct 2026, who asked for it: "a little script that opens up a upload point GUI app thing... for them to put files or folders or whatever they want into there, and then Claude can... index that stuff or work with those files", with the agent sorting them "into AI brain link or the repo or knowledge or skills or whatever", so "there'd be no need to keep copies of everything that was uploaded to that point". **Windows only for now; a Mac version is still to come** (Matt: "make a note that we have to do the Mac version in the future").

## What the owner does
1. **Drops things on it:** drags files or folders onto the "Upload point" window (its shortcut is on their desktop), or selects them in File Explorer, right-clicks, and picks Send to, then My brain (on Windows 11, Send to is under "Show more options"). With the window already open, Send to hands them to it.
2. **Tells you what to do with them,** in a session: "sort what I dropped", "make a note from the quote", "learn this project".

The window is plain on purpose (Matt, 1 Nov 2026: "Just make it a minimalist window... Something cheap, something reliable"): a list of what's waiting, each one's path, kind and size, and a line at the bottom saying how things stand: "Sent. Tell Claude what to do with them.", "Can't reach GitHub. It will try again.", or "Nothing waiting" once you've sorted everything. The Delete key, or a right-click's Remove, takes one off the list; the file stays where it is. The right-click also shows it in File Explorer or opens the list on GitHub. Send to doesn't open the window: it adds what was sent and says so in a small message box.

## How it works
- **Paths, not copies.** The window keeps only where each thing is, so a code repo or a big video isn't duplicated or pulled out of place. The one exception: anything on a USB stick or other removable drive is copied to `C:\AI-Brain-Link\_upload\<date>\` first, since the stick may be gone when you look, and the copy is what's listed.
- **The list is [knowledge/systems/upload-point.md](../../knowledge/systems/upload-point.md),** under "Waiting": one line per item, like `` - `C:\Users\Sam\Downloads\quote.pdf`: file, 2.3 MB, added 31 Oct 2026 14:02 ``, or "Nothing waiting." A folder's size says how many files it holds, and a folder with a `.git` in it is a `git repo`.
- **The window writes it through GitHub** (`gh api`, the contents of that one file), never through the brain's copy on the PC, so it can't clash with Obsidian Git or the owner's unsaved edits. It reads the list when it opens, sends a change a moment after the last one, and reads it again every 30 seconds and whenever it gets focus, so it sees what you've taken off. If the list changed in between, it reads it again and redoes its own change; offline, it keeps the change and tries again.
- **At session start,** `reminders.py` says how many things are waiting and since when.
- **The files here:** [upload-point.ps1](upload-point.ps1), the window (Windows PowerShell 5.1 and Windows Forms, nothing to install); [setup-upload-point.ps1](setup-upload-point.ps1), its shortcuts; [look.ps1](look.ps1), a look at what's waiting, run as a job on the PC.

## Setting it up
The installer runs the setup when it makes the brain. For a brain set up before the upload point, or when the shortcut has gone, give the owner this to paste into PowerShell (no admin rights needed, safe to run again):
```
powershell -ExecutionPolicy Bypass -File "C:\AI-Brain-Link\<repo name>\skills\upload-point\setup-upload-point.ps1"
```
It makes the "Upload point" shortcut on the desktop and "My brain" in Send to, both opening the window from this folder in the brain's copy, so a change to the window reaches the PC with Obsidian Git's next sync. The window finds the brain's repo from that copy's `origin`, and needs GitHub's `gh` signed in, which the installer did. If it isn't, the window says so, and a click on its last line copies the command that fixes it.

## Sorting what's waiting
1. **Read the list,** after `git pull --rebase`: the window writes it on GitHub, so your copy may be behind. Do what the owner asked. If they didn't say, sort everything into the brain as below, but first ask about anything unclear or personal: what a file is, whose it is, or where it should live.
2. **Look at them on the PC,** with one job ([my-pc](../my-pc/SKILL.md)): `pc-run.yml` with `checkout` on and the command `& "$env:GITHUB_WORKSPACE\skills\upload-point\look.ps1"`. It reads the list from the checkout and, for each path, says whether it's there, its kind and size, and a peek inside: a folder's top two levels, a text file's first lines, and for a code repo its remote, latest commits, what isn't committed, and the start of its README and `CLAUDE.md`. It changes nothing. If a path isn't there any more (a drive unplugged, a file moved), ask the owner.
3. **Files that belong in the brain,** up to about 25 MB each (documents, PDFs, spreadsheets, notes, the images a note is about), move into their place in the brain's copy on the PC, next to the note each becomes, and are pushed from there, so you can read them in your session. One job does them all; the brain's copy is `C:\AI-Brain-Link\<repo name>`, or the folder in [the PC's note](../../knowledge/systems/my-pc.md):
   ```
   # Upload point: the quote, into the brain
   $copy = 'C:\AI-Brain-Link\<repo name>'
   $moves = @'
   C:\Users\Sam\Downloads\quote.pdf | knowledge/areas/money/2026-10-31-quote.pdf
   '@ -split "`r?`n" | Where-Object { $_.Trim() }
   git -C $copy pull --rebase --autostash
   foreach ($line in $moves) {
     $from, $to = $line -split '\s*\|\s*', 2
     $dest = Join-Path $copy $to
     if (Test-Path -LiteralPath $dest) { "already there, not moved: $to"; continue }
     New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
     Move-Item -LiteralPath $from -Destination $dest
     if (Test-Path -LiteralPath $dest) { git -C $copy add -- $to; "moved: $to" } else { "NOT moved: $from" }
   }
   git -C $copy commit -m 'Upload point: the quote, into the brain'
   git -C $copy push
   ```
   The here-string keeps each path exactly as written, apostrophes and all, so copy them from the list; the `'@` stays at the start of its line. Then pull, read each file, and write its note beside it, saying the file next to it is the raw original. If the job's push failed, the commit is in the copy, and Obsidian Git pushes it at its next sync.
   - **Bigger files and media** (video, audio, big sets of images, zips, installers) stay on the PC, not in the repo: code lives in the repo, data lives on the PC ([my-pc](../my-pc/SKILL.md)). A job moves them to `C:\AI-Brain-Link\<Project>\...`, and a note in the brain says what's there and where.
   - **A folder that's a skill** (it has a `SKILL.md`) moves into `skills/<name>/`, with its line in a topic list ([the brain spec](../brain-spec/SKILL.md#a-skill)); one from somewhere else is recorded the way [find-skills](../find-skills/SKILL.md) says.
   - **A copy from a USB stick,** in `C:\AI-Brain-Link\_upload\<date>\`, is sorted like any other file; delete the date's folder once it's empty.
4. **Code repos are learned, never moved or copied.** Matt, 31 Oct 2026: "it should go through and index things that that have been learned in that in those projects. Go through their progress and decisions, do a quick look on their files, just like kind of index them, get a general picture of it, maybe some in-depth knowledge here and there, and then save all that to the brain. It's important, you know? So the agent is sufficiently prepared to work on those projects if asked." So read it where it is: through jobs on the PC (its README, `CLAUDE.md`, docs, `git log`, its folders and the files that matter), or from GitHub if it has a remote your session can reach. Then save a note for the project on the ventures shelf (a folder once it has several notes): what it is and its goal, where it lives on the PC and its remote, where it stands and what's next, the decisions its history shows (dated, with where each came from), how to build, run and test it, a map of its code, and in-depth notes on the parts that matter.
5. **Move, don't copy** (Matt, 31 Oct 2026: "Sorting should move files, not copy them"), so nothing's kept twice. But leave a thing where it is when moving it would break something: a file inside a code repo or an app's folder, or a folder something syncs. Its note says where it is.
6. **Take what's done off the list:** delete its line (leave "Nothing waiting." when none are left), commit and push, and the window shows "Your brain has them". If your push clashes on this note, the window added something meanwhile: keep its new lines, and drop only the ones you sorted. Tell the owner in a few lines where things went.
