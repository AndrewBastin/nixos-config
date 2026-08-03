{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "impeccable-skills";
  version = "skill-v4.0.4-unstable-2026-08-03";

  src = fetchFromGitHub {
    owner = "pbakaus";
    repo = "impeccable";
    rev = "33b9a3752b8852c7adb7f4935a3f6c160bf3fefc";
    hash = "sha256-/bWOc98fmtTwEhyQ24Qe11v2q4IkMzPVhnmJuOhASdQ=";
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
