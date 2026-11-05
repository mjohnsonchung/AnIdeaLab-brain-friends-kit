# Puts a key into the brain's GitHub Actions secrets with one paste: opens the page that makes it,
# says what to press there, reads the key hidden, checks it if asked, and hands it to GitHub with gh.
# Never a file, the clipboard or the screen. It knows no service: the agent's command says which key.
# The owner runs it from their copy of the brain on the PC, with what the agent filled in:
#   powershell -ExecutionPolicy Bypass -File "<the brain's folder>\skills\add-a-key\add-api-keys.ps1" -Secret OPENAI_API_KEY -Page "https://platform.openai.com/api-keys" -Tell "Sign in, press Create new secret key, and copy it." -Prefix "sk-" -Check "https://api.openai.com/v1/models"
# Only -Secret is needed. -Prefix takes how keys start, comma-separated for more than one. -Check is a URL
# that answers 401 to a bad key, sent the key as "Authorization: Bearer <key>", or in the header -Header names.
# The brain's repo is the one that copy syncs with (or -Repo owner/name). Safe to run again: a key already
# there is replaced. Plain ASCII, for Windows PowerShell 5.1 (the windows-powershell skill).
param(
    [string]$Secret = '', [string]$Page = '', [string]$Tell = '', [string]$Prefix = '',
    [string]$Check = '', [string]$Header = 'Authorization', [string]$Repo = ''
)

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Main {
    $name = $Secret.Trim().ToUpper()
    if ($name -notmatch '^[A-Z_][A-Z0-9_]*$') { Write-Host 'Say what to call the key, like -Secret OPENAI_API_KEY (letters, digits and _).'; return }

    $repo = $Repo
    if (-not $repo -and $PSScriptRoot) {
        $brain = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $url = "$(git -C $brain remote get-url origin 2>$null)"
        if ($url -match 'github\.com[/:]([^/\s]+/[^/\s]+?)(\.git)?\s*$') { $repo = $Matches[1] }
    }
    if (-not $repo) { $repo = "$(Read-Host "Your brain's repo on GitHub, as owner/name")".Trim() }
    $owner = $repo.Split('/')[0]

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
    $admin = "$(gh api "repos/$repo" --jq .permissions.admin 2>$null)".Trim()
    if ($admin -ne 'true') { Write-Host "GitHub is signed in as $login, which can't change $repo's secrets. Run gh auth login and pick $owner, then run this again."; return }

    if ($Page) { Start-Process $Page }
    if ($Tell) { Write-Host $Tell }
    $secure = Read-Host -AsSecureString "Paste the key for $name (it will not show)"
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim()
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    if (-not $key) { Write-Host 'Nothing was pasted. Run this again and paste the key.'; return }
    $starts = @($Prefix -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($starts.Count -gt 0 -and @($starts | Where-Object { $key.StartsWith($_) }).Count -eq 0) {
        Write-Host "That doesn't look like the right key (it should start with $($starts -join ' or ')). Run this again and paste it fresh."; return
    }

    # Only a 401 means the key is bad; any other answer, or none, lets it through.
    if ($Check) {
        $value = $key
        if ($Header -eq 'Authorization') { $value = 'Bearer ' + $key }
        try {
            Invoke-RestMethod -Uri $Check -Headers @{ $Header = $value } -TimeoutSec 30 | Out-Null
        } catch {
            $code = 0
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -eq 401) { Write-Host 'The service did not accept that key. Run this again and paste it fresh.'; return }
        }
    }

    gh secret set $name --repo $repo --body $key 2>&1 | Out-Null
    $failed = $LASTEXITCODE -ne 0
    $key = $null
    if ($failed) { Write-Host "GitHub would not take the key. Run this again."; return }
    Write-Host "Success: $name is in $repo's secrets."
}

Main
