{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "2.1.207-unstable-2026-07-11";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "d4d8fbbb333c627d8fe2c1c583a5ccc26fdb1aed";
    hash = "sha256-fVtZ5SpQO75FKHgRXWQwImFoCg5pwRWbrzkIQ7RDQPY=";
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
