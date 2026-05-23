{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "impeccable-skills";
  version = "skill-v3.1.1-unstable-2026-05-22";

  src = fetchFromGitHub {
    owner = "pbakaus";
    repo = "impeccable";
    rev = "84135db0e6bdd58d22828f7bc8331cae7bde3e7f";
    hash = "sha256-7RvZqieiIOXtMBTg4XX8OMcaETMr1mFjx+IW55iL0EU=";
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
