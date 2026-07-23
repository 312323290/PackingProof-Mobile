[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $PSScriptRoot 'Build-Android.ps1'
$pubspecPath = Join-Path $repo 'pubspec.yaml'

if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw "找不到 Android 构建脚本：$builder"
}

$pattern = '^version:\s*([^+\s]+)\+([1-9]\d*)\s*$'
$versionLine = [IO.File]::ReadAllLines($pubspecPath, [Text.Encoding]::UTF8) |
    Where-Object { [regex]::IsMatch($_, $pattern) } |
    Select-Object -First 1
if (-not $versionLine) {
    throw 'pubspec.yaml 缺少有效的 version: x.y.z+versionCode'
}
$match = [regex]::Match($versionLine, $pattern)
$versionName = $match.Groups[1].Value
$versionCode = [int]$match.Groups[2].Value

Write-Host "正在构建 Release 调试安装包：$versionName+$versionCode"
Write-Host '该 APK 使用调试证书，仅用于本地安装和问题排查'

& $builder -VersionName $versionName -VersionCode $versionCode
if ($LASTEXITCODE -ne 0) {
    throw "Release 调试安装包构建失败，退出代码：$LASTEXITCODE"
}

$apkPath = Join-Path $repo 'dist/android/PackingProof-Mobile.apk'
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "构建完成但找不到安装包：$apkPath"
}
Write-Host "构建成功：$apkPath" -ForegroundColor Green
