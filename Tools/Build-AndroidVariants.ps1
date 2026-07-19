[CmdletBinding()]
param(
    [string]$VersionName = '0.3.1',
    [int]$VersionCode = 9002,
    [string]$OutputDirectory = 'dist/android'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

if ($VersionName -notmatch '^\d+\.\d+\.\d+$') {
    throw 'VersionName 必须为 x.y.z 格式'
}
if ($VersionCode -le 0) {
    throw 'VersionCode 必须大于 0'
}

$manifestPath = Join-Path $repo 'assets/audio/tts/manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "缺少内置 Edge 语音清单：$manifestPath"
}
$manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
foreach ($prompt in $manifest.prompts) {
    $audioPath = Join-Path (Split-Path -Parent $manifestPath) $prompt.file
    if (-not (Test-Path -LiteralPath $audioPath)) {
        throw "缺少内置 Edge 语音：$($prompt.file)"
    }
    if ((Get-Item -LiteralPath $audioPath).Length -ne [long]$prompt.bytes) {
        throw "内置 Edge 语音大小与清单不一致：$($prompt.file)"
    }
}

flutter clean
flutter pub get
flutter analyze
flutter test

$editions = @(
    @{ Flavor = 'standard'; OnlineTts = 'true'; NetworkPolicy = 'publicAllowed' },
    @{ Flavor = 'standalone'; OnlineTts = 'false'; NetworkPolicy = 'localOnly' }
)
$resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path $repo $OutputDirectory))
New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
$checksumLines = @()

foreach ($edition in $editions) {
    flutter build apk --release `
        --flavor $edition.Flavor `
        --build-name $VersionName `
        --build-number $VersionCode `
        --dart-define="APP_EDITION=$($edition.Flavor)" `
        --dart-define="ONLINE_EDGE_TTS_ENABLED=$($edition.OnlineTts)" `
        --dart-define="NETWORK_POLICY=$($edition.NetworkPolicy)"

    $source = Join-Path $repo "build/app/outputs/flutter-apk/app-$($edition.Flavor)-release.apk"
    if (-not (Test-Path -LiteralPath $source)) {
        throw "未找到构建产物：$source"
    }
    $fileName = "PackingProof-Mobile-$($edition.Flavor).apk"
    $destination = Join-Path $resolvedOutput $fileName
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
    $checksumLines += "$hash  $fileName"
}

$checksumPath = Join-Path $resolvedOutput 'SHA256SUMS.txt'
[System.IO.File]::WriteAllLines(
    $checksumPath,
    $checksumLines,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host "两个 Android 版本已输出到 $resolvedOutput"
