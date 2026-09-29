<#
.SYNOPSIS
    Build release APKs and copy them into dist/ with the version and ABI in the
    file name.

.DESCRIPTION
    Output naming convention:

        loop_island-<versionName>-<versionCode>-<abi>.apk

    e.g. loop_island-1.0.0-1-arm64-v8a.apk

    The version is read from pubspec.yaml ("version: 1.0.0+1" -> 1.0.0 / 1).
    Gradle always writes the APK files with fixed names (app-release.apk, ...),
    so this script renames copies of them; the files inside build/ stay as-is.
    A SHA256SUMS.txt is written next to the APKs.

.PARAMETER Universal
    Also build the universal APK (all ABIs in one file, ~62 MB) in addition to
    the three per-ABI APKs.

.PARAMETER SkipBuild
    Only re-copy/rename the APKs that already exist in build/ (no flutter build).

.PARAMETER OutDir
    Output directory, relative to the project root. Default: dist

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool\package.ps1 -Universal

.EXAMPLE
    # 只重新命名，不重新构建（快）
    powershell -ExecutionPolicy Bypass -File tool\package.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    [switch]$Universal,
    [switch]$SkipBuild,
    [string]$OutDir = "dist"
)

$ErrorActionPreference = "Stop"

# project root = parent of the folder this script lives in
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# ---------------------------------------------------------------- 1) version
$pubspecPath = Join-Path $root "pubspec.yaml"
if (-not (Test-Path $pubspecPath)) { throw "pubspec.yaml not found at $pubspecPath" }
$pubspec = Get-Content $pubspecPath -Raw
$m = [regex]::Match($pubspec, '(?m)^version:\s*(\d+(?:\.\d+)*)\+(\d+)\s*$')
if (-not $m.Success) {
    throw "cannot parse 'version: x.y.z+N' from pubspec.yaml"
}
$versionName = $m.Groups[1].Value
$versionCode = $m.Groups[2].Value
Write-Host "version: $versionName+$versionCode" -ForegroundColor Cyan

# ---------------------------------------------------------------- 2) build
if (-not $SkipBuild) {
    Write-Host "building per-ABI release APKs ..." -ForegroundColor Cyan
    & flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk --release --split-per-abi failed" }

    if ($Universal) {
        Write-Host "building universal release APK ..." -ForegroundColor Cyan
        & flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk --release failed" }
    }
}

# ---------------------------------------------------------------- 3) rename
$srcDir = Join-Path $root "build/app/outputs/flutter-apk"
if (-not (Test-Path $srcDir)) { throw "no build output at $srcDir (run a build first)" }

$targets = @(
    @{ File = "app-arm64-v8a-release.apk";   Abi = "arm64-v8a" },
    @{ File = "app-armeabi-v7a-release.apk"; Abi = "armeabi-v7a" },
    @{ File = "app-x86_64-release.apk";      Abi = "x86_64" },
    @{ File = "app-release.apk";             Abi = "universal" }
)

$outPath = Join-Path $root $OutDir
New-Item -ItemType Directory -Force $outPath | Out-Null

# drop stale artifacts from previous versions so dist/ never mixes versions
Get-ChildItem $outPath -Filter "loop_island-*.apk" -ErrorAction SilentlyContinue |
    Remove-Item -Force

$made = @()
foreach ($t in $targets) {
    $src = Join-Path $srcDir $t.File
    if (-not (Test-Path $src)) {
        Write-Host ("skip (not built): {0}" -f $t.File) -ForegroundColor DarkGray
        continue
    }
    $name = "loop_island-$versionName-$versionCode-$($t.Abi).apk"
    $dst = Join-Path $outPath $name
    Copy-Item $src $dst -Force
    $made += $dst
}

if ($made.Count -eq 0) { throw "no APK found in $srcDir" }

# ---------------------------------------------------------------- 4) checksums
$sums = foreach ($f in $made) {
    $hash = (Get-FileHash $f -Algorithm SHA256).Hash
    "{0}  {1}" -f $hash, (Split-Path -Leaf $f)
}
$sumFile = Join-Path $outPath "SHA256SUMS.txt"
$sums | Set-Content -Path $sumFile -Encoding ASCII

# ---------------------------------------------------------------- 5) summary
Write-Host ""
Write-Host ("output: {0}" -f $outPath) -ForegroundColor Green
foreach ($f in $made) {
    $item = Get-Item $f
    Write-Host ("  {0,-42} {1,7:N1} MB" -f $item.Name, ($item.Length / 1MB))
}
Write-Host ("  {0,-42} {1,7:N1} KB" -f "SHA256SUMS.txt", ((Get-Item $sumFile).Length / 1KB))
Write-Host ""
Write-Host "install on a phone (arm64 is the one modern phones need):" -ForegroundColor Cyan
Write-Host ("  adb install -r `"{0}`"" -f (Join-Path $outPath "loop_island-$versionName-$versionCode-arm64-v8a.apk"))
