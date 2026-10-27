#!/usr/bin/env bash
#
# ci/gitleaks.sh — scan a range of commits with the pinned gitleaks and a rules file.
#
#   ci/gitleaks.sh <git-log-range> [rules-file]      (rules default: .gitleaks.toml)
#
# Shared by .forgejo/workflows/leak-check.yml and publish.yml, so both gates run the
# same binary. The release tarball is downloaded once into a cache and its sha256 is
# checked on EVERY run, cache hit or not: a tampered or truncated cache fails closed
# instead of scanning with a binary nobody pinned. Needs only curl, tar, sha256sum
# and git; nothing else on the runner is trusted or assumed.
#
# Bumping the pin: change the version and both hashes together, from the release's
# own gitleaks_<version>_checksums.txt, in a PR of its own.

set -euo pipefail

GITLEAKS_VERSION=8.30.1
declare -A GITLEAKS_SHA256=(
  [x64]=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
  [arm64]=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080
)

range=${1:?usage: ci/gitleaks.sh <git-log-range> [rules-file]}
rules=${2:-.gitleaks.toml}

case "$(uname -m)" in
  x86_64)        arch=x64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "gitleaks.sh: no pinned gitleaks build for $(uname -m)" >&2; exit 1 ;;
esac

tarball="gitleaks_${GITLEAKS_VERSION}_linux_${arch}.tar.gz"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/fangs-doc/gitleaks"
mkdir -p "$cache"

if [ ! -f "$cache/$tarball" ]; then
  curl -fsSL --retry 3 -o "$cache/$tarball.part" \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${tarball}"
  mv "$cache/$tarball.part" "$cache/$tarball"
fi

if ! echo "${GITLEAKS_SHA256[$arch]}  $cache/$tarball" | sha256sum --check --quiet -; then
  rm -f "$cache/$tarball"
  echo "gitleaks.sh: $tarball does not match its pinned sha256; removed it, refusing to scan" >&2
  exit 1
fi

bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
tar -xzf "$cache/$tarball" -C "$bin" gitleaks

# --redact: findings land in CI logs; name the commit, file, line and rule, never the value.
"$bin/gitleaks" git --config "$rules" --log-opts="$range" \
  --redact --no-banner --exit-code 1 .
