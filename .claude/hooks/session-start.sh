#!/usr/bin/env bash
# .claude/hooks/session-start.sh
# Installs a Swift 6.1 toolchain in Linux cloud sessions so package tests can run.
# download.swift.org may be blocked, so the toolchain layer is pulled from the official
# Docker Hub image (swift:6.1-noble) instead. No-op on macOS or when swift is present.
set -euo pipefail
[[ "$(uname)" == "Linux" ]] || exit 0
command -v swift >/dev/null 2>&1 && exit 0
[[ -x /opt/swiftroot/usr/bin/swift ]] || {
  export DEBIAN_FRONTEND=noninteractive
  apt-get -qq update >/dev/null
  apt-get -qq install -y binutils libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libpython3-dev \
    libsqlite3-0 libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev pkg-config tzdata zlib1g-dev >/dev/null
  repo=library/swift; tag=6.1-noble
  token=$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repo:pull" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
  index=$(curl -fsS -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.oci.image.index.v1+json" "https://registry-1.docker.io/v2/$repo/manifests/$tag")
  digest=$(python3 -c 'import sys,json;print([m["digest"] for m in json.loads(sys.argv[1])["manifests"] if m.get("platform",{}).get("architecture")=="amd64"][0])' "$index")
  manifest=$(curl -fsS -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" "https://registry-1.docker.io/v2/$repo/manifests/$digest")
  # The largest layer is the toolchain.
  layer=$(python3 -c 'import sys,json;print(max(json.loads(sys.argv[1])["layers"],key=lambda l:l["size"])["digest"])' "$manifest")
  mkdir -p /opt/swiftroot
  curl -fsSL -H "Authorization: Bearer $token" "https://registry-1.docker.io/v2/$repo/blobs/$layer" | tar -xz -C /opt/swiftroot
}
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  echo 'export PATH=/opt/swiftroot/usr/bin:$PATH' >> "$CLAUDE_ENV_FILE"
fi
