{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "impeccable-skills";
  version = "skill-v4.0.4-unstable-2026-08-04";

  src = fetchFromGitHub {
    owner = "pbakaus";
    repo = "impeccable";
    rev = "620ba1fe7d87a39039a8528bfaa319ecfa893cb2";
    hash = "sha256-uQTEundxOl6qdb5wOf88JX3urMa9i2ALNd+5RNZqYpM=";
  };

  dontBuild = true;

  # Use the .agents/skills directory — it's tool-agnostic ("the model" vs "Claude")
  # and works across both Claude Code and pi/maniyan.
  installPhase = ''
    runHook preInstall
    cp -r .agents/skills $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Impeccable design skills for AI coding assistants — 21 commands for frontend design quality";
    homepage = "https://impeccable.style";
    license = licenses.asl20;
    platforms = platforms.all;
  };
}
