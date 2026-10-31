# Puts service API keys for the brain's jobs into the brain's GitHub Actions secrets, one paste each:
# for each service it opens the page that makes the key, reads the key hidden, checks it with the
# service, and hands it to GitHub with gh. Never a file, the clipboard or the screen.
# The owner runs it from their copy of the brain on the PC, naming the services, comma-separated:
#   powershell -ExecutionPolicy Bypass -File "<the brain's folder>\skills\add-a-key\add-api-keys.ps1" -Services elevenlabs,openai
# The brain's repo is the one that copy syncs with (or -Repo owner/name). The same script is in Matt's
# brain and in brains from his starter kit. Safe to run again: a key already there is replaced.
# Add a service to $known below. Plain ASCII, for Windows PowerShell 5.1 (the windows-powershell skill).
param([string]$Services = 'elevenlabs,openai', [string]$Repo = '')

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
if (-not $Repo -and $PSScriptRoot) {
    $brain = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $url = "$(git -C $brain remote get-url origin 2>$null)"
    if ($url -match 'github\.com[/:]([^/\s]+/[^/\s]+?)(\.git)?\s*$') { $Repo = $Matches[1] }
}
if (-not $Repo) { $Repo = "$(Read-Host "Your brain's repo on GitHub, as owner/name")".Trim() }
$owner = $Repo.Split('/')[0]
$brainName = $Repo.Split('/')[-1]

$known = @{
    elevenlabs = @{
        Name = 'ElevenLabs'; Secret = 'ELEVENLABS_API_KEY'; Prefix = 'sk_'
        Page = 'https://elevenlabs.io/app/settings/api-keys'
        Tell = 'ElevenLabs: sign in (the free plan is enough), press Create API Key, call it {brain}, leave its access as it is, and copy the key.'
        Check = 'https://api.elevenlabs.io/v1/models'; Header = 'xi-api-key'; Scheme = ''; Reject = @(401)
    }
    openai = @{
        Name = 'OpenAI'; Secret = 'OPENAI_API_KEY'; Prefix = 'sk-'
        Page = 'https://platform.openai.com/api-keys'
        Tell = 'OpenAI: sign in, press Create new secret key, call it {brain}, leave the project as Default, and copy the key.'
        Check = 'https://api.openai.com/v1/models'; Header = 'Authorization'; Scheme = 'Bearer '; Reject = @(401)
    }
    gemini = @{
        # AI Studio has issued only "AQ." keys since mid-2026; older ones start "AIza". Some AQ keys are
        # reported to fail checks while real, so this one never turns a key away: the first real call tests it.
        Name = 'Gemini'; Secret = 'GEMINI_API_KEY'; Prefix = @('AQ.', 'AIza')
        Page = 'https://aistudio.google.com/apikey'
        Tell = 'Gemini: sign in with a Google account (free, no billing needed), press Create API key, and copy the key.'
        Check = 'https://generativelanguage.googleapis.com/v1beta/models'; Header = 'x-goog-api-key'; Scheme = ''; Reject = @()
    }
}

function Main {
    $wanted = @($Services -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
    foreach ($w in $wanted) {
        if (-not $known.ContainsKey($w)) { Write-Host "No service called $w here. Known: $($known.Keys -join ', ')"; return }
    }

    # gh, signed in as an account that can change the repo's secrets (its owner's)
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        winget install -e --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements | Out-Null
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Host 'GitHub CLI did not install. Run: winget install -e --id GitHub.cli'; return }
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { gh auth login --web --git-protocol https }
    $login = (gh api user --jq .login 2>$null)
    if ($login -ne $owner) {
        gh auth switch --user $owner 2>&1 | Out-Null
        $login = (gh api user --jq .login 2>$null)
    }
    $admin = "$(gh api "repos/$Repo" --jq .permissions.admin 2>$null)".Trim()
    if ($admin -ne 'true') { Write-Host "GitHub is signed in as $login, which can't change $Repo's secrets. Run gh auth login and pick $owner, then run this again."; return }

    foreach ($w in $wanted) {
        $s = $known[$w]
        Start-Process $s.Page
        Write-Host $s.Tell.Replace('{brain}', $brainName)
        $secure = Read-Host -AsSecureString "Paste the $($s.Name) key (it will not show)"
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $starts = @($s.Prefix | Where-Object { $key.StartsWith($_) })
        if ($starts.Count -eq 0) { Write-Host "That is not a $($s.Name) key (they start with $(@($s.Prefix) -join ' or ')). Run this again and paste it fresh."; return }

        # A key the service turns away (its Reject codes) stops here; any other answer means the key is real.
        try {
            Invoke-RestMethod -Uri $s.Check -Headers @{ $s.Header = $s.Scheme + $key } -TimeoutSec 30 | Out-Null
        } catch {
            $code = 0
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($s.Reject -contains $code) { Write-Host "$($s.Name) did not accept that key. Run this again and paste it fresh."; return }
        }

        gh secret set $s.Secret --repo $Repo --body $key 2>&1 | Out-Null
        $failed = $LASTEXITCODE -ne 0
        $key = $null
        if ($failed) { Write-Host "GitHub would not take the $($s.Name) key. Run this again."; return }
    }
    Write-Host 'Success'
}

Main
