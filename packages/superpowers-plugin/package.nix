{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-plugin";
  version = "6.2.0-unstable-2026-07-28";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "44c9b2d6e889982ac18c27d05a19fefe335194e1";
    hash = "sha256-fnl+HbPL2qD5Zgz8a1NctjFJSqu6UsyHJAhQMLQNXXc=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    rm -rf $out/.git $out/.github $out/tests $out/docs
    chmod +x $out/hooks/session-start
    chmod +x $out/skills/brainstorming/scripts/start-server.sh
    chmod +x $out/skills/brainstorming/scripts/stop-server.sh
    chmod +x $out/skills/systematic-debugging/find-polluter.sh
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Superpowers — an agentic skills framework & software development methodology for Claude Code";
    homepage = "https://github.com/obra/superpowers";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
