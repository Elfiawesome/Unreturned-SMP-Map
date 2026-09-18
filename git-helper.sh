#!/usr/bin/env bash
# git-chunk-push.sh — stage up to 500 MB, commit, push. Repeat to drain the rest.

set -euo pipefail

LIMIT_MB=500
LIMIT_BYTES=$(( LIMIT_MB * 1024 * 1024 ))

# Portable file-size in bytes
filesize() {
    if stat -c%s "$1" >/dev/null 2>&1; then
        stat -c%s "$1"          # GNU
    else
        stat -f%z "$1"          # BSD/macOS
    fi
}

human() {
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec "$1"
    else
        awk -v b="$1" 'BEGIN{ split("B KB MB GB TB",u," "); i=1; while(b>=1024 && i<5){b/=1024;i++} printf "%.1f %s\n", b, u[i] }'
    fi
}

echo "==> Collecting candidate files (respecting .gitignore)..."
# untracked (not ignored) + modified tracked files
mapfile -t FILES < <(
    git ls-files --others --exclude-standard
    git ls-files --modified
)

TOTAL=0
ADDED=0
SKIPPED=0
SKIPPED_LIST=()

for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || continue
    SIZE=$(filesize "$f")

    if (( TOTAL + SIZE <= LIMIT_BYTES )); then
        git add -- "$f"
        TOTAL=$(( TOTAL + SIZE ))
        ADDED=$(( ADDED + 1 ))
    else
        SKIPPED=$(( SKIPPED + 1 ))
        SKIPPED_LIST+=("$f")
        printf '  skip  %-60s %s\n' "$f" "$(human "$SIZE")"
    fi
done

echo
echo "==> Staged $ADDED file(s), $(human "$TOTAL") total."
echo "==> Skipped $SKIPPED file(s) for this round."

if (( ADDED == 0 )); then
    echo "Nothing staged. Either the tree is clean or every remaining file is oversized."
    exit 0
fi

git commit -m "Added files $ADDED"
git push

echo
echo "==> Done. Re-run this script to push the next 500 MB batch."