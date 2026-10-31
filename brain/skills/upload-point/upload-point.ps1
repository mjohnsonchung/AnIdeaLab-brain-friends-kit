# Upload point: a plain window for dropping files and folders into the brain.
# Drag them onto the window, or right-click them in File Explorer and pick Send to, then My brain. It
# keeps only where each one is: the paths go in a list in the brain's repo on GitHub,
# knowledge/systems/upload-point.md, and an agent sorts them into the brain when the owner says what to
# do (SKILL.md in this folder). Anything on a USB stick or other removable drive is copied to
# C:\AI-Brain-Link\_upload\<date>\ first, since the stick may be gone by the time the agent looks.
# The list is read and written with gh's contents API, never through the local copy, so it can't clash
# with Obsidian Git or unsaved edits.
# Started with paths (Send to does that), it adds them, says so in a message box and closes; an open
# window picks them up within 30 seconds. Plain on purpose (Matt, 1 Nov 2026: "Just make it a
# minimalist window... Something cheap, something reliable"). setup-upload-point.ps1 makes the shortcuts.
# Windows PowerShell 5.1, plain ASCII. Windows only for now: a Mac version is still to come.

$given = @($args | ForEach-Object { "$_".Trim().Trim('"') } | Where-Object { $_ })
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$inv = [Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object Text.UTF8Encoding $false

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

# One waiting item: - `<path>`: <kind>, <size>, added <when>. A path with a backtick in it gets two.
$itemRx = '^\s*[-*]\s+(`+)\s?(.+?)\s?\1(?!`)(.*)$'

# Taking in what was dropped ----------------------------------------------------------------------------
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
function Measure-Drop([string]$p) {
  # Its kind and size. A big folder is counted for a few seconds at most, and then says so with a +.
  $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if (-not $i) { return $null }
  if (-not $i.PSIsContainer) { return 'file, ' + (Size-Text $i.Length) }
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
  return $kind + ', ' + (Size-Text $bytes) + $plus + ' in ' + $files.ToString('N0', $inv) + $plus + $word
}
function Copy-In([string]$p) {
  # A copy in _upload\<date>\ next to the brain's copy, under a name nothing there has yet.
  $item = Get-Item -LiteralPath $p -Force -ErrorAction Stop
  $dir = Join-Path $root ('_upload\' + (Get-Date).ToString('yyyy-MM-dd'))
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
function Take-In($paths) {
  # Each dropped path as a line for the list, or a note of why it couldn't be.
  $lines = New-Object 'Collections.Generic.List[object]'
  $trouble = New-Object 'Collections.Generic.List[string]'
  foreach ($raw in @($paths)) {
    $p = "$raw".Trim().Trim('"')
    if (-not $p) { continue }
    try { $p = [IO.Path]::GetFullPath($p) } catch { }
    if ($p.Length -gt 3) { $p = $p.TrimEnd('\') }
    if (On-Removable $p) {
      try { $p = Copy-In $p } catch { $trouble.Add("Couldn't copy " + [IO.Path]::GetFileName($p) + " off the drive, so it's listed where it is.") }
    }
    $what = Measure-Drop $p
    if (-not $what) { $trouble.Add("Couldn't find " + $p); continue }
    $code = if ($p.Contains('`')) { '`` ' + $p + ' ``' } else { '`' + $p + '`' }
    $lines.Add(@{ path = $p; line = ('- ' + $code + ': ' + $what + ', added ' + (Get-Date).ToString('d MMM yyyy HH:mm', $inv)) })
  }
  return @{ lines = $lines; trouble = $trouble }
}

# The list on GitHub ------------------------------------------------------------------------------------
function Gh([string[]]$a) {
  $out = New-Object 'Collections.Generic.List[string]'
  $err = New-Object 'Collections.Generic.List[string]'
  & $gh @a 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { $err.Add("$_") } else { $out.Add("$_") } }
  return @{ code = $LASTEXITCODE; out = ($out -join "`n"); err = ($err -join "`n") }
}
function Problem([string]$err) {
  if ($err -match 'gh auth login|HTTP 401|Bad credentials|not logged in|authentication') { return 'auth' }
  if ($err -match 'HTTP 404|Not Found|HTTP 403') { return 'norepo' }
  if ($err -match 'HTTP 409|HTTP 422') { return 'conflict' }
  return 'offline'
}
function Split-Note([string]$text) {
  # The note as lines, and where its Waiting section starts and ends.
  $lines = New-Object 'Collections.Generic.List[string]'
  foreach ($l in ($text -replace "`r`n", "`n").Split("`n")) { $lines.Add($l) }
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##\s+Waiting\s*$') { $start = $i; break } }
  $end = $lines.Count
  if ($start -ge 0) { for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^#{1,2}\s') { $end = $i; break } } }
  $entries = New-Object 'Collections.Generic.List[object]'
  if ($start -ge 0) {
    for ($i = $start + 1; $i -lt $end; $i++) {
      if ($lines[$i] -match $itemRx) { $entries.Add(@{ path = $Matches[2].Trim(); line = $lines[$i].TrimEnd() }) }
    }
  }
  return @{ lines = $lines; start = $start; end = $end; entries = $entries }
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
function Sync($adds, $removes) {
  # Reads the list on GitHub, applies the adds and removes, and writes it back if that changed it.
  if (-not $gh) { return @{ ok = $false; problem = 'nogh' } }
  if (-not $repo) { return @{ ok = $false; problem = 'nobrain' } }
  $url = 'repos/' + $repo + '/contents/' + $notePath
  for ($try = 1; $try -le 4; $try++) {
    $r = Gh @('api', $url)
    $sha = $null; $text = $blank
    if ($r.code -ne 0) {
      $why = Problem $r.err
      if ($r.err -notmatch 'HTTP 404|Not Found') { return @{ ok = $false; problem = $why; detail = $r.err } }
    } else {
      try {
        $j = $r.out | ConvertFrom-Json
        $sha = $j.sha
        $text = $utf8.GetString([Convert]::FromBase64String(($j.content -replace '\s', ''))).TrimStart([char]0xFEFF)
      } catch { return @{ ok = $false; problem = 'offline'; detail = "$_" } }
    }
    $s = Split-Note $text
    $entries = New-Object 'Collections.Generic.List[object]'
    $removed = 0
    foreach ($e in $s.entries) {
      $off = $false
      foreach ($p in @($removes)) { if ($p -and (Same-Path $e.path $p)) { $off = $true } }
      if ($off) { $removed++ } else { $entries.Add($e) }
    }
    $added = 0
    foreach ($a in @($adds)) {
      if (-not $a) { continue }
      $have = $false
      foreach ($e in $entries) { if (Same-Path $e.path $a.path) { $have = $true; break } }
      if (-not $have) { $entries.Add($a); $added++ }
    }
    if (-not ($added + $removed)) { return @{ ok = $true; entries = $entries; added = 0 } }
    $bits = @()
    if ($added) { $bits += 'added ' + $added }
    if ($removed) { $bits += 'took off ' + $removed }
    $body = @{ message = ('Upload point: ' + ($bits -join ', ')); content = [Convert]::ToBase64String($utf8.GetBytes((Render $s $entries))) }
    if ($sha) { $body.sha = $sha }
    $req = Join-Path $env:TEMP ('upload-point-' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($req, ($body | ConvertTo-Json -Compress), $utf8)
    $w = Gh @('api', '-X', 'PUT', $url, '--input', $req)
    Remove-Item -LiteralPath $req -Force -ErrorAction SilentlyContinue
    if ($w.code -eq 0) { return @{ ok = $true; entries = $entries; added = $added } }
    $why = Problem $w.err
    if ($why -ne 'conflict') { return @{ ok = $false; problem = $why; detail = $w.err } }
    # The list changed on GitHub since it was read (an agent sorting it, most likely): read it again.
  }
  return @{ ok = $false; problem = 'offline'; detail = 'The list kept changing on GitHub while saving it.' }
}
function Problem-Text($r) {
  switch ($r.problem) {
    'nogh' { return @("GitHub's gh tool isn't on this PC. Click here to copy the fix, then paste it into PowerShell.", 'winget install --id GitHub.cli -e') }
    'auth' { return @("GitHub isn't signed in on this PC. Click here to copy the fix, then paste it into PowerShell.", 'gh auth login --hostname github.com --git-protocol https --web --scopes workflow') }
    'norepo' { return @("Can't save the list to $repo on GitHub. Is gh signed in to your own account? Click here to copy a check.", 'gh auth status') }
    'nobrain' { return @("Can't tell which brain this is: this window has to run from the brain's own folder, in skills\upload-point.", '') }
    default { return @("Can't reach GitHub. It will try again.", '') }
  }
}

# Started by Send to: add them and close, no window ------------------------------------------------------
if ($given.Count) {
  $t = Take-In $given
  $msg = @($t.trouble)
  if ($t.lines.Count) {
    $r = Sync $t.lines @()
    if ($r.ok) { $msg = @('Sent to your brain: ' + $t.lines.Count + '. Tell Claude what to do with them.') + $msg }
    else { $msg = @('Not sent. ' + (Problem-Text $r)[0], (Problem-Text $r)[1]) + $msg }
  }
  [void][Windows.Forms.MessageBox]::Show((($msg | Where-Object { $_ }) -join "`r`n`r`n"), 'Upload point')
  exit 0
}

# The window --------------------------------------------------------------------------------------------
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Upload point'
$form.Size = New-Object Drawing.Size(520, 360)
$form.StartPosition = 'CenterScreen'
$form.AllowDrop = $true

$top = New-Object Windows.Forms.Label
$top.Dock = 'Top'
$top.Height = 40
$top.TextAlign = 'MiddleCenter'
$top.UseMnemonic = $false
$top.Text = 'Drop files or folders here, or right-click them: Send to, My brain.'

$list = New-Object Windows.Forms.ListBox
$list.Dock = 'Fill'
$list.IntegralHeight = $false
$list.HorizontalScrollbar = $true
$list.SelectionMode = 'MultiExtended'
$list.AllowDrop = $true

$status = New-Object Windows.Forms.Label
$status.Dock = 'Bottom'
$status.Height = 44
$status.Padding = New-Object Windows.Forms.Padding(6, 4, 6, 4)
$status.UseMnemonic = $false
$form.Controls.AddRange(@($list, $top, $status))

$script:entries = New-Object 'Collections.Generic.List[object]'   # the list on GitHub, as last read
$script:adds = New-Object 'Collections.Generic.List[object]'      # dropped here, not on GitHub yet
$script:removes = New-Object 'Collections.Generic.List[string]'   # taken off here, not on GitHub yet
$script:shown = @()
$script:fix = ''
$script:last = [DateTime]::MinValue

function Say([string]$text, [string]$fix = '') {
  $status.Text = $text
  $status.ForeColor = if ($fix -or $text -like "Can't*" -or $text -like 'Not *') { [Drawing.Color]::DarkRed } else { [Drawing.SystemColors]::ControlText }
  $status.Cursor = if ($fix) { [Windows.Forms.Cursors]::Hand } else { [Windows.Forms.Cursors]::Default }
  $script:fix = $fix
  $status.Refresh()
}
function Show-List {
  $items = @()
  foreach ($e in $script:entries) {
    $off = $false
    foreach ($p in $script:removes) { if (Same-Path $e.path $p) { $off = $true } }
    if (-not $off) { $items += $e }
  }
  foreach ($a in $script:adds) {
    $have = $false
    foreach ($i in $items) { if (Same-Path $i.path $a.path) { $have = $true } }
    if (-not $have) { $items += $a }
  }
  $list.BeginUpdate()
  $list.Items.Clear()
  foreach ($i in $items) {
    $rest = if ($i.line -match $itemRx) { $Matches[3] -replace ',\s*added\s.*$', '' } else { '' }
    [void]$list.Items.Add($i.path + $rest)
  }
  $list.EndUpdate()
  $script:shown = @($items | ForEach-Object { $_.path })
  return $items.Count
}
function Send-Now {
  $script:last = [DateTime]::Now
  if ($script:adds.Count -or $script:removes.Count) { Say 'Sending...' }
  $form.Cursor = [Windows.Forms.Cursors]::WaitCursor
  $r = Sync $script:adds.ToArray() $script:removes.ToArray()
  $form.Cursor = [Windows.Forms.Cursors]::Default
  if ($r.ok) {
    $script:adds.Clear(); $script:removes.Clear()
    $script:entries = $r.entries
    $n = Show-List
    if ($r.added) { Say 'Sent. Tell Claude what to do with them.' }
    elseif ($n) { Say ([string]$n + ' waiting for your brain.') }
    else { Say 'Nothing waiting. Your brain has everything.' }
  } else {
    [void](Show-List)
    $p = Problem-Text $r
    Say $p[0] $p[1]
  }
}

$onEnter = {
  param($s, $e)
  if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' } else { $e.Effect = 'None' }
}
$onDrop = {
  param($s, $e)
  Say 'Taking it in...'
  $t = Take-In @($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
  foreach ($l in $t.lines) {
    for ($i = $script:removes.Count - 1; $i -ge 0; $i--) { if (Same-Path $script:removes[$i] $l.path) { $script:removes.RemoveAt($i) } }
    $script:adds.Add($l)
  }
  Send-Now
  if ($t.trouble.Count) { Say ($t.trouble -join ' ') }
}
foreach ($c in @($form, $top, $list, $status)) { $c.AllowDrop = $true; $c.Add_DragEnter($onEnter); $c.Add_DragDrop($onDrop) }

function Remove-Selected {
  $paths = @(foreach ($i in $list.SelectedIndices) { $script:shown[$i] })
  if (-not $paths.Count) { return }
  foreach ($p in $paths) {
    for ($i = $script:adds.Count - 1; $i -ge 0; $i--) { if (Same-Path $script:adds[$i].path $p) { $script:adds.RemoveAt($i) } }
    $script:removes.Add($p)
  }
  Send-Now
}
$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Remove from the list (the file stays where it is)', $null, { Remove-Selected })
[void]$menu.Items.Add('Show in File Explorer', $null, {
  if ($list.SelectedIndices.Count) { Start-Process explorer.exe -ArgumentList ('/select,"' + $script:shown[$list.SelectedIndices[0]] + '"') }
})
[void]$menu.Items.Add('See the list on GitHub', $null, { if ($repo) { Start-Process ('https://github.com/' + $repo + '/blob/main/' + $notePath) } })
$list.ContextMenuStrip = $menu
$list.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Delete') { Remove-Selected; $e.Handled = $true } })
$status.Add_Click({ if ($script:fix) { try { [Windows.Forms.Clipboard]::SetText($script:fix); Say 'Copied. Paste it into PowerShell, then come back to this window.' } catch { } } })

# Checks GitHub when it opens, every 30 seconds, and when it gets focus, so it sees what an agent has taken.
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 30000
$timer.Add_Tick({ try { Send-Now } catch { Say ('Something went wrong: ' + $_.Exception.Message) } })
$form.Add_Activated({ if (([DateTime]::Now - $script:last).TotalSeconds -gt 10) { try { Send-Now } catch { } } })
$form.Add_FormClosing({
  param($s, $e)
  if ($script:adds.Count -or $script:removes.Count) {
    $a = [Windows.Forms.MessageBox]::Show("Some changes aren't on GitHub yet, so your brain won't see them. Close anyway?", 'Upload point', 'YesNo', 'Warning')
    if ("$a" -ne 'Yes') { $e.Cancel = $true }
  }
})
$form.Add_Shown({ Say 'Checking GitHub...'; Send-Now; $timer.Start() })
[Windows.Forms.Application]::Run($form)
exit 0
