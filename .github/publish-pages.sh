#!/usr/bin/env bash
# Replace one folder of the gh-pages branch and push, keeping everything else.
#   publish-pages.sh <source dir or ""> <dest: "." for the site root, or pr/N> <message>
# An empty source deletes dest. Publishing the root keeps the pr/ previews. The branch is
# kept to one commit (builds are large).
set -euo pipefail
SRC="$1"; DEST="$2"; MSG="$3"
REPO="${PAGES_REPO:-https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git}"
for attempt in $(seq 1 10); do
  WORK="$(mktemp -d)"
  if git clone -q --depth 1 --branch gh-pages "$REPO" "$WORK" 2>/dev/null; then :; else
    git -C "$WORK" init -q -b gh-pages && git -C "$WORK" remote add origin "$REPO"
  fi
  cd "$WORK"
  OLD="$(git rev-parse -q --verify HEAD || true)"
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  if [ "$DEST" = "." ]; then
    find . -mindepth 1 -maxdepth 1 ! -name .git ! -name pr -exec rm -rf {} +
  else
    rm -rf "$DEST"
  fi
  if [ -n "$SRC" ]; then
    mkdir -p "$DEST"
    cp -r "$SRC/." "$DEST/"
  fi
  touch .nojekyll
  git add -A
  if [ -n "$OLD" ] && git diff --cached --quiet; then echo "nothing to publish"; exit 0; fi
  # keep a single commit on gh-pages so builds don't pile up in the repo's history;
  # the lease makes a build that raced with another one retry instead of overwriting it
  git checkout -q --orphan site
  git commit -q -m "$MSG"
  if git push -q --force-with-lease="gh-pages:${OLD}" origin site:gh-pages; then exit 0; fi
  echo "push raced with another build, retrying ($attempt)"
  cd / && rm -rf "$WORK"
  sleep $((attempt * 3))
done
exit 1
