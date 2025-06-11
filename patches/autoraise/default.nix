# Custom AutoRaise derivation that enables focus-without-raising functionality
# This differs from the nixpkgs version by adding compilation flags:
# - OLD_ACTIVATION_METHOD: Better support for non-native apps (GTK, SDL, Wine)
# - EXPERIMENTAL_FOCUS_FIRST: Allows focusing windows without raising them when delay=0
# 
# Usage: Set delay=0 to get focus-follows-mouse without auto-raise behavior
# Warning: Uses undocumented macOS APIs that may break in future versions

{ lib
, stdenv
, fetchFromGitHub
, apple-sdk
}:

stdenv.mkDerivation rec {
  pname = "autoraise";
  version = "5.3";

  src = fetchFromGitHub {
    owner = "sbmpost";
    repo = "AutoRaise";
    rev = "v${version}";
    sha256 = "14cvilc2kl89khcjqz4b4lai5250zlzkfy24bafazqshg8sfdjrs";
  };

  buildInputs = [
    apple-sdk.privateFrameworksHook
  ];

  buildPhase = ''
    runHook preBuild
    $CXX -std=c++03 -fobjc-arc \
      -D"NS_FORMAT_ARGUMENT(A)=" \
      -D"SKYLIGHT_AVAILABLE=1" \
      -DOLD_ACTIVATION_METHOD \
      -DEXPERIMENTAL_FOCUS_FIRST \
      -o AutoRaise AutoRaise.mm \
      -framework AppKit -framework SkyLight
    bash create-app-bundle.sh
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications $out/bin
    mv AutoRaise.app $out/Applications/AutoRaise.app
    ln -s $out/Applications/AutoRaise.app/Contents/MacOS/AutoRaise $out/bin/autoraise
    runHook postInstall
  '';

  meta = {
    description = "AutoRaise (and focus) a window when hovering over it with the mouse";
    homepage = "https://github.com/sbmpost/AutoRaise";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ nickhu ];
    mainProgram = "autoraise";
    platforms = lib.platforms.darwin;
  };
}