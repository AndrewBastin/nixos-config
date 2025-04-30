# Custom Override for Claude Code. Builds 0.2.92 version if nixpkgs
# version is below that, else just returns the nixpkgs version

# TODO: Remove this when claude-code version is above 0.2.92
#       as the override will become a no-op after that

# NOTE: pkgs is expected to be a nixos unstable branch nixpkgs
{ pkgs }:
  let
    patchVersion = "0.2.92";
    nixpkgsVersion = pkgs.claude-code.version;

    compareVersions = pkgs.lib.strings.compareVersions;
  in
    if compareVersions nixpkgsVersion patchVersion < 0 then 
      # Copy-pasted in from https://github.com/NixOS/nixpkgs/blob/aafd9d5cdc9fedc95f00db40d4800f28d707df73/pkgs/by-name/cl/claude-code/package.nix
      pkgs.buildNpmPackage rec {
        pname = "claude-code";
        version = "0.2.92";

        src = pkgs.fetchzip {
          url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
          hash = "sha256-PYNtUsexEdl8QphDclgb8v37mN8WvjJO5A8yLiJ6zAs=";
        };

        npmDepsHash = "sha256-jSiYaCr8iSAi+368orDnBpDt1XbXGkfULMRKs9XURZY=";

        postPatch = ''
          cp ${./package-lock.json} package-lock.json
        '';

        dontNpmBuild = true;

        AUTHORIZED = "1";

        # `claude-code` tries to auto-update by default, this disables that functionality.
        # https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview#environment-variables
        postInstall = ''
          wrapProgram $out/bin/claude \
            --set DISABLE_AUTOUPDATER 1
        '';

        meta = {
          description = "An agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
          homepage = "https://github.com/anthropics/claude-code";
          downloadPage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
          license = pkgs.lib.licenses.unfree;
          maintainers = [ pkgs.lib.maintainers.malo ];
          mainProgram = "claude";
        };
      }
    else pkgs.claude-code
