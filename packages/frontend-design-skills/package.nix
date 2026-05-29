{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.156-unstable-2026-05-29";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "2d5c3c6c85048de7a4426a91268076807ebaeba5";
    hash = "sha256-YZ9ToLuIfrRPOfilDcMbzkoqvKlpp5/QrBAuLMmECuI=";
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
