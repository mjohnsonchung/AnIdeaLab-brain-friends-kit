---
name: windows-powershell
description: "The traps in Windows PowerShell 5.1, the PowerShell every Windows PC has, that keep breaking scripts and commands written for the owner's PC or a my-pc runner job: double quotes stripped on the way to programs like gh, git and python, \"$name:\" parse errors, a program's stderr turned into errors, encodings and byte-order marks, one-item lists, one-command scripts run with irm | iex, the runner's PATH, and how to check a script before handing it over. Read before writing any PowerShell."
---

# Windows PowerShell 5.1

From Matt's brain, which this one was started from: these traps kept breaking agents' scripts there, so on 27 Oct 2026 he asked for a skill with them all in one place ("it keeps tripping you up. I've seen it happen multiple times"). Every Windows PC has Windows PowerShell 5.1 (`powershell.exe`), and that's what runs the commands the owner pastes, the `my-pc` runner's jobs (its default shell) and this brain's own scripts. PowerShell 7 (`pwsh`) usually isn't installed, so write for 5.1. No provider's skill covers these traps (checked 27 Oct 2026: GitHub's awesome-copilot `powershell.instructions.md` is about cmdlet style, and the community PowerShell skills say nothing on quoting).

## Before you hand one over
1. **Read it against the traps below,** the quotes first. Two greps catch the commonest: `grep -nP '[^\x00-\x7F]' script.ps1` (anything not plain ASCII) and `grep -nE '"[^"]*\$[A-Za-z_]+:' script.ps1` (a `$name:` inside double quotes).
2. **Parse it in Windows PowerShell 5.1,** with a job on the owner's PC through the `my-pc` runner ([the my-pc skill](../my-pc/SKILL.md)):
   ```
   $t = $null; $e = $null
   [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
   if ($e.Count) { $e | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" } } else { 'OK' }
   ```
   A parse catches syntax and `$name:`, not stripped quotes, which only show when the program runs. A command that passes quotes to a program needs one real run.
3. **Fetch a just-pushed script by its commit,** not `main`: `raw.githubusercontent.com` serves a file up to 5 minutes old after a push, so a parse can check the old one. Hand the owner the `main` link once those minutes are up, or the commit link.

## Double quotes don't reach programs
Windows PowerShell 5.1 passes arguments to programs (`gh`, `git`, `python`, `winget`, anything that's an `.exe`) the old way, which Microsoft's docs call "Legacy": it doesn't escape double quotes inside an argument, so the program never gets them ([about_Parsing](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_parsing), "Passing arguments that contain quote characters"; PowerShell 7.3 changed it, and `$PSNativeCommandArgumentPassing` doesn't exist in 5.1). Cmdlets aren't affected; only programs.

So `gh api user/repository_invitations --jq '.[] | "\(.id) \(.repository.full_name)"'` reaches `gh` as `.[] | \(.id) \(.repository.full_name)`, which it splits into several arguments: "accepts 1 arg(s), received 6". The same goes for `join(" | ")`, `// ""`, and JSON or a quoted string in any argument. It broke three jobs in Matt's brain in two days. Fixes, best first:
- **Write it with no double quotes inside.** For jq: build a list and join it with a tab, `[(.id|tostring), .repository.full_name] | @tsv`, then split in PowerShell (`$id, $name = $line -split "`t"`); `// empty` instead of `// ""`; or one call per field (`--jq .permission`).
- **Pass the data through a file or stdin,** not an argument: `gh api --input body.json`, `-F field=@file.txt`, `python script.py` rather than `python -c "..."`.
- **Escape each inner quote as `\"`** (`'.[] | \"\(.id)\"'`). That works in 5.1 but breaks in PowerShell 7.3 and later, which escapes for you, so use it only in a script that's for 5.1 alone, and say so in a comment.
- **The stop-parsing token, `--%`,** passes the rest of the line as written (`icacls X:\VMS --% /grant Dom\HVAdmin:(CI)(OI)F`), but no PowerShell variables after it, only `%NAME%` environment variables, and only to the end of the line.

**An empty string isn't passed at all:** `git config x ''` gives git one argument too few. Avoid needing one; `git -c credential.helper= ...` (an `=` with nothing after it) works.

## Strings and variables
- **`"$name: text"` fails the whole script before it starts:** PowerShell reads `$name:` as a drive-qualified variable, like `$env:Path`. Write `"${name}: text"` or `"$name, text"`.
- **Variable names ignore case:** `$t` and `$T` are the same variable.
- **The escape character is the backtick:** `` "`n" `` is a new line, `` "`t" `` a tab, `` "`$" `` a dollar sign. A backslash is just a character to PowerShell.
- **In a double-quoted string, `$(...)` runs code:** `"Signed in as $(gh api user --jq .login)"`. Single quotes are literal.

## Errors and exit codes
- **With `$ErrorActionPreference = 'Stop'`, anything a program writes to stderr is an error,** and git, gh, winget and tools like COLMAP write their progress there. Run programs with `'Continue'` (the kit installer's `Native { ... }` wrapper does it for one call) and check `$LASTEXITCODE` after each.
- **`try`/`catch` doesn't see a program fail;** only `$LASTEXITCODE` does.
- **`Set-ExecutionPolicy` throws "Security error."** whenever a narrower scope overrides it, which a script started with `-ExecutionPolicy Bypass` always is, and `-ErrorAction` can't stop it: catch it and check `Get-ExecutionPolicy -List` instead.
- **With `'Continue'`, a failed step doesn't stop the script:** a `Move-Item` on a file open in a player fails and the next line runs anyway. Check the result (`if (-not (Test-Path $dest)) { exit 1 }`) before anything writes over the source, and say done only once the thing works.

## Files and encodings
- **Keep a `.ps1` plain ASCII.** 5.1 reads a script without a byte-order mark as Windows-1252, so a curly quote, a long dash or an ellipsis turns into junk, sometimes into a parse error.
- **`Out-File`, `Tee-Object` and `>` write UTF-16,** so the runner's logs are UTF-16.
- **`Set-Content -Encoding UTF8` adds a byte-order mark,** which Python's `json` and Obsidian refuse. Write JSON and anything another program reads with `[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))`.
- **Piping a string to a program adds a new line at the end,** so a token piped to `gh secret set` would carry one: pass it with `--body`.

## Lists and JSON
- **A function or command that returns one item hands back the item, not a list,** so `$x[0]` gives its first letter and `.Count` misleads: wrap the call in `@(...)`.
- **`ConvertFrom-Json` sends a JSON list down the pipeline as one item,** so `| Where-Object` and `-contains` see one thing: write `@(($json | ConvertFrom-Json) | ForEach-Object { $_ })`, or assign it to a variable and `foreach` over that.
- **`[math]::Max(0, $bytes)` picks the whole-number version from its first argument** and fails past 2 GB: write `[math]::Max([double]0, [double]$bytes)`.
- **Setting an environment variable to `''` deletes it,** so `GIT_CONFIG_*` can't carry an empty value: put it on git's command line.

## Commands for the owner to paste
- **A script run with `irm <raw link> | iex`:** wrap the whole of it in `& { ... }` and stop with `return`, never `exit`, which closes the window. `iex` can't pass arguments to a `param()` block, so read settings from `$env:` variables (or run it as `& ([scriptblock]::Create((irm <raw link>))) -Name value`). The script policy doesn't apply to `iex`. Inside, set TLS 1.2 before downloading: `[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072`.
- **After `winget install`,** the same window doesn't see the new program until you reload the PATH: `$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')`. If it still isn't there, tell them to open PowerShell again and paste the same command.
- **`gh auth login --web` signs in whatever account the browser is on.** When it must be one account, open the sign-in in a private window (`$env:GH_BROWSER = 'cmd /c start msedge --inprivate'` for that call), check `gh api user --jq .login` after, and end with `gh auth switch --user <main account>`: `gh` is git's sign-in too, as its active account, so leaving it on another account breaks pushes (Obsidian's syncing included).
- **Edge isn't on the PATH,** but `Start-Process msedge` finds it through Windows' App Paths.
- **Say little.** Print "Success", or one line saying what went wrong and what to do; no step headings (Matt, 27 Oct 2026, on a script for friends: "just have the word success").

## Runner jobs on the owner's PC
- **The runner's service sees the PATH from when it started,** so a program winget installed since isn't found: start the job with the PATH reload above, or restart the service.
- **Writing the job from a cloud session:** a bash heredoc without quotes (`<<EOF`) swallows every `$name` and runs backticks there and then. Use `<<'EOF'`, or a file. If you need bash to fill something in (a commit hash, say), use `<<EOF` and escape every PowerShell `$` as `\$`, then read the start of the generated script before starting the job.
- More on jobs (the queue, logs, files the runner makes belonging to Administrators): the [my-pc skill](../my-pc/SKILL.md).
