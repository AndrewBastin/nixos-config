{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-plugin";
  version = "5.0.7-unstable-2026-04-24";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "6efe32c9e2dd002d0c394e861e0529675d1ab32e";
    hash = "sha256-0WupTacT1jIwVBloj1i0RF7wIllVtP8eMPRl7VrXdbE=";
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
