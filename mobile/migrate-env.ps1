# =============================================================================
# WhatEat APK 开发环境一键迁移脚本
# 生成日期: 2026-08-29
# 生成依据: ENVIRONMENT_REPORT.md (环境评估报告) + 用户决策记录
#
# 用法:
#   .\migrate-env.ps1                 # 交互模式（每步确认）
#   .\migrate-env.ps1 --dry-run       # 只打印将执行的动作，不落盘
#   .\migrate-env.ps1 --yes           # 跳过确认直接执行
#   .\migrate-env.ps1 --skip <phase>  # 跳过指定阶段，如 --skip migrate-tools
#   .\migrate-env.ps1 --rollback      # 从备份恢复环境变量与项目配置
#
# 执行要求:
#   - 以【管理员】PowerShell 运行（卸载注册表项、改系统环境变量需要）
#   - 先关闭 Android Studio / VS Code / GitHub Desktop / Docker Desktop
#     （脚本会尝试自动关闭，若进程残留请手动结束）
#
# 回滚:
#   脚本会在 D:\app\env-backup\<date> 保存完整快照；
#   执行 .\migrate-env.ps1 --rollback 即可还原环境变量与项目配置。
#   已复制（未删除）的原目录均保留，可手动切回。
# =============================================================================

param(
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Rollback,
  [string[]]$Skip
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = 'WhatEat Env Migrate'

# ---- 目标布局（唯一真相源） --------------------------------------------------
$Target = [ordered]@{
  'jdk'        = 'D:\app\jdk-21'
  'android'    = 'D:\app\Android'
  'sdk'        = 'D:\app\Android\Sdk'
  'gradle'     = 'D:\app\.gradle'
  'flutter'    = 'D:\app\Flutter'
  'git'        = 'D:\app\Git'
  'vscode'     = 'D:\app\Microsoft VS Code'
  'ghdesktop'  = 'D:\app\GitHub Desktop'
  'pub'        = 'D:\app\.pub-cache'
  'backup'     = 'D:\app\env-backup'
  'downloads'  = 'D:\app\downloads'
}

# ---- 原始路径（迁移来源） ---------------------------------------------------
$Src = [ordered]@{
  'sdk'        = 'C:\Users\huwentao\AppData\Local\Android\Sdk'
  'gradle'     = 'C:\Users\huwentao\.gradle'
  'flutter'    = 'D:\flutter_windows_3.47.2-stable\flutter'
  'git'        = 'D:\软件\Git'
  'vscode'     = 'D:\软件\Microsoft VS Code'
  'ghdesktop'  = 'C:\Users\huwentao\AppData\Local\GitHubDesktop'
  'pub'        = 'C:\Users\huwentao\AppData\Local\Pub'
  'jbrBroken'  = 'D:\app\android\jbr'
}

# ---- 版本选型（修正自原方案：AGP 9.1.0 要求 JDK 21） -----------------------
# Eclipse Temurin 21.0.9 LTS Windows x64 安装器
# 官方下载: https://adoptium.net/temurin/releases/?version=21
# 归档地址: https://api.adoptium.net/v3/binary/version/jdk-21.0.9+10/ga/windows/x64/installer
$JdkVersion   = '21.0.9+10'
$JdkInstaller = 'D:\app\downloads\OpenJDK21U-jdk_x64_windows.exe'
$JdkDownload  = 'https://api.adoptium.net/v3/binary/version/jdk-21.0.9+10/ga/windows/x64/installer'

$ProjectRoot = 'd:\git\源码\WhatEat\mobile'
$ProjectAndroid = Join-Path $ProjectRoot 'android'

# ---- 工具函数 ---------------------------------------------------------------
function Say($msg, [ConsoleColor]$color = 'Gray') { Write-Host ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $msg) -ForegroundColor $color }
function Step($msg) { Write-Host ""; Write-Host ("  ==> " + $msg) -ForegroundColor Cyan; Write-Host ("  " + ('-' * 58)) -ForegroundColor DarkGray }
function Warn($msg) { Write-Host ("  ! {0}" -f $msg) -ForegroundColor Yellow }
function Fail($msg) { Write-Host ("  X {0}" -f $msg) -ForegroundColor Red }

function Confirm($msg) {
  if ($Yes) { Say ('auto-yes: ' + $msg); return $true }
  $r = Read-Host ("  确认执行: {0} (Y/N/全部)" -f $msg)
  if ($r -in @('全部', 'a', 'A', 'all')) { $script:Yes = $true; return $true }
  return $r -in @('Y', 'y', '是')
}

function Run($desc, $cmd) {
  Say ('run: ' + $desc)
  if ($DryRun) { Say ('  [dry-run] ' + $cmd); return 0 }
  & $cmd
  return $LASTEXITCODE
}

function TestWritable($path) {
  if (-not (Test-Path $path)) { return $false }
  $probe = Join-Path $path '.writetest_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
  try { Set-Content $probe 'x' -ErrorAction Stop; Remove-Item $probe -Force -ErrorAction SilentlyContinue; return $true }
  catch { return $false }
}

$Script:SkipHash = @{}
foreach ($s in $Skip) { $Script:SkipHash[$s] = $true }
function Skipped($phase) { if ($Script:SkipHash.ContainsKey($phase)) { Say ('skip: ' + $phase) -ForegroundColor DarkGray; return $true }; return $false }

# =============================================================================
# 回滚
# =============================================================================
function Invoke-Rollback {
  Step '回滚环境'
  $snap = Get-ChildItem $Target.backup -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $snap) { Fail ('未找到备份目录 ' + $Target.backup); return }
  Say ('使用快照: ' + $snap.FullName)

  $snapFiles = Get-ChildItem $snap.FullName -Recurse -File | Where-Object { $_.Name -like 'env-*' -or $_.Name -like 'WhatEat-*' -or $_.Name -like 'git-config*' }
  foreach ($f in $snapFiles) {
    $base = $f.Name
    $dst = switch -Regex ($base) {
      '^env-user-HKCU'      { 'HKCU:\Environment' }
      '^env-system'         { 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' }
      '^WhatEat-local'      { Join-Path $ProjectAndroid 'local.properties' }
      '^WhatEat-gradle'     { Join-Path $ProjectAndroid 'gradle.properties' }
      '^WhatEat-settings'   { Join-Path $ProjectAndroid 'settings.gradle.kts' }
      '^WhatEat-build'      { Join-Path $ProjectAndroid 'build.gradle.kts' }
      '^WhatEat-app-build'  { Join-Path $ProjectAndroid 'app\build.gradle.kts' }
      default               { $null }
    }
    if ($base -match '^env-') {
      if ($DryRun) { Say ('  [dry-run] 恢复环境变量 -> ' + $dst); continue }
      if (Confirm ('恢复注册表 ' + $dst)) {
        $obj = Import-Clixml $f.FullName
        foreach ($p in $obj.PSObject.Properties) {
          if ($p.Name -like 'PS*') { continue }
          Set-ItemProperty $dst -Name $p.Name -Value $p.Value -Type 'String'
        }
        Say ('  已恢复: ' + $dst)
      }
    }
    elseif ($base -like 'WhatEat-*' -and $dst) {
      if ($DryRun) { Say ('  [dry-run] 恢复 ' + $f.Name + ' -> ' + $dst); continue }
      if (Confirm ('恢复项目配置 ' + $f.Name)) {
        Copy-Item $f.FullName $dst -Force
        Say ('  已恢复: ' + $dst)
      }
    }
    elseif ($base -like 'git-config*') {
      if ($DryRun) { Say ('  [dry-run] 恢复 git 全局配置'); continue }
      if (Confirm '恢复 git 全局配置' -and (Test-Path $dst)) {
        Copy-Item $f.FullName ($env:USERPROFILE + '\.gitconfig') -Force
        Say '  已恢复 git 全局配置'
      }
    }
  }
  Warn '原工具目录（D:\软件\Git 等）若已被迁移移动，需手动移回。请检查备份目录中的目录清单。'
  Say '回滚完成' -ForegroundColor Green
  exit 0
}
if ($Rollback) { Invoke-Rollback }

# =============================================================================
# 阶段 0: 前置检查
# =============================================================================
Step '阶段 0/9 - 前置检查'

# 管理员检查
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail '请以【管理员】身份运行本脚本（需写 HKLM 与卸载注册表项）'; if (-not $DryRun) { exit 1 } else { Warn 'dry-run 模式继续' } }

# 关键路径可写性
foreach ($k in @('sdk', 'gradle', 'jdk', 'backup', 'downloads')) {
  $parent = Split-Path $Target[$k] -Parent
  if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $ok = TestWritable $parent
  if ($ok) { Say ('可写: ' + $parent) -ForegroundColor Green } else { Fail ('不可写: ' + $parent) }
  if (-not $ok -and -not $DryRun) {
    Fail ('路径 ' + $parent + ' 不可写。请在 TraeCode 设置 -> 权限与审批 -> 自定义配置 中授权该路径，')
    Fail '或直接在自己的 PowerShell 中运行本脚本。'
    exit 1
  }
}

# 关闭占用进程
$killProcs = @(
  @{ Name = 'studio64';  Label = 'Android Studio' },
  @{ Name = 'Code';      Label = 'Visual Studio Code' },
  @{ Name = 'GitHubDesktop'; Label = 'GitHub Desktop' },
  @{ Name = 'qemu-system-x86_64'; Label = 'Android Emulator' }
)
foreach ($p in $killProcs) {
  $proc = Get-Process -Name $p.Name -ErrorAction SilentlyContinue
  if ($proc) {
    if ($DryRun) { Say ('  [dry-run] 结束 ' + $p.Label); continue }
    if (Confirm ('关闭 ' + $p.Label)) { Stop-Process -Name $p.Name -Force; Say ('已关闭 ' + $p.Label) }
  } else { Say ($p.Label + ' 未运行') }
}

# Docker 先不关（保留卷），仅提示
Say 'Docker Desktop 本次不迁移（保持 C 盘安装，仅后续可选迁数据卷）'

# 磁盘空间
$drive = Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID="D:"'
$freeGB = [math]::Round($drive.FreeSpace / 1GB, 1)
NeedGB = 20  # JDK 300M + SDK 8.4G + gradle 5.6G + Flutter 1.5G + 工具 3G
if ($freeGB -lt 25) { Fail ('D 盘可用 ' + $freeGB + 'GB，建议至少 25GB'); if (-not $DryRun) { exit 1 } }
Say ('D 盘可用 ' + $freeGB + 'GB') -ForegroundColor Green

# =============================================================================
# 阶段 1: 备份
# =============================================================================
if (-not (Skipped 'backup')) {
  Step '阶段 1/9 - 备份当前环境快照'
  $snapDir = Join-Path $Target.backup ((Get-Date -f 'yyyy-MM-dd'))
  if (-not $DryRun) { New-Item -ItemType Directory -Path $snapDir -Force | Out-Null }

  $userEnv = Get-ItemProperty 'HKCU:\Environment'
  $sysEnv  = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
  if ($DryRun) { Say '  [dry-run] 导出环境变量' } else {
    $userEnv | Export-Clixml (Join-Path $snapDir 'env-user-HKCU.xml')
    $sysEnv  | Export-Clixml (Join-Path $snapDir 'env-system.xml')
    Say '  已导出用户/系统环境变量'
  }

  # 项目配置
  foreach ($f in @('local.properties', 'gradle.properties', 'settings.gradle.kts', 'build.gradle.kts')) {
    $s = Join-Path $ProjectAndroid $f
    if (Test-Path $s) {
      if ($DryRun) { Say ('  [dry-run] 备份 ' + $f) } else { Copy-Item $s (Join-Path $snapDir ('WhatEat-' + $f)) -Force }
    }
  }
  $appBuild = Join-Path $ProjectAndroid 'app\build.gradle.kts'
  if (Test-Path $appBuild) {
    if ($DryRun) { Say '  [dry-run] 备份 app/build.gradle.kts' } else { Copy-Item $appBuild (Join-Path $snapDir 'WhatEat-app-build.gradle.kts') -Force }
  }

  # Git 全局配置（含 LFS 与 GCM 配置）
  $gitcfg = Join-Path $env:USERPROFILE '.gitconfig'
  if (Test-Path $gitcfg) {
    if ($DryRun) { Say '  [dry-run] 备份 .gitconfig' } else { Copy-Item $gitcfg (Join-Path $snapDir 'gitconfig-backup') -Force }
  }

  # Docker 配置（不含凭据文件）
  $dockerDir = Join-Path $snapDir 'docker-config'
  if (-not $DryRun) { New-Item -ItemType Directory -Path $dockerDir -Force | Out-Null }
  if (Test-Path 'C:\Users\huwentao\.docker') {
    foreach ($f in @('config.json', 'daemon.json', 'windows-daemon.json')) {
      $s = 'C:\Users\huwentao\.docker\' + $f
      if (Test-Path $s) { if ($DryRun) { Say ('  [dry-run] 备份 .docker\' + $f) } else { Copy-Item $s $dockerDir -Force } }
    }
  }

  # 目录迁移清单（记录来源，便于回滚）
  if (-not $DryRun) {
    $lines = @()
    $lines += ('# 迁移清单 - ' + (Get-Date))
    foreach ($k in $Src.Keys) { $lines += ('{0,-12} {1}' -f $k, $Src[$k]) }
    $lines | Set-Content (Join-Path $snapDir 'migration-manifest.txt') -Encoding UTF8
  }

  Say ('备份目录: ' + $snapDir) -ForegroundColor Green
}

# =============================================================================
# 阶段 2: 安装 JDK 21
# =============================================================================
if (-not (Skipped 'jdk')) {
  Step '阶段 2/9 - 安装 Eclipse Temurin 21 LTS 至 ' + $Target.jdk
  if (Test-Path (Join-Path $Target.jdk 'bin\javac.exe')) {
    Say ('已存在: ' + $Target.jdk)
    & (Join-Path $Target.jdk 'bin\javac.exe') -version 2>&1
  }
  elseif ($DryRun) {
    Say '  [dry-run] 下载 ' + $JdkDownload
    Say '  [dry-run] 静默安装: ' + $JdkInstaller + ' INSTALLDIR="' + $Target.jdk + '" /qn'
  }
  else {
    if (-not (Test-Path $Target.downloads)) { New-Item -ItemType Directory -Path $Target.downloads -Force | Out-Null }
    $env:DOTNET_NOLOGO = 1
    if (-not (Test-Path $JdkInstaller) -or ((Get-Item $JdkInstaller).Length -lt 100MB)) {
      if (Confirm '下载 Temurin 21 安装包（约 200MB）') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $JdkDownload -OutFile $JdkInstaller -UseBasicParsing
        Say ('下载完成: ' + ((Get-Item $JdkInstaller).Length / 1MB).ToString('0.0') + ' MB')
      }
    }
    if (Test-Path $JdkInstaller) {
      if (Confirm ('静默安装 JDK 21 -> ' + $Target.jdk)) {
        $p = Start-Process -FilePath $JdkInstaller -ArgumentList ('/INSTALLDIR="' + $Target.jdk + '" /norestart /q /log ' + $Target.downloads + '\jdk-install.log') -Wait -PassThru
        Say ('安装退出码: ' + $p.ExitCode)
        if (Test-Path (Join-Path $Target.jdk 'bin\javac.exe')) {
          Say 'JDK 21 安装成功' -ForegroundColor Green
          & (Join-Path $Target.jdk 'bin\java.exe') -version 2>&1
        } else {
          Fail 'JDK 安装后未找到 javac.exe，请查看 ' + $Target.downloads + '\jdk-install.log'
        }
      }
    }
  }
}

# =============================================================================
# 阶段 3: 清理损坏的 JBR
# =============================================================================
if (-not (Skipped 'jbr-clean')) {
  Step '阶段 3/9 - 清理损坏的 JBR 残留'
  if (Test-Path $Src.jbrBroken) {
    $sz = [math]::Round(((Get-ChildItem $Src.jbrBroken -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB, 1)
    Warn ('将删除: ' + $Src.jbrBroken + ' (' + $sz + ' MB, 缺 lib/jvm.cfg 与 javac.exe)')
    if ($DryRun) { Say '  [dry-run] 删除损坏 JBR' }
    elseif (Confirm '删除损坏的 JBR 目录') {
      Remove-Item $Src.jbrBroken -Recurse -Force
      Say '已删除损坏 JBR' -ForegroundColor Green
    }
  } else { Say '已不存在，跳过' }
}

# =============================================================================
# 阶段 4: 复制 Android SDK 至 D 盘
# =============================================================================
if (-not (Skipped 'sdk')) {
  Step '阶段 4/9 - 复制 Android SDK 至 ' + $Target.sdk
  if ((Test-Path (Join-Path $Target.sdk 'platform-tools\adb.exe')) -and (Test-Path (Join-Path $Target.sdk 'build-tools'))) {
    Say ('已存在: ' + $Target.sdk)
  }
  elseif ($DryRun) {
    Say ('  [dry-run] robocopy ' + $Src.sdk + ' -> ' + $Target.sdk + ' /MIR /COPY:DAT /MT:16')
    Say '  [dry-run] 保留原目录 C 盘 SDK 作为回滚点（约 8.4GB，验证通过后可手动删除）'
  }
  else {
    if (Confirm '复制 Android SDK（约 8.4GB，建议先确保 D 盘空间充足）') {
      $rcArgs = @($Src.sdk, $Target.sdk, '/MIR', '/COPY:DAT', '/R:2', '/W:5', '/MT:16', '/NFL', '/NDL', '/NP')
      $p = Start-Process -FilePath 'robocopy.exe' -ArgumentList $rcArgs -Wait -PassThru -NoNewWindow
      $code = $p.ExitCode
      if ($code -lt 8) { Say ('robocopy 退出码 ' + $code + '（<8 表示成功）') -ForegroundColor Green }
      else { Fail ('robocopy 退出码 ' + $code + '，复制失败，已中止后续') }
      # 校验关键组件
      $checks = @('platform-tools\adb.exe', 'build-tools', 'platforms', 'cmdline-tools', 'licenses', 'emulator', 'ndk')
      $bad = @()
      foreach ($c in $checks) { if (-not (Test-Path (Join-Path $Target.sdk $c))) { $bad += $c } }
      if ($bad.Count -eq 0) { Say 'SDK 组件校验通过' -ForegroundColor Green }
      else { Fail ('SDK 组件缺失: ' + ($bad -join ', ')) }
    }
  }
}

# =============================================================================
# 阶段 5: 迁移工具目录（Git / VS Code / GitHub Desktop / Flutter）
# =============================================================================
if (-not (Skipped 'migrate-tools')) {
  Step '阶段 5/9 - 迁移工具目录至 D:\app'

  # 卸载注册表项，避免迁移后启动器失效
  function Unregister-App($name, $idPattern) {
    if ($DryRun) { Say ('  [dry-run] 卸载注册表项: ' + $name); return }
    Say ('卸载注册表项: ' + $name)
    $items = Get-CimInstance Win32_Product -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $idPattern }
    if ($items) {
      foreach ($i in $items) {
        Say ('  卸载: ' + $i.Name)
        $p = Start-Process -FilePath $i.InstallLocation + '\uninstall.exe' -ArgumentList '/S' -Wait -PassThru -NoNewWindow -ErrorAction SilentlyContinue
      }
    } else {
      Warn ('未找到 Win32_Product 项，尝试直接删除 Uninstall 注册表键')
    }
  }

  # 5.1 Git: D:\软件\Git -> D:\app\Git
  if (Test-Path $Src.git) {
    if ($DryRun) { Say ('  [dry-run] 迁移 Git: ' + $Src.git + ' -> ' + $Target.git) }
    else {
      if (Confirm ('迁移 Git (' + $Src.git + ')')) {
        Get-Process -Name 'git','git-credential-manager','git-lfs' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $Target.git)) {
          Robo-Copy-Dir $Src.git $Target.git
          Remove-Item $Src.git -Recurse -Force -ErrorAction SilentlyContinue
        }
        # 重建注册表（Git 自身卸载器已随目录迁移，手动登记卸载入口）
        if (Confirm '重新登记 Git 到控制面板卸载列表') {
          Register-Uninstall $Target.git 'Git' '2.55.0.5'
        }
      }
    }
  } else { Say 'Git 源目录不存在，跳过' }

  # 5.2 VS Code
  if (Test-Path $Src.vscode) {
    if ($DryRun) { Say ('  [dry-run] 迁移 VS Code -> ' + $Target.vscode) }
    else {
      if (Confirm '迁移 VS Code') {
        Get-Process -Name 'Code' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $Target.vscode)) {
          Robo-Copy-Dir $Src.vscode $Target.vscode
          Remove-Item $Src.vscode -Recurse -Force -ErrorAction SilentlyContinue
        }
      }
    }
  } else { Say 'VS Code 源目录不存在，跳过' }

  # 5.3 GitHub Desktop
  if (Test-Path $Src.ghdesktop) {
    if ($DryRun) { Say ('  [dry-run] 迁移 GitHub Desktop -> ' + $Target.ghdesktop) }
    else {
      if (Confirm '迁移 GitHub Desktop') {
        Get-Process -Name 'GitHubDesktop' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $Target.ghdesktop)) {
          Robo-Copy-Dir $Src.ghdesktop $Target.ghdesktop
          Remove-Item $Src.ghdesktop -Recurse -Force -ErrorAction SilentlyContinue
        }
      }
    }
  } else { Say 'GitHub Desktop 源目录不存在，跳过' }

  # 5.4 Flutter（保持版本化实体目录，用 D:\app\Flutter 作为入口）
  if (Test-Path $Src.flutter) {
    if ($DryRun) { Say ('  [dry-run] 迁移 Flutter -> ' + $Target.flutter) }
    else {
      if (Confirm ('迁移 Flutter (' + $Src.flutter + ')')) {
        if (-not (Test-Path $Target.flutter)) {
          Robo-Copy-Dir $Src.flutter $Target.flutter
          Remove-Item $Src.flutter -Recurse -Force -ErrorAction SilentlyContinue
        }
        # 更新 Flutter 内置路径缓存
        if (Confirm '刷新 Flutter 工具缓存') {
          & (Join-Path $Target.flutter 'bin\flutter.bat') --version 2>&1 | Select-Object -First 3
        }
      }
    }
  } else { Say 'Flutter 源目录不存在，跳过' }
}

# =============================================================================
# 阶段 6: 迁移并清理 Gradle / Pub 缓存
# =============================================================================
if (-not (Skipped 'cache')) {
  Step '阶段 6/9 - 迁移 Gradle / Pub 缓存'

  if (Test-Path $Src.gradle) {
    $sz = [math]::Round(((Get-ChildItem $Src.gradle -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB)
    Warn ('旧缓存大小: ' + $sz + ' MB')
    if ($DryRun) { Say '  [dry-run] 清理旧缓存 + 建立 ' + $Target.gradle }
    else {
      if (Confirm ('删除旧 Gradle 缓存（' + $sz + 'MB），首次构建将重新下载依赖') {
        Get-Process -Name 'java' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep 2
        Remove-Item $Src.gradle -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $Src.gradle) { Fail '旧缓存删除失败，仍有文件被占用'; } else { Say '旧 Gradle 缓存已清理' -ForegroundColor Green }
      }
    }
  }
  New-Item -ItemType Directory -Path $Target.gradle -Force | Out-Null

  if (Test-Path $Src.pub) {
    if ($DryRun) { Say ('  [dry-run] 复制 Pub 缓存 -> ' + $Target.pub) }
    else {
      if (Confirm '复制 Pub 缓存到 D 盘（保留原位，仅切换 PUB_CACHE）') {
        if (-not (Test-Path $Target.pub)) { Robo-Copy-Dir $Src.pub $Target.pub }
      }
    }
  }
}

# =============================================================================
# 阶段 7: 环境变量
# =============================================================================
if (-not (Skipped 'env')) {
  Step '阶段 7/9 - 重写环境变量与 PATH'

  # 期望的最终 PATH（保留业务无关项，清理失效项）
  $sysPath = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').Path
  $newPath = @()
  # 系统基础段
  $sysPrefix = ($sysPath -split ';') | Where-Object { $_ -match 'Windows|dotnet|PhysX|NvDLISR' }
  $newPath += @($sysPrefix)
  # 新增 D 盘工具链
  $newPath += @(
    (Join-Path $Target.jdk 'bin')
    (Join-Path $Target.sdk 'platform-tools')
    (Join-Path $Target.flutter 'bin')
    (Join-Path $Target.git 'cmd')
    (Join-Path $Target.git 'mingw64\bin')
    (Join-Path $Target.vscode 'bin')
  )
  # 保留用户业务项
  $newPath += @(
    'd:\app\Trae CN\bin'
    'C:\Users\huwentao\AppData\Local\Programs\Python\Python312\Scripts\;C:\Users\huwentao\AppData\Local\Programs\Python\Python312\;C:\Users\huwentao\AppData\Local\Programs\Python\Launcher\'
    'C:\Users\huwentao\AppData\Local\Microsoft\WindowsApps'
    'C:\Users\huwentao\AppData\Local\Programs\DockerDesktop\resources\bin'
  )
  $ghBin = Join-Path $Target.ghdesktop 'bin'
  if (Test-Path $ghBin) { $newPath += $ghBin }

  $flat = @()
  foreach ($x in $newPath) { $flat += ($x -split ';') }
  $final = ($flat | Where-Object { $_.Trim() -ne '' } | Select-Object -Unique) -join ';'

  # 移除已知失效项
  $bad = @('D:\git\flutter\bin', 'D:\app\android\jbr\bin', 'D:\软件\Git\cmd', 'D:\软件\Microsoft VS Code\bin', 'C:\Users\huwentao\AppData\Local\GitHubDesktop\bin', 'C:\Users\huwentao\AppData\Local\Android\Sdk\platform-tools', $Src.flutter + '\bin')
  $final = ($final -split ';') | Where-Object { $_ -notin $bad } | ForEach-Object { $_.TrimEnd('\\') }
  $finalPath = ($final | Where-Object { $_ -ne '' } | Select-Object -Unique) -join ';'

  $userEnv = @{
    'Path'                     = $finalPath
    'JAVA_HOME'                = $Target.jdk
    'ANDROID_HOME'             = $Target.sdk
    'ANDROID_SDK_ROOT'         = $Target.sdk
    'GRADLE_USER_HOME'         = $Target.gradle
    'PUB_CACHE'                = $Target.pub
    'PUB_HOSTED_URL'           = 'https://pub.flutter-io.cn'
    'FLUTTER_STORAGE_BASE_URL' = 'https://storage.flutter-io.cn'
  }

  if ($DryRun) {
    Say '  [dry-run] 将写入以下用户环境变量:'
    foreach ($k in $userEnv.Keys) { Say ('    {0,-28} = {1}' -f $k, $userEnv[$k]) }
  }
  else {
    if (Confirm '写入用户环境变量') {
      foreach ($k in $userEnv.Keys) {
        Set-ItemProperty 'HKCU:\Environment' -Name $k -Value $userEnv[$k] -Type 'String'
      }
      # 系统级 ANDROID_HOME（供管理员工具与构建脚本使用）
      if (Confirm '同时在系统级写入 ANDROID_HOME / ANDROID_SDK_ROOT') {
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name 'ANDROID_HOME' -Value $Target.sdk -Type 'String'
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name 'ANDROID_SDK_ROOT' -Value $Target.sdk -Type 'String'
      }
      # 广播环境变量变更，使已打开的进程也能感知
      $sig = [IntPtr]::Size -eq 8 ? 64 : 32
      $HWND_BROADCAST = [int]0xFFFF
      $WM_SETTINGCHANGE = 0x001A
      $src = "using System; using System.Runtime.InteropServices; public class E { [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern int SendMessageTimeout(IntPtr h, uint m, IntPtr w, string t, uint f, uint t, out int r); }"
      $null = Add-Type -TypeDefinition $src -PassThru
      $r = 0
      [E]::SendMessageTimeout([IntPtr]$HWND_BROADCAST, $WM_SETTINGCHANGE, [IntPtr]0, 'Environment', 0x0002, 1000, [ref]$r) | Out-Null
      Say '环境变量已写入并广播' -ForegroundColor Green
    }
  }
}

# =============================================================================
# 阶段 8: 修正 WhatEat 项目配置
# =============================================================================
if (-not (Skipped 'project')) {
  Step '阶段 8/9 - 修正 WhatEat 项目构建配置'

  # 8.1 gradle.properties: 修正堆参数 + 开启增量编译
  $gp = Join-Path $ProjectAndroid 'gradle.properties'
  if (Test-Path $gp) {
    $txt = Get-Content $gp -Raw
    $new = $txt
    $new = $new -replace 'org\.gradle\.jvmargs=.*', 'org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError -XX:+UseStringDeduplication'
    $new = $new -replace 'kotlin\.incremental=false', 'kotlin.incremental=true'
    # 补充构建速度相关优化项
    if ($new -notmatch 'org\.gradle\.caching') { $new += "`norg.gradle.caching=true`norg.gradle.parallel=true`norg.gradle.configureondemand=true`n" }
    if ($new -notmatch 'android\.nonFinalResIds') { $new += "`nandroid.nonFinalResIds=false`n" }

    if ($DryRun) { Say '  [dry-run] 更新 gradle.properties'; Write-Host ($new -split "`n" | Where-Object { $_ -match 'jvmargs|incremental|caching|parallel|configureondemand|nonFinalResIds' }) -ForegroundColor DarkCyan }
    elseif (Confirm '更新 gradle.properties（修正 -Xmx8G -> 4G，开启增量编译）') {
      Set-Content $gp $new -Encoding UTF8
      Say 'gradle.properties 已更新' -ForegroundColor Green
    }
  }

  # 8.2 local.properties: 指向新 SDK 路径
  $lp = Join-Path $ProjectAndroid 'local.properties'
  if (Test-Path $lp) {
    $txt = Get-Content $lp -Raw
    $new = $txt -replace 'sdk\.dir=.*', ('sdk.dir=' + ($Target.sdk -replace '\\', '\\'))
    $new = $new -replace 'flutter\.sdk=.*', ('flutter.sdk=' + ($Target.flutter -replace '\\', '\\'))
    if ($DryRun) { Say '  [dry-run] 更新 local.properties'; Write-Host ($new -split "`n" | Where-Object { $_ -match 'sdk\.dir|flutter\.sdk' }) -ForegroundColor DarkCyan }
    elseif (Confirm '更新 local.properties 指向 D 盘 SDK / Flutter') {
      Set-Content $lp $new -Encoding UTF8
      Say 'local.properties 已更新' -ForegroundColor Green
    }
  }

  # 8.3 settings.gradle.kts: 已含阿里云仓库（无需改动）
  $sg = Join-Path $ProjectAndroid 'settings.gradle.kts'
  if (Test-Path $sg) {
    $txt = Get-Content $sg -Raw
    if ($txt -match 'maven\.aliyun\.com') { Say 'settings.gradle.kts 已含阿里云仓库，无需改动' }
    else { Warn 'settings.gradle.kts 未配置国内 Maven 源，建议补充' }
  }
}

# =============================================================================
# 阶段 9: 验证
# =============================================================================
if (-not (Skipped 'verify')) {
  Step '阶段 9/9 - 验证'
  if ($DryRun) { Say '  [dry-run] 将运行 flutter doctor / build apk / docker ps / git clone'; exit 0 }

  $results = @()

  Say '--- [1/5] JAVA_HOME ---'
  $j = Join-Path $Target.jdk 'bin\javac.exe'
  if (Test-Path $j) { & $j -version 2>&1 | ForEach-Object { $results += [pscustomobject]@{Item='JDK';Status='OK';Detail=$_} }; } else { $results += [pscustomobject]@{Item='JDK';Status='FAIL';Detail='javac.exe 缺失'} }

  Say '--- [2/5] Android SDK ---'
  $adb = Join-Path $Target.sdk 'platform-tools\adb.exe'
  if (Test-Path $adb) { $v = (Get-Item $adb).VersionInfo.ProductVersion; $results += [pscustomobject]@{Item='adb';Status='OK';Detail=$v} } else { $results += [pscustomobject]@{Item='adb';Status='FAIL';Detail='adb.exe 缺失'} }

  Say '--- [3/5] flutter doctor ---'
  $fl = Join-Path $Target.flutter 'bin\flutter.bat'
  if (Test-Path $fl) {
    & $fl doctor 2>&1 | Select-Object -First 25
    $results += [pscustomobject]@{Item='flutter';Status='OK';Detail=(Get-Item $fl).FullName}
  } else { $results += [pscustomobject]@{Item='flutter';Status='FAIL';Detail='flutter.bat 缺失'} }

  Say '--- [4/5] Docker ---'
  $docker = Get-Command docker -ErrorAction SilentlyContinue
  if ($docker) {
    $info = & docker version --format '{{.Server.Version}}' 2>&1
    $results += [pscustomobject]@{Item='docker';Status='OK';Detail=$info}
  } else { $results += [pscustomobject]@{Item='docker';Status='WARN';Detail='docker 命令不可用'} }

  Say '--- [5/5] GitHub 连通性 ---'
  $url = 'https://github.com/piggecn/whateat.git'
  $tmp = Join-Path $env:TEMP ('gh-test-' + (Get-Date -f 'HHmmss'))
  $cmd = @('--version','clone','-q','--depth','1',$url,$tmp)
  $r = Run 'git clone 测试仓库' $cmd
  if ($r -eq 0 -and (Test-Path $tmp)) {
    $results += [pscustomobject]@{Item='git-push';Status='OK';Detail='clone 成功'}
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    $results += [pscustomobject]@{Item='git-push';Status='WARN';Detail='clone 失败（可能需先配置凭据）'}
  }

  Say ''
  $results | Sort-Object Status | Format-Table Item, Status, Detail -AutoSize -Wrap
  Say ''
  if ($results | Where-Object { $_.Status -eq 'FAIL' }) { Fail '存在 FAIL 项，请检查对应阶段'; $exitCode = 1 }
  else { Say '迁移验证全部通过' -ForegroundColor Green; $exitCode = 0 }

  if (-not $DryRun -and $exitCode -eq 0) {
    Warn '验证通过后建议执行:'
    Say '  1. 重启所有终端与 IDE 以加载新环境变量'
    Say '  2. 删除 C 盘旧 Android SDK (释放约 8.4GB):'
    Say '     Remove-Item "C:\Users\huwentao\AppData\Local\Android\Sdk" -Recurse -Force'
    Say '  3. 清理微信缓存 (释放约 24.4GB): 需在微信设置中执行'
    Say '  4. 生成 SSH 密钥并上传 GitHub（当前无密钥，依赖弹窗认证）:'
    Say '     ssh-keygen -t ed25519 -C "hu85454@gmail.com"'
  }
  exit $exitCode
}
