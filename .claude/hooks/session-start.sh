#!/usr/bin/env bash
# .claude/hooks/session-start.sh
# Installs a Swift 6.1 toolchain in Linux cloud sessions so package tests can run.
# download.swift.org may be blocked, so the toolchain layer is pulled from the official
# swift:6.1-noble image instead: first from Google's Docker Hub mirror (mirror.gcr.io,
# no auth, no pull-rate limit), then from Docker Hub itself. No-op on macOS or when swift
# is present.
set -euo pipefail
[[ "$(uname)" == "Linux" ]] || exit 0
command -v swift >/dev/null 2>&1 && exit 0

# Prints the digest of the largest layer (the toolchain) of swift:6.1-noble for amd64.
# $1 = registry base URL, $2 = optional bearer token.
toolchain_layer() {
  local base=$1 auth=() index digest manifest
  [[ -n "${2:-}" ]] && auth=(-H "Authorization: Bearer $2")
  index=$(curl -fsS "${auth[@]}" -H "Accept: application/vnd.oci.image.index.v1+json" "$base/manifests/6.1-noble")
  digest=$(python3 -c 'import sys,json;print([m["digest"] for m in json.loads(sys.argv[1])["manifests"] if m.get("platform",{}).get("architecture")=="amd64"][0])' "$index")
  manifest=$(curl -fsS "${auth[@]}" -H "Accept: application/vnd.oci.image.manifest.v1+json" "$base/manifests/$digest")
  python3 -c 'import sys,json;print(max(json.loads(sys.argv[1])["layers"],key=lambda l:l["size"])["digest"])' "$manifest"
}

[[ -x /opt/swiftroot/usr/bin/swift ]] || {
  export DEBIAN_FRONTEND=noninteractive
  apt-get -qq update >/dev/null
  apt-get -qq install -y binutils libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libpython3-dev \
    libsqlite3-0 libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev pkg-config tzdata zlib1g-dev >/dev/null
  mkdir -p /opt/swiftroot
  base=https://mirror.gcr.io/v2/library/swift
  if layer=$(toolchain_layer "$base"); then
    curl -fsSL "$base/blobs/$layer" | tar -xz -C /opt/swiftroot
  else
    base=https://registry-1.docker.io/v2/library/swift
    token=$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/swift:pull" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
    layer=$(toolchain_layer "$base" "$token")
    curl -fsSL -H "Authorization: Bearer $token" "$base/blobs/$layer" | tar -xz -C /opt/swiftroot
  fi
}
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  echo 'export PATH=/opt/swiftroot/usr/bin:$PATH' >> "$CLAUDE_ENV_FILE"
fi
