# Sets up the PC runner for this brain, or sets it up again: GitHub's Actions runner, registered with
# this brain's repo under the label my-pc (and gpu with an NVIDIA card), running as a Windows service
# under your own account, so AI agents can run jobs on this PC whenever it's on.
#   powershell -ExecutionPolicy Bypass -File skills\my-pc\setup-runner.ps1 [-Repo owner/name]
# It asks for admin rights, then your Windows password (not your PIN). Safe to run again.
# How agents use the runner: skills/my-pc/SKILL.md. Works in Windows PowerShell 5.1.
param([string]$Repo = '', [string]$Root = 'C:\AI-Brain-Link', [switch]$Elevated)
$ErrorActionPreference = 'Stop'

function Find-First($paths) { foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $p } }; return $null }
function Find-Gh {
  $c = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return Find-First @("$env:ProgramFiles\GitHub CLI\gh.exe", "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe")
}
# Runs a program without Windows PowerShell 5.1 turning what it writes to stderr into errors.
function Native([scriptblock]$Block) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & $Block } finally { $ErrorActionPreference = $old }
}
function Yes($q) { $a = Read-Host "$q [Y/n]"; return -not ($a -match '^\s*[Nn]') }
# Adds a folder to the PATH Windows keeps for the whole PC, which the runner's jobs get, and to this window's.
function Add-MachinePath($dir) {
  $p = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  if (@($p -split ';' | ForEach-Object { $_.TrimEnd('\') }) -contains $dir.TrimEnd('\')) { return $false }
  [Environment]::SetEnvironmentVariable('Path', ($p.TrimEnd(';') + ';' + $dir), 'Machine')
  $env:Path = "$env:Path;$dir"
  return $true
}

if (-not $Repo) {
  $brain = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  $url = "$(Native { git -C $brain remote get-url origin 2>$null })"
  if ($url -match 'github\.com[/:]([^/\s]+/[^/\s]+?)(\.git)?\s*$') { $Repo = $Matches[1] }
}
if (-not $Repo) { $Repo = (Read-Host "Your brain's repo on GitHub, as owner/name").Trim() }

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host 'Setting up the PC runner needs admin rights. Windows will ask, then a new window opens.' -ForegroundColor Cyan
  $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Repo "{1}" -Root "{2}" -Elevated' -f $PSCommandPath, $Repo, $Root
  try { $p = Start-Process powershell -Verb RunAs -Wait -PassThru -ArgumentList $argLine }
  catch { Write-Host "Admin rights weren't given, so the runner isn't set up. Paste the same command again when you're ready." -ForegroundColor Yellow; exit 1 }
  exit $p.ExitCode
}

$code = 0
$runner = Join-Path $Root '_runner'
try {
  $gh = Find-Gh
  if (-not $gh) { throw "GitHub's command line tool (gh) isn't installed. Run the brain's installer first, or: winget install --id GitHub.cli -e" }
  foreach ($d in $Root, $runner, (Join-Path $Root '_logs'), (Join-Path $Root 'Tools')) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

  # Git's installer can leave Git off the PC's PATH and its first-run setup undone, when it didn't run
  # as admin ("cannot remove /etc/post-install/*.post"). Jobs and gh need Git, and the service only
  # sees the PATH it starts with, so both are done here, before it starts; running the first-run setup
  # again does no harm (a friend's PC, 22 Oct 2026).
  $gitRoot = Join-Path $env:ProgramFiles 'Git'
  if (Test-Path (Join-Path $gitRoot 'cmd\git.exe')) {
    if (Add-MachinePath (Join-Path $gitRoot 'cmd')) { Write-Host "Added Git to this PC's PATH." }
    Native { & (Join-Path $gitRoot 'bin\bash.exe') --login -c exit } | Out-Null
  }

  Write-Host 'Letting your account run scripts (RemoteSigned), which the runner needs...'
  # It saves the setting, then throws "Security error." whenever a narrower scope overrides it, which
  # this script's own -ExecutionPolicy Bypass always does; -ErrorAction can't stop that kind of error,
  # so it's caught, and only the check below counts (a friend's PC, 22 Oct 2026).
  try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop } catch { }
  if ((Get-ExecutionPolicy -Scope CurrentUser) -notin 'RemoteSigned', 'Unrestricted', 'Bypass') {
    Write-Host "  It didn't change (a policy on this PC may set it). If jobs fail with a script policy error, tell an agent." -ForegroundColor Yellow
  }

  if (-not (Test-Path (Join-Path $runner 'bin\Runner.Listener.exe'))) {
    $tag = "$(Native { & $gh api repos/actions/runner/releases/latest --jq .tag_name })".Trim()
    if ($tag -notmatch '^v(\d+\.\d+\.\d+)$') { throw "Couldn't find the latest version of GitHub's runner ('$tag'). Check the internet connection and run this again." }
    $ver = $Matches[1]
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $zip = Join-Path $env:TEMP "actions-runner-win-$arch-$ver.zip"
    Write-Host "Downloading GitHub's runner $ver..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue' # the progress bar makes downloads very slow in PowerShell 5.1
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/actions/runner/releases/download/v$ver/actions-runner-win-$arch-$ver.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $runner -Force
    Remove-Item $zip -Force
  }
  Set-Location $runner
  # Called directly rather than through config.cmd, so cmd.exe can't trip on & or ^ in a password.
  $listener = Join-Path $runner 'bin\Runner.Listener.exe'

  function Remove-OldRegistration {
    if (-not (Test-Path '.runner')) { return }
    Write-Host 'Removing the old registration first...'
    $rt = "$(Native { & $gh api -X POST "repos/$Repo/actions/runners/remove-token" --jq .token })".Trim()
    if ($rt) { Native { & $listener remove --token $rt } | Out-Host }
    if (Test-Path '.runner') { # GitHub had already forgotten it, or the removal failed: clear it here
      $old = Get-Content '.service' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($old) { Stop-Service $old -Force -ErrorAction SilentlyContinue; Native { sc.exe delete $old } | Out-Null }
      Remove-Item '.runner', '.credentials', '.credentials_rsaparams', '.service' -Force -ErrorAction SilentlyContinue
    }
  }

  $name = $env:COMPUTERNAME
  $labels = 'my-pc'
  if (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' }) { $labels = 'my-pc,gpu' }
  $account = "$(whoami)".Trim()
  $ok = $false
  for ($try = 1; $try -le 3 -and -not $ok; $try++) {
    Remove-OldRegistration
    $token = "$(Native { & $gh api -X POST "repos/$Repo/actions/runners/registration-token" --jq .token })".Trim()
    if (-not $token) { throw "GitHub didn't hand over a runner token for $Repo. Check the repo is yours and that gh is signed in (gh auth status)." }
    Write-Host ''
    Write-Host "The runner runs as you ($account), so it can reach your files and apps." -ForegroundColor Cyan
    $sec = Read-Host -AsSecureString 'Your Windows password, not your PIN (with a Microsoft account, that account''s password)'
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    Native { & $listener configure --unattended --url "https://github.com/$Repo" --token $token --name $name --labels $labels --work _work --replace --runasservice --windowslogonaccount $account --windowslogonpassword $pw } | Out-Host
    $ok = ($LASTEXITCODE -eq 0) -and (Test-Path '.service')
    $pw = $null
    if (-not $ok) {
      Write-Host "That didn't work. The usual cause is the password: it's the one for your Windows account (for a Microsoft account, that account's password), never the PIN." -ForegroundColor Yellow
    }
  }
  if (-not $ok) { throw "The runner couldn't be registered. Ask an agent, and say what the window showed." }

  $svc = (Get-Content '.service' | Select-Object -First 1).Trim()
  Set-Service -Name $svc -StartupType Automatic
  Native { sc.exe failure $svc reset= 86400 actions= restart/60000/restart/60000/restart/60000 } | Out-Null
  if ((Get-Service $svc).Status -ne 'Running') { Start-Service $svc }

  Write-Host 'Adding the "AI Brain Link - live jobs" window to your desktop...'
  $watch = Join-Path $Root 'Tools\watch-jobs.ps1'
  Copy-Item (Join-Path $PSScriptRoot 'watch-jobs.ps1') $watch -Force
  $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'AI Brain Link - live jobs.lnk'))
  $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $lnk.Arguments = '-NoExit -ExecutionPolicy Bypass -File "' + $watch + '"'
  $lnk.Save()

  Write-Host ''
  if (Yes "Keep this PC awake while it's plugged in, so jobs can run? The screen still turns off as usual.") {
    Native { powercfg /change standby-timeout-ac 0; powercfg /change hibernate-timeout-ac 0 } | Out-Null
    Write-Host 'Done: it no longer sleeps while plugged in.'
  }

  # Done only once GitHub sees the runner online, so nobody is told it worked when it didn't.
  $state = ''
  for ($i = 0; $i -lt 12 -and $state -ne 'online'; $i++) {
    Start-Sleep -Seconds 5
    try { $list = Native { & $gh api "repos/$Repo/actions/runners" } | Out-String | ConvertFrom-Json } catch { $list = $null }
    $state = "$(($list.runners | Where-Object { $_.name -eq $name } | Select-Object -First 1).status)"
  }
  if ($state -ne 'online') { throw "The runner is installed, but GitHub doesn't see it online yet ($(if ($state) { "it says $state" } else { 'it isn''t listed' })). Run this again, or ask an agent, and say what this window showed." }
  Write-Host ''
  Write-Host "The PC runner '$name' is set up, and GitHub sees it online." -ForegroundColor Green
  Write-Host 'It starts with Windows, so agents can run jobs whenever this PC is on.'
} catch {
  Write-Host ''
  Write-Host "Something went wrong: $($_.Exception.Message)" -ForegroundColor Red
  $code = 1
} finally {
  if ($Elevated) { Write-Host ''; Read-Host 'Press Enter to close this window' | Out-Null }
}
exit $code
