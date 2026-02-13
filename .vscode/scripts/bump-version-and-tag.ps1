param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('major', 'minor', 'patch')]
    [string]$BumpType
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$buildGradlePath = Join-Path (Get-Location) 'app/build.gradle'

if (-not (Test-Path $buildGradlePath)) {
    throw "未找到文件: $buildGradlePath"
}

$content = Get-Content -Path $buildGradlePath -Raw -Encoding UTF8

$versionNameMatch = [regex]::Match($content, '(?m)^\s*versionName\s+"(\d+)\.(\d+)\.(\d+)"\s*$')
$versionCodeMatch = [regex]::Match($content, '(?m)^\s*versionCode\s+(\d+)\s*$')

if (-not $versionNameMatch.Success -or -not $versionCodeMatch.Success) {
    throw '无法从 app/build.gradle 解析 versionName/versionCode'
}

$major = [int]$versionNameMatch.Groups[1].Value
$minor = [int]$versionNameMatch.Groups[2].Value
$patch = [int]$versionNameMatch.Groups[3].Value
$currentCode = [int]$versionCodeMatch.Groups[1].Value

switch ($BumpType) {
    'major' {
        $major++
        $minor = 0
        $patch = 0
    }
    'minor' {
        $minor++
        $patch = 0
    }
    'patch' {
        $patch++
    }
}

$newVersion = "$major.$minor.$patch"
$newCode = $currentCode + 1
$newTag = "v$newVersion"

& git rev-parse -q --verify "refs/tags/$newTag" | Out-Null
if ($LASTEXITCODE -eq 0) {
    throw "Tag 已存在: $newTag"
}

$updated = [regex]::Replace(
    $content,
    '(?m)^(\s*versionCode\s+)\d+\s*$',
    { param($m) "$($m.Groups[1].Value)$newCode" },
    1
)

$updated = [regex]::Replace(
    $updated,
    '(?m)^(\s*versionName\s+)"\d+\.\d+\.\d+"\s*$',
    { param($m) $m.Groups[1].Value + '"' + $newVersion + '"' },
    1
)

Set-Content -Path $buildGradlePath -Value $updated -Encoding UTF8

& git add 'app/build.gradle'
if ($LASTEXITCODE -ne 0) {
    throw 'git add 执行失败'
}

& git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    throw '没有检测到版本变更，提交已取消'
}

& git commit -m "chore: bump version to $newVersion"
if ($LASTEXITCODE -ne 0) {
    throw 'git commit 执行失败'
}

& git tag $newTag
if ($LASTEXITCODE -ne 0) {
    throw 'git tag 执行失败'
}

& git push origin $newTag
if ($LASTEXITCODE -ne 0) {
    throw 'git push tag 执行失败'
}

Write-Host "已完成: versionName=$newVersion, versionCode=$newCode, tag=$newTag"