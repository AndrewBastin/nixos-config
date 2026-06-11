{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.172-unstable-2026-06-10";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "ca34f27543215fa4212872401dff00ba0ff0a034";
    hash = "sha256-EfG0piJ4DDq/zAmgkzZKb0H2Y5D9bEom8/S3UsqSKrg=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r plugins/frontend-design/skills $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Frontend design skills for AI coding assistants from Claude Code";
    homepage = "https://github.com/anthropics/claude-code";
    platforms = platforms.all;
  };
}
