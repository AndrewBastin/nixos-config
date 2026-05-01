{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-plugin";
  version = "5.0.7-unstable-2026-04-30";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "e7a2d16476bf042e9add4699c9d018a90f86e4a6";
    hash = "sha256-8/M/S0BUYurZkFqe6LemVtBQnPSxBNfy1C7Q6f92hjE=";
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
