# find-big-files.ps1
$Limit = 500MB

$repoRoot = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { Write-Error "Not a git repository"; exit 1 }
Set-Location $repoRoot

# Untracked (not ignored) + modified tracked files
$files = @(
    git ls-files --others --exclude-standard
    git ls-files --modified
) | Sort-Object -Unique

$big = foreach ($f in $files) {
    if (Test-Path -LiteralPath $f -PathType Leaf) {
        $size = (Get-Item -LiteralPath $f).Length
        if ($size -gt $Limit) {
            [pscustomobject]@{
                MB   = [math]::Round($size / 1MB, 1)
                Path = $f
            }
        }
    }
}

if ($big) {
    Write-Host "Files larger than 500 MB:" -ForegroundColor Yellow
    $big | Sort-Object MB -Descending | Format-Table -AutoSize
    Write-Host ("Total: {0} file(s)" -f $big.Count)
} else {
    Write-Host "No files over 500 MB. ✅" -ForegroundColor Green
}