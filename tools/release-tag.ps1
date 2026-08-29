# release-tag.ps1 - create and push a release tag (triggers GitHub release workflow: Docker image + Release)
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release-tag.ps1            # auto: patch +1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release-tag.ps1 0.1.5     # specify version
param([string]$Version)
$ErrorActionPreference = 'Stop'

$Repo = 'D:\git\WhatEat'
Push-Location $Repo
try {
    git fetch origin --tags --quiet 2>$null
    $tags = git tag -l 'v[0-9]*.[0-9]*.[0-9]*'
    if (-not $Version) {
        if (-not $tags) {
            Write-Host 'no version given and no existing tags - pass a version, e.g.: release-tag.ps1 0.1.0'
            exit 1
        }
        $latest = ($tags | ForEach-Object { $_ -replace '^v', '' } | Sort-Object { [version]$_ } | Select-Object -Last 1)
        $p = $latest.Split('.')
        $Version = "$($p[0]).$($p[1]).$([int]$p[2] + 1)"
    }
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "invalid version: $Version (expect X.Y.Z)" }

    $tag = "v$Version"
    if (git rev-parse $tag >/dev/null 2>&1) { throw "tag $tag already exists" }
    if ($tags) {
        $latest = ($tags | ForEach-Object { $_ -replace '^v', '' } | Sort-Object { [version]$_ } | Select-Object -Last 1)
        if ([version]$Version -le [version]$latest) { throw "version not increasing: $Version <= $latest" }
    }

    $env:GIT_TERMINAL_PROMPT = '0'
    git push origin main
    if ($LASTEXITCODE -ne 0) { throw 'git push failed - sync changes first' }
    git tag $tag
    git push origin $tag
    if ($LASTEXITCODE -ne 0) { throw 'tag push failed' }

    Write-Host "tag $tag pushed - GitHub will build the Docker image and create the release."
    Write-Host "Watch: https://github.com/piggecn/WhatEat/actions"
} finally { Pop-Location }
