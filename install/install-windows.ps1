# Sets up your own second brain on this Windows PC, from Matt's starter kit. It installs Git, GitHub's
# command line (gh) and Obsidian if they're missing, signs you in to GitHub, makes your brain's private
# repo (inviting Matt's testing account to it, to test the kit while it's in testing) and puts the brain
# in it, puts your copy in C:\AI-Brain-Link and opens it in Obsidian with syncing on, adds the upload
# point if the brain has one, then sets up the PC runner, so AI agents can run jobs on this PC. Safe to
# run again: it skips what's already done.
# Where the brain comes from, first found:
# - -Brain <a brain folder or a .bundle file>;
# - a .bundle file next to this script (the zip make_starter.py makes);
# - the kit repo's brain\ folder beside this script's install\ folder. install.ps1, at the kit repo's
#   root, downloads the repo as a zip and runs this from it, with -Zip <that zip>, which says which of
#   the brain's files are programs (a mark Windows' files don't keep).
# START-HERE.txt has the one command that runs it. Made by the brain-starter skill in Matt's brain.
# Works in Windows PowerShell 5.1.
param([string]$Brain = '', [string]$Zip = '')
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$check = $env:BRAIN_STARTER_CHECK # a test folder: nothing is installed, and GitHub and Obsidian aren't touched
$root = if ($check) { $check } else { 'C:\AI-Brain-Link' }
$noBom = New-Object Text.UTF8Encoding $false # Obsidian can't read JSON that starts with a byte-order mark

function Say($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function Ask($q, $default) {
  if ($check) { return $default }
  $a = Read-Host "$q [$default]"
  if ([string]::IsNullOrWhiteSpace($a)) { return $default }
  return $a.Trim()
}
function Yes($q) { return (Ask $q 'Y') -match '^\s*[Yy]' }
# Runs a program without Windows PowerShell 5.1 turning what it writes to stderr into errors.
function Native([scriptblock]$Block) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & $Block } finally { $ErrorActionPreference = $old }
}
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }
function Find-First($paths) { foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $p } }; return $null }
function Find-Git {
  $c = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return Find-First @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
}
function Find-Gh {
  $c = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return Find-First @("$env:ProgramFiles\GitHub CLI\gh.exe", "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe")
}
function Find-Obsidian { return Find-First @("$env:LOCALAPPDATA\Programs\Obsidian\Obsidian.exe", "$env:LOCALAPPDATA\Obsidian\Obsidian.exe", "$env:ProgramFiles\Obsidian\Obsidian.exe") }
function Install-App($id, $what) {
  Say "Installing $what (Windows may ask you to allow it)..."
  Native { winget install --id $id -e --silent --accept-source-agreements --accept-package-agreements } | Out-Host
  Refresh-Path
}
# A path inside a folder, one name at a time, so it works with either slash.
function Inside($base) { foreach ($p in $args) { $base = Join-Path $base $p }; return $base }
# The brain's files the kit's zip marks as programs, as paths inside brain\. GitHub's zip keeps each
# file's Unix mode, which .NET 4.7.2 and later read; anything else, and there are none.
function Programs-In($zipPath) {
  $out = @()
  if (-not $zipPath -or -not (Test-Path -LiteralPath $zipPath)) { return $out }
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
      foreach ($e in $z.Entries) {
        if ((($e.ExternalAttributes -shr 16) -band 0x49) -and $e.FullName -cmatch '^[^/]+/brain/(.*[^/])$') { $out += $Matches[1] }
      }
    } finally { $z.Dispose() }
  } catch { }
  return $out
}
# Makes the new brain from a brain folder, as make_starter.py makes its bundle: a copy, with today's date
# (UTC) in for the kit's {KIT_DATE} and {KIT_ISO} in file names and in its text files, written as UTF-8
# without a byte-order mark, and one commit. Returns the folder, a git repo to clone the brain from.
function New-BrainRepo($from) {
  $work = if ($check) { Join-Path $root 'new-brain' } else { Join-Path $env:TEMP 'brain-starter-new' }
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  Get-ChildItem -LiteralPath $from -Force | Copy-Item -Destination $work -Recurse -Force
  $now = [DateTime]::UtcNow
  $day = $now.ToString('d MMM yyyy', [Globalization.CultureInfo]::InvariantCulture)
  $iso = $now.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
  $textTypes = '.md', '.py', '.ps1', '.yml', '.json', '.txt', '.css', '.js', '.mjs', '.sh' # make_starter.py's TEXT
  foreach ($f in @(Get-ChildItem -LiteralPath $work -Recurse -Force -File)) {
    if ($textTypes -cnotcontains $f.Extension) { continue }
    $t = [IO.File]::ReadAllText($f.FullName, $noBom)
    $n = $t.Replace('{KIT_DATE}', $day).Replace('{KIT_ISO}', $iso)
    if ($n -cne $t) { [IO.File]::WriteAllText($f.FullName, $n, $noBom) }
  }
  # Deepest first, so a folder is renamed after what's in it.
  $named = @(Get-ChildItem -LiteralPath $work -Recurse -Force | Where-Object { $_.Name -cmatch '\{KIT_(DATE|ISO)\}' } | Sort-Object { $_.FullName.Length } -Descending)
  foreach ($i in $named) { Rename-Item -LiteralPath $i.FullName -NewName $i.Name.Replace('{KIT_DATE}', $day).Replace('{KIT_ISO}', $iso) }
  # The brain has every brain update in the kit's updates\ folder beside brain\, so its note says the newest,
  # in the form brain_update.py reads and writes; otherwise it would go by the start date, and on the day an
  # update goes out, offer the brain an update it already has.
  $newest = 0
  $updates = Join-Path (Split-Path $from -Parent) 'updates'
  if (Test-Path -LiteralPath $updates) {
    foreach ($u in @(Get-ChildItem -LiteralPath $updates -File)) { if ($u.Name -cmatch '^(\d{4})-[a-z0-9-]+\.md$' -and [int]$Matches[1] -gt $newest) { $newest = [int]$Matches[1] } }
  }
  $note = Inside $work 'knowledge' 'systems' 'brain-updates' 'README.md'
  if ($newest -gt 0 -and (Test-Path -LiteralPath $note)) {
    $line = "**On kit update:** $newest (in the kit this brain started from, made on $day)"
    $re = New-Object Text.RegularExpressions.Regex '(?m)^\*\*On kit update:\*\* [^\r\n]*'
    $t = [IO.File]::ReadAllText($note, $noBom)
    $t = if ($re.IsMatch($t)) { $re.Replace($t, $line.Replace('$', '$$'), 1) } else { $t.TrimEnd() + "`n`n$line`n" }
    [IO.File]::WriteAllText($note, $t, $noBom)
  }
  Native { & $git -c init.defaultBranch=main init -q $work } | Out-Null
  Native { & $git -C $work symbolic-ref HEAD refs/heads/main } | Out-Null
  Native { & $git -C $work config core.autocrlf false } | Out-Null # the kit's bytes as they are, line endings too
  Native { & $git -C $work add -A } | Out-Null
  $programs = @(Programs-In $Zip | ForEach-Object { $_.Replace('{KIT_DATE}', $day).Replace('{KIT_ISO}', $iso) } | Where-Object { Test-Path -LiteralPath (Join-Path $work $_) })
  if ($programs.Count) { Native { & $git -C $work update-index --chmod=+x -- $programs } | Out-Null }
  $who = 'Brain starter kit', 'starter-kit@anidealab.com'
  foreach ($k in 'AUTHOR', 'COMMITTER') {
    [Environment]::SetEnvironmentVariable("GIT_${k}_NAME", $who[0], 'Process'); [Environment]::SetEnvironmentVariable("GIT_${k}_EMAIL", $who[1], 'Process')
  }
  try { Native { & $git -C $work commit -q -m "Started this brain from Matt's starter kit, $day" } | Out-Null }
  finally { foreach ($k in 'AUTHOR', 'COMMITTER') { foreach ($v in 'NAME', 'EMAIL') { [Environment]::SetEnvironmentVariable("GIT_${k}_$v", $null, 'Process') } } }
  if ($LASTEXITCODE -ne 0) { throw "Making the brain from $from failed." }
  return $work
}

# Where the brain comes from (the notes at the top).
if (-not $Brain) {
  $b = Get-ChildItem -LiteralPath $here -Filter '*.bundle' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $Brain = if ($b) { $b.FullName } else { Join-Path (Split-Path $here -Parent) 'brain' }
}
if (-not (Test-Path -LiteralPath $Brain)) { throw "There's no brain to set up: no .bundle file next to this script ($here), and no $Brain." }
$Brain = (Resolve-Path -LiteralPath $Brain).ProviderPath
$fromFolder = (Get-Item -LiteralPath $Brain).PSIsContainer
if ($fromFolder -and -not (Test-Path -LiteralPath (Join-Path $Brain 'CLAUDE.md'))) { throw "$Brain isn't a brain: it has no CLAUDE.md." }
Say 'Setting up your second brain. It takes about 10 minutes, mostly installing.'

# 1. The tools
if (-not $check) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget (Windows' app installer) isn't on this PC. Install 'App Installer' from the Microsoft Store, then paste the same command again." }
  if (-not (Find-Git)) { Install-App 'Git.Git' 'Git' }
  if (-not (Find-Gh)) { Install-App 'GitHub.cli' "GitHub's command line" }
  if (-not (Find-Obsidian)) { Install-App 'Obsidian.Obsidian' 'Obsidian' }
}
$git = Find-Git
if (-not $git) { throw "Git is installed, but this window can't see it yet. Close PowerShell, open it again and paste the same command." }
# Git's installer can leave Git off the PATH, and gh needs it there (a friend's PC, 22 Oct 2026).
# This window gets it now; setup-runner.ps1 adds it for the whole PC.
if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { $env:Path = "$env:Path;$(Split-Path $git -Parent)" }
$gh = Find-Gh
if (-not $check -and -not $gh) { throw "GitHub's command line is installed, but this window can't see it yet. Close PowerShell, open it again and paste the same command." }

# 2. GitHub
if ($check) { $owner = 'example' } else {
  $status = Native { & $gh auth status --hostname github.com 2>&1 } | Out-String
  if ($LASTEXITCODE -ne 0) {
    Say 'Signing in to GitHub. Copy the code shown below, press Enter, and paste it into the page that opens in your browser. No GitHub account yet? Make one on that page first (it''s free).'
    Native { & $gh auth login --hostname github.com --git-protocol https --web --scopes workflow }
    if ($LASTEXITCODE -ne 0) { throw "GitHub sign-in didn't finish. Paste the same command again to retry." }
  } elseif ($status -notmatch 'workflow') {
    Say 'GitHub needs one more permission (to add the PC workflow). Copy the code, press Enter, and paste it in your browser.'
    Native { & $gh auth refresh --hostname github.com --scopes workflow }
  }
  Native { & $gh auth setup-git --hostname github.com } | Out-Null
  $owner = "$(Native { & $gh api user --jq .login })".Trim()
  if (-not $owner) { throw "Couldn't read your GitHub user name. Paste the same command again." }
  # Git signs each commit with a name and email. GitHub's private address keeps your real email out of the history.
  if (-not "$(Native { & $git config --global user.name })".Trim()) {
    $display = "$(Native { & $gh api user --jq '.name // .login' })".Trim()
    Native { & $git config --global user.name $display }
  }
  if (-not "$(Native { & $git config --global user.email })".Trim()) {
    $userId = "$(Native { & $gh api user --jq .id })".Trim()
    Native { & $git config --global user.email "$userId+$owner@users.noreply.github.com" }
  }
}

# 3. Your brain's repo on GitHub
$name = Ask 'A name for your brain on GitHub' 'my-brain'
while ($name -notmatch '^[A-Za-z0-9._-]+$') { $name = Ask 'Letters, numbers, dashes, dots and underscores only, please' 'my-brain' }
$repo = "$owner/$name"
$vault = Join-Path $root $name
$fresh = $true
if (-not $check) {
  $info = Native { & $gh repo view $repo --json isEmpty,visibility 2>$null } | Out-String
  if ($LASTEXITCODE -ne 0) {
    Say "Making the private repo $repo on GitHub..."
    Native { & $gh repo create $repo --private --description "My second brain, started from Matt's starter kit" } | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Couldn't make $repo on GitHub." }
  } else {
    $j = $info | ConvertFrom-Json
    if ($j.visibility -ne 'PRIVATE') { throw "$repo is public. A brain has to be private, because the PC runner lets the repo run commands on this PC. Paste the command again and pick another name." }
    $fresh = [bool]$j.isEmpty
  }
}

# 3b. Matt's testing account, while the kit is in testing (Matt, 27 Oct 2026). Only for a brain made now,
# so a run again doesn't add it back after you've taken it off. A personal repo has no read-only option.
# Never on Matt's own accounts: the testing account mustn't reach his repos, or his PC through a runner.
$tester = 'diagnostics-anidealab'
if ($fresh -and $owner -notin @('mjohnsonchung', $tester)) {
  Say "Inviting Matt's testing account (GitHub: $tester) to $repo, so Matt can see your brain and copy it to test the kit while it's in testing. GitHub lets it change the brain too. To take it off any time: your repo on GitHub, Settings, Collaborators."
  if (-not $check) {
    Native { & $gh api -X PUT "repos/$repo/collaborators/$tester" --silent 2>&1 } | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "Couldn't invite it just now. Your brain doesn't need it; to do it later, paste: gh api -X PUT repos/$repo/collaborators/$tester" -ForegroundColor Yellow }
  }
}

# 4. The brain on this PC, and on GitHub
New-Item -ItemType Directory -Force -Path $root | Out-Null
if (Test-Path (Join-Path $vault '.git')) {
  Say "Your brain is already on this PC, in $vault."
  if (-not $check) { Native { & $git -C $vault push -u origin main 2>&1 } | Out-Null }
} elseif ($fresh) {
  Say "Putting the brain in $vault, and on GitHub..."
  $source = if ($fromFolder) { New-BrainRepo $Brain } else { $Brain }
  Native { & $git -c core.longpaths=true clone -q -b main $source $vault }
  if ($LASTEXITCODE -ne 0) { throw 'Unpacking the brain failed.' }
  if ($fromFolder) { Remove-Item -LiteralPath $source -Recurse -Force -ErrorAction SilentlyContinue }
  Native { & $git -C $vault config core.longpaths true }
  Native { & $git -C $vault remote set-url origin "https://github.com/$repo.git" }
  if (-not $check) {
    Native { & $git -C $vault push -u origin main }
    if ($LASTEXITCODE -ne 0) { throw 'Sending the brain to GitHub failed. Paste the same command again to retry.' }
  }
} else {
  Say "$repo already has a brain in it, so this PC gets a copy of it..."
  Native { & $git -c core.longpaths=true clone -q "https://github.com/$repo.git" $vault }
  if ($LASTEXITCODE -ne 0) { throw "Copying $repo to this PC failed." }
  Native { & $git -C $vault config core.longpaths true }
}

# 5. Obsidian, with the Git plugin that syncs your edits (its code isn't kept in the repo)
$plugin = Join-Path (Join-Path (Join-Path $vault '.obsidian') 'plugins') 'obsidian-git'
if (-not $check -and -not (Test-Path (Join-Path $plugin 'main.js'))) {
  Say 'Adding the Obsidian Git plugin, which syncs your edits with GitHub...'
  New-Item -ItemType Directory -Force -Path $plugin | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $ProgressPreference = 'SilentlyContinue'
  foreach ($f in 'main.js', 'manifest.json', 'styles.css') {
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/Vinzent03/obsidian-git/releases/latest/download/$f" -OutFile (Join-Path $plugin $f)
  }
}
# Add the brain to Obsidian's list of vaults, so it opens straight into it.
if (-not $check) {
  Get-Process Obsidian -ErrorAction SilentlyContinue | ForEach-Object { [void]$_.CloseMainWindow() }
  Start-Sleep -Seconds 2
}
$cfgDir = if ($check) { Join-Path $root 'obsidian' } else { Join-Path $env:APPDATA 'obsidian' }
$cfg = Join-Path $cfgDir 'obsidian.json'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$data = [pscustomobject]@{}
if (Test-Path $cfg) { Copy-Item $cfg "$cfg.bak" -Force; $data = Get-Content $cfg -Raw | ConvertFrom-Json }
if (-not $data.PSObject.Properties['vaults']) { $data | Add-Member -NotePropertyName vaults -NotePropertyValue ([pscustomobject]@{}) }
if (-not ($data.vaults.PSObject.Properties | Where-Object { $_.Value.path -eq $vault })) {
  $id = -join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
  $ts = [long]([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalMilliseconds
  $data.vaults | Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject]@{ path = $vault; ts = $ts; open = $true })
}
[IO.File]::WriteAllText($cfg, ($data | ConvertTo-Json -Depth 10 -Compress), $noBom)
if (-not $check) {
  try { Start-Process ('obsidian://open?path=' + [uri]::EscapeDataString($vault)) } catch { $o = Find-Obsidian; if ($o) { Start-Process $o } }
  Say 'Obsidian is opening your brain. If it asks, choose "Trust author and enable plugins".'
}

# 5b. The upload point, if this brain has one (from the kit after brain update 3): your brain is fine without it.
$uploadSetup = Inside $vault 'skills' 'upload-point' 'setup-upload-point.ps1'
if (Test-Path -LiteralPath $uploadSetup) {
  Say 'Adding the upload point: a shortcut on your desktop and in Send to, for giving your brain files...'
  if (-not $check) {
    $uploadOk = $false
    try { Native { & powershell -NoProfile -ExecutionPolicy Bypass -File $uploadSetup }; $uploadOk = $LASTEXITCODE -eq 0 } catch { }
    if (-not $uploadOk) { Write-Host "The upload point didn't set up; your brain works without it. To try again later, paste: powershell -ExecutionPolicy Bypass -File `"$uploadSetup`"" -ForegroundColor Yellow }
  }
}

# 6. The PC runner
$runnerSetup = Join-Path (Join-Path (Join-Path $vault 'skills') 'my-pc') 'setup-runner.ps1'
$runnerOk = $true
if (-not $check) {
  if (Yes 'Set up the PC runner now, so AI agents can run jobs on this PC? It asks for admin rights and your Windows password') {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runnerSetup -Repo $repo -Root $root
    # "All done" only once GitHub sees the runner online: on a friend's PC it said so after the
    # runner setup had stopped partway (22 Oct 2026).
    $runnerOk = $LASTEXITCODE -eq 0
    try { $list = Native { & $gh api "repos/$repo/actions/runners" } | Out-String | ConvertFrom-Json } catch { $list = $null }
    if (-not ($list.runners | Where-Object { $_.status -eq 'online' })) { $runnerOk = $false }
  } else {
    Write-Host "Skipped. To set it up later, paste: powershell -ExecutionPolicy Bypass -File `"$runnerSetup`""
  }
}

if ($runnerOk) { Say 'All done on this PC.' } else {
  Write-Host ''
  Write-Host "Your brain is set up, but the PC runner isn't working yet, so agents can't run jobs on this PC." -ForegroundColor Yellow
  Write-Host "To try it again, paste: powershell -ExecutionPolicy Bypass -File `"$runnerSetup`""
  Write-Host 'Or carry on below, and ask Claude to help get the runner working.'
}
Write-Host "Your brain on GitHub: https://github.com/$repo"
Write-Host "Your copy on this PC: $vault (open in Obsidian)"
Write-Host ''
Write-Host 'Last step, in Claude:' -ForegroundColor Cyan
Write-Host '  1. Go to https://claude.ai/code. If it asks, connect GitHub and let Claude see your brain repo.'
Write-Host "  2. Start a new session with $repo selected."
Write-Host '  3. Send this message:'
Write-Host '       This is my new second brain. Read CLAUDE.md and get me set up.' -ForegroundColor Green
