# Sets up the upload point on this PC: a desktop shortcut "Upload point", and "My brain" in File
# Explorer's Send to menu (right-click files or folders, Send to, My brain). Both open upload-point.ps1
# from this folder in the brain's copy, so a change to it reaches the PC with the next sync. No admin
# rights needed, and safe to run again. The kit's installer runs it after cloning the brain; otherwise:
#   powershell -ExecutionPolicy Bypass -File "C:\AI-Brain-Link\<repo name>\skills\upload-point\setup-upload-point.ps1"
# It prints one line, and exits 1 if it couldn't. How the upload point works: SKILL.md in this folder.
# Windows PowerShell 5.1, plain ASCII.
$ErrorActionPreference = 'Stop'

try {
  $window = Join-Path $PSScriptRoot 'upload-point.ps1'
  if (-not (Test-Path -LiteralPath $window)) { throw ("upload-point.ps1 isn't next to this script, in " + $PSScriptRoot) }
  $copy = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the brain's copy: <copy>\skills\upload-point
  $sendTo = [Environment]::GetFolderPath('SendTo')
  if (-not $sendTo) { $sendTo = Join-Path $env:APPDATA 'Microsoft\Windows\SendTo' }
  $shell = New-Object -ComObject WScript.Shell
  foreach ($lnkPath in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Upload point.lnk'), (Join-Path $sendTo 'My brain.lnk'))) {
    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $lnk.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $window + '"'
    $lnk.WorkingDirectory = $copy
    $lnk.Description = 'Drop files and folders here for your brain'
    $lnk.Save()
    if (-not (Test-Path -LiteralPath $lnkPath)) { throw ("couldn't save " + $lnkPath) }
  }
  Write-Host 'Upload point ready: "Upload point" on your desktop, and Send to, My brain when you right-click files or folders.'
  exit 0
} catch {
  Write-Host ("The upload point isn't set up: " + $_.Exception.Message)
  exit 1
}
