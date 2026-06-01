{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "impeccable-skills";
  version = "0-unstable-2026-06-01";

  src = fetchFromGitHub {
    owner = "pbakaus";
    repo = "impeccable";
    rev = "ea3e66b9844fbbdbfdbb55b81d4ec6ec3181234b";
    hash = "sha256-8/+ag3MUkYe4GVxQUUmabF+jQJnSn8sUSb9a1Rqqmy0=";
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
