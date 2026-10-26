# Makes this brain's files repo: a private GitHub repo named after the brain's, with -files on the end, for
# the big and binary files its notes link to (images, PDFs, renders, pages for the owner), so the brain stays
# light and any agent can reach them, never only in one AI app. It makes the repo with a README if it's
# missing, copies it to the PC beside the brain (C:\AI-Brain-Link\<brain>-files), and invites Matt's testing
# account to it if the account is on the brain already, so the owner's choice there carries over. It prints
# only "Success", or what went wrong. Safe to run again. For a brain that hasn't got one, paste into PowerShell:
#   irm https://raw.githubusercontent.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/main/brain/skills/my-pc/files-repo.ps1 | iex
# The installer runs it for a new brain, with BRAIN_REPO (owner/name) and BRAIN_ROOT set; without them it
# finds the brain among the signed-in account's repos by the kit's update script. Windows PowerShell 5.1, plain ASCII.
& {
  $ErrorActionPreference = 'Continue'
  $tester = 'diagnostics-anidealab'
  function Fail($t) { Write-Host $t -ForegroundColor Red }
  $root = if ($env:BRAIN_ROOT) { $env:BRAIN_ROOT } else { 'C:\AI-Brain-Link' }

  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Fail "winget (Windows' app installer) isn't on this PC. Install 'App Installer' from the Microsoft Store, then paste the same command again."; return }
    winget install -e --id GitHub.cli --silent --accept-source-agreements --accept-package-agreements | Out-Null
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail "GitHub's command line installed, but this window can't see it yet. Close PowerShell, open it again, and paste the same command."; return }
  }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "Git isn't on this PC's PATH. Run the brain's setup check (skills\my-pc\check-setup.ps1), fix what it finds, and paste the same command again."; return }
  gh auth status --hostname github.com 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Fail "GitHub sign-in didn't finish. Paste the same command again to retry."; return }
  }
  gh auth setup-git --hostname github.com 2>&1 | Out-Null

  $repo = $env:BRAIN_REPO
  if (-not $repo) {
    $me = "$(gh api user --jq .login 2>$null)".Trim()
    $repos = @(gh repo list --limit 200 --json nameWithOwner --jq '.[].nameWithOwner') | Where-Object { $_ -and $_ -notlike '*-files' }
    $brains = @($repos | Where-Object { gh api "repos/$_/contents/skills/brain-spec/brain_update.py" --silent 2>$null; $LASTEXITCODE -eq 0 })
    if (-not $brains.Count) { Fail "None of $me's repos is a brain from the kit. If your brain is on another GitHub account, run gh auth login --web, sign in as that account, and paste the same command again."; return }
    if ($brains.Count -gt 1) { Fail "$me has more than one brain ($($brains -join ', ')). Choose one, then paste the same command: `$env:BRAIN_REPO = 'owner/name'"; return }
    $repo = $brains[0]
  }
  $files = "$repo-files"

  gh repo view $files --json name 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    gh repo create $files --private --description "Files for the second brain $repo, linked from its notes" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Couldn't make $files on GitHub. Paste the same command again to retry."; return }
  }
  # A README, so the repo has a main branch to copy and says what it's for
  gh api "repos/$files/contents/README.md" --silent 2>$null
  if ($LASTEXITCODE -ne 0) {
    $text = "# Files for $repo`n`nThe big and binary files the brain's notes link to by their GitHub address: images, PDFs, renders, and pages for the owner. One folder per project or job, and each file under 50 MB (GitHub refuses one over 100 MB); anything bigger stays on the PC. Keys and passwords never go here.`n"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
    gh api -X PUT "repos/$files/contents/README.md" -f message='Start the files repo' -f content=$b64 --silent 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Made $files, but couldn't add its README. Paste the same command again to retry."; return }
  }

  $dir = Join-Path $root (($files -split '/')[1])
  if (-not (Test-Path (Join-Path $dir '.git'))) {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    git -c core.longpaths=true clone --quiet "https://github.com/$files.git" $dir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Made $files on GitHub, but couldn't copy it to $dir. Paste the same command again to retry."; return }
    git -C $dir config core.longpaths true 2>&1 | Out-Null
  }

  # Matt's testing account follows the owner's choice for the brain itself.
  $onBrain = @(gh api "repos/$repo/collaborators" --jq '.[].login' 2>$null) + @(gh api "repos/$repo/invitations" --jq '.[].invitee.login' 2>$null)
  if ($onBrain -contains $tester) {
    gh api -X PUT "repos/$files/collaborators/$tester" --silent 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Made $files, but couldn't invite Matt's testing account to it. Paste the same command again to retry."; return }
  }
  Write-Host 'Success' -ForegroundColor Green
}
