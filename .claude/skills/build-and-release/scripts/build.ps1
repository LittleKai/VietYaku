<#
.SYNOPSIS
    Build VietYaku Windows release.
    # [DISABLED-ANDROID] APK build tạm thời bị tắt.

.DESCRIPTION
    - Cập nhật version trong pubspec.yaml (tùy chọn)
    - Build Windows release
    # [DISABLED-ANDROID] - Build APK release
    - Đóng gói output vào build/release/

.PARAMETER Version
    Version string (ví dụ: "1.0.0" hoặc "v1.0.0"). Prefix "v" sẽ tự bỏ cho pubspec.

.PARAMETER Targets
    Comma-separated build targets: "windows" (mặc định). # [DISABLED-ANDROID] Trước đó mặc định là "apk,windows".

.PARAMETER SkipVersionUpdate
    Bỏ qua bước cập nhật version trong pubspec.yaml.

.EXAMPLE
    .\build.ps1 -Version "1.2.0"
    .\build.ps1 -Version "v1.2.0" -Targets "apk"
    .\build.ps1 -Version "1.2.0" -Targets "windows" -SkipVersionUpdate
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    # [DISABLED-ANDROID] Mặc định trước đó: "apk,windows"
    [string]$Targets = "windows",

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
# Nếu script nằm ở .claude/skills/build-and-release/scripts/build.ps1
# thì ProjectRoot = project root

# Fallback: nếu gọi từ project root
if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    $ProjectRoot = Get-Location
}

if (-not (Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
    Write-Err "Không tìm thấy pubspec.yaml. Hãy chạy script từ project root."
    exit 1
}

Set-Location $ProjectRoot

# --- Parse version ---

$SemVer = $Version -replace '^v', ''
$TagVersion = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }

# Parse build number from existing pubspec
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$PubspecContent = Get-Content $PubspecPath -Raw

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
    Write-Step "Cập nhật version trong pubspec.yaml"

    $NewPubspec = $PubspecContent -replace 'version:\s*\S+\+\d+', "version: $SemVer+$NewBuildNumber"
    Set-Content -Path $PubspecPath -Value $NewPubspec -NoNewline -Encoding UTF8
    Write-Success "pubspec.yaml → version: $SemVer+$NewBuildNumber"
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

# --- Build APK --- [DISABLED-ANDROID] Tạm thời bị tắt
# if ($TargetList -contains "apk") {
#     Write-Step "Building APK (release)"
#
#     flutter build apk --release
#     if ($LASTEXITCODE -ne 0) {
#         Write-Err "Flutter build apk failed!"
#         exit 1
#     }
#
#     $ApkSource = Join-Path $ProjectRoot "build" "app" "outputs" "flutter-apk" "app-release.apk"
#     if (-not (Test-Path $ApkSource)) {
#         Write-Err "APK not found at: $ApkSource"
#         exit 1
#     }
#
#     $ApkDest = Join-Path $ReleaseDir "VietYaku-$SemVer.apk"
#     Copy-Item $ApkSource $ApkDest
#     $ApkSize = [math]::Round((Get-Item $ApkDest).Length / 1MB, 2)
#     Write-Success "APK: $ApkDest ($ApkSize MB)"
# }

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
        # Fallback cho cấu trúc cũ
        $WinBuildDir = Join-Path $ProjectRoot "build\windows\runner\Release"
    }

    if (-not (Test-Path $WinBuildDir)) {
        Write-Err "Windows build output not found!"
        exit 1
    }

    $ZipDest = Join-Path $ReleaseDir "VietYaku-windows-x64.zip"
    Write-Step "Đóng gói Windows → ZIP"

    Compress-Archive -Path "$WinBuildDir\*" -DestinationPath $ZipDest -Force
    $ZipSize = [math]::Round((Get-Item $ZipDest).Length / 1MB, 2)
    Write-Success "Windows ZIP: $ZipDest ($ZipSize MB)"
}

# --- Summary ---

Write-Step "Build hoàn tất!"

$Artifacts = Get-ChildItem $ReleaseDir
Write-Host "Artifacts:" -ForegroundColor Yellow
foreach ($f in $Artifacts) {
    $Size = [math]::Round($f.Length / 1MB, 2)
    Write-Host "  - $($f.Name)  ($Size MB)"
}

Write-Host ""
Write-Host "Tiếp theo: chạy release.ps1 để đẩy lên GitHub." -ForegroundColor Cyan
