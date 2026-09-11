#!/usr/bin/env bash
# Re-pin manifest.tsv to what is checked out right now. Run after a verified
# end-to-end run, then commit -- the pins are only worth anything if they name
# a combination that actually worked together.
set -euo pipefail
ROOT="${LAB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/manifest.tsv"
tmp=$(mktemp)

while IFS=$'\t' read -r name path upstream fork branch sha; do
  case "$name" in ''|\#*) printf '%s\n' "$name"; continue ;; esac
  dir="$ROOT/$path"
  new="$sha"
  if [ -d "$dir/.git" ]; then
    # Prefer the branch the manifest names, wherever it is checked out.
    new=$(git -C "$dir" rev-parse --verify --quiet "refs/heads/$branch" || git -C "$dir" rev-parse HEAD)
    [ "$new" = "$sha" ] || echo "re-pin $name  ${sha:0:9} -> ${new:0:9}"
  else
    echo "skip   $name  no checkout at $dir"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$path" "$upstream" "$fork" "$branch" "$new"
done < "$MANIFEST" > "$tmp"

mv "$tmp" "$MANIFEST"
echo "manifest.tsv updated"
