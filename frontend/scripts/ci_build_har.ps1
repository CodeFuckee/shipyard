# ================================================================
# Flutter HAR 构建设置脚本（Windows / PowerShell）
# ================================================================
$ErrorActionPreference = "Stop"

Write-Host "=== HAR Build Setup (Windows) ==="

# 清理构建产物（替代 git clean，因 .ohos 长路径超过 Windows MAX_PATH 260 字符限制）
$dirsToClean = @("$env:CI_PROJECT_DIR\.dart_tool", "$env:CI_PROJECT_DIR\build", "$env:CI_PROJECT_DIR\.android", "$env:CI_PROJECT_DIR\.ios", "$env:CI_PROJECT_DIR\.ohos", "$env:CI_PROJECT_DIR\macos\Flutter\ephemeral")
foreach ($d in $dirsToClean) { if (Test-Path $d) { cmd /c "rmdir /s /q `"\\?\$d`"" 2>$null } }
$filesToClean = @("$env:CI_PROJECT_DIR\.flutter-plugins-dependencies")
foreach ($f in $filesToClean) { if (Test-Path $f) { Remove-Item -Path $f -Force -ErrorAction SilentlyContinue } }

chcp.com 65001 2>$null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "PUB_HOSTED_URL = $env:PUB_HOSTED_URL"
Write-Host "FLUTTER_STORAGE_BASE_URL = $env:FLUTTER_STORAGE_BASE_URL"

git config --global --add safe.directory "$env:CI_PROJECT_DIR"

# Flutter SDK 自动检测
foreach ($p in @($env:FLUTTER_ROOT, 'C:\flutter', "$env:USERPROFILE\flutter", "$env:USERPROFILE\fvm\default")) {
  if ($p -and (Test-Path "$p\bin\flutter.bat")) {
    $env:Path = "$p\bin;$env:Path"
    git config --global --add safe.directory $p
    break
  }
}

# HarmonyOS/OpenHarmony SDK 路径
foreach ($p in @($env:OHOS_SDK_HOME, $env:OHOS_HOME, $env:HOS_SDK_HOME)) {
  if ($p -and (Test-Path $p)) {
    flutter config --ohos-sdk $p
    break
  }
}

# HVIGOR_USER_HOME 设置（路径不能有空格）
if (-not $env:HVIGOR_USER_HOME) { $env:HVIGOR_USER_HOME = 'C:\hvigor_home' }
if ($env:HVIGOR_USER_HOME -match '\s') {
  Write-Error "HVIGOR_USER_HOME contains spaces, which breaks hvigor: $env:HVIGOR_USER_HOME"
  exit 1
}
if (-not (Test-Path $env:HVIGOR_USER_HOME)) {
  New-Item -ItemType Directory -Path $env:HVIGOR_USER_HOME -Force *>$null
  Write-Host "Created HVIGOR_USER_HOME: $env:HVIGOR_USER_HOME"
}
Write-Host "HVIGOR_USER_HOME = $env:HVIGOR_USER_HOME"

# Node.js 健康检查和自动下载
if (-not $env:NODEJS_HOME) { $env:NODEJS_HOME = 'D:\nodejs' }
$nodejsDir = $env:NODEJS_HOME
if ($nodejsDir -match '\s') {
  Write-Error "NODEJS_HOME contains spaces, which breaks npm: $nodejsDir"
  exit 1
}
$npmHealthCheckFile = "$nodejsDir\node_modules\npm\bin\npm-prefix.js"
if (-not (Test-Path $npmHealthCheckFile)) {
  Write-Host "Node.js installation missing or broken at $nodejsDir, re-downloading..."
  Remove-Item -Path $nodejsDir -Recurse -Force -ErrorAction SilentlyContinue
  $ProgressPreference = 'SilentlyContinue'
  if (-not $env:NODEJS_DOWNLOAD_URL) { $env:NODEJS_DOWNLOAD_URL = 'https://npmmirror.com/mirrors/node' }
  if (-not $env:NODEJS_VERSION) { $env:NODEJS_VERSION = 'v20.18.0' }
  $nodeDownloadUrl = "$env:NODEJS_DOWNLOAD_URL/$env:NODEJS_VERSION/node-$env:NODEJS_VERSION-win-x64.zip"
  $nodeZip = "$env:TEMP\node-portable.zip"
  $nodeExtract = "$env:TEMP\node-extract"
  Remove-Item -Path $nodeExtract -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "Downloading Node.js from: $nodeDownloadUrl"
  Invoke-WebRequest -Uri $nodeDownloadUrl -OutFile $nodeZip
  Expand-Archive -Path $nodeZip -DestinationPath $nodeExtract -Force
  $innerDir = Get-ChildItem -Path $nodeExtract -Directory | Select-Object -First 1
  Remove-Item -Path $nodejsDir -Recurse -Force -ErrorAction SilentlyContinue
  Move-Item -Path $innerDir.FullName -Destination $nodejsDir
  Remove-Item $nodeZip -Force -ErrorAction SilentlyContinue
  Remove-Item $nodeExtract -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "Portable Node.js installed to $nodejsDir"
}

$env:NODE_HOME = $env:NODEJS_HOME
$env:Path = "$env:NODEJS_HOME;$env:Path"
Write-Host "NODE_HOME = $env:NODE_HOME"

# npm 注册表配置
if (-not $env:NPM_REGISTRY_URL) { $env:NPM_REGISTRY_URL = 'https://registry.npmmirror.com' }
$env:npm_config_registry = $env:NPM_REGISTRY_URL
npm config set registry $env:NPM_REGISTRY_URL
Write-Host "npm registry set to $env:NPM_REGISTRY_URL"
npm cache clean --force 2>$null
Write-Host "Node.js at $env:NODEJS_HOME, npm registry: $env:NPM_REGISTRY_URL"

# pnpm 预安装（hvigor wrapper 依赖）
Write-Host "Pre-installing pnpm@10.28.2 for hvigor wrapper..."
$hvigorToolsDir = "$env:HVIGOR_USER_HOME\wrapper\tools"
New-Item -ItemType Directory -Path $hvigorToolsDir -Force -ErrorAction SilentlyContinue *>$null
Push-Location $hvigorToolsDir
try {
  npm install pnpm@10.28.2 --no-save --no-audit --no-fund 2>&1
  if ($LASTEXITCODE -ne 0) { Write-Error "pnpm pre-install failed"; exit 1 }
  Write-Host "pnpm pre-installed at: $hvigorToolsDir"
} finally {
  Pop-Location
}

# 备选：SYSTEM 默认 home 目录
if ($env:USERPROFILE -and ($env:USERPROFILE -ne $env:HVIGOR_USER_HOME)) {
  $systemHvigorToolsDir = "$env:USERPROFILE\.hvigor\wrapper\tools"
  New-Item -ItemType Directory -Path $systemHvigorToolsDir -Force -ErrorAction SilentlyContinue *>$null
  Push-Location $systemHvigorToolsDir
  try {
    npm install pnpm@10.28.2 --no-save --no-audit --no-fund 2>&1
    Write-Host "pnpm also installed at: $systemHvigorToolsDir"
  } finally {
    Pop-Location
  }
}

Write-Host "=== Setup complete, running flutter build ==="
flutter pub get
flutter build har --release
