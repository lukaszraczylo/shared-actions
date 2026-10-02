# Shared GitHub Actions

Reusable workflows and composite actions for Go projects.

## Reusable Workflows

### Runner selection

Every reusable workflow accepts `runner` (label, or a JSON object to pick a runner group):

```yaml
with:
  runner: self-hosted
  # or
  runner: '{"group":"ci-linux","labels":["x64"]}'
```

Resolution order: `inputs.runner`, repository/org variable `SHARED_ACTIONS_RUNNER`, `ubuntu-latest`.
Set the variable once to move every consumer. In `go-release-cgo.yaml` the build matrix keeps its
per-platform `os`; `runner` covers the other jobs. Runner groups exist only for organisations and enterprises.

### `go-release.yaml`

Standard Go release workflow using GoReleaser.

```yaml
jobs:
  release:
    uses: lukaszraczylo/shared-actions/.github/workflows/go-release.yaml@main
    with:
      go-version: ">=1.24"
      docker-enabled: true  # optional
    secrets: inherit
```

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `go-version` | `>=1.24` | Go version |
| `semver-config` | `semver.yaml` | Path to semver config |
| `docker-enabled` | `false` | Enable Docker builds |
| `docker-registry` | `ghcr.io` | Docker registry |
| `rolling-release-tag` | `""` | Rolling release tag (e.g., `v1`) |

### `go-release-cgo.yaml`

Go release workflow for CGO-enabled projects. Builds natively on each platform.

```yaml
jobs:
  release:
    uses: lukaszraczylo/shared-actions/.github/workflows/go-release-cgo.yaml@main
    with:
      go-version: ">=1.24"
      node-enabled: true
      node-build-script: "cd ui && npm ci && npm run build"
    secrets: inherit
```

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `go-version` | `>=1.24` | Go version |
| `semver-config` | `semver.yaml` | Path to semver config |
| `rolling-release-tag` | `""` | Rolling release tag |
| `node-enabled` | `false` | Enable Node.js |
| `node-version` | `20` | Node.js version |
| `node-build-script` | `""` | Frontend build script |
| `platforms` | *(all 4)* | JSON array of platforms |

### `go-pr.yaml`

Pull request checks: tests, linting, security scans.

- `go vet` / `staticcheck` findings show as inline annotations on the PR diff; gosec and CodeQL post to code scanning.
- The `report` job posts one sticky comment with every check's result and coverage, and fails if any check fails or coverage is below `coverage-threshold`. Require `PR Checks Report` in branch protection.
- A push to a branch with an open PR skips the duplicate run; stale runs on the same branch are cancelled.
- Fork PRs cannot receive the comment; the report still lands in the job summary.

```yaml
jobs:
  pr-checks:
    uses: lukaszraczylo/shared-actions/.github/workflows/go-pr.yaml@main
    with:
      go-version: ">=1.24"
    secrets: inherit
```

### `go-autoupdate.yaml`

Automatic dependency updates.

```yaml
jobs:
  autoupdate:
    uses: lukaszraczylo/shared-actions/.github/workflows/go-autoupdate.yaml@main
    with:
      go-version: ">=1.24"
      release-workflow: "release.yaml"
    secrets: inherit
```

## Composite Actions

### `actions/go-test`

Run Go tests.

```yaml
- uses: lukaszraczylo/shared-actions/.github/actions/go-test@main
  with:
    go-version: ">=1.24"
    cgo-enabled: "1"  # optional, default "0"
```

### `actions/semver`

Calculate semantic version.

```yaml
- id: semver
  uses: lukaszraczylo/shared-actions/.github/actions/semver@main
  with:
    config-file: semver.yaml

- run: echo "Version: ${{ steps.semver.outputs.version_tag }}"
```

### `actions/goreleaser`

Run GoReleaser with mode support.

```yaml
# Full release (single runner)
- uses: lukaszraczylo/shared-actions/.github/actions/goreleaser@main
  with:
    version-tag: v1.0.0
    mode: full
    github-token: ${{ secrets.GITHUB_TOKEN }}

# Split build (matrix)
- uses: lukaszraczylo/shared-actions/.github/actions/goreleaser@main
  with:
    version-tag: v1.0.0
    mode: split
    cgo-enabled: "1"
    github-token: ${{ secrets.GITHUB_TOKEN }}

# Merge artifacts
- uses: lukaszraczylo/shared-actions/.github/actions/goreleaser@main
  with:
    version-tag: v1.0.0
    mode: merge
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### `actions/preflight`

Fail in seconds when a prerequisite is missing, instead of at the end of a long run. Reads names from the step `env`, so map secrets there.

```yaml
- uses: lukaszraczylo/shared-actions/.github/actions/preflight@main
  with:
    require: GITHUB_TOKEN,NPM_TOKEN          # must be non-empty
    repo-access: lukaszraczylo/helm-charts   # token needs push access
    repo-token-env: HOMEBREW_TAP_TOKEN
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
    HOMEBREW_TAP_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
```

It also scans `.goreleaser.y*ml` and requires every `{{ .Env.NAME }}` (comment lines ignored) to be set. All problems are listed in one run.

`go-release.yaml` and `go-release-cgo.yaml` run it in a first `preflight` job before tests. Set `preflight: false` to skip it, and `preflight-repos` to check access to a tap or helm-charts repo. An empty secret usually means the caller omitted `secrets: inherit`.

### `actions/rolling-release`

Create/update a rolling release tag.

```yaml
- uses: lukaszraczylo/shared-actions/.github/actions/rolling-release@main
  with:
    tag: v1
    version-tag: v1.2.3
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### `actions/node-build`

Setup Node.js and run build script.

```yaml
- uses: lukaszraczylo/shared-actions/.github/actions/node-build@main
  with:
    node-version: "20"
    build-script: "cd ui && npm ci && npm run build"
```

## Outputs

Both release workflows output:
- `version` - Calculated version without `v` prefix (e.g., `1.2.3`)
- `version_tag` - Version with `v` prefix (e.g., `v1.2.3`)
