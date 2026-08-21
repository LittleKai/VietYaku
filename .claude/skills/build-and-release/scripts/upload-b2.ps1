<#
.SYNOPSIS
    Upload VietYaku Windows ZIP + version.json to Backblaze B2 (alpha-studio bucket).

.DESCRIPTION
    Web download link (giaiphapsangtao.com/studio/vietyaku) is served from B2 CDN.
    In-app updater keeps reading GitHub Releases - this script does NOT touch it.

    Uploads:
      vietyaku-app/releases/VietYaku-windows-x64-v<version>.zip
      vietyaku-app/version.json

    version.json mirrors the GitHub release payload shape so the backend
    (GET /api/vietyaku/releases/latest) can parse it the same way.

.PARAMETER Version
    Version/tag string (e.g. "v1.2.0" or "1.2.0").

.PARAMETER ZipPath
    Windows ZIP to upload. Default: build/release/VietYaku-windows-x64.zip

.PARAMETER Title
    Release title stored in version.json (default: "VietYaku v<version>").

.PARAMETER Notes
    Release notes (string or path to a file) stored in version.json.

.PARAMETER ReleaseUrl
    GitHub release html_url stored in version.json.

.PARAMETER PublishedAt
    ISO-8601 publish timestamp. Default: now (UTC).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$ZipPath = "",

    [string]$Title = "",

    [string]$Notes = "",

    [string]$ReleaseUrl = "",

    [string]$PublishedAt = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Invoke-RestMethod is ~10x faster without the progress bar

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

$SemVer = $Version -replace '^v', ''
$TagVersion = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }

if (-not $ZipPath) {
    $ZipPath = Join-Path $ProjectRoot "build\release\VietYaku-windows-x64.zip"
}
if (-not (Test-Path $ZipPath -PathType Leaf)) {
    Write-Err "Windows ZIP not found: $ZipPath"
    exit 1
}

if (-not $Title) { $Title = "VietYaku $TagVersion" }
if ($Notes -and (Test-Path $Notes -PathType Leaf)) {
    $Notes = Get-Content $Notes -Raw -Encoding UTF8
}
if (-not $PublishedAt) {
    $PublishedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

# --- Read B2 config from .env ---

Write-Step "Reading B2 config from .env"

$EnvFile = Join-Path $ProjectRoot ".env"
if (-not (Test-Path $EnvFile)) {
    Write-Err ".env file does not exist!"
    exit 1
}

$EnvVars = @{}
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
        $EnvVars[$Matches[1]] = $Matches[2].Trim('"').Trim("'")
    }
}

$KeyId      = $EnvVars['B2_ACCESS_KEY_ID']
$AppKey     = $EnvVars['B2_SECRET_ACCESS_KEY']
$BucketName = $EnvVars['B2_BUCKET_NAME']
$CdnBase    = $EnvVars['CDN_BASE_URL']

$Missing = @()
if (-not $KeyId)      { $Missing += 'B2_ACCESS_KEY_ID' }
if (-not $AppKey)     { $Missing += 'B2_SECRET_ACCESS_KEY' }
if (-not $BucketName) { $Missing += 'B2_BUCKET_NAME' }
if (-not $CdnBase)    { $Missing += 'CDN_BASE_URL' }

if ($Missing.Count -gt 0) {
    Write-Err ("Missing in .env: " + ($Missing -join ', '))
    Write-Host ""
    Write-Host "Add these lines to .env (values are in alpha-studio-backend/.env):" -ForegroundColor Yellow
    Write-Host "  B2_ACCESS_KEY_ID=<b2 keyID>"
    Write-Host "  B2_SECRET_ACCESS_KEY=<b2 applicationKey>"
    Write-Host "  B2_BUCKET_NAME=alpha-studio"
    Write-Host "  CDN_BASE_URL=https://cdn.giaiphapsangtao.com/file/alpha-studio"
    exit 1
}

$CdnBase = $CdnBase.TrimEnd('/')
Write-Success "Bucket: $BucketName - CDN: $CdnBase"

# --- Authorize ---

Write-Step "Authorizing with Backblaze B2"

$BasicAuth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${KeyId}:${AppKey}"))
try {
    $Auth = Invoke-RestMethod -Uri "https://api.backblazeb2.com/b2api/v3/b2_authorize_account" `
        -Headers @{ Authorization = "Basic $BasicAuth" }
} catch {
    Write-Err "B2 authorize failed: $($_.Exception.Message)"
    exit 1
}

$ApiUrl   = $Auth.apiInfo.storageApi.apiUrl
$BucketId = $Auth.apiInfo.storageApi.bucketId   # set when the key is bucket-restricted

if (-not $BucketId) {
    $ListUrl = "$ApiUrl/b2api/v3/b2_list_buckets?accountId=$($Auth.accountId)&bucketName=$BucketName"
    $Buckets = Invoke-RestMethod -Uri $ListUrl -Headers @{ Authorization = $Auth.authorizationToken }
    $BucketId = ($Buckets.buckets | Select-Object -First 1).bucketId
}

if (-not $BucketId) {
    Write-Err "Could not resolve bucketId for bucket '$BucketName'"
    exit 1
}

Write-Success "Authorized (bucketId: $BucketId)"

# --- Upload helper ---

function Invoke-B2Upload {
    param(
        [string]$Key,
        [string]$FilePath,
        [byte[]]$Bytes,
        [string]$ContentType
    )

    $UploadInfo = Invoke-RestMethod -Uri "$ApiUrl/b2api/v3/b2_get_upload_url" -Method POST `
        -Headers @{ Authorization = $Auth.authorizationToken } `
        -Body (@{ bucketId = $BucketId } | ConvertTo-Json) -ContentType "application/json"

    if ($FilePath) {
        $Sha1 = (Get-FileHash -Path $FilePath -Algorithm SHA1).Hash.ToLower()
    } else {
        $Sha1Provider = [Security.Cryptography.SHA1]::Create()
        $Sha1 = ($Sha1Provider.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    }

    # B2 wants the key percent-encoded, but '/' must stay a literal separator
    $EncodedKey = ($Key.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'

    $Headers = @{
        Authorization       = $UploadInfo.authorizationToken
        'X-Bz-File-Name'    = $EncodedKey
        'X-Bz-Content-Sha1' = $Sha1
    }

    if ($FilePath) {
        return Invoke-RestMethod -Uri $UploadInfo.uploadUrl -Method POST -Headers $Headers `
            -ContentType $ContentType -InFile $FilePath
    }
    return Invoke-RestMethod -Uri $UploadInfo.uploadUrl -Method POST -Headers $Headers `
        -ContentType $ContentType -Body $Bytes
}

# --- Upload Windows ZIP ---

$ZipItem  = Get-Item $ZipPath
$ZipName  = "VietYaku-windows-x64-v$SemVer.zip"
$ZipKey   = "vietyaku-app/releases/$ZipName"
$ZipSizeMb = [math]::Round($ZipItem.Length / 1MB, 2)

Write-Step "Uploading $ZipName ($ZipSizeMb MB) to B2"

if ($ZipItem.Length -gt 200MB) {
    Write-Err "ZIP is larger than 200MB - b2_upload_file single-part upload is not suitable. Use the B2 large-file API."
    exit 1
}

try {
    Invoke-B2Upload -Key $ZipKey -FilePath $ZipItem.FullName -ContentType "application/zip" | Out-Null
} catch {
    Write-Err "ZIP upload failed: $($_.Exception.Message)"
    exit 1
}

$ZipUrl = "$CdnBase/$ZipKey"
Write-Success "ZIP -> $ZipUrl"

# --- Upload version.json ---

Write-Step "Uploading version.json"

$Manifest = [ordered]@{
    tag_name     = $TagVersion
    version      = $SemVer
    name         = $Title
    body         = $Notes
    html_url     = $ReleaseUrl
    published_at = $PublishedAt
    assets       = @(
        [ordered]@{
            name                 = $ZipName
            browser_download_url = $ZipUrl
            size                 = $ZipItem.Length
            content_type         = "application/zip"
        }
    )
}

$ManifestJson  = $Manifest | ConvertTo-Json -Depth 5
$ManifestBytes = [Text.Encoding]::UTF8.GetBytes($ManifestJson)

try {
    Invoke-B2Upload -Key "vietyaku-app/version.json" -Bytes $ManifestBytes -ContentType "application/json" | Out-Null
} catch {
    Write-Err "version.json upload failed: $($_.Exception.Message)"
    exit 1
}

$ManifestUrl = "$CdnBase/vietyaku-app/version.json"
Write-Success "version.json -> $ManifestUrl"

# --- Done ---

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " B2 upload completed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Download (web) : $ZipUrl" -ForegroundColor Yellow
Write-Host "Manifest       : $ManifestUrl" -ForegroundColor Yellow
Write-Host "Studio page    : https://giaiphapsangtao.com/studio/vietyaku"
Write-Host ""

exit 0
