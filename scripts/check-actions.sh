#!/usr/bin/env bash
# Static checks for the workflows and composite actions in this repository:
#   1. actionlint (schema, expressions, and shell steps through shellcheck when present)
#   2. every external `uses:` reference resolves to a real tag or branch
#
# Usage: scripts/check-actions.sh [--ci | --renovate]
#   --ci        exit 1 when a check fails (default)
#   --renovate  exit 0 and write .validation-failed when a check fails, so the
#               Renovate runner deletes the branch before a PR can open
#
# Needs: bash, git, curl, tar, sha256sum or shasum. No other tools: actionlint is
# downloaded at a pinned version and checked against a pinned SHA-256.
set -u

mode=--ci
case "${1:-}" in
  "" | --ci) mode=--ci ;;
  --renovate) mode=--renovate ;;
  *) echo "usage: $0 [--ci | --renovate]" >&2; exit 2 ;;
esac

ACTIONLINT_VERSION=1.7.12
ACTIONLINT_SHA256_AMD64=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
ACTIONLINT_SHA256_ARM64=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6
marker=.validation-failed

cd "$(git rev-parse --show-toplevel)" || exit 2

fail=0
problem() {
  echo "::error::$*" >&2
  fail=1
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

install_actionlint() {
  local os arch want url tmp
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) return 1 ;; esac
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64; want=$ACTIONLINT_SHA256_AMD64 ;;
    aarch64 | arm64) arch=arm64; want=$ACTIONLINT_SHA256_ARM64 ;;
    *) return 1 ;;
  esac
  # The pinned checksums are for the linux builds only.
  [ "$os" = linux ] || return 1
  tmp=$(mktemp -d)
  url="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_${os}_${arch}.tar.gz"
  curl -fsSL --retry 3 -o "$tmp/a.tgz" "$url" || return 1
  [ "$(sha256_of "$tmp/a.tgz")" = "$want" ] || { echo "actionlint checksum mismatch" >&2; return 1; }
  tar -xzf "$tmp/a.tgz" -C "$tmp" actionlint || return 1
  echo "$tmp/actionlint"
}

run_actionlint() {
  local bin
  if command -v actionlint >/dev/null 2>&1; then
    bin=$(command -v actionlint)
  else
    bin=$(install_actionlint) || { problem "cannot install actionlint ${ACTIONLINT_VERSION}"; return; }
  fi
  # -shellcheck= disables the shellcheck pass when the binary is missing.
  local opts=()
  command -v shellcheck >/dev/null 2>&1 || opts+=(-shellcheck=)
  # Info and style findings from shellcheck (for example SC2086 on intentional word
  # splitting) do not fail the gate. Warnings and errors do. Composite actions are
  # not linted by actionlint 1.7; workflows are.
  opts+=(-ignore 'shellcheck reported issue.+SC[0-9]+:(info|style):')
  if ! "$bin" "${opts[@]}" -color .github/workflows/*.y*ml; then
    problem "actionlint reported problems"
  fi
}

# Resolves every `uses: owner/repo[/path]@ref` that points outside this repository.
check_refs() {
  local files uses ref repo path checked=""
  files=$(find .github -type f \( -name '*.yml' -o -name '*.yaml' \))
  uses=$(grep -hoE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[^[:space:]#]+' $files | sed -E 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*//' | sort -u)
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    case "$u" in ./* | docker://*) continue ;; esac
    repo=${u%%@*}
    ref=${u#*@}
    [ "$repo" != "$u" ] || { problem "no @ref in 'uses: $u'"; continue; }
    # owner/repo/sub/path -> owner/repo
    path=$(echo "$repo" | cut -d/ -f1,2)
    # This repository's own composite actions are tracked at @main by design.
    [ "$path" = lukaszraczylo/shared-actions ] && continue
    case " $checked " in *" $path@$ref "*) continue ;; esac
    checked="$checked $path@$ref"
    if ! git ls-remote --exit-code "https://github.com/$path" "refs/tags/$ref" "refs/heads/$ref" >/dev/null 2>&1; then
      # A full commit SHA is not listed by ls-remote; accept it when the repository answers at all.
      if echo "$ref" | grep -qE '^[0-9a-f]{40}$' && git ls-remote --exit-code "https://github.com/$path" HEAD >/dev/null 2>&1; then
        continue
      fi
      problem "'uses: $u' does not resolve: no tag or branch $ref in $path"
    fi
  done <<<"$uses"
}

rm -f "$marker"
run_actionlint
check_refs

if [ "$fail" -ne 0 ]; then
  if [ "$mode" = --renovate ]; then
    echo "validation failed; writing $marker" >&2
    printf 'actions validation failed\n' >"$marker"
    exit 0
  fi
  exit 1
fi
echo "actions validation passed"
