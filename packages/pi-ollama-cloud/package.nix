{
  lib,
  stdenvNoCC,
  fetchzip,
  nix-update-script,
}:

# Ollama Cloud provider extension for pi. Unlike pi-vim this needs no patching:
# it only uses bare imports of the packages pi itself bundles (@earendil-works/*,
# typebox), which pi's extension loader resolves from inside its own binary.
# Verified by loading it with `pi -e` — the ollama-cloud models show up in
# `--list-models`.
#
# Loaded as a directory, not a file, so pi reads the `pi.extensions` manifest in
# package.json rather than us hardcoding an entrypoint that upstream may move.
stdenvNoCC.mkDerivation rec {
  pname = "pi-ollama-cloud";
  version = "0.9.0";

  # See packages/pi-vim/package.nix for why `name` embeds the version: without it
  # a stale hash silently resolves to the previously fetched source.
  src = fetchzip {
    name = "${pname}-${version}-source";
    url = "https://registry.npmjs.org/pi-ollama-cloud/-/pi-ollama-cloud-${version}.tgz";
    hash = "sha256-jfJZ6D5rn9SXRVXe4+kzoEcW7voJXwBWqnGd8Ummao0=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "Ollama Cloud provider extension for pi coding agent";
    homepage = "https://github.com/fgrehm/pi-ollama-cloud";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
