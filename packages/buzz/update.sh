#!/usr/bin/env bash
set -euo pipefail

# Follow the latest desktop-v* release and grab the amd64 .deb asset.
release=$(curl -s https://api.github.com/repos/block/buzz/releases/latest)
tag=$(echo "$release" | jq -r '.tag_name')
version="${tag#desktop-v}"

deb_name=$(echo "$release" | jq -r '.assets[] | select(.name | endswith("amd64.deb")) | .name')
deb_url=$(echo "$release" | jq -r '.assets[] | select(.name | endswith("amd64.deb")) | .browser_download_url')

if [[ -z "$deb_url" || "$deb_url" == "null" ]]; then
  echo "No amd64 .deb asset found in latest release"
  exit 1
fi

# Prefetch and get SRI hash
hash=$(nix-prefetch-url "$deb_url" 2>/dev/null)
sri_hash=$(nix hash convert --hash-algo sha256 --to sri "$hash")

# NOTE: no sed -i (not portable between GNU and BSD sed); write to temp + mv instead.
pkg_file="$(dirname "$0")/package.nix"
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

sed \
  -e "s|version = \"[^\"]*\"|version = \"${version}\"|" \
  -e "s|url = \"[^\"]*\"|url = \"${deb_url}\"|" \
  -e "s|hash = \"[^\"]*\"|hash = \"${sri_hash}\"|" \
  "$pkg_file" > "$tmp_file"
mv "$tmp_file" "$pkg_file"

echo "Updated buzz to v${version} (${deb_name})"