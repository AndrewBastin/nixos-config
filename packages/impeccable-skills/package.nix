{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "impeccable-skills";
  version = "skill-v3.0.5-unstable-2026-04-29";

  src = fetchFromGitHub {
    owner = "pbakaus";
    repo = "impeccable";
    rev = "9a5d0e71a9011def4fbd011d5fca33360880b409";
    hash = "sha256-aS8BGsSw6RcraTQQ11WI21O/1GdjRV5sGGb5w/6mnlI=";
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
