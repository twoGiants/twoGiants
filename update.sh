#!/usr/bin/env bash
set -euo pipefail

TARGET_FILE="${TARGET_FILE:-README.md}"

main() {
  readme_exists
  update_date
  commit_and_push
}

today() {
  echo "$(TZ=Europe/Berlin date +'%d. %B %Y' | sed 's/^0//')"
}

readme_exists() {
  if [ ! -f "$TARGET_FILE" ]; then
    echo "$TARGET_FILE not found" >&2
    exit 1
  fi
}

update_date() {
  local marker="_Last updated: $(today)_"
  if grep -q '_Last updated: ' "$TARGET_FILE"; then
    sed -E -i.bak "0,/_Last updated: [^_]*_/ s|_Last updated: [^_]*_|${marker}|" "$TARGET_FILE"
    rm -f "${TARGET_FILE}.bak"
    echo "Replaced existing marker in ${TARGET_FILE}"
  else
    printf "\n%s\n" "${marker}" >> "$TARGET_FILE"
    echo "Appended marker to ${TARGET_FILE}"
  fi
}

commit_and_push() {
  git add "$TARGET_FILE"
  if git diff --cached --quiet; then
    echo "No changes to commit."
    return 1
  fi

  local ci="${GITHUB_ACTIONS:-false}"
  if [ "$ci" != "true" ]; then
    echo "Not running in CI; skipping commit/push"
    return 0
  fi
  
  git config user.name "${GIT_USER_NAME:-twoGiants}"
  git config user.email "${GIT_USER_EMAIL:-twoGiants@users.noreply.github.com}"
  git commit -m "chores: last update ran on $(today)"
  git push
}

main