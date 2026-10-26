# Checks a second brain's setup on this Windows PC against Matt's starter kit: the tools, the GitHub
# sign-in, the brain's repo and its settings, the PC runner and its service, your copy of the brain
# and Obsidian, and the PC's settings. It changes nothing, apart from saving its report. Each line
# says OK, FIX (with what to do, as a command where there is one), NOTE or INFO. The report is saved
# in C:\AI-Brain-Link (or your temp folder) and copied, so you can paste it into a Claude session on
# your brain with: Fix what this setup check found.
#   powershell -ExecutionPolicy Bypass -File check-setup.ps1 [-Repo owner/name] [-Vault folder]
# Agents can run it through the runner too (skills/my-pc/SKILL.md). Works in Windows PowerShell 5.1.
param([string]$Repo = '', [string]$Vault = '', [string]$Root = 'C:\AI-Brain-Link')
$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]
$script:fixes = 0
$colours = @{ 'OK' = 'Green'; 'FIX' = 'Red'; 'NOTE' = 'Yellow'; 'INFO' = 'Gray' }
function Report($kind, $text, $todo) {
  $line = '[{0,-4}] {1}' -f $kind, $text
  if ($todo) { $line += "`r`n         -> $todo" }
  $lines.Add($line)
  Write-Host $line -ForegroundColor $colours[$kind]
  if ($kind -eq 'FIX') { $script:fixes++ }
}
function Ok($t) { Report 'OK' $t $null }
function Fix($t, $todo) { Report 'FIX' $t $todo }
function Note($t, $todo) { Report 'NOTE' $t $todo }
function Info($t) { Report 'INFO' $t $null }
function Section($t) { $lines.Add(''); $lines.Add("== $t"); Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }
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
# gh's output as text, or $null if gh isn't there or the call failed.
function Gh {
  if (-not $script:gh) { return $null }
  $out = & $script:gh @args 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  return ($out -join "`n")
}
function GhJson { $t = Gh @args; if ($t) { try { return ($t | ConvertFrom-Json) } catch { } }; return $null }
function Origin($folder) { return "$(& $script:git -C $folder remote get-url origin 2>$null)".Trim() }
function Same-Repo($url, $repo) { return $url -and $repo -and ($url -replace '\.git$', '') -match ('[/:]' + [regex]::Escape($repo) + '$') }

$me = "$(whoami)".Trim()
$rootGiven = $PSBoundParameters.ContainsKey('Root')
Section 'This PC'
Info "$env:COMPUTERNAME, checked as $me on $(Get-Date -Format 'd MMM yyyy HH:mm')"
$nvidia = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' })

# The tools ----------------------------------------------------------------------------------------
Section 'Tools'
$script:git = Find-Git
if ($git) { Ok "Git: $((& $git --version) -join ' ')" } else { Fix 'Git is not installed' 'winget install --id Git.Git -e' }
$script:gh = Find-Gh
if ($gh) { Ok "GitHub's command line: $((& $gh --version) | Select-Object -First 1)" } else { Fix "GitHub's command line (gh) is not installed, so the repo can't be checked from here" 'winget install --id GitHub.cli -e   then: gh auth login --web --scopes workflow' }
if (Find-Obsidian) { Ok 'Obsidian is installed' } else { Fix 'Obsidian is not installed' 'winget install --id Obsidian.Obsidian -e' }
$login = $null
if ($gh) {
  $st = (& $gh auth status --hostname github.com 2>&1) | Out-String
  if ($LASTEXITCODE -eq 0) {
    $login = Gh api user --jq .login
    Ok "gh is signed in to GitHub as $login"
    if ($st -notmatch 'workflow') { Note "gh's sign-in can't change workflow files" 'gh auth refresh --hostname github.com --scopes workflow' }
  } else {
    Fix "gh isn't signed in to GitHub, so the repo can't be checked from here" 'gh auth login --hostname github.com --git-protocol https --web --scopes workflow'
    $script:gh = $null
  }
}

# The runner on this PC ----------------------------------------------------------------------------
Section 'The PC runner'
$runnerDir = $null; $runnerRepo = $null; $runnerName = $null
$services = @(Get-CimInstance Win32_Service -Filter "Name LIKE 'actions.runner.%'" -ErrorAction SilentlyContinue)
foreach ($s in $services) {
  Info "Service $($s.Name)"
  if ($s.State -eq 'Running') { Ok 'It is running' } else { Fix "It is $($s.State.ToLower()), so jobs wait in the queue" "PowerShell as administrator: Start-Service '$($s.Name)'" }
  if ($s.StartMode -eq 'Auto') { Ok 'It starts with Windows' } else { Fix "It doesn't start with Windows (start type: $($s.StartMode))" "PowerShell as administrator: Set-Service '$($s.Name)' -StartupType Automatic" }
  $acct = "$($s.StartName)"
  if ($acct -match 'NETWORK SERVICE|LocalService|LocalSystem|^NT AUTHORITY') {
    Fix "It runs as $acct, not as your account, so jobs can't reach your files and apps, and checkouts can fail with 'dubious ownership'" 'Set it up again under your account with setup-runner.ps1 (my-pc skill)'
  } elseif ($acct -ieq $me -or $acct -ieq (".\" + $me.Split('\')[-1])) {
    Ok "It runs as your account ($acct), so jobs can reach the whole PC"
  } else {
    Note "It runs as $acct, and you are $me" "Fine if that's you; otherwise set it up again with setup-runner.ps1"
  }
  if (((& sc.exe qfailure $s.Name 2>$null) -join ' ') -match 'RESTART') { Ok 'Windows restarts it if it ever stops' } else { Note "Windows won't restart it if it stops" "PowerShell as administrator: sc.exe failure '$($s.Name)' reset= 86400 actions= restart/60000/restart/60000/restart/60000" }
  $m = [regex]::Match("$($s.PathName)", '"?([^"]+?)\\bin\\RunnerService\.exe')
  if ($m.Success -and -not $runnerDir) { $runnerDir = $m.Groups[1].Value }
}
if (-not $services) {
  $dirs = @((Join-Path $Root '_runner'), 'C:\actions-runner', 'D:\AI-Brain-Link\_runner', 'D:\actions-runner')
  $runnerDir = $dirs | Where-Object { Test-Path (Join-Path $_ '.runner') } | Select-Object -First 1
  if ($runnerDir) { Fix "There's a runner in $runnerDir, but not as a Windows service, so it only runs while its window is open" 'Set it up as a service with setup-runner.ps1 (my-pc skill)' }
  else { Fix 'No GitHub Actions runner is set up on this PC, so agents can''t run jobs here' "Set one up with setup-runner.ps1, from Matt's starter kit (skills\my-pc)" }
}
if ($runnerDir) {
  $cfg = Join-Path $runnerDir '.runner'
  if (Test-Path $cfg) {
    $rc = Get-Content $cfg -Raw | ConvertFrom-Json
    $runnerName = $rc.agentName
    if ($rc.gitHubUrl -match 'github\.com/([^/]+/[^/]+?)/?$') { $runnerRepo = $Matches[1] }
    Info "Runner '$runnerName' in $runnerDir, registered to $($rc.gitHubUrl)"
    if (-not $runnerRepo) { Note 'It is registered to a whole account or organisation, not to one repo' 'Fine if you meant that; the kit registers it to the brain repo only' }
  }
  $ver = (Get-Item (Join-Path $runnerDir 'bin\Runner.Listener.exe') -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
  if ($ver) { Info "Runner version $ver (it updates itself)" }
  if (-not $rootGiven) { $Root = Split-Path $runnerDir -Parent }
}

# Which repo is the brain --------------------------------------------------------------------------
$obsVaults = @()
$obsCfg = Join-Path $env:APPDATA 'obsidian\obsidian.json'
if (Test-Path $obsCfg) { try { $obsVaults = @((Get-Content $obsCfg -Raw | ConvertFrom-Json).vaults.PSObject.Properties | ForEach-Object { $_.Value.path }) } catch { } }
if (-not $Repo -and $Vault -and $git) { $u = Origin $Vault; if ($u -match 'github\.com[/:]([^/\s]+/[^/\s]+?)(\.git)?$') { $Repo = $Matches[1] } }
if (-not $Repo) { $Repo = $runnerRepo }
if (-not $Repo -and $git) {
  foreach ($v in $obsVaults) { $u = Origin $v; if ($u -match 'github\.com[/:]([^/\s]+/[^/\s]+?)(\.git)?$' -and (Test-Path (Join-Path $v 'CLAUDE.md'))) { $Repo = $Matches[1]; break } }
}

# The repo on GitHub -------------------------------------------------------------------------------
Section 'The brain on GitHub'
$mine = $null; $pcText = $null; $tree = $null; $r = $null
if (-not $Repo) { Note "Couldn't tell which repo is the brain" 'Run this again with: -Repo owner/name' }
elseif (-not $gh) { Note "Can't check $Repo on GitHub without gh signed in" }
else {
  $r = GhJson api "repos/$Repo"
  if (-not $r) { Fix "GitHub doesn't show $Repo to $login" 'Check the name, and that this GitHub account owns it' }
  else {
    Info "Repo https://github.com/$Repo"
    if ($r.private) { Ok 'It is private' } else { Fix "It is public: anyone can read the brain, and a runner on a public repo isn't safe" "gh repo edit $Repo --visibility private --accept-visibility-change-consequences" }
    if ($r.permissions.admin) { Ok 'You are its admin' } else { Note "You aren't its admin, so some settings can't be checked" }
    if ($r.default_branch -ne 'main') { Note "Its main branch is called $($r.default_branch); the kit uses main" }
    if ($runnerRepo -and $runnerRepo -ne $Repo) { Fix "The runner on this PC is registered to $runnerRepo, not $Repo" "Set it up again from the brain's copy with setup-runner.ps1" }
    $ap = GhJson api "repos/$Repo/actions/permissions"
    if ($ap) { if ($ap.enabled) { Ok 'GitHub Actions is on' } else { Fix "GitHub Actions is off for the repo, so nothing can run on the PC" "gh api -X PUT repos/$Repo/actions/permissions -F enabled=true" } }
    $rl = GhJson api "repos/$Repo/actions/runners"
    if ($rl) {
      if (-not $rl.total_count) { Fix 'No runner is registered to the repo' 'Set one up with setup-runner.ps1 (my-pc skill)' }
      foreach ($x in $rl.runners) {
        $labels = ($x.labels | ForEach-Object { $_.name }) -join ', '
        if ($x.status -eq 'online') { Ok "Runner '$($x.name)' is online (labels: $labels)" } else { Fix "Runner '$($x.name)' is $($x.status) (labels: $labels)" "Is that PC on and awake, with its runner service running?" }
        if ($x.name -eq $runnerName -or (-not $runnerName -and $x.name -eq $env:COMPUTERNAME)) { $mine = $x }
      }
      if ($runnerName -and -not $mine -and $runnerRepo -eq $Repo) { Fix "This PC's runner ('$runnerName') isn't registered on GitHub any more" 'Set it up again with setup-runner.ps1' }
    }
    $col = GhJson api "repos/$Repo/collaborators"
    if ($col) {
      $others = @($col | Where-Object { $_.login -ne $login })
      if ($others.Count) { Note "Others can write to it ($(($others | ForEach-Object { $_.login }) -join ', ')), and anyone who can write can run commands on this PC through the runner" "Remove them in the repo's Settings, Collaborators, unless you'd trust them with your PC" }
      else { Ok 'Nobody else has access to it' }
    }
    $wf = @(GhJson api "repos/$Repo/contents/.github/workflows")
    $pcWorkflow = $null
    if (-not $wf -or -not $wf[0]) { Fix "The repo has no workflows, so agents have no way to run jobs on the PC" "Add pc-run.yml from Matt's starter kit (.github/workflows)" }
    else {
      foreach ($f in ($wf | Where-Object { $_.name -match '\.ya?ml$' })) {
        $c = GhJson api "repos/$Repo/contents/$($f.path)"
        if (-not $c) { continue }
        $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($c.content -replace '\s', '')))
        if ($text -notmatch 'self-hosted') { continue }
        $want = @(([regex]::Match($text, 'runs-on:\s*\[([^\]]*)\]')).Groups[1].Value -split ',' | ForEach-Object { $_.Trim(" '`"") } | Where-Object { $_ -and $_ -ne 'self-hosted' })
        Info "$($f.name) runs on a PC (runs-on: self-hosted, $($want -join ', '))"
        if ($text -match '(?m)^\s*(pull_request|pull_request_target)\s*:' -or $text -match '(?m)^on:\s*\[[^\]]*pull_request') { Fix "$($f.name) can be started by a pull request, which could run commands on this PC" 'Start PC workflows only by workflow_dispatch (and schedule)' }
        if ($text -match 'workflow_dispatch' -and $text -match '(?m)^\s+command:') { $pcWorkflow = $f.name; $pcText = $text }
        if ($rl) {
          $fits = @($rl.runners | Where-Object { $have = @($_.labels | ForEach-Object { $_.name }); -not @($want | Where-Object { $have -notcontains $_ }).Count })
          $pick = if ($mine) { $mine } else { $rl.runners | Select-Object -First 1 }
          $its = if ($pick) { @($pick.labels | ForEach-Object { $_.name } | Where-Object { $_ -notin 'self-hosted', 'Windows', 'X64', 'ARM64' }) -join ', ' } else { '' }
          if ($fits.Count) { Ok "Runner '$($fits[0].name)' has the labels $($f.name) asks for" }
          elseif ($pick) { Fix "$($f.name) waits for a runner labelled $($want -join ', '), and no runner on the repo has them all, so its jobs would queue forever" "Change runs-on in $($f.name) to [self-hosted, $its], or set the runner up again with those labels" }
        }
      }
      if ($pcWorkflow) { Ok "$pcWorkflow lets agents run a command on the PC" } else { Fix 'No workflow lets agents run a command on the PC (workflow_dispatch with a command input, on the self-hosted runner)' "Add pc-run.yml from Matt's starter kit (.github/workflows)" }
      if (@($wf | ForEach-Object { $_.name }) -contains 'library.yml') { Ok 'library.yml rebuilds the knowledge indexes on each push' } else { Note 'No library.yml, so the knowledge indexes update only when an agent runs library.py build' "Add library.yml from Matt's starter kit (.github/workflows)" }
    }
    $sec = GhJson api "repos/$Repo/actions/secrets"
    if ($sec) { if ($sec.total_count) { Info "Actions secrets, names only: $(($sec.secrets | ForEach-Object { $_.name }) -join ', ')" } else { Info 'No Actions secrets yet; keys get added when a job needs one' } }
    $tree = GhJson api "repos/$Repo/git/trees/$($r.default_branch)?recursive=1"
  }
}

# The brain's shape, against the kit ---------------------------------------------------------------
if ($tree) {
  Section "The brain's shape, compared with Matt's starter kit"
  $paths = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($t in $tree.tree) { [void]$paths.Add($t.path) }
  if ($paths.Contains('CLAUDE.md')) { Ok 'The core (CLAUDE.md) is there' } else { Fix 'There is no core (CLAUDE.md), the page every agent reads first' "Copy the kit's CLAUDE.md in, and make it yours" }
  $parts = [ordered]@{
    'README.md' = 'the front door'
    'skills/README.md' = 'the skills list'
    'knowledge/README.md' = "the knowledge library's index"
    'skills/brain-spec/SKILL.md' = 'the brain spec'
    'skills/brain-spec/library.py' = 'the script that builds the indexes from the cards'
    'skills/brain-spec/check_links.py' = 'the link checker'
    'skills/brain-spec/reminders.py' = 'the reminders script'
    'skills/guide-mode/SKILL.md' = 'guide mode'
    'skills/find-skills/SKILL.md' = 'the way to find more skills'
    '.claude/settings.json' = "Claude Code's settings (it runs the reminders at the start of a session)"
    '.obsidian/graph.json' = "the map's colours by shelf"
    '.obsidian/plugins/obsidian-git/data.json' = "Obsidian Git's sync settings"
    '.obsidian/plugins/brain-graph/main.js' = 'the brain graph'
  }
  foreach ($s in 'tasks', 'ventures', 'areas', 'decisions', 'people', 'systems', 'ideas', 'subjects') { $parts["knowledge/$s/README.md"] = "the $s shelf" }
  $missing = @($parts.Keys | Where-Object { -not $paths.Contains($_) })
  if ($missing.Count) { Note "It has $($parts.Count - $missing.Count) of the kit's $($parts.Count) parts. Missing: $(($missing | ForEach-Object { $parts[$_] + ' (' + $_ + ')' }) -join '; ')" 'Fine if it was set up differently on purpose; an agent can copy them in from the kit' }
  else { Ok "It has all $($parts.Count) of the kit's parts" }
  $pcSkill = @($paths | Where-Object { $_ -match '^skills/[^/]*pc[^/]*/SKILL\.md$' })
  if ($pcSkill.Count) { Ok "Agents have a skill for using the PC ($($pcSkill -join ', '))" } else { Note "No skill tells agents how to use the PC runner" "Copy the kit's skills/my-pc in" }
  $skills = @($paths | Where-Object { $_ -match '^skills/[^/]+/SKILL\.md$' }).Count
  Info "$skills skills"
  $core = GhJson api "repos/$Repo/contents/CLAUDE.md"
  if ($core) {
    $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($core.content -replace '\s', '')))
    $rules = [ordered]@{ 'gate' = 'the gates (money, secrets, the sign-off, the owner''s voice)'; 'One check is enough' = '"one check is enough"'; 'Guide mode' = 'guide mode'; 'made with love by AnIdeaLab.com' = 'the AnIdeaLab sign-off'; 'command' = '"give the owner a command"'; 'pull --rebase' = 'committing straight to main' }
    $gone = @($rules.Keys | Where-Object { $text -notmatch [regex]::Escape($_) })
    if ($gone.Count) { Note "The core doesn't have: $(($gone | ForEach-Object { $rules[$_] }) -join ', ')" "Fine if on purpose; the kit's core has them" } else { Ok "The core has the kit's rules" }
    if ($text.Length -gt 6144) { Note "The core is $([int]($text.Length / 1024)) KB; the kit keeps it under 6 KB, because every agent reads it first" }
  }
}

# Your copy of the brain, and Obsidian -------------------------------------------------------------
Section 'Your copy of the brain, and Obsidian'
if (-not $Vault -and $git) {
  $candidates = @($obsVaults) + @(Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  foreach ($v in $candidates) {
    if (-not (Test-Path (Join-Path $v '.git'))) { continue }
    if (($Repo -and (Same-Repo (Origin $v) $Repo)) -or (-not $Repo -and (Test-Path (Join-Path $v 'CLAUDE.md')))) { $Vault = $v; break }
  }
}
if (-not $Vault) {
  if ($Repo) { Fix "Couldn't find your copy of the brain on this PC" "git clone https://github.com/$Repo.git `"$Root\$($Repo.Split('/')[-1])`"   then in Obsidian: Manage vaults, Open folder as vault, and pick that folder" }
  else { Note "Couldn't find a copy of the brain on this PC" 'Run this again with: -Vault <folder>' }
} else {
  Info "Your copy: $Vault"
  if ($Vault -match 'OneDrive|Dropbox|iCloud') { Fix "It's inside a synced folder (OneDrive, Dropbox or iCloud), and two sync systems on one git folder can corrupt it" "Clone it again into $Root and open that copy in Obsidian instead" }
  if ($git) {
    $st = (& $git -C $Vault status --porcelain -b 2>&1) | Out-String
    if ($st -match 'dubious ownership') { Fix "Git refuses this folder ('dubious ownership'), so Obsidian can't sync it" "PowerShell as administrator: icacls `"$Vault`" /setowner `"$me`" /T /C" }
    elseif ($LASTEXITCODE -ne 0) { Fix "Git can't read it: $($st.Trim())" 'Ask an agent, with this line' }
    else {
      $u = Origin $Vault
      if ($Repo -and -not (Same-Repo $u $Repo)) { Fix "It syncs with $u, not $Repo" "git -C `"$Vault`" remote set-url origin https://github.com/$Repo.git" } elseif ($u) { Ok "It syncs with $u" }
      $changed = @($st -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch '^##' }).Count
      if ($changed) { Note "$changed file(s) changed here and not yet synced" 'Obsidian Git syncs them every 10 minutes while Obsidian is open' }
      if ($gh -and $Repo -and $r) {
        $remote = Gh api "repos/$Repo/commits/$($r.default_branch)" --jq .sha
        $local = "$(& $git -C $Vault rev-parse HEAD 2>$null)".Trim()
        if ($remote -and $local -eq $remote) { Ok 'It matches GitHub' } elseif ($remote) { Note "It isn't at the same commit as GitHub" 'Obsidian Git catches up while Obsidian is open; or: git -C "<folder>" pull' }
      }
    }
    if (-not "$(& $git config --global user.name 2>$null)".Trim() -or -not "$(& $git config --global user.email 2>$null)".Trim()) { Fix "Git doesn't know your name and email, so commits from Obsidian fail" 'git config --global user.name "Your Name"; git config --global user.email "you@users.noreply.github.com"' }
    $helper = "$(& $git config --get-all credential.helper 2>$null)".Trim()
    if ($helper) { Info "Git signs in to GitHub with: $($helper -replace '\s+', ' ')" }
  }
  $obs = Join-Path $Vault '.obsidian'
  # In PowerShell 5.1 ConvertFrom-Json hands a JSON list back as one item, so it's piped on to split it.
  $on = @(); if (Test-Path (Join-Path $obs 'community-plugins.json')) { try { $on = @((Get-Content (Join-Path $obs 'community-plugins.json') -Raw | ConvertFrom-Json) | ForEach-Object { $_ }) } catch { } }
  $pluginDir = Join-Path $obs 'plugins\obsidian-git'
  if (-not (Test-Path (Join-Path $pluginDir 'main.js'))) { Fix "The Obsidian Git plugin isn't installed in this vault, so edits don't sync" "`$p='$pluginDir'; New-Item -ItemType Directory -Force `$p | Out-Null; 'main.js','manifest.json','styles.css' | ForEach-Object { Invoke-WebRequest -UseBasicParsing `"https://github.com/Vinzent03/obsidian-git/releases/latest/download/`$_`" -OutFile `"`$p\`$_`" }" }
  elseif ($on -notcontains 'obsidian-git') { Fix 'The Obsidian Git plugin is switched off, so the vault doesn''t sync' 'In Obsidian: Settings, Community plugins, and switch on Git' }
  else { Ok 'The Obsidian Git plugin is installed and on, so edits sync' }
  if (Test-Path (Join-Path $obs 'plugins\brain-graph\main.js')) { if ($on -contains 'brain-graph') { Ok 'The brain graph is installed and on' } else { Note 'The brain graph is installed but switched off' 'In Obsidian: Settings, Community plugins, and switch on Brain graph' } }
  if (@($obsVaults | Where-Object { $_ -ieq $Vault }).Count) { Ok 'Obsidian has it as a vault' } else { Fix "Obsidian hasn't opened this folder as a vault" "In Obsidian: Manage vaults (bottom left), Open folder as vault, and pick $Vault" }
}

# PC settings ----------------------------------------------------------------------------------------
Section 'PC settings'
$pol = Get-ExecutionPolicy -Scope CurrentUser
if ($pol -in 'RemoteSigned', 'Unrestricted', 'Bypass') { Ok "Your account can run scripts ($pol), which the runner needs" }
elseif ((Get-ExecutionPolicy -Scope LocalMachine) -in 'RemoteSigned', 'Unrestricted', 'Bypass' -and $pol -eq 'Undefined') { Ok "Scripts can run (set for the whole PC: $(Get-ExecutionPolicy -Scope LocalMachine))" }
else { Fix "Your account can't run scripts ($pol), and the runner's own steps need to" 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force' }
$q = (& powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null) -join "`n"
$hex = @([regex]::Matches($q, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
if ($hex.Count -ge 2) {
  $ac = [Convert]::ToInt64($hex[$hex.Count - 2], 16)
  if ($ac -eq 0) { Ok "It doesn't sleep while plugged in, so jobs can run any time it's on" }
  else { Note "It sleeps after $([int]($ac / 60)) minutes while plugged in, and jobs wait while it's asleep" 'powercfg /change standby-timeout-ac 0' }
}
$desk = [Environment]::GetFolderPath('Desktop')
if ($desk -and (Test-Path (Join-Path $desk 'AI Brain Link - live jobs.lnk'))) { Ok 'The live jobs window is on the desktop' } else { Note 'No "AI Brain Link - live jobs" shortcut on the desktop' 'setup-runner.ps1 adds it; it shows what agents run, live' }
if ($pcText) {
  $logDir = ([regex]::Match($pcText, '([A-Za-z]:\\[^"''\s]*?\\_logs)\\')).Groups[1].Value
  if ($logDir) { if (Test-Path $logDir) { Ok "The jobs' log folder is there ($logDir)" } else { Fix "The PC workflow writes its logs to $logDir, which doesn't exist, so every job fails" "New-Item -ItemType Directory -Force '$logDir'" } }
}
if ($nvidia.Count -and $mine -and -not (@($mine.labels | ForEach-Object { $_.name }) -contains 'gpu')) { Note "This PC has an NVIDIA card ($($nvidia[0].Name)), but its runner has no gpu label" 'Fine unless a workflow asks for gpu; setup-runner.ps1 adds it' }
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object { Info ('Disk {0} {1:N0} GB free of {2:N0} GB' -f $_.DeviceID, ($_.FreeSpace / 1GB), ($_.Size / 1GB)) }

# The report ---------------------------------------------------------------------------------------
Section 'Summary'
if ($script:fixes) { Report 'INFO' "$($script:fixes) thing(s) to fix, marked FIX above." $null } else { Report 'INFO' 'Nothing to fix.' $null }
$text = $lines -join "`r`n"
$out = if (Test-Path $Root) { Join-Path $Root 'setup-check.txt' } else { Join-Path $env:TEMP 'brain-setup-check.txt' }
try { [IO.File]::WriteAllText($out, $text, (New-Object Text.UTF8Encoding $false)); Write-Host "Saved to $out" } catch { }
$copied = $false
try { Set-Clipboard -Value $text; $copied = $true } catch { }
Write-Host ''
if ($copied) { Write-Host 'The report is copied. To get help fixing it, start a Claude session on your brain at claude.ai/code, press Ctrl+V and add: Fix what this setup check found.' -ForegroundColor Cyan }
exit 0
