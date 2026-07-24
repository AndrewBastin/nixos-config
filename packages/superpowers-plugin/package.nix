{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "superpowers-plugin";
  version = "6.2.0-unstable-2026-07-24";

  src = fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9";
    hash = "sha256-F5LEk0yNWbMpan1vZSFZM76XSpsFGvA7h8q6Idrvenk=";
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
