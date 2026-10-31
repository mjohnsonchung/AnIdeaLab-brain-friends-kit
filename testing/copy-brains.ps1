# Gets Matt an exact copy of each friend's brain his testing account has been invited to, on his
# Windows PC, while the kit is in testing. Paste into PowerShell:
#   irm https://raw.githubusercontent.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/main/testing/copy-brains.ps1 | iex
#
# The kit's installer invites the testing account to each brain repo it makes, and big-brain's "Accept
# brain invitations" workflow accepts them once a day (testing/auto-accept-setup.ps1 sets it up). This
# installs GitHub's command line with winget if it's missing and adds the testing account to it the first
# time, accepts any invitation still waiting (the account is only for friends' brains, so it declines one
# to Matt's own repos), and clones each brain the account can reach into
# D:\AI-Brain-Link\Friend-Brains\<owner>\<repo>, every branch and the whole history, or brings a copy it
# made before up to date.
# It uses the testing account for this run only: gh and git stay on whatever account they were on, and
# the account's token is never written to a file. Safe to run again.
# Set $env:FRIEND_BRAINS first to use another folder. Kept to Windows PowerShell 5.1 and plain ASCII.
& {
  $ErrorActionPreference = 'Continue'
  $tester = 'diagnostics-anidealab'
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
    Write-Host "Adding $tester to gh. Press Enter when asked: an Edge private window opens on GitHub's device page."
    Write-Host "Sign in there as $tester, paste the code gh shows (it's copied), and approve. Then close the private window."
    Write-Host "If no private window opens, open one yourself (Ctrl+Shift+N in Edge) and go to github.com/login/device."
    $env:GH_BROWSER = 'cmd /c start msedge --inprivate' # starts signed out, whatever account the browser is on
    try { gh auth login --hostname github.com --git-protocol https --web } finally { Remove-Item Env:GH_BROWSER -ErrorAction SilentlyContinue }
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
    $inv = @(gh api user/repository_invitations --paginate --jq '.[] | [(.id|tostring), .repository.full_name] | @tsv') | Where-Object { $_ }
    if (-not $inv) { Write-Host 'None waiting.' }
    foreach ($line in $inv) {
      $id, $full = $line -split "`t", 2
      # Matt's own repos are never the testing account's: it mustn't reach his brain, or his PC through its runner.
      if ($full -like 'mjohnsonchung/*') {
        gh api -X DELETE "user/repository_invitations/$id" --silent
        Write-Host "Declined $full, one of Matt's own repos" -ForegroundColor Yellow
        continue
      }
      gh api -X PATCH "user/repository_invitations/$id" --silent
      if ($LASTEXITCODE -eq 0) { Write-Host "Accepted $full" -ForegroundColor Green } else { Write-Host "Couldn't accept $full" -ForegroundColor Yellow }
    }

    Write-Host "`n3. The brains"
    # A brain is a repo the account collaborates on with the kit's brain spec in it.
    $repos = @(gh api 'user/repos?affiliation=collaborator&per_page=100' --paginate --jq '.[].full_name') | Where-Object { $_ -and $_ -notlike 'mjohnsonchung/*' }
    $brains = @($repos | Where-Object { gh api "repos/$_/contents/skills/brain-spec/SKILL.md" --silent 2>$null; $LASTEXITCODE -eq 0 })
    if (-not $brains.Count) { Write-Host 'No brains to copy yet. An invitation shows up here once a friend runs the installer.'; return }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    foreach ($full in $brains) {
      $dir = Join-Path $root ($full -replace '/', '\')
      if (Test-Path (Join-Path $dir '.git')) {
        # A copy is a mirror: take exactly what the friend's brain has now, even if their history was rewritten
        # (an update sent again), and never leave a copy behind on an old commit.
        git config --global --add safe.directory ($dir -replace '\\', '/') 2>&1 | Out-Null
        $out = git -c $auth -C $dir fetch origin '+refs/heads/*:refs/remotes/origin/*' --prune --tags --force 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host "Couldn't fetch $full : $out" -ForegroundColor Red; continue }
        $head = "$(git -C $dir symbolic-ref --short refs/remotes/origin/HEAD 2>$null)".Trim()
        if (-not $head) { git -c $auth -C $dir remote set-head origin --auto 2>&1 | Out-Null; $head = "$(git -C $dir symbolic-ref --short refs/remotes/origin/HEAD 2>$null)".Trim() }
        if (-not $head) { $head = 'origin/main' }
        git -C $dir checkout -f -B ($head -replace '^origin/', '') $head 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "Up to date: $full in $dir ($(git -C $dir rev-parse --short HEAD))" -ForegroundColor Green }
        else { Write-Host "Fetched $full, but couldn't move the copy in $dir to $head. Delete the folder and paste the command again." -ForegroundColor Yellow }
      } else {
        git -c $auth -c core.longpaths=true clone --quiet "https://github.com/$full.git" $dir 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { git -C $dir config core.longpaths true; Write-Host "Copied $full to $dir" -ForegroundColor Green } else { Write-Host "Couldn't copy $full" -ForegroundColor Red }
      }
    }
    Write-Host "`nEvery branch is in each copy (git branch -r lists them). Open one in Obsidian as a vault to see it as its owner does. To bring them up to date, paste the same command again."
  } finally { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }
}
