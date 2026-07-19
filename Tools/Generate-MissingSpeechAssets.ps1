[CmdletBinding()]
param(
    [string]$ManifestPath = 'assets/audio/tts/manifest.json',
    [string]$PythonCommand = 'python'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$resolvedManifest = [IO.Path]::GetFullPath((Join-Path $repo $ManifestPath))
if (-not (Test-Path -LiteralPath $resolvedManifest)) {
    throw "找不到语音清单：$resolvedManifest"
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
$changed = $false

foreach ($prompt in $manifest.prompts) {
    $expectedKey = Get-CacheKey -Text $prompt.text -Voice $prompt.voice -Format $manifest.format -Version "$($manifest.version)"
    $audioPath = Join-Path $audioRoot $prompt.file
    $isReusable = $false
    if (Test-Path -LiteralPath $audioPath) {
        $file = Get-Item -LiteralPath $audioPath
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $audioPath).Hash.ToLowerInvariant()
        $isReusable = $file.Length -ge 128 -and
            $file.Length -eq [long]$prompt.bytes -and
            $hash -eq "$($prompt.sha256)".ToLowerInvariant() -and
            $expectedKey -eq "$($prompt.cacheKey)".ToLowerInvariant()
    }

    if ($isReusable) {
        Write-Host "复用：$($prompt.file)"
        continue
    }

    $temporaryPath = "$audioPath.generating"
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    try {
        Write-Host "生成缺失语音：$($prompt.file)"
        & $PythonCommand -m edge_tts `
            --voice $prompt.voice `
            --text $prompt.text `
            --write-media $temporaryPath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryPath)) {
            throw "Edge TTS 生成失败：$($prompt.file)"
        }
        $generated = Get-Item -LiteralPath $temporaryPath
        if ($generated.Length -lt 128) { throw "生成的语音文件无效：$($prompt.file)" }
        Move-Item -LiteralPath $temporaryPath -Destination $audioPath -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }

    $prompt.bytes = (Get-Item -LiteralPath $audioPath).Length
    $prompt.sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $audioPath).Hash.ToLowerInvariant()
    $prompt.cacheKey = $expectedKey
    $changed = $true
}

if ($changed) {
    $json = $manifest | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($resolvedManifest, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Write-Host '语音清单已更新'
}
else {
    Write-Host '所有语音资产均可复用，未发起网络生成'
}
