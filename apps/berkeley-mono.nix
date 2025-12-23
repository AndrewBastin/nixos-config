# Berkeley Mono (https://usgraphics.com/products/berkeley-mono) font
# patched with Nerd Fonts using nerd-font-patcher.
#
# This derivation uses `requireFile` to reference the font from the Nix store
# by its hash, allowing it to work with pure flake builds without committing
# the proprietary font to the repository.
#
# SETUP:
#   1. Purchase and download Berkeley Mono from:
#      https://usgraphics.com/typefaces/berkeley-mono/
#
#   2. Add the zip file to the Nix store:
#      nix-prefetch-url file:///path/to/berkeley-mono.zip
#
#   3. The command will output a hash. Update the `sha256` below if it differs.
#
# FONT COMPILER OPTIONS (Standard Compiler):
#   Font Name: Typeface Name
#   Font Formats: TTF
#   Font Width: 100
#   Font Weight: 400, 700
#   Font Slant: 0, -16
#   Glyph Alternatives:
#     - Zero: 2nd option (slash going through it)
#     - Seven: 1st option (no dash going through it)
#   Version: 2.004
{
  lib,
  stdenvNoCC,
  requireFile,
  unzip,
  nerd-font-patcher
}:

stdenvNoCC.mkDerivation {
  pname = "berkeley-mono";
  version = "2.004";

  src = requireFile {
    name = "berkeley-mono.zip";
    sha256 = "0pigbjbzzm912lkavgwj6c0d4l0yny7k3mymwcsdq4ykif9r14fx";
    message = ''
      Berkeley Mono font not found in the Nix store.

      To add it, download Berkeley Mono from:
        https://usgraphics.com/typefaces/berkeley-mono/

      Then run:
        nix-prefetch-url file:///path/to/berkeley-mono.zip

      Update the sha256 in apps/berkeley-mono.nix if the hash differs.
    '';
  };

  nativeBuildInputs = [ unzip nerd-font-patcher ];

  sourceRoot = ".";

  buildPhase = ''
    runHook preBuild

    mkdir -p patched
    find . -name "*.ttf" -o -name "*.otf" | while read font; do
      nerd-font-patcher --complete --no-progressbars --outputdir patched "$font"
    done

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/truetype
    find patched -name "*.ttf" -exec install -Dm644 {} $out/share/fonts/truetype/ \;

    mkdir -p $out/share/fonts/opentype
    find patched -name "*.otf" -exec install -Dm644 {} $out/share/fonts/opentype/ \;

    runHook postInstall
  '';

  meta = with lib; {
    description = "Berkeley Mono font patched with Nerd Fonts";
    homepage = "https://berkeleygraphics.com/typefaces/berkeley-mono/";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
