# release-tag.ps1 - create and push a release tag (triggers GitHub release workflow: Docker image + Release)
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release-tag.ps1                  # auto: patch +1, 打开记事本填写更新说明
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release-tag.ps1 0.1.5           # specify version
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release-tag.ps1 0.1.5 -Notes "修复xx"  # 直接给定说明
param([string]$Version, [string]$Notes)
$ErrorActionPreference = 'Stop'

$Repo = 'D:\git\WhatEat'
$NotesFile = Join-Path $Repo 'RELEASE_NOTES.md'

# 更新说明：优先 -Notes 参数；否则用记事本打开 RELEASE_NOTES.md 人工填写
if ($Notes) {
    [System.IO.File]::WriteAllText($NotesFile, $Notes, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'RELEASE_NOTES.md written from -Notes'
} else {
    $cur = [System.IO.File]::ReadAllText($NotesFile, [System.Text.Encoding]::UTF8)
    if (-not $cur -or $cur -match '在此填写本次更新内容') {
        Write-Host '请在记事本中填写本次更新内容，保存并关闭窗口...'
        Start-Process notepad -Wait -ArgumentList $NotesFile
    }
    $cur = [System.IO.File]::ReadAllText($NotesFile, [System.Text.Encoding]::UTF8)
    if (-not $cur -or $cur -match '在此填写本次更新内容') {
        throw 'RELEASE_NOTES.md 内容为空或未修改 - 请填写本次更新内容后重试'
    }
}

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
    $ErrorActionPreference = 'Continue'
    $null = git rev-parse -q --verify $tag 2>$null
    $tagRc = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($tagRc -eq 0) { throw "tag $tag already exists" }
    if ($tags) {
        $latest = ($tags | ForEach-Object { $_ -replace '^v', '' } | Sort-Object { [version]$_ } | Select-Object -Last 1)
        if ([version]$Version -le [version]$latest) { throw "version not increasing: $Version <= $latest" }
    }

    $env:GIT_TERMINAL_PROMPT = '0'
    # 更新说明随 main 一起提交，保证 tag 指向的版本里包含 RELEASE_NOTES.md
    git add RELEASE_NOTES.md
    git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        git -c user.name=piggecn -c user.email=hu85454@gmail.com commit -m "docs: release notes for v$Version" --quiet
        Write-Host 'RELEASE_NOTES.md committed'
    }
    git push origin main
    if ($LASTEXITCODE -ne 0) { throw 'git push failed - sync changes first' }
    git tag $tag
    git push origin $tag
    if ($LASTEXITCODE -ne 0) { throw 'tag push failed' }

    Write-Host "tag $tag pushed - GitHub will build the Docker image and create the release."
    Write-Host "Watch: https://github.com/piggecn/WhatEat/actions"
} finally { Pop-Location }
