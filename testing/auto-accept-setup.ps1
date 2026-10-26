# Sets up the daily acceptance of invitations to Matt's testing account, from his Windows PC. Paste into PowerShell:
#   irm https://raw.githubusercontent.com/mjohnsonchung/AnIdeaLab-brain-friends-kit/main/testing/auto-accept-setup.ps1 | iex
#
# GitHub drops a repo invitation nobody accepts within 7 days, and an accepted one lasts until the owner
# takes it off. So big-brain's "Accept brain invitations" workflow accepts every invitation to
# diagnostics-anidealab once a day, on GitHub's machines. It needs a token of that account that can only
# accept invitations: a classic token with just the repo:invite scope and no expiry. This installs GitHub's
# command line with winget if it's missing and signs it in as mjohnsonchung the first time (in an Edge
# private window, whatever account the browser is on), opens the token form, filled in, for you to make
# as diagnostics-anidealab, reads the token hidden, checks it's that account's and can read invitations,
# saves it as big-brain's DIAGNOSTICS_INVITE_TOKEN secret, and runs the workflow once. The token goes
# straight to GitHub, never to a file. Safe to run again: it replaces the secret. Kept to Windows
# PowerShell 5.1 and plain ASCII.
& {
  $ErrorActionPreference = 'Continue'
  $main = 'mjohnsonchung'
  $tester = 'diagnostics-anidealab'
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
  # gh signs git in too, as its active account, so gh ends on $main (Matt's PC, 27 Oct 2026: his browser was on
  # the testing account, so gh's sign-in went to it). The sign-in page opens in an Edge private window, which
  # starts signed out whatever the browser is signed in as.
  if (-not "$(gh auth token --hostname github.com --user $main 2>$null)".Trim()) {
    Write-Host "Signing gh in as ${main}. Press Enter when asked: an Edge private window opens on GitHub's device page."
    Write-Host "Sign in there as $main (not $tester), paste the code gh shows (it's copied), and approve. Then close the private window."
    Write-Host "If no private window opens, open one yourself (Ctrl+Shift+N in Edge) and go to github.com/login/device."
    $env:GH_BROWSER = 'cmd /c start msedge --inprivate'
    try { gh auth login --hostname github.com --git-protocol https --web } finally { Remove-Item Env:GH_BROWSER -ErrorAction SilentlyContinue }
  }
  if ("$(gh auth token --hostname github.com --user $main 2>$null)".Trim()) { gh auth switch --hostname github.com --user $main 2>&1 | Out-Null }
  $me = "$(gh api user --jq .login 2>$null)".Trim()
  if ($me -ne $main) { Write-Host "gh isn't signed in as $main (it's on '$me'). Paste the command again, and in the private window sign in as $main." -ForegroundColor Red; return }
  Write-Host "gh is on $main, so git on this PC is too"

  Write-Host "`n2. The token, made by $tester"
  Write-Host "GitHub's token form opens in your browser, filled in. Check the picture at the top right is $tester's:"
  Write-Host "if it isn't, click it, choose Switch account (or Add account) and pick $tester, then press Enter here to open the form again."
  Write-Host 'On the form: under Expiration, choose "No expiration", leave the ticks as they are (only repo:invite),'
  Write-Host 'press "Generate token" at the bottom, and copy the token (it starts ghp_).'
  $token = ''
  while (-not $token) {
    Start-Process $form
    $secure = Read-Host 'Paste the token here (it will not show) and press Enter, or just press Enter to open the form again' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr).Trim()
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
  if ($token -notmatch '^ghp_') { Write-Host "That doesn't look like a classic GitHub token (they start ghp_). Paste the command again to retry." -ForegroundColor Red; return }
  $env:GH_TOKEN = $token
  try {
    $who = "$(gh api user --jq .login 2>$null)".Trim()
    gh api user/repository_invitations --silent 2>$null
    $canAccept = $LASTEXITCODE -eq 0
  } finally { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }
  if ($who -ne $tester) {
    Write-Host "That token belongs to '$who', not $tester. Delete it (GitHub, Settings, Developer settings, Tokens (classic)), then paste the command again, with the browser switched to $tester." -ForegroundColor Red
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
