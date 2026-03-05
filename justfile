# Bump all auto-updatable packages and flake inputs
bump:
  #!/usr/bin/env bash
  set -euo pipefail

  system=$(nix eval --raw --impure --expr 'builtins.currentSystem')

  for dir in packages/*/; do
    name=$(basename "$dir")
    if [[ ! -f "$dir/package.nix" ]]; then
      continue
    fi

    # Skip packages that opt out of auto-updates (e.g. requireFile-based packages)
    if nix eval --raw ".#packages.${system}.${name}.passthru.skipAutoUpdate" 2>/dev/null | grep -q "true"; then
      echo "Skipping $name (skipAutoUpdate=true)"
      continue
    fi

    echo "Updating $name..."
    if [[ -x "$dir/update.sh" ]]; then
      "$dir/update.sh" || echo "  Failed to update $name, continuing..."
    elif grep -q 'version=branch' "$dir/package.nix"; then
      nix-update --flake "$name" --version=branch || echo "  Failed to update $name, continuing..."
    else
      nix-update --flake "$name" || echo "  Failed to update $name, continuing..."
    fi
  done

  echo "Updating flake inputs..."
  nix flake update
