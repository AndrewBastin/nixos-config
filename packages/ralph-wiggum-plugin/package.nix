{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "2.1.123-unstable-2026-04-29";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "e512ec99188d191b07662fc9f69c5764f750a302";
    hash = "sha256-O66x6qxUk/qmEXS0USORS2nhfvHdP/2cbj7RJ6bPhqY=";
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
