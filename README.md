# Shared GitHub Actions

Reusable workflows and composite actions for Go projects.

## Reusable Workflows

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
