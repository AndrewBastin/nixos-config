#!/usr/bin/env bash
set -euo pipefail

# Plain nix-update picks up desktop-v* tags pushed before their release (no
# AppImage yet) and keeps the "desktop-v" prefix, so ask for the latest
# published release instead.
tag=$(curl -fsSL https://api.github.com/repos/ParadevAI/Paradev/releases/latest | jq -r .tag_name)
nix-update --flake paradev --version="${tag#desktop-v}"
