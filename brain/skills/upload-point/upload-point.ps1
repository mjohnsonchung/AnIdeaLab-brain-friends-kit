# Upload point: a small window for dropping files and folders into the brain.
# Drag them onto it, or right-click them in File Explorer and pick Send to, then My brain. It keeps
# only where each one is: the paths go in a list in the brain's repo on GitHub,
# knowledge/systems/upload-point.md, and an agent sorts them into the brain when the owner says what
# to do (SKILL.md in this folder). Anything on a USB stick or other removable drive is copied to
# C:\AI-Brain-Link\_upload\<date>\ first, since the stick may be gone by the time the agent looks.
# The list is read and written with gh's contents API, never through the local copy, so it can't clash
# with Obsidian Git or unsaved edits. It checks GitHub every 30 seconds, and when the window gets focus,
# so it sees what an agent has taken.
# Started with paths (Send to does that), it adds them; if the window is already open, it hands them
# over and closes. setup-upload-point.ps1 makes the shortcuts. Windows PowerShell 5.1, plain ASCII.
# Windows only for now: a Mac version is still to come (Matt, 31 Oct 2026).

# Before anything else: the paths it was started with, and its own folder (dot-sourcing below resets $args).
$given = @($args | ForEach-Object { "$_".Trim().Trim('"') } | Where-Object { $_ })
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# The work that can take a while runs away from the window, so the window never freezes: taking in
# what was dropped (measuring it, and copying anything on a removable drive), then reading the list on
# GitHub, applying the window's adds and removes, and writing it back. The window dot-sources it with
# no cycle, for its helper functions.
$work = {
  param($cycle)
  $ErrorActionPreference = 'Continue'
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $utf8 = New-Object Text.UTF8Encoding $false
  # One waiting item: - `<path>`: <kind>, <size>, added <when>. A path with a backtick in it gets two.
  $itemRx = '^\s*[-*]\s+(`+)\s?(.+?)\s?\1(?!`)(.*)$'

  function Same-Path([string]$a, [string]$b) {
    return [string]::Equals($a.TrimEnd('\'), $b.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
  }
  function Size-Text([double]$b) {
    if ($b -ge 1GB) { return ($b / 1GB).ToString('0.0', $inv) + ' GB' }
    if ($b -ge 1MB) { return ($b / 1MB).ToString('0.0', $inv) + ' MB' }
    if ($b -ge 1KB) { return ($b / 1KB).ToString('0', $inv) + ' KB' }
    return $b.ToString('0', $inv) + ' bytes'
  }
  function On-Removable([string]$p) {
    try {
      $r = [IO.Path]::GetPathRoot($p)
      if (-not $r -or $r.StartsWith('\\')) { return $false }
      $t = (New-Object IO.DriveInfo $r).DriveType
      return ($t -eq [IO.DriveType]::Removable -or $t -eq [IO.DriveType]::CDRom)
    } catch { return $false }
  }
  if ($null -eq $cycle) { return }

  function Measure-Drop([string]$p) {
    # Its kind and size. A big folder is counted for a few seconds at most, and then says so with a +.
    $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if (-not $i) { return $null }
    if (-not $i.PSIsContainer) { return @{ kind = 'file'; size = (Size-Text $i.Length) } }
    $files = 0; $bytes = 0.0; $more = $false
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $todo = New-Object 'Collections.Generic.Stack[string]'
    $todo.Push($i.FullName)
    while ($todo.Count -gt 0) {
      if ($clock.ElapsedMilliseconds -gt 3000) { $more = $true; break }
      $d = New-Object IO.DirectoryInfo $todo.Pop()
      try { foreach ($f in $d.GetFiles()) { $files++; $bytes += $f.Length } } catch { }
      try {
        foreach ($s in $d.GetDirectories()) {
          if (-not ($s.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $todo.Push($s.FullName) }
        }
      } catch { }
    }
    $kind = if (Test-Path -LiteralPath (Join-Path $i.FullName '.git')) { 'git repo' } else { 'folder' }
    $plus = if ($more) { '+' } else { '' }
    $word = if ($files -eq 1 -and -not $more) { ' file' } else { ' files' }
    return @{ kind = $kind; size = ((Size-Text $bytes) + $plus + ' in ' + $files.ToString('N0', $inv) + $plus + $word) }
  }
  function Copy-In([string]$p) {
    # A copy in _upload\<date>\ next to the brain's copy, under a name nothing there has yet.
    $item = Get-Item -LiteralPath $p -Force -ErrorAction Stop
    $dir = Join-Path $cycle.root ('_upload\' + (Get-Date).ToString('yyyy-MM-dd'))
    [void](New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop)
    $name = $item.Name
    if (-not $name -or $name.Contains(':')) { $name = 'drive-' + $p.Substring(0, 1) }
    $dest = Join-Path $dir $name
    $n = 2
    while (Test-Path -LiteralPath $dest) {
      if ($item.PSIsContainer) { $dest = Join-Path $dir ($name + ' (' + $n + ')') }
      else { $dest = Join-Path $dir ($item.BaseName + ' (' + $n + ')' + $item.Extension) }
      $n++
    }
    Copy-Item -LiteralPath $item.FullName -Destination $dest -Recurse -Force -ErrorAction Stop
    return $dest
  }
  function Line-For([string]$p, $m) {
    $code = if ($p.Contains('`')) { '`` ' + $p + ' ``' } else { '`' + $p + '`' }
    return '- ' + $code + ': ' + $m.kind + ', ' + $m.size + ', added ' + (Get-Date).ToString('d MMM yyyy HH:mm', $inv)
  }
  function Gh([string[]]$a) {
    # gh's output and its errors apart, and its exit code.
    $out = New-Object 'Collections.Generic.List[string]'
    $err = New-Object 'Collections.Generic.List[string]'
    & $cycle.gh @a 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { $err.Add("$_") } else { $out.Add("$_") } }
    return @{ code = $LASTEXITCODE; out = ($out -join "`n"); err = ($err -join "`n") }
  }
  function Problem([string]$err) {
    if ($err -match 'gh auth login|HTTP 401|Bad credentials|not logged in|authentication') { return 'auth' }
    if ($err -match 'HTTP 404|Not Found') { return 'missing' }
    if ($err -match 'HTTP 403') { return 'denied' }
    if ($err -match 'HTTP 409|HTTP 422') { return 'conflict' }
    return 'offline'
  }
  function Read-Note {
    $r = Gh @('api', ('repos/' + $cycle.repo + '/contents/' + $cycle.note))
    if ($r.code -ne 0) {
      $why = Problem $r.err
      if ($why -eq 'missing') { return @{ ok = $true; sha = $null; text = $cycle.blank } }
      return @{ ok = $false; problem = $why; detail = $r.err }
    }
    try {
      $j = $r.out | ConvertFrom-Json
      $text = $utf8.GetString([Convert]::FromBase64String(($j.content -replace '\s', '')))
      return @{ ok = $true; sha = $j.sha; text = $text.TrimStart([char]0xFEFF) }
    } catch { return @{ ok = $false; problem = 'offline'; detail = "$_" } }
  }
  function Write-Note([string]$text, $sha, [string]$message) {
    $body = @{ message = $message; content = [Convert]::ToBase64String($utf8.GetBytes($text)) }
    if ($sha) { $body.sha = $sha }
    $req = Join-Path $env:TEMP ('upload-point-' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($req, ($body | ConvertTo-Json -Compress), $utf8)
    $r = Gh @('api', '-X', 'PUT', ('repos/' + $cycle.repo + '/contents/' + $cycle.note), '--input', $req)
    Remove-Item -LiteralPath $req -Force -ErrorAction SilentlyContinue
    if ($r.code -eq 0) { return @{ ok = $true } }
    return @{ ok = $false; problem = (Problem $r.err); detail = $r.err }
  }
  function Split-Note([string]$text) {
    # The note as lines, and where its Waiting section starts and ends.
    $lines = New-Object 'Collections.Generic.List[string]'
    foreach ($l in ($text -replace "`r`n", "`n").Split("`n")) { $lines.Add($l) }
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s+Waiting\s*$') { $start = $i; break } }
    $end = $lines.Count
    if ($start -ge 0) { for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^#{1,2}\s') { $end = $i; break } } }
    return @{ lines = $lines; start = $start; end = $end }
  }
  function Read-Entries($s) {
    $found = New-Object 'Collections.Generic.List[object]'
    if ($s.start -ge 0) {
      for ($i = $s.start + 1; $i -lt $s.end; $i++) {
        if ($s.lines[$i] -match $itemRx) { $found.Add(@{ path = $Matches[2].Trim(); line = $s.lines[$i].TrimEnd() }) }
      }
    }
    return ,$found
  }
  function Render($s, $entries) {
    # Everything outside the Waiting section stays as it was; inside it, any other lines, then one line per item.
    $out = New-Object 'Collections.Generic.List[string]'
    $upTo = if ($s.start -ge 0) { $s.start } else { $s.lines.Count }
    for ($i = 0; $i -lt $upTo; $i++) { $out.Add($s.lines[$i]) }
    if ($s.start -lt 0) {
      while ($out.Count -and -not $out[$out.Count - 1].Trim()) { $out.RemoveAt($out.Count - 1) }
      $out.Add('')
    }
    $out.Add('## Waiting')
    if ($s.start -ge 0) {
      for ($i = $s.start + 1; $i -lt $s.end; $i++) {
        $l = $s.lines[$i]
        if ($l.Trim() -and $l -notmatch $itemRx -and $l.Trim() -ne 'Nothing waiting.') { $out.Add($l) }
      }
    }
    if ($entries.Count) { foreach ($e in $entries) { $out.Add($e.line) } } else { $out.Add('Nothing waiting.') }
    if ($s.end -lt $s.lines.Count) { $out.Add(''); for ($i = $s.end; $i -lt $s.lines.Count; $i++) { $out.Add($s.lines[$i]) } }
    $text = ($out -join "`n").TrimEnd() + "`n"
    return ([regex]'(?m)^updated:.*$').Replace($text, 'updated: ' + (Get-Date).ToString('d MMM yyyy', $inv), 1)
  }

  $result = @{
    ok = $false; problem = ''; detail = ''; entries = $null; changed = $false; added = 0
    taken = (New-Object 'Collections.Generic.List[object]')
    missing = (New-Object 'Collections.Generic.List[string]')
    notCopied = (New-Object 'Collections.Generic.List[string]')
  }
  # 1. Take in what was dropped.
  foreach ($p in @($cycle.take)) {
    if (-not $p) { continue }
    $path = $p
    if (On-Removable $p) { try { $path = Copy-In $p } catch { $result.notCopied.Add($p) } }
    $m = Measure-Drop $path
    if ($m) { $result.taken.Add(@{ path = $path; line = (Line-For $path $m) }) } else { $result.missing.Add($p) }
  }
  if (-not $cycle.gh) { $result.problem = 'nogh'; return $result }
  if (-not $cycle.repo) { $result.problem = 'norepo'; return $result }
  $adds = New-Object 'Collections.Generic.List[object]'
  foreach ($a in @($cycle.adds)) { if ($a) { $adds.Add($a) } }
  foreach ($t in $result.taken) { $adds.Add($t) }

  # 2. Bring the list on GitHub in line, and write it back if that changed it.
  for ($try = 1; $try -le 4; $try++) {
    $note = Read-Note
    if (-not $note.ok) { $result.problem = $note.problem; $result.detail = $note.detail; return $result }
    $s = Split-Note $note.text
    $entries = New-Object 'Collections.Generic.List[object]'
    $removed = 0
    foreach ($e in (Read-Entries $s)) {
      $off = $false
      foreach ($r in @($cycle.removes)) { if ($r -and (Same-Path $e.path $r)) { $off = $true } }
      if ($off) { $removed++ } else { $entries.Add($e) }
    }
    $added = 0
    foreach ($a in $adds) {
      $have = $false
      foreach ($e in $entries) { if (Same-Path $e.path $a.path) { $have = $true; break } }
      if (-not $have) { $entries.Add($a); $added++ }
    }
    $result.entries = $entries
    if (($added + $removed) -eq 0) { $result.ok = $true; return $result }
    $bits = @()
    if ($added) { $bits += 'added ' + $added }
    if ($removed) { $bits += 'took off ' + $removed }
    $put = Write-Note (Render $s $entries) $note.sha ('Upload point: ' + ($bits -join ', '))
    if ($put.ok) { $result.ok = $true; $result.changed = $true; $result.added = $added; return $result }
    if ($put.problem -ne 'conflict') {
      $result.problem = if ($put.problem -eq 'missing' -or $put.problem -eq 'denied') { 'norepo' } else { $put.problem }
      $result.detail = $put.detail
      return $result
    }
    # The list changed on GitHub since it was read (an agent sorting it, most likely): read it again and redo.
  }
  $result.problem = 'offline'
  $result.detail = 'The list kept changing on GitHub while saving it.'
  return $result
}
. $work $null

# The note as the kit has it, for a brain whose list has gone missing.
$blank = @'
---
about: "What's waiting at the upload point: files and folders the owner dropped on the Upload point window or sent with Send to, My brain, listed by path, for an agent to sort into the brain. Read when the owner mentions dropping something."
tags: [the-brain]
updated: 1 Jan 2026
---
# The upload point

The owner drops files and folders on the Upload point window on their desktop, or sends them with Send to, then My brain. The window lists them here by where they are on the PC, and an agent sorts them into the brain when the owner says what to do: the [upload-point skill](../../skills/upload-point/SKILL.md).

The window rewrites the "Waiting" section through GitHub, so keep its shape: one line per item, as the window writes it, or "Nothing waiting." Take an item's line off once it's sorted.

## Waiting
Nothing waiting.
'@ -replace "`r`n", "`n"

# Which brain this is, from where this script sits: <the brain's copy>\skills\upload-point.
$copy = Split-Path (Split-Path $here -Parent) -Parent
$root = Split-Path $copy -Parent
$notePath = 'knowledge/systems/upload-point.md'
function Find-Tool([string]$name, [string[]]$places) {
  $c = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  foreach ($p in $places) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
  return $null
}
$git = Find-Tool 'git' @("$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
$gh = Find-Tool 'gh' @("$env:ProgramFiles\GitHub CLI\gh.exe", "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe")
$env:GH_PROMPT_DISABLED = '1'
$env:GH_NO_UPDATE_NOTIFIER = '1'
$origin = ''
if ($git) { $origin = "$(& $git -C $copy remote get-url origin 2>$null)".Trim() }
$gitConfig = Join-Path $copy '.git\config'
if (-not $origin -and (Test-Path -LiteralPath $gitConfig)) {
  $m = [regex]::Match([IO.File]::ReadAllText($gitConfig), '(?ms)^\s*\[remote "origin"\][^\[]*?^\s*url\s*=\s*(\S+)')
  if ($m.Success) { $origin = $m.Groups[1].Value }
}
$repo = $null
if ($origin -match 'github\.com[/:]([^/\s]+)/([^/\s]+?)(\.git)?/?$') { $repo = $Matches[1] + '/' + $Matches[2] }

# One window per brain. A second run hands its paths to the open window and closes.
$key = ($copy.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
if ($key.Length -gt 60) { $key = $key.Substring($key.Length - 60) }
$hand = Join-Path $env:TEMP ('upload-point-' + $key)
$wakeName = 'Local\UploadPointWake-' + $key
$mutex = New-Object Threading.Mutex($false, ('Local\UploadPoint-' + $key))
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch { $owned = $true }  # abandoned by a window that ended without letting go
if (-not $owned) {
  $file = $null
  if ($given.Count) {
    try {
      [void](New-Item -ItemType Directory -Force -Path $hand)
      $file = Join-Path $hand ([DateTime]::Now.ToString('yyyyMMddHHmmssfff') + '-' + [guid]::NewGuid().ToString('N') + '.txt')
      [IO.File]::WriteAllLines($file + '.part', [string[]]$given, $utf8)
      [IO.File]::Move($file + '.part', $file)
    } catch { $file = $null }
  }
  try { [void][Threading.EventWaitHandle]::OpenExisting($wakeName).Set() } catch { }
  if ($given.Count) {
    $until = [DateTime]::Now.AddSeconds(8)
    while ($file -and (Test-Path -LiteralPath $file) -and [DateTime]::Now -lt $until) { Start-Sleep -Milliseconds 200 }
    if (-not $file -or (Test-Path -LiteralPath $file)) {
      # The open window didn't take them (it may be stuck): add them through GitHub from here instead.
      if ($file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
      [void](& $work @{ gh = $gh; repo = $repo; note = $notePath; root = $root; blank = $blank; take = $given; adds = @(); removes = @() })
    }
  }
  exit
}

# The look: dark and monospace, like a terminal, in AnIdeaLab's warm dark with one blue accent ------------
[Windows.Forms.Application]::EnableVisualStyles()
function Colour([string]$h) { return [Drawing.ColorTranslator]::FromHtml($h) }
$bg = Colour '#1A1713'; $panel = Colour '#231F1B'; $ink = Colour '#ECE7DE'; $dim = Colour '#B8B2A8'
$accent = Colour '#84AEFA'; $warn = Colour '#E0B15F'
$mono = 'Consolas'
if (-not ((New-Object Drawing.Text.InstalledFontCollection).Families | Where-Object { $_.Name -eq 'Consolas' })) { $mono = 'Courier New' }
$orbFont = New-Object Drawing.Font($mono, [single]10)
$listFont = New-Object Drawing.Font($mono, [single]9.75)
$smallFont = New-Object Drawing.Font($mono, [single]9)

# The orb: a sphere of plain ASCII, lit from the upper left, with bands that show it turning (the ascii-look
# skill's soft ramp). Each frame is worked out once and kept.
$W = 44; $H = 13; $R = 5.2; $aspect = 2.05
$ramp = ' .-:=+*o#%@'
$steps = 48
$orbCache = @{}
function Orb-Cells([int]$k, [int]$lift) {
  $key = [string]$k + '/' + $lift
  if (-not $orbCache.ContainsKey($key)) {
    $a = 2 * [math]::PI * $k / $steps
    $ca = [math]::Cos($a); $sa = [math]::Sin($a)
    $cells = New-Object char[] ($W * $H)
    $cx = ($W - 1) / 2; $cy = ($H - 1) / 2; $top = $ramp.Length - 1
    for ($r = 0; $r -lt $H; $r++) {
      $y = ($cy - $r) / $R
      for ($c = 0; $c -lt $W; $c++) {
        $x = ($c - $cx) / ($R * $aspect)
        $d = $x * $x + $y * $y
        if ($d -gt 1) { $cells[$r * $W + $c] = ' '; continue }
        $z = [math]::Sqrt(1 - $d)
        $lit = -0.45 * $x + 0.55 * $y + 0.70 * $z
        if ($lit -lt 0) { $lit = 0 }
        $lon = [math]::Atan2($x * $ca + $z * $sa, $z * $ca - $x * $sa)
        $v = (0.12 + 0.88 * $lit) * (0.55 + 0.225 * (1 + [math]::Cos(4 * $lon)))
        $i = [int][math]::Floor($v * $top + 0.5) + $lift
        if ($i -gt $top) { $i = $top } elseif ($i -lt 1) { $i = 1 }
        $cells[$r * $W + $c] = $ramp[$i]
      }
    }
    $orbCache[$key] = $cells
  }
  return ,($orbCache[$key])
}
function Put($cells, [double]$rho, [double]$t, [char]$ch) {
  # A mark at distance rho (1 is the orb's edge) and angle t from the middle, if it's on the grid.
  $c = [int][math]::Round(($W - 1) / 2 + $rho * [math]::Cos($t) * $R * $aspect)
  $r = [int][math]::Round(($H - 1) / 2 - $rho * [math]::Sin($t) * $R)
  if ($c -ge 0 -and $c -lt $W -and $r -ge 0 -and $r -lt $H) { $cells[$r * $W + $c] = $ch }
}
function Join-Cells($cells) {
  $rows = New-Object 'string[]' $H
  for ($r = 0; $r -lt $H; $r++) { $rows[$r] = [string]::new($cells, $r * $W, $W) }
  return [string]::Join("`r`n", $rows)
}
function Orb-Icon {
  $bmp = New-Object Drawing.Bitmap 32, 32
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $shape = New-Object Drawing.Drawing2D.GraphicsPath
  $shape.AddEllipse(2, 2, 28, 28)
  $fill = New-Object Drawing.Drawing2D.PathGradientBrush $shape
  $fill.CenterPoint = New-Object Drawing.PointF(12, 11)
  $fill.CenterColor = Colour '#D6E4FD'
  $fill.SurroundColors = [Drawing.Color[]]@((Colour '#2F4F86'))
  $g.FillPath($fill, $shape)
  $g.Dispose()
  return [Drawing.Icon]::FromHandle($bmp.GetHicon())
}

# The window ---------------------------------------------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.Text = 'Upload point'
$form.BackColor = $bg
$form.ForeColor = $ink
$form.Font = $smallFont
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
try { $form.Icon = Orb-Icon } catch { }

$orb = New-Object Windows.Forms.Label
$orb.Font = $orbFont
$orb.ForeColor = $accent
$orb.BackColor = $bg
$orb.UseMnemonic = $false
$orb.AutoSize = $false
$orb.TextAlign = 'TopLeft'
# Double-buffered, so the turning orb doesn't flicker (a Label doesn't offer it publicly).
try { [Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($orb, $true, $null) } catch { }

$hint = New-Object Windows.Forms.Label
$hint.ForeColor = $dim
$hint.BackColor = $bg
$hint.UseMnemonic = $false
$hint.TextAlign = 'MiddleCenter'

$list = New-Object Windows.Forms.ListBox
$list.Font = $listFont
$list.BackColor = $panel
$list.ForeColor = $ink
$list.BorderStyle = 'None'
$list.IntegralHeight = $false
$list.SelectionMode = 'MultiExtended'

$status = New-Object Windows.Forms.Label
$status.ForeColor = $dim
$status.BackColor = $bg
$status.UseMnemonic = $false
$tip = New-Object Windows.Forms.ToolTip

# Sizes from the font, so it lays out the same at any scaling.
$m = 14
$orbWide = [Windows.Forms.TextRenderer]::MeasureText(('@' * $W), $orbFont).Width
$orbHigh = [Windows.Forms.TextRenderer]::MeasureText((Join-Cells (Orb-Cells 0 0)), $orbFont).Height
$orb.Size = New-Object Drawing.Size(($orbWide + 6), ($orbHigh + 2))
$width = [math]::Max(400, $orb.Width + 2 * $m)
$lineH = [Windows.Forms.TextRenderer]::MeasureText('Ag', $smallFont).Height
$orb.Location = New-Object Drawing.Point([int](($width - $orb.Width) / 2), 10)
$hint.SetBounds($m, $orb.Bottom + 2, $width - 2 * $m, 2 * $lineH + 4)
$list.SetBounds($m, $hint.Bottom + 6, $width - 2 * $m, 10 * $list.ItemHeight + 4)
$status.SetBounds($m, $list.Bottom + 8, $width - 2 * $m, 3 * $lineH + 4)
$form.ClientSize = New-Object Drawing.Size($width, ($status.Bottom + 10))
$form.Controls.AddRange(@($orb, $hint, $list, $status))
$charW = [Windows.Forms.TextRenderer]::MeasureText('M', $listFont, (New-Object Drawing.Size(100, 100)), [Windows.Forms.TextFormatFlags]::NoPadding).Width
$nameW = [math]::Max(12, [int][math]::Floor(($list.ClientSize.Width - 4) / $charW) - 23)

# What the window holds --------------------------------------------------------------------------------
$script:entries = New-Object 'Collections.Generic.List[object]'   # the list on GitHub, as last read
$script:queue = New-Object 'Collections.Generic.List[string]'     # dropped, not taken in yet
$script:adds = New-Object 'Collections.Generic.List[object]'      # taken in, not on GitHub yet
$script:removes = New-Object 'Collections.Generic.List[string]'   # taken off here, not on GitHub yet
$script:shown = New-Object 'Collections.Generic.List[string]'     # the path of each row in the list
$script:running = $null
$script:problem = ''
$script:checkNow = $true
$script:lastTry = [DateTime]::MinValue
$script:lastChange = [DateTime]::MinValue
$script:lastScan = [DateTime]::MinValue
$script:lastRows = $null
$script:started = $false
$script:closing = $false
$script:closingAt = [DateTime]::MinValue
$script:quitting = $false
$script:mode = 'idle'
$script:modeAt = [DateTime]::Now
$script:k = 0
$script:tick = 0
$script:fix = ''
$script:rs = [runspacefactory]::CreateRunspace()
$script:rs.Open()
$script:wake = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, $wakeName)

function Pending { return ($script:queue.Count + $script:adds.Count + $script:removes.Count) }
function Say([string]$Text, [string]$Fix = '', [string]$Detail = '', [switch]$Problem) {
  $status.Text = $Text
  $status.ForeColor = if ($Problem) { $warn } else { $dim }
  $script:fix = $Fix
  $status.Cursor = if ($Fix) { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Default }
  $tipText = if ($Detail) { $Detail } elseif ($Fix) { 'Click to copy: ' + $Fix } else { '' }
  $tip.SetToolTip($status, $tipText)
}
function Set-Mode([string]$mode) {
  $script:mode = $mode
  $script:modeAt = [DateTime]::Now
  $orb.ForeColor = if ($mode -eq 'done') { $ink } else { $accent }
}
function Visible-Items {
  # What the list shows: the list on GitHub less what was taken off here, then what's on its way.
  $out = New-Object 'Collections.Generic.List[object]'
  $seen = @{}
  foreach ($e in $script:entries) {
    $off = $false
    foreach ($r in $script:removes) { if (Same-Path $e.path $r) { $off = $true; break } }
    if (-not $off -and -not $seen.ContainsKey($e.path.ToLowerInvariant())) { $out.Add($e); $seen[$e.path.ToLowerInvariant()] = $true }
  }
  foreach ($a in $script:adds) { if (-not $seen.ContainsKey($a.path.ToLowerInvariant())) { $out.Add($a); $seen[$a.path.ToLowerInvariant()] = $true } }
  foreach ($p in $script:queue) { if (-not $seen.ContainsKey($p.ToLowerInvariant())) { $out.Add(@{ path = $p; line = '' }); $seen[$p.ToLowerInvariant()] = $true } }
  return ,$out
}
function Row-Text($item) {
  $name = [IO.Path]::GetFileName($item.path.TrimEnd('\'))
  if (-not $name) { $name = $item.path }
  $kind = 'file'; $size = '...'
  if ($item.line -and $item.line -match $itemRx) {
    $rest = $Matches[3]
    if ($rest -match '^\s*:\s*([^,]+),\s*(.+?)(,\s*added\s.*)?$') { $kind = $Matches[1].Trim(); $size = ($Matches[2] -split ' in ')[0].Trim() }
  } elseif (Test-Path -LiteralPath $item.path -PathType Container) { $kind = 'folder' }
  if ($name.Length -gt $nameW) { $name = $name.Substring(0, $nameW - 1) + '~' }
  if ($kind.Length -gt 8) { $kind = $kind.Substring(0, 8) }
  return $name.PadRight($nameW) + ' ' + $kind.PadRight(8) + ' ' + $size.PadLeft(10)
}
function Show-List {
  $items = Visible-Items
  $rows = New-Object 'Collections.Generic.List[string]'
  foreach ($it in $items) { $rows.Add((Row-Text $it)) }
  $joined = $rows -join "`n"
  if ($joined -ne $script:lastRows) {
    $keep = @{}
    foreach ($i in $list.SelectedIndices) { if ($i -lt $script:shown.Count) { $keep[$script:shown[$i].ToLowerInvariant()] = $true } }
    $list.BeginUpdate()
    $list.Items.Clear()
    $script:shown = New-Object 'Collections.Generic.List[string]'
    for ($i = 0; $i -lt $rows.Count; $i++) { [void]$list.Items.Add($rows[$i]); $script:shown.Add($items[$i].path) }
    for ($i = 0; $i -lt $script:shown.Count; $i++) { if ($keep.ContainsKey($script:shown[$i].ToLowerInvariant())) { $list.SetSelected($i, $true) } }
    $list.EndUpdate()
    $script:lastRows = $joined
  }
  $n = $items.Count
  $first = if ($n) { [string]$n + ' waiting for your brain. Drop more here,' } else { 'Drop files or folders here,' }
  $hint.Text = $first + "`r`n" + 'or right-click them: Send to, My brain.'
}
function Idle-Text {
  $n = (Visible-Items).Count
  if ($n) { return [string]$n + ' waiting. Tell Claude what to do with them.' }
  return 'Nothing waiting.'
}
function Add-Paths($paths) {
  $n = 0
  foreach ($raw in @($paths)) {
    $p = "$raw".Trim().Trim('"')
    if (-not $p) { continue }
    try { $p = [IO.Path]::GetFullPath($p) } catch { }
    if ($p.Length -gt 3) { $p = $p.TrimEnd('\') }
    $undo = $false
    for ($i = $script:removes.Count - 1; $i -ge 0; $i--) { if (Same-Path $script:removes[$i] $p) { $script:removes.RemoveAt($i); $undo = $true } }
    if ($undo) { $n++; continue }
    $known = $false
    foreach ($it in (Visible-Items)) { if (Same-Path $it.path $p) { $known = $true; break } }
    if ($known) { continue }
    $script:queue.Add($p)
    $n++
  }
  if ($n) {
    $script:lastChange = [DateTime]::Now
    Set-Mode 'take'
    Show-List
    Say 'Taking it in...'
  }
}
function Remove-Selected {
  $paths = @(foreach ($i in $list.SelectedIndices) { if ($i -lt $script:shown.Count) { $script:shown[$i] } })
  if (-not $paths.Count) { return }
  foreach ($p in $paths) {
    for ($i = $script:queue.Count - 1; $i -ge 0; $i--) { if (Same-Path $script:queue[$i] $p) { $script:queue.RemoveAt($i) } }
    for ($i = $script:adds.Count - 1; $i -ge 0; $i--) { if (Same-Path $script:adds[$i].path $p) { $script:adds.RemoveAt($i) } }
    $onList = $false
    foreach ($e in $script:entries) { if (Same-Path $e.path $p) { $onList = $true; break } }
    # On GitHub, or maybe on its way there right now: take it off there too.
    if ($onList -or $script:running) {
      $already = $false
      foreach ($r in $script:removes) { if (Same-Path $r $p) { $already = $true } }
      if (-not $already) { $script:removes.Add($p) }
    }
  }
  $script:lastChange = [DateTime]::Now
  Show-List
  if ($paths.Count -eq 1) { Say 'Took it off the list. The file stays where it is.' }
  else { Say ('Took ' + $paths.Count + ' off the list. The files stay where they are.') }
}
function Show-Selected {
  if ($list.SelectedIndices.Count -lt 1) { return }
  $p = $script:shown[$list.SelectedIndices[0]]
  if (Test-Path -LiteralPath $p) { Start-Process explorer.exe -ArgumentList ('/select,"' + $p + '"') }
  else { Say ("It isn't there any more: " + $p) -Problem }
}
function Bring-Up {
  if (-not $form.Visible) { return }
  if ($form.WindowState -eq 'Minimized') { $form.WindowState = 'Normal' }
  $form.Activate()
}
function Take-Handoffs {
  # Paths from a second run (Send to while the window is open): a file each, and a wake-up.
  $woke = $false
  try { $woke = $script:wake.WaitOne(0) } catch { }
  $now = [DateTime]::Now
  if (-not $woke -and ($now - $script:lastScan).TotalSeconds -lt 2) { return }
  $script:lastScan = $now
  if (Test-Path -LiteralPath $hand) {
    foreach ($f in @(Get-ChildItem -LiteralPath $hand -Filter '*.txt' -ErrorAction SilentlyContinue | Sort-Object Name)) {
      $paths = $null
      try { $paths = [IO.File]::ReadAllLines($f.FullName) } catch { continue }
      Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
      Add-Paths $paths
    }
  }
  if ($woke) { Bring-Up }
}
function Start-Cycle {
  if ($script:running) { return }
  $now = [DateTime]::Now
  $since = ($now - $script:lastTry).TotalSeconds
  $quiet = ($now - $script:lastChange).TotalSeconds
  $wait = if ($script:problem -eq 'offline') { 10 } elseif ($script:problem) { 30 } else { 0 }
  $due = $script:checkNow -or $since -ge 30
  if ((Pending) -gt 0 -and ($quiet -ge 1.5 -or $script:closing) -and $since -ge $wait) { $due = $true }
  if (-not $due) { return }
  $script:checkNow = $false
  $script:lastTry = $now
  $sent = @{ take = $script:queue.ToArray(); adds = $script:adds.ToArray(); removes = $script:removes.ToArray() }
  $in = @{ gh = $gh; repo = $repo; note = $notePath; root = $root; blank = $blank; take = $sent.take; adds = $sent.adds; removes = $sent.removes }
  $ps = [PowerShell]::Create()
  $ps.Runspace = $script:rs
  [void]$ps.AddScript($work.ToString()).AddArgument($in)
  $script:running = @{ ps = $ps; handle = $ps.BeginInvoke(); sent = $sent }
  foreach ($p in $sent.take) { if (On-Removable $p) { Say 'Copying from the USB stick to this PC...'; break } }
}
function Read-Cycle {
  $j = $script:running
  if (-not $j -or -not $j.handle.IsCompleted) { return }
  $script:running = $null
  $r = $null
  try {
    $out = $j.ps.EndInvoke($j.handle)
    if ($out.Count) { $r = $out[$out.Count - 1] }
  } catch { $r = @{ ok = $false; problem = 'offline'; detail = $_.Exception.Message } }
  try { $j.ps.Dispose() } catch { }
  if ($r -is [Management.Automation.PSObject]) { $r = $r.psobject.BaseObject }   # not .BaseObject: on a hashtable that reads a key
  if ($r -isnot [hashtable]) { $r = @{ ok = $false; problem = 'offline'; detail = 'The background work gave no answer.' } }
  foreach ($p in $j.sent.take) { [void]$script:queue.Remove($p) }
  if ($r.ok) {
    foreach ($a in $j.sent.adds) { [void]$script:adds.Remove($a) }
    foreach ($p in $j.sent.removes) { [void]$script:removes.Remove($p) }
    $before = $script:entries
    $script:entries = New-Object 'Collections.Generic.List[object]'
    foreach ($e in $r.entries) { $script:entries.Add($e) }
    # Gone from the list on GitHub, and not taken off here: an agent has sorted it.
    $gone = 0
    if ($script:started) {
      foreach ($o in $before) {
        $still = $false
        foreach ($e in $script:entries) { if (Same-Path $e.path $o.path) { $still = $true; break } }
        foreach ($p in $j.sent.removes) { if (Same-Path $p $o.path) { $still = $true } }
        if (-not $still) { $gone++ }
      }
    }
    $wasProblem = $script:problem -or -not $script:started
    $script:started = $true
    $script:problem = ''
    $left = (Visible-Items).Count
    if ($gone -and -not $left) { Set-Mode 'done'; Say 'Your brain has them.' }
    elseif ($gone) { Say ('Your brain has taken ' + $gone + '. ' + $left + ' still waiting.') }
    elseif ($r.added) { Say 'Sent. Tell Claude what to do with them.' }
    elseif ($r.changed) { Say 'Taken off the list on GitHub too.' }
    elseif ($wasProblem) { Say (Idle-Text) }
  } else {
    foreach ($t in $r.taken) { $script:adds.Add($t) }
    $script:problem = $r.problem
    $keep = if ((Pending) -gt 0) { ' Nothing is lost: it keeps trying.' } else { '' }
    switch ($r.problem) {
      'nogh' { Say "GitHub's gh tool isn't on this PC, so the list can't be sent. Click here to copy the fix, then paste it into PowerShell." -Fix 'winget install --id GitHub.cli -e' -Problem }
      'auth' { Say "GitHub isn't signed in on this PC. Click here to copy the fix, then paste it into PowerShell." -Fix 'gh auth login --hostname github.com --git-protocol https --web --scopes workflow' -Problem }
      'norepo' {
        if ($repo) { Say ("Can't save the list to " + $repo + " on GitHub. Is gh signed in to your own account? Click here to copy a check.") -Fix 'gh auth status' -Detail $r.detail -Problem }
        else { Say "Can't tell which brain this is: this window has to run from the brain's own folder, in skills\upload-point." -Problem }
      }
      default { Say ("Can't reach GitHub, will try again." + $keep) -Detail $r.detail -Problem }
    }
  }
  if ($r.missing.Count) { Say ("Couldn't find " + ((@($r.missing) | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ', ') + ' any more.') -Problem }
  if ($r.notCopied.Count) { Say ("Couldn't copy " + ((@($r.notCopied) | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ', ') + " from the drive, so it's listed where it is.") -Problem }
  Show-List
}
function Animate {
  if ($form.WindowState -eq 'Minimized' -or -not $form.Visible) { return }
  $script:tick++
  $q = 0.0
  $lift = 0
  if ($script:mode -eq 'take') {
    $q = ([DateTime]::Now - $script:modeAt).TotalSeconds / 1.4
    if ($q -ge 1) { Set-Mode 'idle' } else { $script:k = ($script:k + 2) % $steps }
  } elseif ($script:mode -eq 'done') {
    $q = ([DateTime]::Now - $script:modeAt).TotalSeconds / 2.4
    if ($q -ge 1) { Set-Mode 'idle' } else { $script:k = ($script:k + 1) % $steps; $lift = if ($q -lt 0.5) { 2 } else { 1 } }
  }
  if ($script:mode -eq 'idle') {
    if ($script:tick % 3) { return }   # idle: a step every third tick, a slow turn
    $script:k = ($script:k + 1) % $steps
  }
  $cells = (Orb-Cells $script:k $lift).Clone()
  if ($script:mode -eq 'take') {
    # What was dropped falls into the orb.
    $rho = 2.0 - 1.15 * $q
    $ch = if ($rho -gt 1.02) { '*' } else { '.' }
    for ($j = 0; $j -lt 8; $j++) { Put $cells $rho ($j * [math]::PI / 4 + $q * 1.6) $ch }
  } elseif ($script:mode -eq 'done') {
    # Your brain has them: a ring goes out from the orb.
    $rho = 1.08 + 0.85 * $q
    $ch = if ($q -lt 0.6) { '*' } else { '.' }
    for ($j = 0; $j -lt 40; $j++) { Put $cells $rho ($j * [math]::PI / 20) $ch }
  }
  $orb.Text = Join-Cells $cells
}

# What it does when ---------------------------------------------------------------------------------------
$onEnter = {
  param($s, $e)
  if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
    # A link, not a copy or a move: the file stays where it is.
    if (([int]$e.AllowedEffect -band [int][Windows.Forms.DragDropEffects]::Link) -ne 0) { $e.Effect = 'Link' } else { $e.Effect = 'Copy' }
  } else { $e.Effect = 'None' }
}
$onDrop = {
  param($s, $e)
  try { Add-Paths @($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) } catch { Say ('Something went wrong: ' + $_.Exception.Message) -Problem }
}
foreach ($c in @($form, $orb, $hint, $list, $status)) { $c.AllowDrop = $true; $c.Add_DragEnter($onEnter); $c.Add_DragDrop($onDrop) }

$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Remove', $null, { Remove-Selected })
[void]$menu.Items.Add('Show in File Explorer', $null, { Show-Selected })
$menu.Add_Opening({ param($s, $e) if ($list.SelectedIndices.Count -lt 1) { $e.Cancel = $true } })
$list.ContextMenuStrip = $menu
$list.Add_MouseDown({
  param($s, $e)
  if ($e.Button -eq 'Right') {
    $i = $list.IndexFromPoint($e.Location)
    if ($i -ge 0 -and -not $list.GetSelected($i)) { $list.ClearSelected(); $list.SetSelected($i, $true) }
  }
})
$list.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Delete') { Remove-Selected; $e.Handled = $true } })

$more = New-Object Windows.Forms.ContextMenuStrip
$onTop = New-Object Windows.Forms.ToolStripMenuItem('Keep on top')
$onTop.CheckOnClick = $true
$onTop.Add_CheckedChanged({ $form.TopMost = $onTop.Checked })
[void]$more.Items.Add($onTop)
[void]$more.Items.Add('See the list on GitHub', $null, { if ($repo) { Start-Process ('https://github.com/' + $repo + '/blob/main/' + $notePath) } })
$orb.ContextMenuStrip = $more
$hint.ContextMenuStrip = $more

$status.Add_Click({
  if ($script:fix) {
    try { [Windows.Forms.Clipboard]::SetText($script:fix); Say 'Copied. Paste it into PowerShell, then come back to this window.' } catch { }
  }
})
$form.Add_Activated({ if (([DateTime]::Now - $script:lastTry).TotalSeconds -gt 5) { $script:checkNow = $true } })
$form.Add_FormClosing({
  param($s, $e)
  if ($script:quitting -or "$($e.CloseReason)" -ne 'UserClosing' -or (Pending) -eq 0) { return }
  if ($script:problem) {
    $answer = [Windows.Forms.MessageBox]::Show(([string](Pending) + " change(s) aren't on GitHub yet, so your brain won't see them. Close anyway?"), 'Upload point', 'YesNo', 'Warning')
    if ("$answer" -ne 'Yes') { $e.Cancel = $true }
    return
  }
  # Send what's left first, out of sight, then close.
  $e.Cancel = $true
  $script:closing = $true
  $script:closingAt = [DateTime]::Now
  $form.Hide()
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 120
$timer.Add_Tick({
  try {
    Animate
    Take-Handoffs
    Read-Cycle
    Start-Cycle
    if ($script:closing) {
      if (-not $script:running -and (Pending) -eq 0) { $script:quitting = $true; $timer.Stop(); $form.Close() }
      elseif (-not $script:running -and $script:problem) { $script:closing = $false; $form.Show(); Bring-Up }
      elseif (([DateTime]::Now - $script:closingAt).TotalSeconds -gt 90) { $script:quitting = $true; $timer.Stop(); $form.Close() }
    }
  } catch {
    Say ('Something went wrong: ' + $_.Exception.Message) -Problem
  }
})
$form.Add_Shown({ $form.Activate() })

$orb.Text = Join-Cells (Orb-Cells 0 0)
Show-List
Say 'Checking GitHub...'
Add-Paths $given
$timer.Start()
[Windows.Forms.Application]::Run($form)
$timer.Stop()
if ($script:running) { try { $script:running.ps.Stop() } catch { } }
try { $mutex.ReleaseMutex() } catch { }
try { $script:rs.Dispose() } catch { }
exit 0
