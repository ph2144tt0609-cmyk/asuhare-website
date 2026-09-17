# publish.ps1 - Commit local changes and push to GitHub.
# GitHub Pages then auto-publishes to https://tetote-links.co.jp/ within ~1-2min.
#
# Usage:
#   - Double-click "公開.bat", or
#   - Run: powershell -ExecutionPolicy Bypass -File publish.ps1 ["message"]

param(
    [string]$Message = ""
)

Set-Location -Path $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = "Update site " + (Get-Date -Format "yyyyMMdd-HHmmss")
}

Write-Host "Staging changes..." -ForegroundColor Cyan
git add -A

$changes = git status --porcelain
if ([string]::IsNullOrWhiteSpace($changes)) {
    Write-Host "No changes to publish." -ForegroundColor Yellow
    exit 0
}

Write-Host ("Committing: " + $Message) -ForegroundColor Cyan
git commit -m $Message
if ($LASTEXITCODE -ne 0) { Write-Host "Commit failed." -ForegroundColor Red; exit 1 }

Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
git push
if ($LASTEXITCODE -ne 0) { Write-Host "Push failed." -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "Done. GitHub Pages is publishing. Live in ~1-2min:" -ForegroundColor Green
Write-Host "  https://tetote-links.co.jp/" -ForegroundColor Green
