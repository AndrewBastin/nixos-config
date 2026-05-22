{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "andrej-karpathy-skills-plugin";
  version = "1.0.0-unstable-2026-04-20";

  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "andrej-karpathy-skills";
    rev = "2c606141936f1eeef17fa3043a72095b4765b9c2";
    hash = "sha256-4z/wRdYH7UXRzF8RJU0sw8xbpx0BW/7CBv5sVEC2knY=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    rm -rf $out/.git $out/.github $out/.cursor
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Claude Code plugin packaging Andrej Karpathy's behavioral guidelines to reduce common LLM coding mistakes";
    homepage = "https://github.com/multica-ai/andrej-karpathy-skills";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
