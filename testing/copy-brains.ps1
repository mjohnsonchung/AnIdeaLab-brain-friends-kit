# Gets Matt an exact copy of each friend's brain his testing account has been invited to, on his
# Windows PC, while the kit is in testing. Paste into PowerShell:
#   irm https://raw.githubusercontent.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/main/testing/copy-brains.ps1 | iex
#
# The kit's installer invites the testing account to each brain repo it makes. This installs GitHub's
# command line with winget if it's missing and adds the testing account to it the first time, accepts
# every invitation to a repo described as started from the starter kit, and clones each brain the
# account can reach into D:\AI-Brain-Link\Friend-Brains\<owner>\<repo>, every branch and the whole
# history, or brings a copy it made before up to date. Other invitations are listed and left alone.
# It uses the testing account for this run only: gh and git stay on whatever account they were on, and
# the account's token is never written to a file. Safe to run again.
# Set $env:FRIEND_BRAINS first to use another folder. Kept to Windows PowerShell 5.1 and plain ASCII.
& {
  $ErrorActionPreference = 'Continue'
  $tester = 'diagnoticsanidealab'
  $root = if ($env:FRIEND_BRAINS) { $env:FRIEND_BRAINS } else { 'D:\AI-Brain-Link\Friend-Brains' }

  Write-Host "`n1. GitHub's command line, signed in as $tester"
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host 'Installing it with winget...'
    winget install -e --id GitHub.cli --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
      Write-Host "It didn't install. Close PowerShell, open it again, and paste the command again." -ForegroundColor Red
      return
    }
  }
  $token = "$(gh auth token --hostname github.com --user $tester 2>$null)".Trim()
  if (-not $token) {
    $before = "$(gh api user --jq .login 2>$null)".Trim()
    Write-Host "Adding $tester to gh. Copy the code shown and press Enter. In the browser page that opens, be signed in to GitHub as $tester (a private window, if your browser is signed in as another account), then paste the code."
    gh auth login --hostname github.com --git-protocol https --web
    $token = "$(gh auth token --hostname github.com --user $tester 2>$null)".Trim()
    # Logging in makes the new account gh's active one; put back the one it was on.
    if ($before -and $before -ne $tester) { gh auth switch --hostname github.com --user $before 2>&1 | Out-Null }
    if (-not $token) { Write-Host "gh isn't signed in as $tester. Paste the command again, and sign in as $tester in the browser." -ForegroundColor Red; return }
  }
  $env:GH_TOKEN = $token # for this window's gh only; removed at the end
  try {
    $me = "$(gh api user --jq .login)".Trim()
    if ($me -ne $tester) { Write-Host "That token is for $me, not $tester." -ForegroundColor Red; return }
    Write-Host "Using $tester for this run."
    # Git gets the token as a header on each command, so it isn't saved and the copies' settings stay plain.
    $auth = 'http.https://github.com/.extraheader=AUTHORIZATION: basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))

    Write-Host "`n2. Invitations"
    # No double quotes inside the jq: Windows PowerShell 5.1 strips them on the way to gh.
    $inv = @(gh api user/repository_invitations --paginate --jq '.[] | [(.id|tostring), .repository.full_name, (.repository.description // empty)] | @tsv') | Where-Object { $_ }
    if (-not $inv) { Write-Host 'None waiting.' }
    foreach ($line in $inv) {
      $id, $full, $about = $line -split "`t", 3
      if ($about -match 'starter kit') {
        gh api -X PATCH "user/repository_invitations/$id" --silent
        if ($LASTEXITCODE -eq 0) { Write-Host "Accepted $full" -ForegroundColor Green } else { Write-Host "Couldn't accept $full" -ForegroundColor Yellow }
      } else {
        Write-Host "Left for you: $full isn't described as a brain from the kit. Accept it on github.com, signed in as $tester, if it is one."
      }
    }

    Write-Host "`n3. The brains"
    # A brain is a repo the account collaborates on with the kit's brain spec in it.
    $repos = @(gh api 'user/repos?affiliation=collaborator&per_page=100' --paginate --jq '.[].full_name') | Where-Object { $_ }
    $brains = @($repos | Where-Object { gh api "repos/$_/contents/skills/brain-spec/SKILL.md" --silent 2>$null; $LASTEXITCODE -eq 0 })
    if (-not $brains.Count) { Write-Host 'No brains to copy yet. An invitation shows up here once a friend runs the installer.'; return }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    foreach ($full in $brains) {
      $dir = Join-Path $root ($full -replace '/', '\')
      if (Test-Path (Join-Path $dir '.git')) {
        git -c $auth -C $dir fetch --all --prune --quiet 2>&1 | Out-Null
        git -c $auth -C $dir pull --ff-only --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "Up to date: $full in $dir" -ForegroundColor Green }
        else { Write-Host "Fetched $full, but your copy in $dir has changes of its own, so it wasn't moved on. To start it over: delete the folder and paste the command again." -ForegroundColor Yellow }
      } else {
        git -c $auth -c core.longpaths=true clone --quiet "https://github.com/$full.git" $dir 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { git -C $dir config core.longpaths true; Write-Host "Copied $full to $dir" -ForegroundColor Green } else { Write-Host "Couldn't copy $full" -ForegroundColor Red }
      }
    }
    Write-Host "`nEvery branch is in each copy (git branch -r lists them). Open one in Obsidian as a vault to see it as its owner does. To bring them up to date, paste the same command again."
  } finally { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }
}
