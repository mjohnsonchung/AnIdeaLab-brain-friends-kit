# Sets up the daily acceptance of invitations to Matt's testing account, from his Windows PC. Paste into PowerShell:
#   irm https://raw.githubusercontent.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/main/testing/auto-accept-setup.ps1 | iex
#
# GitHub drops a repo invitation nobody accepts within 7 days, and an accepted one lasts until the owner
# takes it off. So big-brain's "Accept brain invitations" workflow accepts every invitation to
# diagnoticsanidealab once a day, on GitHub's machines. It needs a token of that account that can only
# accept invitations: a classic token with just the repo:invite scope and no expiry. This installs GitHub's
# command line with winget if it's missing and signs in as mjohnsonchung the first time, opens the token
# form, filled in, in an Edge InPrivate window for you to sign in as diagnoticsanidealab, reads the token
# hidden, checks it's that account's and can read invitations, saves it as big-brain's
# DIAGNOSTICS_INVITE_TOKEN secret, and runs the workflow once. The token goes straight to GitHub, never to a
# file. Safe to run again: it replaces the secret. Kept to Windows PowerShell 5.1 and plain ASCII.
& {
  $ErrorActionPreference = 'Continue'
  $main = 'mjohnsonchung'
  $tester = 'diagnoticsanidealab'
  $brain = 'mjohnsonchung/big-brain'
  $secret = 'DIAGNOSTICS_INVITE_TOKEN'
  $form = 'https://github.com/settings/tokens/new?scopes=repo:invite&description=Accept+invitations+to+friends+brains'

  Write-Host "`n1. GitHub's command line, signed in as $main"
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host 'Installing it with winget...'
    winget install -e --id GitHub.cli --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
      Write-Host "It didn't install. Close PowerShell, open it again, and paste the command again." -ForegroundColor Red
      return
    }
  }
  if ("$(gh api user --jq .login 2>$null)".Trim() -ne $main) {
    if ("$(gh auth token --hostname github.com --user $main 2>$null)".Trim()) { gh auth switch --hostname github.com --user $main 2>&1 | Out-Null }
    else {
      Write-Host "Sign in to GitHub as ${main}: copy the code shown, press Enter, and paste it in your browser."
      gh auth login --hostname github.com --git-protocol https --web
    }
  }
  $me = "$(gh api user --jq .login 2>$null)".Trim()
  if ($me -ne $main) { Write-Host "gh is signed in as '$me', not $main. Paste the command again, and sign in as $main in the browser." -ForegroundColor Red; return }
  Write-Host "Signed in as $main"

  Write-Host "`n2. The token, made by $tester"
  Write-Host "An Edge private window opens on GitHub. Sign in there as $tester, not $main. The form is filled in:"
  Write-Host 'under Expiration, choose "No expiration", leave the ticks as they are (only repo:invite),'
  Write-Host 'press "Generate token" at the bottom, and copy the token (it starts ghp_).'
  try { Start-Process 'msedge.exe' -ArgumentList @('--inprivate', $form) -ErrorAction Stop }
  catch {
    Set-Clipboard -Value $form
    Write-Host "Edge didn't open. Open a private window in your browser, sign in to GitHub as $tester, and paste this address (it's copied):"
    Write-Host $form
  }
  $secure = Read-Host 'Paste the token here (it will not show), then press Enter' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr).Trim()
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  if ($token -notmatch '^ghp_') { Write-Host "That doesn't look like a classic GitHub token (they start ghp_). Paste the command again to retry." -ForegroundColor Red; return }
  $env:GH_TOKEN = $token
  try {
    $who = "$(gh api user --jq .login 2>$null)".Trim()
    gh api user/repository_invitations --silent 2>$null
    $canAccept = $LASTEXITCODE -eq 0
  } finally { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }
  if ($who -ne $tester) {
    Write-Host "That token belongs to '$who', not $tester. Delete it (GitHub, Settings, Developer settings, Tokens (classic)), then paste the command again and sign in as $tester in the private window." -ForegroundColor Red
    return
  }
  if (-not $canAccept) { Write-Host "That token can't read $tester's invitations: tick repo:invite when you make it. Paste the command again to retry." -ForegroundColor Red; return }
  Write-Host "It's $tester's, and it can accept invitations."

  Write-Host "`n3. Saving it in big-brain as $secret"
  gh secret set $secret --repo $brain --body $token
  $saved = $LASTEXITCODE -eq 0
  $token = $null
  if (-not $saved) { Write-Host "Couldn't save the secret in $brain. Paste the command again to retry." -ForegroundColor Red; return }

  Write-Host "`n4. A first run"
  gh workflow run accept-brain-invites.yml --repo $brain
  if ($LASTEXITCODE -eq 0) { Write-Host 'Started. Invitations to the testing account are accepted once a day from now on.' -ForegroundColor Green }
  else { Write-Host "The secret is saved, but the workflow didn't start. It runs by itself tomorrow morning anyway." -ForegroundColor Yellow }
  Write-Host 'Tell the agent: the auto-accept token is in.'
}
