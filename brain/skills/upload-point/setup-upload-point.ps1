# Sets up the upload point on this PC: a desktop shortcut "Upload point", and "My brain" in File
# Explorer's Send to menu (right-click files or folders, Send to, My brain). Both open upload-point.ps1
# from this folder in the brain's copy, so a change to it reaches the PC with the next sync. No admin
# rights needed, and safe to run again. The kit's installer runs it after cloning the brain; otherwise:
#   powershell -ExecutionPolicy Bypass -File "C:\AI-Brain-Link\<repo name>\skills\upload-point\setup-upload-point.ps1"
# It prints one line, and exits 1 if it couldn't. How the upload point works: SKILL.md in this folder.
# Windows PowerShell 5.1, plain ASCII.
$ErrorActionPreference = 'Stop'

function Save-OrbIcon([string]$path) {
  # The window's orb as a 256-pixel icon: a PNG inside an .ico file, which Windows shows at any size.
  Add-Type -AssemblyName System.Drawing
  $bmp = New-Object Drawing.Bitmap 256, 256
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $shape = New-Object Drawing.Drawing2D.GraphicsPath
  $shape.AddEllipse(16, 16, 224, 224)
  $fill = New-Object Drawing.Drawing2D.PathGradientBrush $shape
  $fill.CenterPoint = New-Object Drawing.PointF(96, 88)
  $fill.CenterColor = [Drawing.ColorTranslator]::FromHtml('#D6E4FD')
  $fill.SurroundColors = [Drawing.Color[]]@([Drawing.ColorTranslator]::FromHtml('#2F4F86'))
  $g.FillPath($fill, $shape)
  $g.Dispose()
  $png = New-Object IO.MemoryStream
  $bmp.Save($png, [Drawing.Imaging.ImageFormat]::Png)
  $bytes = $png.ToArray()
  $ico = New-Object IO.MemoryStream
  $w = New-Object IO.BinaryWriter $ico
  $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]1)               # an icon file holding one image
  $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0)  # 256 by 256 (written as 0), no palette
  $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$bytes.Length); $w.Write([uint32]22)
  $w.Write($bytes)
  $w.Flush()
  [IO.File]::WriteAllBytes($path, $ico.ToArray())
}

try {
  $window = Join-Path $PSScriptRoot 'upload-point.ps1'
  if (-not (Test-Path -LiteralPath $window)) { throw ("upload-point.ps1 isn't next to this script, in " + $PSScriptRoot) }
  $copy = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # the brain's copy: <copy>\skills\upload-point
  $icon = $null
  try {
    # Beside the live jobs window's script, out of the brain's copy, so Obsidian Git doesn't commit it.
    $tools = Join-Path (Split-Path $copy -Parent) 'Tools'
    [void](New-Item -ItemType Directory -Force -Path $tools)
    $icon = Join-Path $tools 'upload-point.ico'
    Save-OrbIcon $icon
  } catch { $icon = $null }   # the shortcuts work without it, with PowerShell's icon
  $sendTo = [Environment]::GetFolderPath('SendTo')
  if (-not $sendTo) { $sendTo = Join-Path $env:APPDATA 'Microsoft\Windows\SendTo' }
  $shell = New-Object -ComObject WScript.Shell
  foreach ($lnkPath in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Upload point.lnk'), (Join-Path $sendTo 'My brain.lnk'))) {
    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $lnk.Arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $window + '"'
    $lnk.WorkingDirectory = $copy
    $lnk.Description = 'Drop files and folders here for your brain'
    if ($icon) { $lnk.IconLocation = $icon + ',0' }
    $lnk.Save()
    if (-not (Test-Path -LiteralPath $lnkPath)) { throw ("couldn't save " + $lnkPath) }
  }
  Write-Host 'Upload point ready: "Upload point" on your desktop, and Send to, My brain when you right-click files or folders.'
  exit 0
} catch {
  Write-Host ("The upload point isn't set up: " + $_.Exception.Message)
  exit 1
}
