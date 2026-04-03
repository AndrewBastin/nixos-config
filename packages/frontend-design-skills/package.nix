{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.91-unstable-2026-04-02";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "1e03cc7fc40d9bab33f24855a8b5d31ba66205cb";
    hash = "sha256-0a0UCD0WeUyN0vBaSYXxCaIIv3iT7coduQKpjcQaeQQ=";
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
