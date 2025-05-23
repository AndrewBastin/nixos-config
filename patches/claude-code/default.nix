# Custom Override for Claude Code. Builds 0.2.92 version if nixpkgs
# version is below that, else just returns the nixpkgs version

# TODO: Remove this when claude-code version is above 1.0.0
#       as the override will become a no-op after that

# NOTE: pkgs is expected to be a nixos unstable branch nixpkgs
{
  buildNpmPackage,
  claude-code,

  fetchzip,
  lib
}:
  let
    patchVersion = "1.0.2";
    nixpkgsVersion = claude-code.version;

    compareVersions = lib.strings.compareVersions;
  in
    if compareVersions nixpkgsVersion patchVersion < 0 then 
      # Copy-pasted in from https://github.com/NixOS/nixpkgs/blob/aafd9d5cdc9fedc95f00db40d4800f28d707df73/pkgs/by-name/cl/claude-code/package.nix
      buildNpmPackage rec {
        pname = "claude-code";
        version = patchVersion;

        src = fetchzip {
          url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
          hash = "sha256-mQv2o9uaOZiZSdkNmLiqJs66fe9fiHfEmrXQZwmME34=";
        };

        npmDepsHash = "sha256-Diii1tBBzYlB4svlphtu1VAOoijoq9WudxtJFSXXbbE=";

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
          license = lib.licenses.unfree;
          maintainers = [ lib.maintainers.malo ];
          mainProgram = "claude";
        };
      }
    else claude-code
