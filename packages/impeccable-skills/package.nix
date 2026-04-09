{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "impeccable-skills";
  version = "0-unstable-2026-04-08";

  src = fetchFromGitHub {
    owner = "pbakaus";
    repo = "impeccable";
    rev = "e7afda2c5505a8893bc4d05267949b3197b4c00f";
    hash = "sha256-bUaVfF+4ilcazXnyLWa9nuqUINnH8WgElcTVFYodeTY=";
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
