{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script
}:

stdenvNoCC.mkDerivation {
  pname = "frontend-design-skills";
  version = "2.1.197-unstable-2026-06-30";

  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "a56ff02e8592fb2ad056e60d6f4fa231724deabb";
    hash = "sha256-uFfwj0w6tKlWXkvG1BK1LxWqeAd5E1M6fhr0jvx1nAw=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r plugins/frontend-design/skills $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Frontend design skills for AI coding assistants from Claude Code";
    homepage = "https://github.com/anthropics/claude-code";
    platforms = platforms.all;
  };
}
