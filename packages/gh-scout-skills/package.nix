{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "gh-scout-skills";
  version = "0-unstable-2026-02-14";

  src = fetchFromGitHub {
    owner = "AndrewBastin";
    repo = "gh-scout";
    rev = "7bbfa2529514dc3641905e452d0ff68f513d4b39";
    hash = "sha256-XivUPqFqkeOXBj34sQHJcJqBkxACf/kVCx65MHw8zK0=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r skills $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "GitHub Scout skills for AI coding assistants";
    homepage = "https://github.com/AndrewBastin/gh-scout";
    platforms = platforms.all;
  };
}
