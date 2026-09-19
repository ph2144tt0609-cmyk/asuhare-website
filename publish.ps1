# publish.ps1 - Commit local changes and push to GitHub.
# GitHub Pages then auto-publishes to https://tetote-links.co.jp/ within ~1-2min.
#
# Usage:
#   - Double-click the .bat file in this folder, or
#   - Run: powershell -ExecutionPolicy Bypass -File publish.ps1 ["message"] [-Yes]
#
# Safety checks (the repository is Public):
#   - must be on branch "main" and origin must be ph2144tt0609-cmyk/asuhare-website
#   - CNAME must exist with the expected domain
#   - the list of changed files is shown and must be confirmed (skip with -Yes)
#   - stops on files that should never be published (.env, csv, xlsx, pdf, key ...)

param(
    [string]$Message = "",
    [switch]$Yes
)

$ExpectedDomain = "tetote-links.co.jp"
$ExpectedRepo   = "ph2144tt0609-cmyk/asuhare-website"

function Fail([string]$msg) {
    Write-Host $msg -ForegroundColor Red
    exit 1
}

Set-Location -Path $PSScriptRoot

# 1. branch and remote
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($LASTEXITCODE -ne 0) { Fail "Not a git repository." }
if ($branch -ne "main") { Fail ("Current branch is '" + $branch + "'. Switch to 'main' before publishing.") }

$origin = (git remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0) { Fail "Remote 'origin' is not set." }
if ($origin -notmatch [regex]::Escape($ExpectedRepo)) { Fail ("origin is '" + $origin + "', expected " + $ExpectedRepo + ".") }

# 2. custom domain file
if (-not (Test-Path -LiteralPath "CNAME")) { Fail "CNAME file is missing. The custom domain would be lost. Aborted." }
$cname = (Get-Content -LiteralPath "CNAME" -Raw).Trim()
if ($cname -ne $ExpectedDomain -and $cname -ne ("www." + $ExpectedDomain)) {
    Fail ("CNAME is '" + $cname + "', expected " + $ExpectedDomain + ". Aborted.")
}

# 3. what would be published
$changes = git status --porcelain
if ($LASTEXITCODE -ne 0) { Fail "git status failed." }
if ([string]::IsNullOrWhiteSpace(($changes -join ""))) {
    Write-Host "No changes to publish." -ForegroundColor Yellow
    exit 0
}

$blocked = @()
foreach ($line in $changes) {
    $path = $line.Substring(3).Trim('"')
    if ($path -match '(?i)(^|/)\.env|\.(csv|tsv|xlsx?|xlsm|pdf|docx?|pptx?|txt|json|key|pem|pfx)$') {
        if ($path -notmatch '(?i)^robots\.txt$') { $blocked += $path }
    }
}
if ($blocked.Count -gt 0) {
    Write-Host "These files must not be published (Public repository):" -ForegroundColor Red
    $blocked | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Red }
    Fail "Remove them or add them to .gitignore, then try again."
}

Write-Host "Files to publish:" -ForegroundColor Cyan
$changes | ForEach-Object { Write-Host ("  " + $_) }
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Publish these changes to https://$cname/ ? (y/N)"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "Cancelled. Nothing was published." -ForegroundColor Yellow
        exit 0
    }
}

# 4. commit and push
if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = "Update site " + (Get-Date -Format "yyyyMMdd-HHmmss")
}

git add -A
if ($LASTEXITCODE -ne 0) { Fail "git add failed." }

Write-Host ("Committing: " + $Message) -ForegroundColor Cyan
git commit -m $Message
if ($LASTEXITCODE -ne 0) { Fail "Commit failed." }

Write-Host "Pushing to GitHub (origin main)..." -ForegroundColor Cyan
git push origin main
if ($LASTEXITCODE -ne 0) { Fail "Push failed. The site was NOT updated." }

Write-Host ""
Write-Host "Pushed. GitHub Pages is publishing. Check in ~1-2min:" -ForegroundColor Green
Write-Host ("  https://" + $cname + "/") -ForegroundColor Green
