#!/usr/bin/env bash
set -euo pipefail

# Fetch latest release metadata
release=$(curl -s https://api.github.com/repos/scriptingosx/desktoppr/releases/latest)
tag=$(echo "$release" | jq -r '.tag_name')
version="${tag#v}"

# Find the .zip asset name (contains the dynamic build number)
zip_name=$(echo "$release" | jq -r '.assets[] | select(.name | endswith(".zip")) | .name')
zip_url=$(echo "$release" | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url')

if [[ -z "$zip_url" || "$zip_url" == "null" ]]; then
  echo "No .zip asset found in latest release"
  exit 1
fi

# Prefetch and get SRI hash
hash=$(nix-prefetch-url --unpack "$zip_url" 2>/dev/null)
sri_hash=$(nix hash convert --hash-algo sha256 --to sri "$hash")

# NOTE: no sed -i (not portable between GNU and BSD sed); write to temp + mv instead.
pkg_file="$(dirname "$0")/package.nix"
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

sed \
  -e "s|version = \"[^\"]*\"|version = \"${version}\"|" \
  -e "s|url = \"[^\"]*\"|url = \"${zip_url}\"|" \
  -e "s|hash = \"[^\"]*\"|hash = \"${sri_hash}\"|" \
  "$pkg_file" > "$tmp_file"
mv "$tmp_file" "$pkg_file"

echo "Updated desktoppr to v${version} (${zip_name})"