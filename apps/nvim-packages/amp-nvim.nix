# A temporary derivation for amp.nvim until it lands in nixpkgs

{ vimUtils, fetchFromGitHub }:

vimUtils.buildVimPlugin {
  pname = "amp-nvim";
  version = "2025-10-01";
  src = fetchFromGitHub {
    owner = "sourcegraph";
    repo = "amp.nvim";
    rev = "ceeed031e70966492a01a33774b48652ba3f1043";
    sha256 = "sha256-ZfMdGt6G8vG0BAIdsxhaH/x0dd0Zwopw9Ob5qZZFzdg=";
  };
  meta.homepage = "https://github.com/sourcegraph/amp.nvim";
  meta.hydraPlatforms = [];
}


