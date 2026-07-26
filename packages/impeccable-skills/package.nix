{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "impeccable-skills";
  version = "skill-v4.0.2-unstable-2026-07-27";

  src = fetchFromGitHub {
    owner = "pbakaus";
    repo = "impeccable";
    rev = "5e572c8b8af3e108ab52ce4180adb4d6eb1c2ebc";
    hash = "sha256-wcqhQiIjy9WO1OxgXVDJ4P6gyVQhxWxtE53XajG3BOs=";
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
