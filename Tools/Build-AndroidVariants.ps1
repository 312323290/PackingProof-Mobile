[CmdletBinding()]
param(
    [string]$VersionName = '0.5.0',
    [int]$VersionCode = 11000,
    [string]$OutputDirectory = 'dist/android',
    [string]$SigningDirectory = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

if ($VersionName -notmatch '^\d+\.\d+\.\d+$') { throw 'VersionName 必须为 x.y.z 格式' }
if ($VersionCode -le 0) { throw 'VersionCode 必须大于 0' }

function Get-TtsAssetState {
    param([Parameter(Mandatory)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "缺少内置 Edge 语音清单：$ManifestPath"
    }
    $manifest = Get-Content -Raw -Encoding UTF8 $ManifestPath | ConvertFrom-Json
    $result = [ordered]@{}
    foreach ($prompt in $manifest.prompts) {
        $audioPath = Join-Path (Split-Path -Parent $ManifestPath) $prompt.file
        if (-not (Test-Path -LiteralPath $audioPath)) { throw "缺少内置 Edge 语音：$($prompt.file)" }
        $file = Get-Item -LiteralPath $audioPath
        if ($file.Length -ne [long]$prompt.bytes) { throw "内置 Edge 语音大小与清单不一致：$($prompt.file)" }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $audioPath).Hash.ToLowerInvariant()
        if ($hash -ne "$($prompt.sha256)".ToLowerInvariant()) { throw "内置 Edge 语音哈希与清单不一致：$($prompt.file)" }
        $cacheInput = "$($prompt.text)|$($prompt.voice)|$($manifest.format)|$($manifest.version)"
        $cacheHash = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($cacheInput))
        ).ToLowerInvariant()
        if ($cacheHash -ne "$($prompt.cacheKey)".ToLowerInvariant()) { throw "内置 Edge 语音缓存键与清单不一致：$($prompt.file)" }
        $result[$prompt.file] = $hash
    }
    return $result
}

function Assert-SameTtsState {
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After)
    if ($Before.Count -ne $After.Count) { throw '构建过程改变了内置语音文件数量' }
    foreach ($name in $Before.Keys) {
        if (-not $After.Contains($name) -or $Before[$name] -ne $After[$name]) {
            throw "构建过程覆盖了内置语音：$name"
        }
    }
}

function Resolve-ApkAnalyzer {
    $candidates = @(
        (Join-Path "$env:ANDROID_HOME" 'cmdline-tools/latest/bin/apkanalyzer.bat'),
        (Join-Path "$env:ANDROID_SDK_ROOT" 'cmdline-tools/latest/bin/apkanalyzer.bat'),
        (Join-Path "$env:LOCALAPPDATA" 'Android/Sdk/cmdline-tools/latest/bin/apkanalyzer.bat')
    )
    $resolved = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $resolved) { throw '找不到 apkanalyzer，无法校验 APK 元数据' }
    return $resolved
}

function Resolve-ApkSigner {
    $sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android/Sdk')) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($root in $sdkRoots) {
        $tool = Get-ChildItem -LiteralPath (Join-Path $root 'build-tools') -Directory -ErrorAction SilentlyContinue |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($tool) { return $tool }
    }
    throw '找不到 apksigner，无法校验 APK 正式签名'
}

function Resolve-KeyTool {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin/keytool.exe') }
    $candidates += @(
        'C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe',
        'C:/Program Files/Android/Android Studio/jre/bin/keytool.exe'
    )
    $javaRoots = Get-ChildItem -LiteralPath 'C:/Program Files/Java' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    $candidates += $javaRoots | ForEach-Object { Join-Path $_.FullName 'bin/keytool.exe' }
    $resolved = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $resolved) { throw '找不到 JDK keytool，无法读取正式签名证书' }
    return $resolved
}

function Get-SigningConfiguration {
    param([Parameter(Mandatory)][string]$Directory)
    $resolved = [IO.Path]::GetFullPath($Directory)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "签名目录不存在：$resolved"
    }
    $credentialPath = Join-Path $resolved '签名凭据.txt'
    if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
        throw "签名目录缺少签名凭据.txt：$resolved"
    }
    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($credentialPath, [Text.Encoding]::UTF8)) {
        $separator = $line.IndexOf([char]0xFF1A)
        if ($separator -lt 0) { $separator = $line.IndexOf(':') }
        if ($separator -le 0) { continue }
        $label = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        if ($label -in @('密钥文件', '别名', '密钥库密码', '密钥密码')) {
            $values[$label] = $value
        }
    }
    foreach ($label in @('密钥文件', '别名', '密钥库密码', '密钥密码')) {
        if ([string]::IsNullOrWhiteSpace($values[$label])) {
            throw "签名凭据缺少字段：$label"
        }
    }
    $keyStorePath = $values['密钥文件']
    if (-not [IO.Path]::IsPathRooted($keyStorePath)) {
        $keyStorePath = Join-Path $resolved $keyStorePath
    }
    $keyStorePath = [IO.Path]::GetFullPath($keyStorePath)
    if (-not (Test-Path -LiteralPath $keyStorePath -PathType Leaf)) {
        throw "找不到签名密钥文件：$keyStorePath"
    }
    return [ordered]@{
        KeyStorePath = $keyStorePath
        KeyAlias = $values['别名']
        StorePassword = $values['密钥库密码']
        KeyPassword = $values['密钥密码']
    }
}

function Get-KeyStoreCertificateSha256 {
    param(
        [Parameter(Mandatory)]$Signing,
        [Parameter(Mandatory)][string]$KeyTool
    )
    $env:PACKING_PROOF_STORE_PASSWORD = $Signing.StorePassword
    $output = (& $KeyTool -list -v -keystore $Signing.KeyStorePath -alias $Signing.KeyAlias -storepass:env PACKING_PROOF_STORE_PASSWORD) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'SHA256:\s*([0-9A-F:]{95})') {
        throw '无法读取正式签名证书，请检查别名和密钥库密码'
    }
    return $matches[1].Replace(':', '').ToLowerInvariant()
}

function Assert-ApkSignature {
    param(
        [Parameter(Mandatory)][string]$ApkPath,
        [Parameter(Mandatory)][string]$ApkSigner,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )
    $output = (& $ApkSigner verify --verbose --print-certs $ApkPath) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "APK 签名校验失败：$ApkPath" }
    if ($output -notmatch 'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})') {
        throw "无法读取 APK 签名证书：$ApkPath"
    }
    if ($matches[1].ToLowerInvariant() -ne $ExpectedSha256) {
        throw "APK 未使用指定的 PackingProof 正式证书：$ApkPath"
    }
}

function Assert-ApkMetadata {
    param(
        [Parameter(Mandatory)][string]$ApkPath,
        [Parameter(Mandatory)][string]$Edition,
        [Parameter(Mandatory)][string]$Revision,
        [Parameter(Mandatory)][string]$Timestamp,
        [Parameter(Mandatory)][datetime]$BuildStartedAt,
        [Parameter(Mandatory)][string]$Analyzer
    )
    $file = Get-Item -LiteralPath $ApkPath
    if ($file.LastWriteTimeUtc -lt $BuildStartedAt.AddSeconds(-2)) { throw "APK 不是本次构建产物：$ApkPath" }
    if ((& $Analyzer manifest application-id $ApkPath).Trim() -ne 'app.packingproof.mobile') { throw "APK 包名错误：$ApkPath" }
    if ((& $Analyzer manifest version-name $ApkPath).Trim() -ne $VersionName) { throw "APK 版本名错误：$ApkPath" }
    if ([int](& $Analyzer manifest version-code $ApkPath).Trim() -ne $VersionCode) { throw "APK 版本号错误：$ApkPath" }
    $manifestText = (& $Analyzer manifest print $ApkPath) -join "`n"
    foreach ($expected in @($Edition, $Revision, $Timestamp)) {
        if (-not $manifestText.Contains($expected)) { throw "APK 缺少构建标识 $expected：$ApkPath" }
    }
}

$manifestPath = Join-Path $repo 'assets/audio/tts/manifest.json'
$ttsBefore = Get-TtsAssetState -ManifestPath $manifestPath
$revision = (git rev-parse --short=8 HEAD).Trim()
if (-not $revision) { throw '无法读取 Git 修订号' }
$buildTimestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$buildStartedAt = [DateTime]::UtcNow
$env:PACKING_PROOF_BUILD_REVISION = $revision
$env:PACKING_PROOF_BUILD_TIMESTAMP = $buildTimestamp
$analyzer = Resolve-ApkAnalyzer
$signing = $null
$signingCertificateSha256 = $null
if (-not [string]::IsNullOrWhiteSpace($SigningDirectory)) {
    $signing = Get-SigningConfiguration -Directory $SigningDirectory
    $env:PACKING_PROOF_KEYSTORE_PATH = $signing.KeyStorePath
    $env:PACKING_PROOF_KEY_ALIAS = $signing.KeyAlias
    $env:PACKING_PROOF_STORE_PASSWORD = $signing.StorePassword
    $env:PACKING_PROOF_KEY_PASSWORD = $signing.KeyPassword
    $env:PACKING_PROOF_REQUIRE_RELEASE_SIGNING = 'true'
    $keyTool = Resolve-KeyTool
    $signingCertificateSha256 = Get-KeyStoreCertificateSha256 -Signing $signing -KeyTool $keyTool
    $apkSigner = Resolve-ApkSigner
}

$resolvedOutput = [IO.Path]::GetFullPath((Join-Path $repo $OutputDirectory))
$resolvedRepo = [IO.Path]::GetFullPath($repo).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedOutput.StartsWith($resolvedRepo, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory 必须位于当前仓库内'
}
$outputParent = Split-Path -Parent $resolvedOutput
$temporaryOutput = Join-Path $outputParent ".packing-proof-android-$([Guid]::NewGuid().ToString('N'))"
if (-not ([IO.Path]::GetFullPath($temporaryOutput)).StartsWith($resolvedRepo, [StringComparison]::OrdinalIgnoreCase)) {
    throw '临时输出目录必须位于当前仓库内'
}
New-Item -ItemType Directory -Force -Path $temporaryOutput | Out-Null

try {
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $repo 'build/app/outputs/flutter-apk/*.apk')
    if (Test-Path -LiteralPath $resolvedOutput) {
        Get-ChildItem -LiteralPath $resolvedOutput -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'PackingProof-Mobile-*.apk' -or $_.Name -in @('SHA256SUMS.txt', 'build-manifest.json') } |
            Remove-Item -Force
    }

    flutter clean
    flutter pub get
    flutter analyze
    flutter test

    $editions = @(
        @{ Flavor = 'standard'; OnlineTts = 'true'; NetworkPolicy = 'publicAllowed' },
        @{ Flavor = 'standalone'; OnlineTts = 'false'; NetworkPolicy = 'localOnly' }
    )
    $artifacts = @()
    foreach ($edition in $editions) {
        flutter build apk --release `
            --flavor $edition.Flavor `
            --build-name $VersionName `
            --build-number $VersionCode `
            --dart-define="APP_EDITION=$($edition.Flavor)" `
            --dart-define="ONLINE_EDGE_TTS_ENABLED=$($edition.OnlineTts)" `
            --dart-define="NETWORK_POLICY=$($edition.NetworkPolicy)" `
            --dart-define="BUILD_REVISION=$revision" `
            --dart-define="BUILD_TIMESTAMP=$buildTimestamp"

        $source = Join-Path $repo "build/app/outputs/flutter-apk/app-$($edition.Flavor)-release.apk"
        if (-not (Test-Path -LiteralPath $source)) { throw "未找到构建产物：$source" }
        Assert-ApkMetadata -ApkPath $source -Edition $edition.Flavor -Revision $revision -Timestamp $buildTimestamp -BuildStartedAt $buildStartedAt -Analyzer $analyzer
        if ($signing) {
            Assert-ApkSignature -ApkPath $source -ApkSigner $apkSigner -ExpectedSha256 $signingCertificateSha256
        }
        $fileName = "PackingProof-Mobile-$($edition.Flavor).apk"
        $destination = Join-Path $temporaryOutput $fileName
        Copy-Item -LiteralPath $source -Destination $destination
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
        $artifacts += [ordered]@{ edition = $edition.Flavor; file = $fileName; sha256 = $hash; bytes = (Get-Item $destination).Length }
    }

    $checksumLines = $artifacts | ForEach-Object { "$($_.sha256)  $($_.file)" }
    [IO.File]::WriteAllLines((Join-Path $temporaryOutput 'SHA256SUMS.txt'), $checksumLines, [Text.UTF8Encoding]::new($false))
    $buildManifest = [ordered]@{
        versionName = $VersionName
        versionCode = $VersionCode
        packageName = 'app.packingproof.mobile'
        revision = $revision
        builtAtUtc = $buildTimestamp
        releaseSigned = [bool]$signing
        signingCertificateSha256 = $signingCertificateSha256
        artifacts = $artifacts
    }
    [IO.File]::WriteAllText(
        (Join-Path $temporaryOutput 'build-manifest.json'),
        ($buildManifest | ConvertTo-Json -Depth 5),
        [Text.UTF8Encoding]::new($false)
    )

    $ttsAfter = Get-TtsAssetState -ManifestPath $manifestPath
    Assert-SameTtsState -Before $ttsBefore -After $ttsAfter

    $previousOutput = "$resolvedOutput.previous"
    if (-not ([IO.Path]::GetFullPath($previousOutput)).StartsWith($resolvedRepo, [StringComparison]::OrdinalIgnoreCase)) {
        throw '旧输出目录必须位于当前仓库内'
    }
    Remove-Item -LiteralPath $previousOutput -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $resolvedOutput) { Move-Item -LiteralPath $resolvedOutput -Destination $previousOutput }
    Move-Item -LiteralPath $temporaryOutput -Destination $resolvedOutput
    Remove-Item -LiteralPath $previousOutput -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "两个 Android 版本已输出到 $resolvedOutput"
}
finally {
    Remove-Item -LiteralPath $temporaryOutput -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:PACKING_PROOF_BUILD_REVISION -ErrorAction SilentlyContinue
    Remove-Item Env:PACKING_PROOF_BUILD_TIMESTAMP -ErrorAction SilentlyContinue
    Remove-Item Env:PACKING_PROOF_KEYSTORE_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:PACKING_PROOF_KEY_ALIAS -ErrorAction SilentlyContinue
    Remove-Item Env:PACKING_PROOF_STORE_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:PACKING_PROOF_KEY_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:PACKING_PROOF_REQUIRE_RELEASE_SIGNING -ErrorAction SilentlyContinue
}
