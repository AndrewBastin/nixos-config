{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "impeccable-skills";
  version = "skill-v3.7.1-unstable-2026-06-17";

  src = fetchFromGitHub {
    owner = "pbakaus";
    repo = "impeccable";
    rev = "1c897a09c86ea7ed7e5cc3affaabcbbb46a05a7d";
    hash = "sha256-SkZTqKYvbsEgGpbeRxitt7O2wOruJyQXPq6GxEIBmYQ=";
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
