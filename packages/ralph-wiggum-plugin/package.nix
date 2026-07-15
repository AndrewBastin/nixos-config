{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "2.1.210-unstable-2026-07-14";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "b7784f2c63ed4585c32bc20b94d3b64cf4fe6df3";
    hash = "sha256-jb6SQOzQyYLoBoXMW1A2iTKFh/Z457/iJ/z7YPj4ri4=";
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
