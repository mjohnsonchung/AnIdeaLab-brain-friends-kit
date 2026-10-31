---
name: my-pc
description: "How to run commands and jobs on the owner's Windows PC through the my-pc GitHub Actions runner: starting a run, reading its log, getting files to and from the PC, deleting leftover branches, the PC's quirks, keeping it safe, where files go, setting the runner up again, and what to do when it stops. Use whenever a job needs the owner's PC: its GPU, its installed apps, their files, or anything a cloud session can't do."
---

# Running jobs on the owner's PC
The owner's PC is a GitHub Actions self-hosted runner for this brain's repo, with the label `my-pc` (and `gpu` if it has an NVIDIA card). It runs as a Windows service under the owner's own account, so a job can reach the whole PC and their apps. It starts with Windows, so the owner doesn't need to be logged in, but the PC has to be on and awake. It's set up the same way as the runner on Matt's PC, which runs his GPU jobs, installs and fixes. What this PC has is in [the PC's note](../../knowledge/systems/my-pc.md).

## Running a command
Start the workflow [`pc-run.yml`](../../.github/workflows/pc-run.yml) ("Run on my PC") on `main` with the GitHub tool's run-workflow method. Inputs:
- `command`: the command or a whole script. Start it with a `# comment` saying what it's for: the run's name in the Actions list starts with it.
- `shell`: `powershell` (Windows PowerShell 5.1, the default), `cmd` or `bash` (Git Bash).
- `workdir`: where it runs. Default `C:\AI-Brain-Link`.
- `timeout`: minutes, default 60, up to 4320 (three days).
- `checkout`: true to get this repo at `$env:GITHUB_WORKSPACE` first, so the command can run the repo's scripts. Set it whenever the command calls them: without it, the job quietly runs whatever older copy the last checked-out job left in `_runner\_work`, with no error (Matt's PC, 24 Oct 2026).
- `artifact`: a file, folder or wildcard on the PC to attach to the run for 3 days, so you can look at it (stills, a small file). The GitHub tool's artifact download gives a short-lived link.

Then find your run in the workflow's run list, wait until it shows as completed, and read the job log. A copy of each run's output stays on the PC in `C:\AI-Brain-Link\_logs\pc-run-<run id>.log`.

From a cloud session, the `gh` command line usually works through the session's proxy even when `gh auth status` calls the token invalid, so try the command itself (`gh run view <id> --json status,conclusion`, `gh run view <id> --log`); a loop on `gh run view` in a background shell says when a job ends. If `gh` is refused, the GitHub tool's actions methods do the same: list the run's jobs for the job's id, then read that job's log (Matt's PC, 22 to 24 Oct 2026).

**How the queue and logs behave** (learnt on Matt's PC, 17 Oct 2026):
- Jobs run one at a time, in order. Don't add a concurrency group to the workflow: GitHub keeps only one waiting run per group and cancels the others.
- A job's log can only be read once it has finished (asking earlier gets a 404). For a long job, check the run list for "completed", and have the job write progress to a file on the PC.
- If the run-workflow call times out, the run may still have been queued. Check the run list before trying again.
- Jobs check out `main` when they start, so push a script before starting the job that runs it.

## Getting files to and from the PC
- **From the PC:** the `artifact` input.
- **To the PC,** for a file the owner gave a cloud session: push it alone to a temporary branch (`git hash-object -w`, `git mktree`, `git commit-tree`, then push to `refs/heads/transfer/<name>`), fetch it in the job with `git fetch --depth 1 origin transfer/<name>` and `git archive -o "$env:RUNNER_TEMP\x.zip" FETCH_HEAD`, then `Expand-Archive`. Then delete the branch with the workflow [`delete-branch.yml`](../../.github/workflows/delete-branch.yml) ("Delete branches", input `branches`), since a session's git proxy refuses branch deletes. It keeps `main` clean (Matt's PC, 21 Oct 2026).
- **Other leftover branches,** like a session's own `claude/...` branch once its work is on `main`, go the same way: the workflow takes several names at once, never deletes `main`, and logs each branch's last commit so it can be pushed back (a friend's brain, 22 Oct 2026).

## Things to know
- **No pop-ups.** Nobody is there to click. Use installers' silent switches (`winget install --silent`, `/S`, `/quiet`). Anything that needs an admin (UAC) prompt hangs until the timeout: give the owner a command to paste instead, and say it will ask for admin rights.
- **Files the runner makes belong to Administrators,** because the service runs with the owner's full admin rights. The owner's own git (Obsidian's Git plugin, for one) then refuses a repo the runner made or copied ("dubious ownership"). Fix it from a job: `icacls <folder> /setowner "<what whoami prints>" /T /C`.
- **PowerShell 5.1 quirks** (double quotes stripped on the way to programs, `"$p: text"`, stderr as errors, encodings, one-item lists, the runner's PATH): the [windows-powershell skill](../windows-powershell/SKILL.md). Read it before writing a job.
- **The script policy is `RemoteSigned`** for the owner's account (the installer set it); the runner's wrapper needs it. If it ever changes back, give the owner the command: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force`. It says "Security error." when a narrower scope overrides it, though it saved the setting, so check with `Get-ExecutionPolicy -List` rather than trusting the error (a friend's PC, 22 Oct 2026).
- **A tool installed after the runner started isn't found by jobs** until the runner's service restarts: jobs get the PATH the service started with, and on Windows the runner never reads its `.path` file. `Restart-Service` inside a job kills the job, so the job leaves a one-off task that restarts it as SYSTEM two minutes later; start the next job once that's passed, or the restart cuts it off (a friend's PC, 22 Oct 2026):
  ```
  $at = (Get-Date).AddMinutes(2).ToString('HH:mm')
  schtasks /create /tn "Restart the runner" /tr "powershell -NoProfile -Command Restart-Service actions.runner.*" /sc once /st $at /ru SYSTEM /f
  ```
- **`winget` can't install a zip package from a job** (FFmpeg's `Gyan.FFmpeg`: "Failed to extract the contents of the archive"): it unzips through the Windows shell, which a service doesn't have. Installer packages, like Python and Node, are fine. For a zip, take its `Installer Url` and `Installer SHA256` from `winget show <id>`, download it with `curl.exe -L`, check `(Get-FileHash <zip>).Hash` against it, unzip it with `tar.exe -xf <zip> -C C:\AI-Brain-Link\Tools`, add its `bin` folder to the PC's PATH (`[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';<bin folder>', 'Machine')`), and restart the runner as above (a friend's PC, 22 Oct 2026).
- **Code lives in the repo, data lives on the PC.** Scripts stay in the repo (a skill's folder); a job checks the repo out and reads and writes its data under `C:\AI-Brain-Link\<Project>\<Stage>\<job>\`. Big data can go on another drive if the PC has one ([the PC's note](../../knowledge/systems/my-pc.md) lists them).
- **Workflows for the PC** use `runs-on: [self-hosted, my-pc]` (add `gpu` if it needs the GPU). Everything else keeps `ubuntu-latest`, so the index workflow stays on GitHub's machines.
- **Safety.** A runner job can do anything the owner can on their PC. PC workflows are started only by `workflow_dispatch` or a schedule, never by a pull request. The repo must stay private, and nobody else gets write access while the runner is attached. Never put a key in a `command`: commands show in the Actions list and the logs; add it as a secret and pass it in the workflow's `env` (the core's secrets gate). Deleting the owner's files needs their say first, and goes to the Recycle Bin where possible.

## Seeing what runs
The desktop shortcut "AI Brain Link - live jobs" opens [`watch-jobs.ps1`](watch-jobs.ps1) (installed in `C:\AI-Brain-Link\Tools\`). It follows the newest log, showing each command and its output live. Without the shortcut, the owner pastes `powershell -NoExit -ExecutionPolicy Bypass -File C:\AI-Brain-Link\Tools\watch-jobs.ps1` into PowerShell. The full history is the repo's Actions tab, under "Run on my PC".

## Setting it up again
[`setup-runner.ps1`](setup-runner.ps1) sets the runner up, or again from scratch: it puts Git on the PC's PATH and finishes Git's first-run setup, downloads GitHub's runner, registers it with this repo (it removes an old registration first), installs it as a service under the owner's account, restarts it if it ever stops, sets the script policy, adds the live jobs shortcut, and offers to keep the PC awake while plugged in. It says it's done only once GitHub sees the runner online. Give the owner this command to paste into PowerShell (it asks for admin rights, then their Windows password, not their PIN):
```
powershell -ExecutionPolicy Bypass -File "C:\AI-Brain-Link\<repo name>\skills\my-pc\setup-runner.ps1"
```
It needs GitHub's `gh` tool signed in, which the installer did. `C:\AI-Brain-Link\<repo name>` is where the installer puts the brain's copy; a brain cloned somewhere else has its folder in [the PC's note](../../knowledge/systems/my-pc.md), so use that in this command and the ones below.

## If the runner stops picking up jobs
1. **Runs sit in "queued":** the PC is off or asleep, or the service has stopped. Ask the owner to check the PC is on, then give them this to paste into PowerShell: `Get-Service actions.runner.* | Restart-Service` (it asks for admin rights; run PowerShell as administrator if it says access is denied).
2. **The runner's own logs** are in `C:\AI-Brain-Link\_runner\_diag\`.
3. **Still nothing:** have the owner run `setup-runner.ps1` again (above). A wrong Windows password is the usual cause of a service that won't start: it needs the password they'd type at the sign-in screen (for a Microsoft account, that account's password), never the PIN.
4. **After the service ran under another account,** delete the runner's checkout folder in `C:\AI-Brain-Link\_runner\_work\` once, or git refuses it ("dubious ownership").
5. **A runner set up by hand** from GitHub's "New self-hosted runner" page never picks up jobs: that page's `config.cmd` line has no `--labels my-pc`. Run `setup-runner.ps1`, which adds the labels (a friend's first brain, 21 Oct 2026).
6. **To see the PC's state while the runner is down,** give the owner the setup check with `-Send`. It changes nothing, and saves its report in this repo as `knowledge/systems/setup-check.md`, so you can pull and read it:
   ```
   powershell -ExecutionPolicy Bypass -File "C:\AI-Brain-Link\<repo name>\skills\my-pc\check-setup.ps1" -Send
   ```
   It checks the brain it's in, even when Obsidian lists an older vault first (a friend's PC, 31 Oct 2026, before it did).
7. **No runner at all, after the installer:** the setup stopped before its runner step. The installer keeps each step in `C:\AI-Brain-Link\_logs\install.log`, and the setup check's "The installer's last run" part says where it stopped. Give the owner the `setup-runner.ps1` command (above) to paste.
