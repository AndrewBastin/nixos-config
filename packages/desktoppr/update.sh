#!/usr/bin/env bash
set -euo pipefail

# Fetch latest release metadata
release=$(curl -s https://api.github.com/repos/scriptingosx/desktoppr/releases/latest)
tag=$(echo "$release" | jq -r '.tag_name')
version="${tag#v}"

# Find the .zip asset URL (contains the dynamic build number)
zip_url=$(echo "$release" | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url')
zip_name=$(echo "$release" | jq -r '.assets[] | select(.name | endswith(".zip")) | .name')

if [[ -z "$zip_url" || "$zip_url" == "null" ]]; then
  echo "No .zip asset found in latest release"
  exit 1
fi

# Prefetch and get SRI hash
hash=$(nix-prefetch-url --unpack "$zip_url" 2>/dev/null)
sri_hash=$(nix hash convert --hash-algo sha256 --to sri "$hash")

pkg_file="$(dirname "$0")/package.nix"

# Update version
sed -i '' "s|version = \".*\"|version = \"${version}\"|" "$pkg_file"

# Update the full URL (asset name includes the build number)
# Asset format: desktoppr-<version>-<build>.zip
old_url_pattern='url = "https://github.com/scriptingosx/desktoppr/releases/download/.*";'
new_url="url = \"https://github.com/scriptingosx/desktoppr/releases/download/v\${finalAttrs.version}/${zip_name}\";"
sed -i '' "s|${old_url_pattern}|${new_url}|" "$pkg_file"

# Update hash
sed -i '' "s|hash = \".*\"|hash = \"${sri_hash}\"|" "$pkg_file"

echo "Updated desktoppr to v${version} (${zip_name})"
