<#
.SYNOPSIS
    Build VietYaku Windows + Android release.

.DESCRIPTION
    - Update version in pubspec.yaml
    - Build Windows release (ZIP) and/or Android release (APK)
    - Package output into build/release/

.PARAMETER Version
    Version string (e.g. "1.0.0" or "v1.0.0").

.PARAMETER Targets
    Comma-separated build targets: "windows", "android" (default: both).

.PARAMETER SkipVersionUpdate
    Skip updating version in pubspec.yaml.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Targets = "windows,android",

    [switch]$SkipVersionUpdate
)

$ErrorActionPreference = "Stop"

# --- Helpers ---

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Err {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# --- Resolve paths ---

$ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    $ProjectRoot = Get-Location
}

if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    Write-Err "Could not find pubspec.yaml. Please run script from project root."
    exit 1
}

Set-Location $ProjectRoot

# --- Parse version ---

$SemVer = $Version -replace '^v', ''
$TagVersion = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }

# Parse build number from existing pubspec
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$PubspecContent = Get-Content $PubspecPath -Raw -Encoding UTF8

if ($PubspecContent -match 'version:\s*(\S+)\+(\d+)') {
    $OldVersion = $Matches[1]
    $OldBuildNumber = [int]$Matches[2]
} else {
    $OldVersion = "0.0.0"
    $OldBuildNumber = 0
}

$NewBuildNumber = $OldBuildNumber + 1

Write-Host "Project root : $ProjectRoot"
Write-Host "Old version  : $OldVersion+$OldBuildNumber"
Write-Host "New version  : $SemVer+$NewBuildNumber"
Write-Host "Tag          : $TagVersion"
Write-Host "Targets      : $Targets"

# --- Update pubspec.yaml ---

if (-not $SkipVersionUpdate) {
    Write-Step "Updating version in pubspec.yaml"

    $NewPubspec = $PubspecContent -replace 'version:\s*\S+\+\d+', "version: $SemVer+$NewBuildNumber"
    Set-Content -Path $PubspecPath -Value $NewPubspec -NoNewline -Encoding UTF8
    Write-Success "pubspec.yaml -> version: $SemVer+$NewBuildNumber"
}

# --- Prepare output dir ---

$ReleaseDir = Join-Path $ProjectRoot "build\release"
if (Test-Path $ReleaseDir) {
    Remove-Item $ReleaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null
Write-Success "Output dir: $ReleaseDir"

# --- Parse targets ---

$TargetList = $Targets.Split(',') | ForEach-Object { $_.Trim().ToLower() }

# --- Build Windows ---

if ($TargetList -contains "windows") {
    Write-Step "Building Windows (release)"

    & cmd /c "flutter build windows --release"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Flutter build windows failed!"
        exit 1
    }

    $WinBuildDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
    if (-not (Test-Path $WinBuildDir)) {
        $WinBuildDir = Join-Path $ProjectRoot "build\windows\runner\Release"
    }

    if (-not (Test-Path $WinBuildDir)) {
        Write-Err "Windows build output not found!"
        exit 1
    }

    $ZipDest = Join-Path $ReleaseDir "VietYaku-windows-x64.zip"
    Write-Step "Compressing Windows -> ZIP"

    Compress-Archive -Path "$WinBuildDir\*" -DestinationPath $ZipDest -Force
    $ZipSize = [math]::Round((Get-Item $ZipDest).Length / 1MB, 2)
    Write-Success "Windows ZIP: $ZipDest ($ZipSize MB)"
}

# --- Build Android ---

if (($TargetList -contains "android") -or ($TargetList -contains "apk")) {
    Write-Step "Building Android (release APK)"

    & cmd /c "flutter build apk --release"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Flutter build apk failed!"
        exit 1
    }

    $ApkSrc = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $ApkSrc)) {
        Write-Err "APK output not found at $ApkSrc"
        exit 1
    }

    # Ten phai ket thuc bang .apk: findAndroidApkAsset() trong app tim asset
    # theo duoi file nay de mo trinh cai dat khi cap nhat trong app.
    $ApkDest = Join-Path $ReleaseDir "VietYaku-android-v$SemVer.apk"
    Copy-Item $ApkSrc $ApkDest -Force
    $ApkSize = [math]::Round((Get-Item $ApkDest).Length / 1MB, 2)
    Write-Success "Android APK: $ApkDest ($ApkSize MB)"
}

# --- Summary ---

Write-Step "Build completed!"

$Artifacts = Get-ChildItem $ReleaseDir
Write-Host "Artifacts:" -ForegroundColor Yellow
foreach ($f in $Artifacts) {
    $Size = [math]::Round($f.Length / 1MB, 2)
    Write-Host "  - $($f.Name)  ($Size MB)"
}

Write-Host ""
Write-Host "Next step: run release.ps1 to publish to GitHub." -ForegroundColor Cyan
