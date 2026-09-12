#!/usr/bin/env bash
set -uo pipefail

GITHUB_USER="twoGiants"
TARGET_FILE="${TARGET_FILE:-README.md}"
DRY_RUN=false

usage() {
  echo "Usage: $(basename "$0") [--dry-run]"
  echo "  --dry-run  Render README with sample data, no API calls, no commit"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [[ "$DRY_RUN" == "true" ]]; then
    load_sample_data
    build_readme
    return
  fi

  if fetch_contributions \
    && fetch_prs_merged \
    && fetch_issues_created \
    && fetch_reviews \
    && fetch_recent_issues \
    && fetch_recent_prs; then
    build_readme
  else
    echo "Fetch failed, updating date with warning" >&2
    update_date_with_warning
  fi
  commit_and_push
}

today() {
  TZ=Europe/Berlin date +'%d. %B %Y' | sed 's/^0//'
}

# --- Sample Data (dry-run) ---

load_sample_data() {
  contributions=5289
  external_repos=22
  issues_created=50
  prs_merged=77
  review_count=135

  issues_section="- Profiling runs fail locally on Fedora Linux. eventing-kafka-broker#4569 [↗](https://github.com/knative-extensions/eventing-kafka-broker/issues/4569)"$'\n'
  issues_section+="- Cleanup pipelinerunresolution_test.go. pipeline#8921 [↗](https://github.com/tektoncd/pipeline/issues/8921) ✓"$'\n'
  issues_section+="- Implement Github Workflow generation. func#3256 [↗](https://github.com/knative/func/issues/3256)"$'\n'

  prs_section="- Add runtime-aware builder config. func#3479 [↗](https://github.com/knative/func/pull/3479) 🔄"$'\n'
  prs_section+="- Deduplicate concurrent resolver cache requests. pipeline#9365 [↗](https://github.com/tektoncd/pipeline/pull/9365) 🔄"$'\n'
  prs_section+="- Use act for generated workflow testing. knative-func#1 [↗](https://github.com/twoGiants/knative-func/pull/1) ❌"$'\n'

  echo "Loaded sample data for dry-run"
}

# --- Metrics ---

fetch_contributions() {
  local response
  response=$(gh api graphql -f query='
    query {
      user(login: "'"${GITHUB_USER}"'") {
        contributionsCollection {
          contributionCalendar {
            totalContributions
          }
        }
        repositoriesContributedTo(contributionTypes: [COMMIT, PULL_REQUEST, ISSUE]) {
          totalCount
        }
      }
    }
  ')

  contributions=$(echo "$response" | jq -r '.data.user.contributionsCollection.contributionCalendar.totalContributions')
  external_repos=$(echo "$response" | jq -r '.data.user.repositoriesContributedTo.totalCount')

  [[ "$contributions" =~ ^[0-9]+$ ]] && [[ "$external_repos" =~ ^[0-9]+$ ]]
}

fetch_prs_merged() {
  prs_merged=$(gh api "search/issues?q=author:${GITHUB_USER}+type:pr+is:merged" --jq '.total_count')
  [[ "$prs_merged" =~ ^[0-9]+$ ]]
}

fetch_issues_created() {
  issues_created=$(gh api "search/issues?q=author:${GITHUB_USER}+type:issue" --jq '.total_count')
  [[ "$issues_created" =~ ^[0-9]+$ ]]
}

fetch_reviews() {
  review_count=$(gh api "search/issues?q=reviewed-by:${GITHUB_USER}+type:pr" --jq '.total_count')
  [[ "$review_count" =~ ^[0-9]+$ ]]
}

# --- Recent Activity ---

fetch_recent_issues() {
  local raw
  raw=$(gh search issues --author="$GITHUB_USER" --sort=updated --limit=3 --json repository,number,title,state)

  issues_section=""
  while IFS= read -r item; do
    local repo number title state marker repo_name url
    repo=$(echo "$item" | jq -r '.repository.nameWithOwner')
    number=$(echo "$item" | jq -r '.number')
    title=$(echo "$item" | jq -r '.title')
    state=$(echo "$item" | jq -r '.state')
    repo_name=$(echo "$repo" | cut -d/ -f2)
    url="https://github.com/${repo}/issues/${number}"

    marker=""
    if [[ "$state" == "closed" ]]; then
      marker=" ✓"
    fi

    issues_section+="- ${title} ${repo_name}#${number} [↗](${url})${marker}"$'\n'
  done < <(echo "$raw" | jq -c '.[]')

  [[ -n "$issues_section" ]]
}

fetch_recent_prs() {
  local response
  response=$(gh api graphql -f query='
    {
      search(query: "author:'"${GITHUB_USER}"' type:pr sort:updated", type: ISSUE, first: 3) {
        nodes {
          ... on PullRequest {
            repository { nameWithOwner }
            number
            title
            state
          }
        }
      }
    }
  ')

  prs_section=""
  while IFS= read -r item; do
    local repo number title state emoji repo_name url
    repo=$(echo "$item" | jq -r '.repository.nameWithOwner')
    number=$(echo "$item" | jq -r '.number')
    title=$(echo "$item" | jq -r '.title')
    state=$(echo "$item" | jq -r '.state')
    repo_name=$(echo "$repo" | cut -d/ -f2)
    url="https://github.com/${repo}/pull/${number}"

    case "$state" in
      MERGED) emoji="✅" ;;
      OPEN)   emoji="🔄" ;;
      *)      emoji="❌" ;;
    esac

    prs_section+="- ${title} ${repo_name}#${number} [↗](${url}) ${emoji}"$'\n'
  done < <(echo "$response" | jq -c '.data.search.nodes[]')

  [[ -n "$prs_section" ]]
}

# --- Output ---

build_readme() {
  cat > "$TARGET_FILE" <<EOF
## Hi, I'm Stas 👋👨‍💻

Principal Software Engineer. Tekton maintainer. Knative member.

### Activity & Impact
📊 ${contributions} contributions | 🤝 ${external_repos} repos | 📋 ${issues_created} issues | ✅ ${prs_merged} PRs | 🔍 ${review_count} reviews

### Recent Work

**Issues:**
${issues_section}
**Pull Requests:**
${prs_section}
### Let's Connect

- [LinkedIn](https://www.linkedin.com/in/stanislav-jakuschevskij/)
- [CNCF Slack](https://cloud-native.slack.com/)
- [Tekton Slack](https://tektoncd.slack.com/)

_Last updated: $(today)_
EOF
  echo "README generated successfully"
}

update_date_with_warning() {
  if [[ ! -f "$TARGET_FILE" ]]; then
    echo "$TARGET_FILE not found, cannot update date" >&2
    return 0
  fi

  local marker="_Last updated: $(today)_ 🐅"
  if grep -q '_Last updated: ' "$TARGET_FILE"; then
    sed -E -i.bak "0,/_Last updated: [^_]*_[[:space:]]*.*/ s|_Last updated: [^_]*_[[:space:]]*.*|${marker}|" "$TARGET_FILE"
    rm -f "${TARGET_FILE}.bak"
    echo "Updated date with warning in ${TARGET_FILE}"
  fi
}

commit_and_push() {
  git add "$TARGET_FILE"
  if git diff --cached --quiet; then
    echo "No changes to commit."
    return 0
  fi

  local ci="${GITHUB_ACTIONS:-false}"
  if [[ "$ci" != "true" ]]; then
    echo "Not running in CI; skipping commit/push"
    return 0
  fi

  git config user.name "${GIT_USER_NAME:-twoGiants}"
  git config user.email "${GIT_USER_EMAIL:-twoGiants@users.noreply.github.com}"
  git commit -m "chores: daily README update $(today)"
  git push
}

main "$@"
