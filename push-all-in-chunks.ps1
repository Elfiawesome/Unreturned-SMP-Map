# push-all-in-chunks.ps1 — push everything in <=500 MB batches, automatically.

$LimitMB    = 500
$LimitBytes = $LimitMB * 1MB

# ---------- preflight ----------
$repoRoot = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { Write-Error "Not a git repository"; exit 1 }
Set-Location $repoRoot

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$remote = (git config "branch.$branch.remote")
if (-not $remote) {
    Write-Error "Branch '$branch' has no upstream. Run: git push -u origin $branch"
    exit 1
}

Write-Host "Repo:    $repoRoot"
Write-Host "Branch:  $branch (remote: $remote)"
Write-Host "Limit:   $LimitMB MB"
Write-Host ""

$round        = 0
$totalFiles   = 0
$totalBytes   = 0
$oversized    = New-Object System.Collections.Generic.HashSet[string]

while ($true) {
    $round++
    Write-Host "──────── Round $round ────────" -ForegroundColor Cyan

    $files = @(
        git ls-files --others --exclude-standard
        git ls-files --modified
    ) | Sort-Object -Unique

    if ($files.Count -eq 0) {
        Write-Host "No more files to stage. All done." -ForegroundColor Green
        break
    }

    $batchBytes = 0
    $batchCount = 0
    $deferred   = 0

    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        $size = (Get-Item -LiteralPath $f).Length

        if ($size -gt $LimitBytes) {
            [void]$oversized.Add($f)
            Write-Host ("  OVERSIZED  {0}  ({1:N1} MB)" -f $f, ($size / 1MB)) -ForegroundColor Yellow
            continue
        }

        if (($batchBytes + $size) -le $LimitBytes) {
            git add -- $f
            if ($LASTEXITCODE -ne 0) { Write-Error "git add failed for $f"; exit 1 }
            $batchBytes += $size
            $batchCount++
        } else {
            $deferred++
        }
    }

    if ($batchCount -eq 0) {
        Write-Host "Nothing stageable this round (only oversized files remain)." -ForegroundColor Yellow
        break
    }

    Write-Host ("  staged {0} file(s), {1:N1} MB" -f $batchCount, ($batchBytes / 1MB))
    Write-Host ("  deferred {0} file(s) to next round" -f $deferred)

    # Nothing actually changed?
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  no staged changes to commit; stopping."
        break
    }

    git commit -m "Added files $batchCount" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error "commit failed"; exit 1 }
    Write-Host "  committed."

    Write-Host "  pushing..."
    git push $remote $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Error "git push failed. Aborting so you can investigate."
        Write-Host "The commit is local but not on the remote. Fix the cause, then re-run."
        exit 1
    }
    Write-Host "  pushed." -ForegroundColor Green

    $totalFiles += $batchCount
    $totalBytes += $batchBytes
    Write-Host ""
}

# ---------- summary ----------
Write-Host "════════ Summary ════════" -ForegroundColor Cyan
Write-Host ("Rounds:       {0}" -f $round)
Write-Host ("Files pushed: {0}" -f $totalFiles)
Write-Host ("Bytes pushed: {0:N1} MB" -f ($totalBytes / 1MB))

if ($oversized.Count -gt 0) {
    Write-Host ""
    Write-Host "Files too large to push (need Git LFS or manual split):" -ForegroundColor Yellow
    $oversized | ForEach-Object { Write-Host "  $_" }
}

$left = (git status --porcelain | Measure-Object).Count
Write-Host ""
Write-Host ("Remaining unstaged/untracked entries: {0}" -f $left)