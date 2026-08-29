# WhatEat release automation (single command):
#   bump version -> sync mobile from dev copy -> commit & push -> wait CI -> download APK
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1   (or double-click release.bat)
param([switch]$SkipWait)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'D:\git\WhatEat'
# dev working copy path (Chinese dir built from code points to avoid script encoding issues)
$Src  = ('D:\git\' + [char]0x6E90 + [char]0x7801 + '\WhatEat\mobile')
$Dst  = Join-Path $Repo 'mobile'
$Pub  = Join-Path $Src 'pubspec.yaml'

function Get-GhToken {
    $out = "protocol=https`nhost=github.com`n`n" | & git credential fill 2>$null
    $pw = $out | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
    if (-not $pw) { throw 'Cannot get GitHub token from credential helper. Open GitHub Desktop once, or set GH_TOKEN env var.' }
    return ($pw -replace '^password=', '').Trim()
}

Write-Host '=== WhatEat release ==='

# 1) determine version: no tags yet -> current; otherwise patch +1
$m = [regex]::Match((Get-Content $Pub -Raw), 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)')
if (-not $m.Success) { throw "cannot parse version line in $Pub" }
$a = [int]$m.Groups[1].Value; $b = [int]$m.Groups[2].Value; $c = [int]$m.Groups[3].Value; $bn = [int]$m.Groups[4].Value
$newV = "$a.$b.$c"

Push-Location $Repo
try {
    git fetch origin --tags --quiet 2>$null
    $tags = git tag -l 'v[0-9]*.[0-9]*.[0-9]*'
    if ($tags) {
        $newV = "$a.$b.$($c + 1)"
        $bn++
        Write-Host "latest tags found; bumping -> v$newV"
    } else {
        Write-Host "no release tags yet; using current version -> v$newV"
    }

    # 2) write bumped version back into the dev pubspec (also keeps build number fresh)
    $raw = Get-Content $Pub -Raw
    $raw = [regex]::Replace($raw, 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $newV+$bn", 1)
    [System.IO.File]::WriteAllText($Pub, $raw, (New-Object System.Text.UTF8Encoding($false)))

    # 3) sync dev mobile -> repo mobile (build artifacts and secrets stay out)
    robocopy $Src $Dst /E /R:2 /W:5 /NFL /NDL /NP /XD build .dart_tool .idea .gradle 'ios\Pods' .git /XF '*.iml' '.flutter-plugins-dependencies' 'local.properties' 'key.properties' | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $LASTEXITCODE" }
    Write-Host 'mobile synced to repo'

    # 4) commit and push (this triggers the GitHub release workflow)
    git add -A
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) { Write-Host 'no changes to commit' }
    else {
        git -c user.name=piggecn -c user.email=hu85454@gmail.com commit -m "release: v$newV" --quiet
        Write-Host "committed: release v$newV"
    }
    $env:GIT_TERMINAL_PROMPT = '0'
    git push origin main
    if ($LASTEXITCODE -ne 0) { throw 'git push failed - check network or GitHub Desktop credentials' }
    $sha = (git rev-parse HEAD).Trim()
    Write-Host "pushed: $sha"
} finally { Pop-Location }

if ($SkipWait) { Write-Host "pushed only (SkipWait). CI: https://github.com/piggecn/WhatEat/actions"; return }

# 5) wait for the CI release run, then download the APK
$tok = Get-GhToken
$headers = @{ Authorization = "token $tok"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'whateat-release-script' }
$deadline = (Get-Date).AddMinutes(30)
$run = $null
Write-Host 'waiting for GitHub Actions to finish (first run takes several minutes)...'
do {
    Start-Sleep 20
    try {
        $runs = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/piggecn/WhatEat/actions/runs?head_sha=$sha&per_page=5"
        $run = $runs.workflow_runs | Where-Object { $_.name -eq 'release' } | Select-Object -First 1
        if ($run) { Write-Host ("  run " + $run.run_number + ": " + $run.status + " " + $run.conclusion) }
    } catch { Write-Host ('  poll error: ' + $_.Exception.Message) }
} while ((!$run -or $run.status -ne 'completed') -and (Get-Date) -lt $deadline)

if (-not $run -or $run.status -ne 'completed') { throw 'CI run did not complete within 30 minutes' }
if ($run.conclusion -ne 'success') { throw ('CI failed, see: ' + $run.html_url) }
Write-Host ('CI success: ' + $run.html_url)

# 6) locate release + download APK
$rel = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/piggecn/WhatEat/releases/tags/v$newV"
$asset = $rel.assets | Where-Object { $_.name -like '*.apk' } | Select-Object -First 1
if (-not $asset) { throw 'release has no APK asset' }
$out = "D:\git\apk\whateat\whateat-v$newV.apk"
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
Invoke-WebRequest -Headers $headers -Uri $asset.browser_download_url -OutFile $out -UseBasicParsing
Write-Host ("APK downloaded: " + $out)
Write-Host ("Release page: " + $rel.html_url)
Write-Host '=== DONE ==='
