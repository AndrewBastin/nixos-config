{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "docker-scout";

  version = "1.18.1";

  src = 
    let
      sources = {
        x86_64-linux = {
          url = "https://github.com/docker/scout-cli/releases/download/v${finalAttrs.version}/docker-scout_${finalAttrs.version}_linux_amd64.tar.gz";
          sha256 = "sha256-n37A8FTXsUOOe/O2qVpZBf537AaXwBpZxRTbM9T/HM4=";
        };

        # NOTE: Lazy to find hashes of the other ones :P
      };

      source = sources.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");
    in
      fetchurl source;

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  sourceRoot = ".";

  installPhase = /* sh  */ ''
    runHook preInstall
    
    install -D -m755 docker-scout $out/bin/docker-scout
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "Docker Scout CLI - Software supply chain security for developers and security teams";
    homepage = "https://github.com/docker/scout-cli";
    license = licenses.unfree;
    maintainers = [ ];

    # NOTE: Only supporting x86_64-linux for now (check `sources`)
    platforms = [ "x86_64-linux" ];
    mainProgram = "docker-scout";
  };
})
