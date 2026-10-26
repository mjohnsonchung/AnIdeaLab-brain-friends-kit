# Live view of what agents run on this PC through the runner (pc-run.yml).
# Each job writes C:\AI-Brain-Link\_logs\pc-run-<run id>.log: the command, then its output.
# This window follows the newest log as it grows. Closing it stops only the watching.
# Installed as C:\AI-Brain-Link\Tools\watch-jobs.ps1, with a desktop shortcut "AI Brain Link - live jobs".
$logs = 'C:\AI-Brain-Link\_logs'
$Host.UI.RawUI.WindowTitle = 'AI Brain Link - live jobs'
Write-Host "Watching $logs. Jobs from GitHub show up here as they run." -ForegroundColor Cyan
Write-Host "Full history: your brain's repo on GitHub, the Actions tab, 'Run on my PC'." -ForegroundColor DarkCyan
$current = $null; $pos = 0
while ($true) {
  $newest = Get-ChildItem $logs -Filter 'pc-run-*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime | Select-Object -Last 1
  if ($newest -and $newest.FullName -ne $current) {
    $current = $newest.FullName; $pos = 0
    Write-Host "`n===== $($newest.Name) =====" -ForegroundColor Yellow
  }
  if ($current) {
    try {
      $fs = [IO.File]::Open($current, 'Open', 'Read', 'ReadWrite')
      [void]$fs.Seek($pos, 'Begin')
      # PowerShell 5.1 writes these logs as UTF-16; the BOM is only at the start.
      $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode, $true)
      $text = $sr.ReadToEnd(); $pos = $fs.Position; $sr.Close()
      if ($text) { Write-Host -NoNewline $text }
    } catch { }
  }
  Start-Sleep -Milliseconds 700
}
