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

### `node-pr.yaml`

Pull request checks for a Node, Vue or Astro project. It installs without changing the lockfile, then runs `lint`, `typecheck`, `test` and `build`. A script that does not exist is skipped. A push to a branch with an open PR skips the duplicate run, and stale runs on the same branch are cancelled. Call it once per project directory.

```yaml
name: Pull Request

on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - "**"
      - "!main"

permissions:
  contents: read
  pull-requests: read

jobs:
  frontend:
    uses: lukaszraczylo/shared-actions/.github/workflows/node-pr.yaml@main
    with:
      working-directory: web
```

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `node-version` | `22` | Node.js version |
| `working-directory` | `.` | Directory that holds `package.json`. With `workspace`, the directory that holds `pnpm-workspace.yaml` and `pnpm-lock.yaml`. |
| `workspace` | `false` | pnpm workspace: install once in `working-directory`, then run `scripts` in each of `packages`. `working-directory` needs no `package.json`. |
| `packages` | | With `workspace`, comma-separated package directories relative to `working-directory`, for example `admin,public,packages/ui` |
| `scripts` | `lint,typecheck,test,build` | Scripts to run in order. A missing script is skipped. |
| `pnpm-version` | | pnpm version for a repo with no `packageManager` field. Empty uses the field, or the newest pnpm. |
| `require-tests` | `false` | Fail when there is no `test` script |
| `lfs` | `false` | Git LFS checkout |
| `npm-registry-scope` | | Scope served by a private npm registry, for example `@fortawesome`. |
| `npm-registry-url` | | URL of that registry, for example `https://npm.fontawesome.com/`. |
| `runner` | | Runner label or runner group, as in the other workflows |

pnpm is used when `pnpm-lock.yaml` exists, yarn for `yarn.lock`, otherwise npm. pnpm and yarn run through Corepack, so set `packageManager` in `package.json`. A workspace with no root `package.json` has no such field, so set `pnpm-version`. With `require-tests`, every listed package needs a `test` script.

**Private npm registry.** Set `npm-registry-scope`, `npm-registry-url` and the `npm-registry-token` secret together; with any one missing nothing changes. The token goes into an npmrc outside the checkout (`NPM_CONFIG_USERCONFIG`), is masked in logs, and works for npm, pnpm and yarn classic. Yarn 2+ ignores npmrc and needs its own `.yarnrc.yml`.

### `go-autoupdate.yaml`

Automatic dependency updates for Go. See `renovate-autoupdate.yaml` for the Renovate-based replacement that also covers npm, pnpm and yarn.

```yaml
jobs:
  autoupdate:
    uses: lukaszraczylo/shared-actions/.github/workflows/go-autoupdate.yaml@main
    with:
      go-version: ">=1.24"
      release-workflow: "release.yaml"
    secrets: inherit
```

### `renovate-autoupdate.yaml`

Daily dependency updates for Go and npm/pnpm/yarn projects, built on Renovate. It replaces `go-autoupdate.yaml`.

1. Renovate upgrades everything that can be upgraded on branches named `deps-autoupdate/*` and opens no PR. All minor and patch updates (direct and indirect Go modules, npm, pnpm and yarn packages) go on `deps-autoupdate/batch`. Each major update gets its own branch.
2. For each branch, one at a time, the workflow merges it into the default branch locally and runs the tests on that result: `go build` and `go test -race -cover` for Go, the `package.json` scripts for Node.
3. If the tests pass, it opens a PR and squash-merges it. If they fail, no PR is opened. The test output goes into a comment on one sticky issue (see below), and Renovate retries on the next run.
4. If anything merged and `release-workflow` is set, it dispatches the release once.

```yaml
name: Update dependencies

on:
  workflow_dispatch:
  schedule:
    - cron: "0 3 * * *"

permissions:
  actions: write       # only to dispatch release-workflow
  contents: write
  issues: write        # only to report failing updates
  pull-requests: write

jobs:
  update:
    uses: lukaszraczylo/shared-actions/.github/workflows/renovate-autoupdate.yaml@main
    with:
      go-version: ">=1.24"
      release-workflow: release.yaml
```

The workflow finds `go.mod` and `package.json` itself and tests what exists. A repo with both, such as a Go backend with a Vue frontend, gets both tested for every branch.

**Inputs:**
| Input | Default | Description |
|-------|---------|-------------|
| `go-version` | `>=1.24` | Go version |
| `go` | `true` | Update and test the Go module. Turn off for a repo with no Go code. |
| `go-working-directory` | `.` | Directory that holds `go.mod`. Only this module is updated and tested. |
| `go-mod-tidy` | `true` | Run `go mod tidy` after a Go update. Turn it off for an Encore app, where tidy prunes `go.sum` entries the build needs. |
| `go-prepare-command` | | Shell commands to run before the Go tests, for example installing a CLI. Append a tool directory to `$GITHUB_PATH` to put it on `PATH`. |
| `go-test-command` | | Replaces the default `go build` and `go test`, for example `encore test ./...` for an Encore app. |
| `node-version` | `22` | Node.js version |
| `node` | `true` | Update and test the Node project. Turn off for a repo with no frontend to test. |
| `node-working-directory` | `.` | Directory that holds `package.json`. Only this project is updated and tested. With `node-workspace`, the directory that holds the workspace files. |
| `node-workspace` | `false` | pnpm workspace: `node-working-directory` holds `pnpm-workspace.yaml` and `pnpm-lock.yaml` and needs no `package.json`. Install once there, then run `node-scripts` in each of `node-packages`. |
| `node-packages` | | With `node-workspace`, comma-separated package directories relative to `node-working-directory`, for example `admin,public,packages/ui`. Only these are updated and tested. |
| `node-scripts` | `lint,typecheck,test,build` | Scripts to run in order. A missing script is skipped. |
| `pnpm-version` | | pnpm version for a repo with no `packageManager` field. Empty uses the field, or the newest pnpm. |
| `require-node-tests` | `true` | Fail when there is no `test` script, so an untested update never merges |
| `major-updates` | `separate` | `separate`: each major gets its own branch, tested and merged on its own. `batch`: majors join the batch. `ignore`: skip majors. |
| `minimum-release-age` | `2 days` | Skip releases younger than this |
| `renovate-version` | `44` | Renovate version |
| `release-workflow` | | Workflow file to dispatch after a merge, for example `release.yaml`. Give several as a comma-separated list. Each needs a `workflow_dispatch` trigger. Empty means no dispatch. |
| `admin-merge` | `false` | Merge with `--admin`. The workflow token cannot bypass branch protection. |
| `lfs` | `false` | Git LFS checkout |
| `npm-registry-scope` | | Scope served by a private npm registry, for example `@fortawesome`. |
| `npm-registry-url` | | URL of that registry, for example `https://npm.fontawesome.com/`. |
| `runner` | | Runner label or runner group, as in the other workflows |

**Private npm registry.** Set `npm-registry-scope`, `npm-registry-url` and the `npm-registry-token` secret together; with any one missing nothing changes. Renovate and the install step both use it. The token goes into an npmrc outside the checkout (`NPM_CONFIG_USERCONFIG`), is masked in logs, and works for npm, pnpm and yarn classic. Yarn 2+ ignores npmrc and needs its own `.yarnrc.yml`.

**Failing updates.** The last 50 KB of the test output goes into a comment on one issue titled "Dependency updates failing tests". Each failing branch has its own comment, updated on every run, and a header with the commit and the run link. When a branch passes and merges, its comment is removed. When no failing branch is left, the issue closes. The output is also in the run summary. Without `issues: write` the run still works, but the issue is skipped.

**Only what is tested is updated.** Renovate manages one Go module and one Node project: the ones in `go-working-directory` and `node-working-directory`. A second `package.json` (docs, e2e tests, another frontend) or a second `go.mod` is left alone, because nothing would test its updates. In a workspace the same rule applies to packages: only those in `node-packages` are updated, plus `pnpm-workspace.yaml` and the root `pnpm-lock.yaml`.

**Branches run one at a time**, so each one is tested on top of the ones merged before it. A branch that conflicts with the default branch is skipped, and Renovate rebases it on the next run.

**Package manager.** pnpm is used when `pnpm-lock.yaml` exists, yarn for `yarn.lock`, otherwise npm. The install step never changes the lockfile (`--frozen-lockfile`, `--immutable`, `npm ci`), so a lockfile that does not match `package.json` fails the run. pnpm and yarn run through Corepack, so set `packageManager` in `package.json`. A workspace with no root `package.json` has no such field, so set `pnpm-version`. With `require-node-tests`, every listed package needs a `test` script.

**Per-project rules.** Put a `renovate.json` in the calling repository. Renovate reads it and merges it with the defaults, so no extra input is needed:

```json
{
  "ignoreDeps": ["some/package"],
  "packageRules": [{ "matchPackageNames": ["vite"], "enabled": false }]
}
```

The defaults already cap `typescript` below 7, which breaks `vue-tsc`.

**Token.** No secret is needed. Everything runs inside the calling repository with the workflow's own token, which needs `contents: write` and `pull-requests: write`. Two repository settings matter:

- Settings, Actions, General: tick "Allow GitHub Actions to create and approve pull requests". Without it the workflow cannot open the PR.
- A push made with the workflow token does not trigger other workflows, so a release workflow that runs on `push` will not start after a merge. Set `release-workflow` to dispatch it, and grant `actions: write`.

**Commit message.** The squash commit subject is the Renovate commit message, for example `chore(deps): update dependencies`, and the body is fixed text. Neither contains `major` or `breaking`, which `semver-generator` matches in commit messages.

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

Optional probes use the real token, so they catch caller `permissions:` that are too narrow:
- `release-write: "true"` runs `git push --dry-run`, which fails when the token cannot push (no tag or release possible).
- `ghcr-push: true|auto` asks ghcr.io for a push token and opens a blob upload session (no package is created). `auto` probes only when the config has `dockers`/`dockers_v2`/`docker_manifests` and mentions `ghcr.io`. The image is the first `ghcr.io/...` path in the config, else the repository (`ghcr-image` overrides).
- A probe that cannot reach a verdict (network error, odd status) warns and does not fail.

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
