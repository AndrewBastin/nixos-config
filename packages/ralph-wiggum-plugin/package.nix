{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "0-unstable-2026-06-04";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "d1e174252d0af47174bd9fbdec6abb092b49226a";
    hash = "sha256-jY8DPVJkmYaS+j6vW3jpPiy9B6OrgPhA8HCfjDu29nI=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r plugins/ralph-wiggum $out
    chmod +x $out/hooks/stop-hook.sh $out/scripts/setup-ralph-loop.sh
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Ralph Wiggum loop plugin for Claude Code — self-referential agentic loops";
    homepage = "https://github.com/anthropics/claude-code";
    platforms = platforms.all;
  };
}
