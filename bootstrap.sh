#!/usr/bin/env bash
# Clone (or verify) every repo in manifest.tsv at its pinned commit.
#
# Safe to re-run: an existing checkout is never reset or cloned over, only
# inspected and reported on. Nothing here builds a venv -- those recipes are
# version-pinned and live next to the code that needs them; see README.md.
set -euo pipefail

ROOT="${LAB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifest.tsv"
NAME="${GIT_AUTHOR_NAME:-Xiangyu Gao}"
EMAIL="${GIT_AUTHOR_EMAIL:-xiangyu.gao@plus.ai}"

command -v git >/dev/null || { echo "git not found" >&2; exit 1; }
command -v git-lfs >/dev/null || echo "WARNING: git-lfs missing; cosmos assets will land as pointer files" >&2

printf 'Checkout root: %s\n\n' "$ROOT"
rc=0

while IFS=$'\t' read -r name path upstream fork branch sha; do
  case "$name" in ''|\#*) continue ;; esac
  dir="$ROOT/$path"

  if [ ! -d "$dir/.git" ]; then
    # Clone from the fork when we have one, so `origin` stays upstream and
    # `fork` is where work goes -- the same remote layout as an existing box.
    src="$fork"; [ "$fork" = "-" ] && src="$upstream"
    echo "CLONE  $name  <- $src"
    git clone --quiet "$src" "$dir"
    git -C "$dir" remote rename origin "$( [ "$fork" = "-" ] && echo origin || echo fork )"
    [ "$fork" = "-" ] || git -C "$dir" remote add origin "$upstream"
    git -C "$dir" fetch --quiet --all
    git -C "$dir" config user.name  "$NAME"
    git -C "$dir" config user.email "$EMAIL"
    git -C "$dir" checkout --quiet -B "$branch" "$sha"
    echo "       at $(git -C "$dir" log -1 --format='%h %s' | cut -c1-64)"
    continue
  fi

  # Existing checkout: verify, never mutate. The pinned commit only has to be
  # *present* -- flashdreams keeps `main` and `dev` in two worktrees, so HEAD
  # here legitimately differs from the pin.
  if git -C "$dir" rev-parse --verify --quiet "${sha}^{commit}" >/dev/null; then
    head=$(git -C "$dir" rev-parse HEAD)
    if [ "$head" = "$sha" ]; then
      echo "OK     $name  HEAD is the pinned commit"
    else
      where=$(git -C "$dir" worktree list --porcelain 2>/dev/null \
                | awk -v s="$sha" '/^worktree /{w=$2} /^HEAD /{if ($2==s) print w}' | head -1)
      echo "OK     $name  pinned commit present${where:+, checked out in $where}"
      [ -n "$where" ] || echo "       note: HEAD is $(git -C "$dir" rev-parse --abbrev-ref HEAD) @ ${head:0:9}, pin is ${sha:0:9}"
    fi
  else
    echo "STALE  $name  pinned commit ${sha:0:9} not in this checkout -- run: git -C $dir fetch --all"
    rc=1
  fi
done < "$MANIFEST"

printf '\nNext: source env.sh, then follow flashdreams/CLOSED_LOOP_EVAL.md section 0.\n'
exit $rc
