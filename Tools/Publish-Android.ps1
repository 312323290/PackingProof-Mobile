[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SigningDirectory
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $PSScriptRoot 'Build-Android.ps1'

function Get-PubspecVersion {
    $pubspecPath = Join-Path $repo 'pubspec.yaml'
    $pattern = '^version:\s*([^+\s]+)\+([1-9]\d*)\s*$'
    $versionLine = [IO.File]::ReadAllLines($pubspecPath, [Text.Encoding]::UTF8) |
        Where-Object { [regex]::IsMatch($_, $pattern) } |
        Select-Object -First 1
    if (-not $versionLine) {
        throw 'pubspec.yaml 缺少有效的 version: x.y.z+versionCode'
    }
    $versionMatch = [regex]::Match($versionLine, $pattern)
    return [ordered]@{
        VersionName = $versionMatch.Groups[1].Value
        VersionCode = [int]$versionMatch.Groups[2].Value
    }
}

function Get-TaggedReleaseVersion {
    $tagsAtHead = @(& git -C $repo tag --points-at HEAD)
    if ($LASTEXITCODE -ne 0) { throw '无法读取当前提交的 Git 标签' }

    $pattern = '^v?(?<name>\d+\.\d+\.\d+)(?:\+(?<code>[1-9]\d*))?$'
    $releaseTags = @($tagsAtHead | Where-Object { [regex]::IsMatch($_, $pattern) })
    if ($releaseTags.Count -eq 0) {
        throw '当前提交没有版本标签。请先创建类似 v0.5.4+11004 的标签'
    }
    if ($releaseTags.Count -gt 1) {
        throw "当前提交存在多个版本标签：$($releaseTags -join ', ')"
    }

    $tag = $releaseTags[0].Trim()
    $tagMatch = [regex]::Match($tag, $pattern)
    if (-not $tagMatch.Success) { throw "版本标签格式无效：$tag" }
    $versionName = $tagMatch.Groups['name'].Value
    $versionCodeText = $tagMatch.Groups['code'].Value
    if ([string]::IsNullOrWhiteSpace($versionCodeText)) {
        $pubspecVersion = Get-PubspecVersion
        if ($pubspecVersion.VersionName -ne $versionName) {
            throw "标签 $tag 未包含 versionCode，且 pubspec.yaml 版本不是 $versionName"
        }
        $versionCode = $pubspecVersion.VersionCode
    }
    else {
        $versionCode = [int]$versionCodeText
    }
    if ($versionCode -le 0 -or $versionCode -gt 2100000000) {
        throw "Android versionCode 超出有效范围：$versionCode"
    }

    return [ordered]@{
        Tag = $tag
        VersionName = $versionName
        VersionCode = $versionCode
    }
}

if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw "找不到 Android 构建脚本：$builder"
}

$resolvedRepo = [IO.Path]::GetFullPath($repo).TrimEnd([IO.Path]::DirectorySeparatorChar)
$resolvedSigningDirectory = [IO.Path]::GetFullPath($SigningDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar)
if ([string]::Equals($resolvedSigningDirectory, $resolvedRepo, [StringComparison]::OrdinalIgnoreCase) -or
    $resolvedSigningDirectory.StartsWith($resolvedRepo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '正式签名目录必须位于仓库外'
}

$changes = @(& git -C $repo status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw '无法检查 Git 工作区状态' }
if ($changes.Count -ne 0) {
    throw '正式发布前 Git 工作区必须干净，请先提交或移除未跟踪文件'
}

$release = Get-TaggedReleaseVersion
Write-Host "准备构建 $($release.Tag)（versionCode $($release.VersionCode)）"

& $builder `
    -VersionName $release.VersionName `
    -VersionCode $release.VersionCode `
    -SigningDirectory $SigningDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Android 正式发布构建失败，退出代码：$LASTEXITCODE"
}

Write-Host '正式签名 APK 已生成；本流程不会创建 ZIP 压缩包'
