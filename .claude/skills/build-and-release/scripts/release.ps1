<#
.SYNOPSIS
    Tạo GitHub Release và upload artifacts cho VietYaku.

.DESCRIPTION
    - Đọc GITHUB_TOKEN từ .env
    - Tạo git tag và push
    - Tạo GitHub Release qua REST API
    - Upload APK và Windows ZIP lên release

.PARAMETER Version
    Version/tag string (ví dụ: "v1.0.0" hoặc "1.0.0"). Auto-prefix "v" nếu thiếu.

.PARAMETER Title
    Tên release hiển thị trên GitHub. Mặc định: "VietYaku <version>".

.PARAMETER Notes
    Release notes (plain text hoặc markdown). Mặc định: auto-generated từ git log.

.PARAMETER Prerelease
    Đánh dấu release là prerelease.

.PARAMETER Draft
    Tạo release ở trạng thái draft (không publish ngay).

.PARAMETER SkipBuild
    Bỏ qua bước build, dùng artifacts có sẵn trong build/release/.

.EXAMPLE
    .\release.ps1 -Version "1.0.0" -Title "VietYaku v1.0.0" -Notes "First release"
    .\release.ps1 -Version "v1.0.0" -Prerelease
    .\release.ps1 -Version "1.0.0" -SkipBuild
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Title = "",

    [string]$Notes = "",

    [switch]$Prerelease,

    [switch]$Draft,

    [switch]$SkipBuild
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
    Write-Err "Không tìm thấy pubspec.yaml. Hãy chạy script từ project root."
    exit 1
}

Set-Location $ProjectRoot

# --- Parse version ---

$TagVersion = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
$SemVer = $Version -replace '^v', ''

# --- Read GITHUB_TOKEN ---

Write-Step "Đọc GITHUB_TOKEN từ .env"

$EnvFile = Join-Path $ProjectRoot ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Err ".env file không tồn tại!"
    exit 1
}

$Token = $null
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*GITHUB_TOKEN\s*=\s*(.+)\s*$') {
        $Token = $Matches[1].Trim()
    }
}

if (-not $Token) {
    Write-Err "Không tìm thấy GITHUB_TOKEN trong .env"
    exit 1
}

Write-Success ("GITHUB_TOKEN loaded (" + $Token.Substring(0,8) + '...)')

# --- Detect repo ---

$RemoteUrl = git remote get-url origin 2>$null
if (-not $RemoteUrl) {
    Write-Err "Không tìm thấy git remote 'origin'"
    exit 1
}

# Parse owner/repo from URL
if ($RemoteUrl -match 'github\.com[:/]([^/]+)/([^/.]+?)(?:\.git)?$') {
    $Owner = $Matches[1]
    $Repo = $Matches[2]
} else {
    Write-Err "Không parse được owner/repo từ remote URL: $RemoteUrl"
    exit 1
}

Write-Host "Repository: $Owner/$Repo"
Write-Host "Tag       : $TagVersion"

# --- Defaults ---

if (-not $Title) {
    $Title = "VietYaku $TagVersion"
}

if (-not $Notes) {
    $Notes = ""
}

# --- Build (nếu cần) ---

$ReleaseDir = Join-Path $ProjectRoot "build\release"

if (-not $SkipBuild) {
    Write-Step "Chạy build script"
    $BuildScript = Join-Path $PSScriptRoot "build.ps1"
    & $BuildScript -Version $SemVer
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Build thất bại!"
        exit 1
    }
}

# --- Verify artifacts ---

Write-Step "Kiểm tra artifacts"

if (-not (Test-Path $ReleaseDir)) {
    Write-Err "Thư mục build/release/ không tồn tại. Chạy build trước!"
    exit 1
}

$Artifacts = Get-ChildItem $ReleaseDir -File
if ($Artifacts.Count -eq 0) {
    Write-Err "Không có artifacts trong build/release/"
    exit 1
}

Write-Host "Artifacts to upload:" -ForegroundColor Yellow
foreach ($f in $Artifacts) {
    $Size = [math]::Round($f.Length / 1MB, 2)
    Write-Host "  - $($f.Name)  ($Size MB)"
}

# --- Create git tag ---

Write-Step "Tạo git tag: $TagVersion"

$ExistingTag = git tag -l $TagVersion 2>$null
if ($ExistingTag) {
    Write-Host "Tag $TagVersion đã tồn tại, bỏ qua tạo tag."
} else {
    git tag -a $TagVersion -m "Release $TagVersion"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Tạo git tag thất bại!"
        exit 1
    }
    Write-Success "Tag $TagVersion đã tạo"
}

# --- Push tag ---

Write-Step "Push tag lên origin"

git push origin $TagVersion
if ($LASTEXITCODE -ne 0) {
    Write-Err "Push tag thất bại!"
    exit 1
}
Write-Success "Tag đã push"

# --- Create GitHub Release ---

Write-Step "Tạo GitHub Release"

$Headers = @{
    "Authorization" = "Bearer $Token"
    "Accept"        = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$ReleaseBody = @{
    tag_name         = $TagVersion
    name             = $Title
    body             = $Notes
    draft            = [bool]$Draft
    prerelease       = [bool]$Prerelease
    generate_release_notes = $false
} | ConvertTo-Json -Depth 3

$ApiUrl = "https://api.github.com/repos/$Owner/$Repo/releases"

try {
    $Response = Invoke-RestMethod -Uri $ApiUrl -Method POST -Headers $Headers `
        -Body $ReleaseBody -ContentType "application/json; charset=utf-8"
    $ReleaseId = $Response.id
    $HtmlUrl = $Response.html_url
    Write-Success "Release created: $HtmlUrl"
} catch {
    $StatusCode = $_.Exception.Response.StatusCode.Value__
    $ErrorBody = $_.ErrorDetails.Message
    Write-Err "GitHub API error ($StatusCode): $ErrorBody"
    exit 1
}

# --- Upload assets ---

Write-Step "Upload artifacts lên release"

$UploadUrlBase = "https://uploads.github.com/repos/$Owner/$Repo/releases/$ReleaseId/assets"

foreach ($Artifact in $Artifacts) {
    $FileName = $Artifact.Name
    $FilePath = $Artifact.FullName
    $FileSize = [math]::Round($Artifact.Length / 1MB, 2)

    Write-Host "Uploading: $FileName ($FileSize MB)..." -NoNewline

    # Detect content type
    $ContentType = switch -Regex ($FileName) {
        '\.apk$'  { "application/vnd.android.package-archive" }
        '\.zip$'  { "application/zip" }
        '\.exe$'  { "application/x-msdownload" }
        default   { "application/octet-stream" }
    }

    $UploadUrl = "$UploadUrlBase`?name=$([Uri]::EscapeDataString($FileName))"

    try {
        $FileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $UploadResponse = Invoke-RestMethod -Uri $UploadUrl -Method POST -Headers $Headers `
            -Body $FileBytes -ContentType $ContentType
        Write-Host " [OK]" -ForegroundColor Green
        Write-Host "  → $($UploadResponse.browser_download_url)"
    } catch {
        $StatusCode = $_.Exception.Response.StatusCode.Value__
        $ErrorBody = $_.ErrorDetails.Message
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Err "Upload failed ($StatusCode): $ErrorBody"
    }
}

# --- Done ---

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Release hoàn tất!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "GitHub Release : $HtmlUrl" -ForegroundColor Yellow
Write-Host "Tag            : $TagVersion"
Write-Host ""

Write-Host "Artifacts:" -ForegroundColor Yellow
foreach ($f in $Artifacts) {
    $Size = [math]::Round($f.Length / 1MB, 2)
    Write-Host "  - $($f.Name)  ($Size MB)"
}
