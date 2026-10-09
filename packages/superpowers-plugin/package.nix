{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-plugin";
  version = "7.0.0-unstable-2026-10-10";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "bb92a77741419a4ab5f06e711a283343f1ada0c3";
    hash = "sha256-UCVI+T7j1Xh1LDkrvnJduis7eHFqrizCyGTWAGW5d6U=";
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
