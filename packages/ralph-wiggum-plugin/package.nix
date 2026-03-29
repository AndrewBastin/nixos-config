{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "ralph-wiggum-plugin";
  version = "2.1.87-unstable-2026-03-29";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "78a44f1b7dbd6f728cb8966b36ab7fa1be99dbc5";
    hash = "sha256-FH0fzx93eQKeX0Pd/FiHIhPmyYGvanv19VtLMHIX6Wk=";
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
