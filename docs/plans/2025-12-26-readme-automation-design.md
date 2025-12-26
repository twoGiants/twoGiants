# README Automation Design

## Overview

Automated GitHub profile README with dynamic statistics and recent activity. Fully automated using Go, GitHub Actions, and graceful fallbacks.

## Goals

- **Minimalist design**: Clean, comprehensive, not overwhelming
- **Daily updates**: Fresh data with daily commits
- **Graceful degradation**: Never show broken stats, use cache on failures
- **Fully tested**: Unit and integration tests, early detection of API changes
- **Zero maintenance**: Runs automatically, alerts on issues

## README Structure

```markdown
## Hi, I'm Stas 👋👨‍💻

Principal Software Engineer. Tekton maintainer. Knative member.

### Activity & Impact
🔥 45 days | 📊 1.2k contributions | 🤝 23 repos | ✅ 156 PRs | 🔍 89 reviews

### Recent Work

**Issues:**
- [tektoncd/pipeline#1234] Refactor step validation ✓
- [knative/func#5678] Add support for custom domains
- [tektoncd/plumbing#910] Fix Docker setup on ARM

**Pull Requests:**
- [tektoncd/pipeline#1235] Implement pipelines in pipelines ✅
- [knative/func#456] Add unit tests for handler 🔄
- [tektoncd/website#789] Update installation docs ✅

### Let's Connect

- [LinkedIn](https://www.linkedin.com/in/stanislav-jakuschevskij/)
- [CNCF Slack](https://cloud-native.slack.com/)
- [Tekton Slack](https://tektoncd.slack.com/)

_Last updated: 26. December 2025_
ℹ️ _Stats from cache (last updated: Dec 25)_ ← only when using cache
```

## Metrics

### Collected & Displayed (5 inline badges)

1. **Current streak** 🔥 - Consecutive days with contributions
2. **Total contributions** 📊 - Last 365 days
3. **External repos** 🤝 - Repos contributed to (not your own)
4. **PRs merged** ✅ - Merged pull requests across all projects
5. **Review count** 🔍 - PR reviews conducted on external repos

### Collected & Cached (for future use)

- Longest streak (all-time)
- Active repositories (commits in last 90 days)
- Organizations collaborated with
- Stars received (sum across repos)
- PR acceptance ratio
- Total commits (own + external repos)
- Issue comments on external repos

### Recent Activity (dynamic)

- **Last 3 issues** created or closed by you
- **Last 3 PRs** authored by you (any state: open/merged/closed)

## Architecture

### Go Program Structure

```
cmd/readme-gen/
├── main.go                   # Entry point, orchestration
├── github/
│   ├── client.go             # GraphQL/REST API client
│   ├── client_test.go        # Unit tests (mocked)
│   ├── queries.go            # GraphQL query definitions
│   ├── metrics.go            # Fetch & calculate metrics
│   ├── metrics_test.go       # Unit tests
│   ├── activity.go           # Fetch recent issues/PRs
│   └── activity_test.go      # Unit tests
├── cache/
│   ├── cache.go              # Read/write stats cache
│   ├── cache_test.go         # Unit tests
│   ├── fallback.go           # Graceful fallback logic
│   └── fallback_test.go      # Unit tests
├── template/
│   ├── render.go             # Template rendering
│   ├── render_test.go        # Unit tests
│   └── README.tmpl           # Go template file
└── main_integration_test.go  # Integration tests (real API)
```

### Data Flow

1. Fetch GitHub data (metrics + recent activity via GraphQL/REST API)
2. **Success path**: Cache data → Render from fresh data → Write README
3. **Failure path**: Load cache → Render with cache indicator → Write README
4. Always exit 0 (never block workflow)

### GitHub Actions Workflow

```yaml
name: Daily README Update

on:
  schedule:
    - cron: '0 16 * * *'  # Daily at 4 PM UTC
  workflow_dispatch:
  pull_request:           # Run tests on PR

permissions:
  contents: write

jobs:
  update-readme:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Run unit tests (must pass)
      - name: Unit tests
        run: go test ./cmd/readme-gen/...

      # Run integration tests (continue on failure)
      - name: Integration tests
        id: integration
        continue-on-error: true
        run: go test -tags=integration ./cmd/readme-gen/...
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      # Send notification if integration tests fail
      - name: Notify on integration test failure
        if: steps.integration.outcome == 'failure'
        # GitHub sends email on workflow failure by default
        # This step just marks the issue for visibility
        run: echo "::warning::Integration tests failed, using cached data"

      # Generate README (always runs, uses cache if needed)
      - name: Generate README
        run: go run ./cmd/readme-gen
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      # Commit changes (always commits daily)
      - name: Commit and push
        run: |
          git config user.name "${{ secrets.GIT_USER_NAME }}"
          git config user.email "${{ secrets.GIT_USER_EMAIL }}"
          git add README.md .github/stats-cache.json
          if ! git diff --cached --quiet; then
            git commit -m "chores: daily README update $(date +'%d. %B %Y')"
            git push
          fi
```

### Secrets Required

- `GITHUB_TOKEN` - Automatic token for API access
- `GIT_USER_NAME` - Git commit author name
- `GIT_USER_EMAIL` - Git commit author email

Optional: Personal Access Token (PAT) for higher rate limits if needed.

## Data Sources

### GitHub GraphQL API (v4)

Primary data source. Single query fetches:
- Contribution graph (total contributions, streaks)
- Repositories (own repos, contributed repos)
- Pull requests (authored, merged, status)
- Issues (created, closed)
- PR reviews (count, repos)

### GitHub REST API (v3)

Fallback for specific endpoints:
- Star counts per repository
- Organization memberships
- Detailed PR/issue data if needed

### Cache File

`.github/stats-cache.json` - Stores last successful fetch:
```json
{
  "timestamp": "2025-12-26T16:00:00Z",
  "metrics": {
    "current_streak": 45,
    "total_contributions": 1234,
    "external_repos": 23,
    "prs_merged": 156,
    "review_count": 89,
    "total_commits": 3456,
    "longest_streak": 67,
    "active_repos": 12,
    "organizations": ["tektoncd", "knative"],
    "stars_received": 0,
    "pr_acceptance_ratio": 0.94
  },
  "recent_issues": [...],
  "recent_prs": [...]
}
```

## Graceful Fallback Strategy

### On API Failure

1. Load previous cache from `.github/stats-cache.json`
2. Render README with cached data
3. Add indicator: `ℹ️ _Stats from cache (last updated: Dec 25)_`
4. Commit result
5. Integration test failure triggers notification

### On Cache Missing/Corrupted

1. Use zero/empty values for metrics
2. Show placeholder: `ℹ️ _Stats temporarily unavailable_`
3. Still generate valid markdown
4. Next successful run will restore normal display

### On Template Error

1. Log error but don't crash
2. Use minimal fallback template
3. Ensure valid markdown output

## Testing Strategy

### Unit Tests (Mocked API)

- **Coverage**: >80%
- **Mocking**: httptest or similar for HTTP responses
- **Test data**: JSON fixtures in `testdata/`
- **Scope**:
  - Metric calculations with known data
  - Template rendering with various states
  - Cache read/write operations
  - Fallback logic (missing cache, corrupted data)
  - Edge cases (zero contributions, no PRs, empty responses)
- **Run**: On every code change (CI + pre-commit)

### Integration Tests (Real API)

- **Scope**:
  - Verify actual GitHub API queries work
  - Test authentication with real token
  - Validate response schema matches expectations
  - End-to-end: fetch → cache → render → valid markdown output
  - Detect API breaking changes early
- **Run**: Daily schedule + on code changes
- **Failure handling**: Continue workflow, use cache, send notification

### CI Workflow

```
Pull Requests:
  → Unit tests (must pass)
  → Block merge if failing

Daily Schedule:
  → Unit tests (must pass)
  → Integration tests (continue on failure)
  → Generate README (always runs)
  → Commit changes (always commits)
```

## Template Data Structure

```go
type ReadmeData struct {
    // Metrics (displayed)
    CurrentStreak      int
    TotalContributions int
    ExternalRepos      int
    PRsMerged          int
    ReviewCount        int

    // Recent activity
    RecentIssues []Issue
    RecentPRs    []PullRequest

    // Metadata
    UpdatedAt    string  // e.g., "26. December 2025"
    UsingCache   bool
    CacheDate    string  // e.g., "Dec 25"
}

type Issue struct {
    Repo   string  // e.g., "tektoncd/pipeline"
    Number int
    Title  string
    Closed bool
}

type PullRequest struct {
    Repo        string
    Number      int
    Title       string
    StatusEmoji string  // ✅ merged, 🔄 open, ❌ closed
}
```

## Go Template (README.tmpl)

```markdown
## Hi, I'm Stas 👋👨‍💻

Principal Software Engineer. Tekton maintainer. Knative member.

### Activity & Impact
🔥 {{.CurrentStreak}} days | 📊 {{.TotalContributions}} contributions | 🤝 {{.ExternalRepos}} repos | ✅ {{.PRsMerged}} PRs | 🔍 {{.ReviewCount}} reviews

### Recent Work

**Issues:**
{{range .RecentIssues}}- [{{.Repo}}#{{.Number}}] {{.Title}}{{if .Closed}} ✓{{end}}
{{end}}

**Pull Requests:**
{{range .RecentPRs}}- [{{.Repo}}#{{.Number}}] {{.Title}} {{.StatusEmoji}}
{{end}}

### Let's Connect

- [LinkedIn](https://www.linkedin.com/in/stanislav-jakuschevskij/)
- [CNCF Slack](https://cloud-native.slack.com/)
- [Tekton Slack](https://tektoncd.slack.com/)

_Last updated: {{.UpdatedAt}}_
{{if .UsingCache}}ℹ️ _Stats from cache (last updated: {{.CacheDate}})_{{end}}
```

## Implementation Phases

### Phase 1: Core Infrastructure
- Set up Go module and project structure
- Implement GitHub API client (GraphQL + REST)
- Implement cache read/write
- Basic template rendering
- Unit tests for all components

### Phase 2: Metrics Collection
- Implement contribution streak calculation
- Fetch total contributions
- Fetch external repos contributed to
- Fetch PRs merged count
- Fetch PR review count
- Store all collected metrics in cache

### Phase 3: Recent Activity
- Fetch last 3 issues (created/closed)
- Fetch last 3 PRs (any state)
- Format with proper links and status indicators

### Phase 4: Integration & Testing
- Integration tests with real API
- End-to-end testing
- Graceful fallback testing
- Cache corruption scenarios

### Phase 5: GitHub Actions
- Create new workflow file
- Configure secrets
- Test daily schedule
- Verify notifications on failure

### Phase 6: Refinement
- Test both list formats (A and B) for recent work
- Adjust styling/formatting based on rendered output
- Performance optimization if needed

## Future Enhancements (Optional)

- Language breakdown chart (top 5 languages)
- Contribution heatmap (weekly activity grid)
- Top contributed repositories
- Response time metrics for maintainer activity
- Expandable `<details>` section for full stats
- Custom styling with SVG badges