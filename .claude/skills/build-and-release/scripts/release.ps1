<#
.SYNOPSIS
    Create GitHub Release and upload artifacts for VietYaku.

.DESCRIPTION
    - Read GITHUB_TOKEN from .env
    - Create git tag and push
    - Create GitHub Release via REST API
    - Upload Windows ZIP to release
    - Upload Windows ZIP + version.json to Backblaze B2 (web download link on /studio/vietyaku)

.PARAMETER Version
    Version/tag string (e.g. "v1.0.0" or "1.0.0").

.PARAMETER Title
    Release title on GitHub.

.PARAMETER Notes
    Release notes (string or path to file).

.PARAMETER Prerelease
    Mark release as prerelease.

.PARAMETER Draft
    Create release as draft.

.PARAMETER SkipBuild
    Skip build step and use existing artifacts in build/release/.

.PARAMETER SkipB2
    Skip the Backblaze B2 upload step (GitHub Release only).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Title = "",

    [string]$Notes = "",

    [switch]$Prerelease,

    [switch]$Draft,

    [switch]$SkipBuild,

    [switch]$SkipB2
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

$TagVersion = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
$SemVer = $Version -replace '^v', ''

# --- Read GITHUB_TOKEN ---

Write-Step "Reading GITHUB_TOKEN from .env"

$EnvFile = Join-Path $ProjectRoot ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Err ".env file does not exist!"
    exit 1
}

$Token = $null
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*GITHUB_TOKEN\s*=\s*(.+)\s*$') {
        $Token = $Matches[1].Trim()
    }
}

if (-not $Token) {
    Write-Err "Could not find GITHUB_TOKEN in .env"
    exit 1
}

Write-Success "GITHUB_TOKEN loaded"

# --- Detect repo ---

$RemoteUrl = git remote get-url origin 2>$null
if (-not $RemoteUrl) {
    Write-Err "Could not find git remote origin"
    exit 1
}

# Parse owner/repo from URL
if ($RemoteUrl -match 'github\.com[:/]([^/]+)/([^/.]+?)(?:\.git)?$') {
    $Owner = $Matches[1]
    $Repo = $Matches[2]
} else {
    Write-Err "Could not parse owner/repo from remote URL: $RemoteUrl"
    exit 1
}

Write-Host "Repository: $Owner/$Repo"
Write-Host "Tag       : $TagVersion"

# --- Defaults ---

if (-not $Title) {
    $Title = "VietYaku $TagVersion"
}

if ($Notes -and (Test-Path $Notes -PathType Leaf)) {
    $Notes = Get-Content $Notes -Raw -Encoding UTF8
} elseif (-not $Notes) {
    $Notes = ""
}

# --- Build (if needed) ---

$ReleaseDir = Join-Path $ProjectRoot "build\release"

if (-not $SkipBuild) {
    Write-Step "Running build script"
    $BuildScript = Join-Path $PSScriptRoot "build.ps1"
    & $BuildScript -Version $SemVer
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Build failed!"
        exit 1
    }
}

# --- Verify artifacts ---

Write-Step "Checking artifacts"

if (-not (Test-Path $ReleaseDir)) {
    Write-Err "Directory build/release/ does not exist. Run build first!"
    exit 1
}

$Artifacts = Get-ChildItem $ReleaseDir -File
if ($Artifacts.Count -eq 0) {
    Write-Err "No artifacts found in build/release/"
    exit 1
}

Write-Host "Artifacts to upload:" -ForegroundColor Yellow
foreach ($f in $Artifacts) {
    $Size = [math]::Round($f.Length / 1MB, 2)
    Write-Host "  - $($f.Name)  ($Size MB)"
}

# --- Create git tag ---

Write-Step "Creating git tag: $TagVersion"

$ExistingTag = git tag -l $TagVersion 2>$null
if ($ExistingTag) {
    Write-Host "Tag $TagVersion already exists, skipping tag creation."
} else {
    git tag -a $TagVersion -m "Release $TagVersion"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Creating git tag failed!"
        exit 1
    }
    Write-Success "Tag $TagVersion created"
}

# --- Push tag ---

Write-Step "Pushing tag to origin"

git push origin $TagVersion
if ($LASTEXITCODE -ne 0) {
    Write-Err "Push tag failed!"
    exit 1
}
Write-Success "Tag pushed"

# --- Create GitHub Release ---

Write-Step "Creating GitHub Release"

# --- Create or Get GitHub Release ---

Write-Step "Creating or updating GitHub Release"

$Headers = @{
    "Authorization" = "Bearer $Token"
    "Accept"        = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$ReleaseId = $null
$HtmlUrl = $null
$ExistingAssets = @()

# Check if release already exists for this tag
$GetReleaseUrl = "https://api.github.com/repos/$Owner/$Repo/releases/tags/$TagVersion"
try {
    $ExistingRelease = Invoke-RestMethod -Uri $GetReleaseUrl -Method GET -Headers $Headers
    $ReleaseId = $ExistingRelease.id
    $HtmlUrl = $ExistingRelease.html_url
    $ExistingAssets = $ExistingRelease.assets
    Write-Host "Found existing release $TagVersion (ID: $ReleaseId)" -ForegroundColor Yellow

    # Update release notes if provided
    if ($Notes) {
        $PatchBody = @{
            body = $Notes
        } | ConvertTo-Json -Depth 3
        Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/$ReleaseId" -Method PATCH -Headers $Headers -Body $PatchBody -ContentType "application/json; charset=utf-8" | Out-Null
        Write-Success "Updated release notes"
    }
} catch {
    # Release does not exist, create new one
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
}

# --- Upload assets ---

Write-Step "Uploading artifacts to release"

$UploadUrlBase = "https://uploads.github.com/repos/$Owner/$Repo/releases/$ReleaseId/assets"

foreach ($Artifact in $Artifacts) {
    $FileName = $Artifact.Name
    $FilePath = $Artifact.FullName
    $FileSize = [math]::Round($Artifact.Length / 1MB, 2)

    # Delete existing asset with same name if present
    if ($ExistingAssets) {
        foreach ($Asset in $ExistingAssets) {
            if ($Asset.name -eq $FileName) {
                Write-Host "Deleting old asset: $FileName (ID: $($Asset.id))..." -NoNewline
                try {
                    Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/assets/$($Asset.id)" -Method DELETE -Headers $Headers
                    Write-Host " [OK]" -ForegroundColor Green
                } catch {
                    Write-Host " [FAILED]" -ForegroundColor Red
                }
            }
        }
    }

    Write-Host "Uploading: $FileName ($FileSize MB)..." -NoNewline

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
        Write-Host "  -> $($UploadResponse.browser_download_url)"
    } catch {
        $StatusCode = $_.Exception.Response.StatusCode.Value__
        $ErrorBody = $_.ErrorDetails.Message
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Err "Upload failed ($StatusCode): $ErrorBody"
    }
}

# --- Upload to Backblaze B2 (web download link) ---

$B2Ok = $false

if ($SkipB2) {
    Write-Host ""
    Write-Host "[SKIP] B2 upload skipped (-SkipB2). Web download link on /studio/vietyaku stays on the previous version." -ForegroundColor Yellow
} else {
    Write-Step "Uploading to Backblaze B2"

    $WinZip = $Artifacts | Where-Object { $_.Name -like "*windows*.zip" } | Select-Object -First 1
    $AndroidApk = $Artifacts | Where-Object { $_.Name -like "*android*.apk" } | Select-Object -First 1
    if (-not $WinZip) {
        Write-Err "No Windows ZIP found in build/release/ - skipping B2 upload."
    } else {
        $UploadScript = Join-Path $PSScriptRoot "upload-b2.ps1"
        $UploadArgs = @("-Version", $SemVer, "-ZipPath", $WinZip.FullName, "-Title", $Title, "-Notes", $Notes, "-ReleaseUrl", $HtmlUrl)
        if ($AndroidApk) {
            $UploadArgs += @("-ApkPath", $AndroidApk.FullName)
        }
        & $UploadScript @UploadArgs
        if ($LASTEXITCODE -eq 0) {
            $B2Ok = $true
        } else {
            Write-Err "B2 upload failed. GitHub Release is already published - rerun the upload alone with:"
            Write-Host "  powershell -ExecutionPolicy Bypass -File `".claude\skills\build-and-release\scripts\upload-b2.ps1`" -Version `"$SemVer`"" -ForegroundColor Yellow
        }
    }
}

# --- Done ---

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Release completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "GitHub Release : $HtmlUrl" -ForegroundColor Yellow
Write-Host "Tag            : $TagVersion"
if ($B2Ok) {
    Write-Host "Studio page    : https://giaiphapsangtao.com/studio/vietyaku" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "Artifacts:" -ForegroundColor Yellow
foreach ($f in $Artifacts) {
    $Size = [math]::Round($f.Length / 1MB, 2)
    Write-Host "  - $($f.Name)  ($Size MB)"
}
