# Invites Matt's testing account to your second brain's repo, for a brain set up before 27 Oct 2026, when
# the kit's installer started doing it. Paste into PowerShell on your PC:
#   irm https://raw.githubusercontent.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/main/testing/invite-matt.ps1 | iex
#
# Matt's testing account (GitHub: diagnoticsanidealab) can then see your brain and copy it, to test the kit
# while it's in testing. GitHub lets a collaborator change the repo too; there's no read-only option for a
# personal repo. It installs GitHub's command line with winget if it's missing and signs you in to GitHub
# the first time, finds your brain among your repos, and invites the account. It changes nothing else.
# To take the account off any time: your repo on GitHub, Settings, Collaborators. Safe to run again.
# Kept to Windows PowerShell 5.1 and plain ASCII.
& {
  $ErrorActionPreference = 'Continue'
  $tester = 'diagnoticsanidealab'

  Write-Host "`n1. GitHub's command line"
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
      Write-Host "winget (Windows' app installer) isn't on this PC. Install 'App Installer' from the Microsoft Store, then paste the same command again." -ForegroundColor Red
      return
    }
    Write-Host 'Installing it (Windows may ask you to allow it)...'
    winget install -e --id GitHub.cli --silent --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
      Write-Host "It installed, but this window can't see it yet. Close PowerShell, open it again, and paste the same command." -ForegroundColor Red
      return
    }
  }
  gh auth status --hostname github.com 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'Signing in to GitHub, as the account your brain is on. Copy the code shown, press Enter, and paste it into the page that opens.'
    gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Write-Host "GitHub sign-in didn't finish. Paste the same command again to retry." -ForegroundColor Red; return }
  }
  $me = "$(gh api user --jq .login 2>$null)".Trim()
  Write-Host "Signed in as $me"

  Write-Host "`n2. Your brain"
  # A brain is one of your repos with the kit's brain spec in it.
  $repos = @(gh repo list --limit 200 --json nameWithOwner --jq '.[].nameWithOwner') | Where-Object { $_ }
  $brains = @($repos | Where-Object { gh api "repos/$_/contents/skills/brain-spec/SKILL.md" --silent 2>$null; $LASTEXITCODE -eq 0 })
  if (-not $brains.Count) {
    Write-Host "None of $me's repos looks like a brain. If your brain is on another GitHub account, run: gh auth login --web, sign in as that account, and paste the same command again." -ForegroundColor Red
    return
  }

  Write-Host "`n3. Inviting Matt's testing account ($tester)"
  foreach ($r in $brains) {
    gh api -X PUT "repos/$r/collaborators/$tester" --silent
    if ($LASTEXITCODE -eq 0) { Write-Host "Invited it to $r" -ForegroundColor Green } else { Write-Host "Couldn't invite it to $r. Paste the same command again to retry." -ForegroundColor Red }
  }
  Write-Host "`nDone. Matt's brain accepts the invitation within a day. To take the account off any time: your repo on GitHub, Settings, Collaborators."
  Write-Host "If your brain already has brain update 3, tell its agent: Matt's testing account is on this repo now, so put its row back in the accounts note."
}
