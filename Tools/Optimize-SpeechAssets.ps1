[CmdletBinding()]
param(
    [string]$ManifestPath = 'assets/audio/tts/manifest.json',
    [int]$AssetVersion = 3,
    [double]$MaximumLeadingSilenceSeconds = 0.04
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$resolvedManifest = [IO.Path]::GetFullPath((Join-Path $repo $ManifestPath))
if (-not (Test-Path -LiteralPath $resolvedManifest)) {
    throw "找不到语音清单：$resolvedManifest"
}
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw '找不到 ffmpeg，无法检测和裁切语音起始静音'
}

function Get-LeadingSilenceSeconds {
    param([Parameter(Mandatory)][string]$AudioPath)
    $lines = & ffmpeg -hide_banner -i $AudioPath `
        -af 'silencedetect=noise=-45dB:d=0.01' -f null NUL 2>&1
    $startsAtBeginning = $false
    foreach ($line in $lines) {
        if ("$line" -match 'silence_start:\s*([0-9.]+)') {
            $start = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
            if ($start -gt 0.005) { return 0.0 }
            $startsAtBeginning = $true
            continue
        }
        if ($startsAtBeginning -and "$line" -match 'silence_end:\s*([0-9.]+)') {
            return [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
        }
    }
    return 0.0
}

function Get-CacheKey {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Voice,
        [Parameter(Mandatory)][string]$Format,
        [Parameter(Mandatory)][string]$Version
    )
    $inputText = "$Text|$Voice|$Format|$Version"
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($inputText))
    ).ToLowerInvariant()
}

$manifest = Get-Content -Raw -Encoding UTF8 $resolvedManifest | ConvertFrom-Json
$audioRoot = Split-Path -Parent $resolvedManifest
$manifest.version = $AssetVersion
$changed = $false

foreach ($prompt in $manifest.prompts) {
    $audioPath = Join-Path $audioRoot $prompt.file
    if (-not (Test-Path -LiteralPath $audioPath)) {
        throw "缺少语音文件：$($prompt.file)"
    }
    $leadingSilence = Get-LeadingSilenceSeconds -AudioPath $audioPath
    if ($leadingSilence -gt $MaximumLeadingSilenceSeconds) {
        $temporaryPath = "$audioPath.optimized.mp3"
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        try {
            & ffmpeg -hide_banner -loglevel error -y -i $audioPath `
                -af 'silenceremove=start_periods=1:start_duration=0.01:start_threshold=-45dB:start_silence=0.025' `
                -ar 24000 -ac 1 -b:a 48k $temporaryPath
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryPath)) {
                throw "语音裁切失败：$($prompt.file)"
            }
            $optimizedSilence = Get-LeadingSilenceSeconds -AudioPath $temporaryPath
            if ($optimizedSilence -gt $MaximumLeadingSilenceSeconds) {
                throw "语音起始静音仍超过限制：$($prompt.file)"
            }
            Move-Item -LiteralPath $temporaryPath -Destination $audioPath -Force
            Write-Host ("已裁切：{0} ({1:N0}ms -> {2:N0}ms)" -f $prompt.file, ($leadingSilence * 1000), ($optimizedSilence * 1000))
            $changed = $true
        }
        finally {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host ("已复用：{0} ({1:N0}ms)" -f $prompt.file, ($leadingSilence * 1000))
    }

    $bytes = (Get-Item -LiteralPath $audioPath).Length
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $audioPath).Hash.ToLowerInvariant()
    $cacheKey = Get-CacheKey -Text $prompt.text -Voice $prompt.voice -Format $manifest.format -Version "$AssetVersion"
    if ([long]$prompt.bytes -ne $bytes -or "$($prompt.sha256)" -ne $sha256 -or "$($prompt.cacheKey)" -ne $cacheKey) {
        $prompt.bytes = $bytes
        $prompt.sha256 = $sha256
        $prompt.cacheKey = $cacheKey
        $changed = $true
    }
}

if ($changed) {
    [IO.File]::WriteAllText(
        $resolvedManifest,
        ($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
    Write-Host '语音文件与清单已更新'
}
else {
    Write-Host '语音文件均符合起始静音限制，无需修改'
}
