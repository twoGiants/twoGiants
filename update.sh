#!/usr/bin/env bash
set -euo pipefail

TARGET_FILE="${TARGET_FILE:-README.md}"
GIT_USER_NAME="${GIT_USER_NAME:-twoGiants}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-twoGiants@users.noreply.github.com}"
GITHUB_CI="${GITHUB_ACTIONS:-false}"

main() {
  get_date
  readme_exists
  update_date
  commit_and_push
}

get_date() {
  DATE="$(TZ=Europe/Berlin date +'%d. %B %Y' | sed 's/^0//')"
  MARKER="<!--DATE-->_Last updated: ${DATE}_<!--DATE-->"
}

readme_exists() {
  if [ ! -f "$TARGET_FILE" ]; then
    echo "$TARGET_FILE not found" >&2
    exit 1
  fi
}

update_date() {
  if grep -q '<!--DATE-->' "$TARGET_FILE"; then
    sed -E -i.bak "0,/<\!--DATE-->/ s|<!--DATE-->.*<!--DATE-->|${MARKER}|" "$TARGET_FILE"
    rm -f "${TARGET_FILE}.bak"
    echo "Replaced existing marker in ${TARGET_FILE}"
  else
    printf "\n%s\n" "${MARKER}" >> "$TARGET_FILE"
    echo "Appended marker to ${TARGET_FILE}"
  fi
}

commit_and_push() {
  git add "$TARGET_FILE"
  if git diff --cached --quiet; then
    echo "No changes to commit."
    return 1
  fi

  if [ "$GITHUB_CI" != "true" ]; then
    echo "Not running in CI; skipping commit/push"
    return 0
  fi
  git config user.name "${GIT_USER_NAME}"
  git config user.email "${GIT_USER_EMAIL}"
  git commit -m "chores: last update ran on ${DATE}"
  git push
}

main