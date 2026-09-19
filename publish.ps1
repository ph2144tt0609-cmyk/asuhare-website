# publish.ps1 - Commit local changes and push to GitHub.
# GitHub Pages then auto-publishes to https://tetote-links.co.jp/ within ~1-2min.
#
# Usage:
#   - Double-click the .bat file in this folder, or
#   - Run: powershell -ExecutionPolicy Bypass -File publish.ps1 ["message"] [-Yes]
#
# Safety checks (the repository is Public):
#   - must be on branch "main"; origin fetch/push URLs must exactly match the repository
#   - CNAME must exist with the expected domain, and index.html canonical must match it
#   - stops if GitHub has commits that are not here; re-pushes commits left by a failed push
#   - every changed file (also inside new folders) is shown and must be confirmed (skip with -Yes)
#   - stops on files that should never be published (.env, csv, xlsx, pdf, key ...)
#   - the staged set must equal the confirmed list

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

# Read git output as UTF-8. PowerShell 5.1 otherwise decodes it as Shift_JIS, which garbles
# Japanese file names (and even the "." before the extension), so the blocked-file check misses them.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
$OutputEncoding = [Console]::OutputEncoding

# 1. branch and remote (exact match, both fetch and push URL)
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($LASTEXITCODE -ne 0) { Fail "Not a git repository." }
if ($branch -ne "main") { Fail ("Current branch is '" + $branch + "'. Switch to 'main' before publishing.") }

$allowed = @(
    ("https://github.com/" + $ExpectedRepo + ".git"),
    ("https://github.com/" + $ExpectedRepo),
    ("git@github.com:" + $ExpectedRepo + ".git"),
    ("git@github.com:" + $ExpectedRepo)
)
$fetchUrl = ("" + (git remote get-url origin)).Trim()
$pushUrls = @(git remote get-url --push --all origin | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($allowed -notcontains $fetchUrl) { Fail ("origin fetch URL is '" + $fetchUrl + "'. Not the expected repository.") }
if ($pushUrls.Count -ne 1) { Fail ("origin has " + $pushUrls.Count + " push URLs (" + ($pushUrls -join ", ") + "). Exactly one is allowed.") }
if ($allowed -notcontains $pushUrls[0]) { Fail ("origin push URL is '" + $pushUrls[0] + "'. Not the expected repository.") }

# 2. custom domain file, and the canonical URL must match it
if (-not (Test-Path -LiteralPath "CNAME")) { Fail "CNAME file is missing. The custom domain would be lost. Aborted." }
$cname = (Get-Content -LiteralPath "CNAME" -Raw).Trim()
if ($cname -ne $ExpectedDomain -and $cname -ne ("www." + $ExpectedDomain)) {
    Fail ("CNAME is '" + $cname + "', expected " + $ExpectedDomain + ". Aborted.")
}
$html = Get-Content -LiteralPath "index.html" -Raw -Encoding UTF8
if ($html -notmatch [regex]::Escape('<link rel="canonical" href="https://' + $cname + '/"')) {
    Fail ("index.html canonical URL does not match CNAME (" + $cname + "). Update canonical/og/JSON-LD/robots/sitemap first.")
}

# 3. sync state with GitHub
git fetch -q origin main
if ($LASTEXITCODE -ne 0) { Fail "git fetch failed. Check the network." }
$counts = ("" + (git rev-list --left-right --count origin/main...HEAD)).Trim() -split '\s+'
$behind = [int]$counts[0]; $ahead = [int]$counts[1]
if ($behind -gt 0) { Fail ("GitHub has " + $behind + " commit(s) that are not here. Run 'git pull' first, then try again.") }

# 4. what would be published (every file, including files inside new folders)
function Get-ChangedPaths {
    $out = @()
    foreach ($line in (git -c core.quotePath=false status --porcelain --untracked-files=all)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $p = $line.Substring(3)
        if ($p -like "* -> *") { $p = $p.Split(@(" -> "), [StringSplitOptions]::None)[1] }
        $out += $p.Trim('"')
    }
    return ,$out
}
function Test-Blocked([string[]]$paths) {
    $bad = @()
    foreach ($p in $paths) {
        if ($p -match '(?i)(^|/)\.env|\.env$|\.(csv|tsv|xlsx?|xlsm|pdf|docx?|pptx?|txt|json|key|pem|pfx)$' -and $p -notmatch '(?i)^robots\.txt$') { $bad += $p }
    }
    return ,$bad
}

$changed = Get-ChangedPaths
# every path touched by commits that are not on GitHub yet (a file added and later deleted
# in those commits would still be in the pushed history, so check each commit, not the net diff)
$aheadPaths = @()
if ($ahead -gt 0) {
    $aheadPaths = @(git -c core.quotePath=false log --name-only --format= origin/main..HEAD | Where-Object { $_ } | Sort-Object -Unique)
}
$blocked = Test-Blocked (@($changed) + @($aheadPaths))
if ($blocked.Count -gt 0) {
    Write-Host "These files must not be published (Public repository):" -ForegroundColor Red
    $blocked | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Red }
    Fail "Remove them or add them to .gitignore, then try again."
}

if ($changed.Count -eq 0 -and $ahead -eq 0) {
    Write-Host "No changes to publish." -ForegroundColor Yellow
    exit 0
}

if ($ahead -gt 0) {
    Write-Host "Commits not yet on GitHub (will be published too):" -ForegroundColor Cyan
    git log --oneline origin/main..HEAD | ForEach-Object { Write-Host ("  " + $_) }
    Write-Host "  files in those commits:" -ForegroundColor Cyan
    $aheadPaths | ForEach-Object { Write-Host ("    " + $_) }
}
if ($changed.Count -gt 0) {
    Write-Host "Files to publish:" -ForegroundColor Cyan
    git -c core.quotePath=false status --short --untracked-files=all | ForEach-Object { Write-Host ("  " + $_) }
}
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Publish these changes to https://$cname/ ? (y/N)"
    # NOTE: with no console input Read-Host returns $null, and "$null -notmatch ..." is
    # NOT true in PowerShell 5.1 (it returns nothing). Normalize to string and compare
    # explicitly, so anything other than y/yes cancels.
    $answer = ("" + $answer).Trim().ToLower()
    if ($answer -ne "y" -and $answer -ne "yes") {
        Write-Host "Cancelled. Nothing was published." -ForegroundColor Yellow
        exit 0
    }
}

# 5. commit (only if there are file changes) and push
if ($changed.Count -gt 0) {
    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "Update site " + (Get-Date -Format "yyyyMMdd-HHmmss")
    }
    git add -A
    if ($LASTEXITCODE -ne 0) { Fail "git add failed." }

    # the staged set must be exactly what was shown
    $staged = @(git -c core.quotePath=false diff --cached --name-only | Where-Object { $_ })
    $diff = Compare-Object -ReferenceObject ($changed | Sort-Object) -DifferenceObject ($staged | Sort-Object)
    if ($diff -or (Test-Blocked $staged).Count -gt 0) {
        git reset -q
        Fail "Staged files differ from the confirmed list. Nothing was committed. Try again."
    }

    Write-Host ("Committing: " + $Message) -ForegroundColor Cyan
    git commit -q -m $Message
    if ($LASTEXITCODE -ne 0) { Fail "Commit failed." }
}

Write-Host "Pushing to GitHub (origin main)..." -ForegroundColor Cyan
git push origin main
if ($LASTEXITCODE -ne 0) { Fail "Push failed. The site was NOT updated. Run this again to retry." }

Write-Host ""
Write-Host "Pushed. GitHub Pages is publishing. Check in ~1-2min:" -ForegroundColor Green
Write-Host ("  https://" + $cname + "/") -ForegroundColor Green
