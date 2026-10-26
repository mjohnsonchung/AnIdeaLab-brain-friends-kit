# Puts AnIdeaLab's brain report inbox on Vercel, from Matt's Windows PC. Paste into PowerShell:
#   irm https://raw.githubusercontent.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/main/inbox/setup-windows.ps1 | iex
#
# It installs Node with winget if it's missing, asks you to log in to Vercel the first time, opens
# GitHub's token form for the reports repo, deploys the inbox as the Vercel project
# anidealab-brain-inbox, checks it answers, and copies its address. Safe to run again: it replaces
# the token and deploys again. Nothing it does is kept in a file; the token goes straight to Vercel.
# Kept to Windows PowerShell 5.1 and plain ASCII.
& {
  $ErrorActionPreference = 'Continue'
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
  $kit = 'https://raw.githubusercontent.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/main/inbox'
  $project = 'anidealab-brain-inbox'
  $cli = 'vercel@65.2.0'
  $form = 'https://github.com/settings/personal-access-tokens/new?name=Brain+reports+inbox&description=Lets+the+brain+update+inbox+save+reports+in+AnIdeaLab-brain-reports&expires_in=none&contents=write'
  $dir = Join-Path $env:TEMP $project

  Write-Host "`n1. Node"
  if (-not (Get-Command npx.cmd -ErrorAction SilentlyContinue)) {
    Write-Host 'Installing Node with winget...'
    winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command npx.cmd -ErrorAction SilentlyContinue)) {
      Write-Host 'Node did not install. Close PowerShell, open it again, and paste the command again.' -ForegroundColor Red
      return
    }
  }
  Write-Host "Node $(node --version)"

  Write-Host "`n2. The inbox's files"
  New-Item -ItemType Directory -Force -Path (Join-Path $dir 'api') | Out-Null
  foreach ($f in 'package.json', 'api/report.js') {
    try { Invoke-WebRequest "$kit/$f" -OutFile (Join-Path $dir $f) -UseBasicParsing -ErrorAction Stop }
    catch { Write-Host "Couldn't download $f from GitHub: $($_.Exception.Message)" -ForegroundColor Red; return }
  }
  Set-Location $dir
  Write-Host "In $dir"

  Write-Host "`n3. Vercel (the first time, it downloads its tool, which takes a minute)"
  npx.cmd --yes $cli whoami 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'Log in to Vercel: a browser page opens (or follow the link below). Use the same login as your other sites.'
    npx.cmd --yes $cli login
    npx.cmd --yes $cli whoami 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host 'Not logged in to Vercel. Paste the command again to retry.' -ForegroundColor Red; return }
  }
  npx.cmd --yes $cli link --yes --project $project
  if ($LASTEXITCODE -ne 0) { Write-Host "Couldn't link the Vercel project $project. Paste the command again to retry." -ForegroundColor Red; return }

  Write-Host "`n4. The token for the reports repo"
  Write-Host 'A GitHub page opens with the token form filled in. Under "Repository access", choose'
  Write-Host '"Only select repositories" and pick AnIdeaLab-brain-reports. Then "Generate token", and copy it.'
  Start-Process $form
  $secure = Read-Host 'Paste the token here (it will not show), then press Enter' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr).Trim()
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  if ($token -notmatch '^github_pat_') { Write-Host "That doesn't look like a GitHub token (they start github_pat_). Paste the command again to retry." -ForegroundColor Red; return }
  npx.cmd --yes $cli env rm REPORTS_TOKEN production --yes 2>&1 | Out-Null
  npx.cmd --yes $cli env add REPORTS_TOKEN production --value $token --yes
  $added = $LASTEXITCODE
  $token = $null
  if ($added -ne 0) { Write-Host "Vercel didn't take the token. Paste the command again to retry." -ForegroundColor Red; return }

  Write-Host "`n5. Deploying"
  $out = (npx.cmd --yes $cli deploy --prod --yes 2>&1 | ForEach-Object { "$_" }) -join "`n"
  $out = $out -replace "$([char]27)\[[0-9;]*m", ''
  Write-Host $out
  $m = [regex]::Match($out, 'Aliased\W+(https://[^\s\[\]]+)')
  $base = if ($m.Success) { $m.Groups[1].Value.TrimEnd('/') } else { "https://$project.vercel.app" }
  $address = "$base/api/report"

  Write-Host "`n6. Checking it answers"
  $code = 0
  for ($i = 0; $i -lt 6 -and $code -ne 405; $i++) {
    try { Invoke-WebRequest $address -UseBasicParsing -ErrorAction Stop | Out-Null; $code = 200 }
    catch { if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } }
    if ($code -ne 405) { Start-Sleep -Seconds 5 }
  }
  if ($code -eq 405) {
    Set-Clipboard $address
    Write-Host "`nThe inbox is up: $address (copied)." -ForegroundColor Green
    Write-Host 'Tell Claude: "The brain report inbox is up", with the address.'
  } else {
    Write-Host "`nIt deployed, but $address didn't answer as the inbox (it answered $code). Send Claude everything above." -ForegroundColor Yellow
  }
}
