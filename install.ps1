# Starts your own second brain from Matt's starter kit, on a Windows PC. Paste into PowerShell:
#   irm https://raw.githubusercontent.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/main/install.ps1 | iex
# It downloads this repo as a zip from GitHub (no Git needed yet), unpacks it in a temporary folder and
# runs the installer in it, install\install-windows.ps1, as a file, which does the rest and says what it's
# doing: Git, GitHub's command line and Obsidian, your brain's private repo made from brain\, your copy in
# C:\AI-Brain-Link, and the PC runner. Safe to run again. Windows PowerShell 5.1, plain ASCII.
# The installer is written into install\ from Matt's brain (its brain-starter skill); this file is kept here.
& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue' # Windows PowerShell 5.1 downloads far slower with its progress bar
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
  $url = 'https://github.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/archive/refs/heads/main.zip'
  $zip = Join-Path $env:TEMP 'brain-starter-kit.zip'
  $kit = Join-Path $env:TEMP 'brain-starter-kit'
  Write-Host ''
  Write-Host "Downloading Matt's starter kit..." -ForegroundColor Cyan
  try {
    if (Test-Path -LiteralPath $kit) { Remove-Item -LiteralPath $kit -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $kit) { $kit = $kit + '-' + (Get-Random) }
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $kit)
    $installer = @(Get-ChildItem -LiteralPath $kit -Directory | ForEach-Object { Join-Path (Join-Path $_.FullName 'install') 'install-windows.ps1' } | Where-Object { Test-Path -LiteralPath $_ })
    if (-not $installer.Count) { throw "the installer isn't in it" }
  } catch {
    Write-Host "Couldn't get the kit ($($_.Exception.Message)). Check the PC is online, then paste the same line again." -ForegroundColor Yellow
    return
  }
  # Windows PowerShell 5.1, which every Windows PC has, whichever PowerShell this is.
  $ps = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
  if (-not $ps -or -not (Test-Path -LiteralPath $ps)) { $ps = if (Get-Command powershell -ErrorAction SilentlyContinue) { 'powershell' } else { 'pwsh' } }
  & $ps -NoProfile -ExecutionPolicy Bypass -File $installer[0] -Zip $zip
  if ($LASTEXITCODE -eq 0) {
    Remove-Item -LiteralPath $kit, $zip -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Host ''
    Write-Host "The setup stopped before the end. What went wrong is just above; once it's sorted, paste the same line again, and it skips what's already done." -ForegroundColor Yellow
  }
}
