{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "impeccable-skills";
  version = "skill-v3.1.1-unstable-2026-05-18";

  src = fetchFromGitHub {
    owner = "pbakaus";
    repo = "impeccable";
    rev = "e1d3ea0b6f79ebccb80b9e4b0d2b2ad62a13205b";
    hash = "sha256-IOc2j7GCXK225uRyfixwjS6IJlZs+hQnf6Kk/HigYIA=";
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
