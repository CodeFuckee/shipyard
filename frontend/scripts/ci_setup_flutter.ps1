# ================================================================
# Flutter SDK 自动检测脚本（Windows / PowerShell）
# ================================================================
if (Get-Command flutter -ErrorAction SilentlyContinue) {
  Write-Host "Flutter found in PATH"
  exit 0
}
foreach ($p in @($env:FLUTTER_ROOT, 'C:\flutter', "$env:USERPROFILE\flutter", "$env:USERPROFILE\fvm\default")) {
  if ($p -and (Test-Path "$p\bin\flutter.bat")) {
    $env:Path = "$p\bin;$env:Path"
    git config --global --add safe.directory $p
    Write-Host "Flutter found at: $p"
    exit 0
  }
}
Write-Host "WARNING: Flutter not found. Set FLUTTER_ROOT in GitLab Variables or add flutter to PATH."
