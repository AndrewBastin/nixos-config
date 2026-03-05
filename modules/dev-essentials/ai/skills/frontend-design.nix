{ fetchFromGitHub }:
let
  src = fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-code";
    rev = "9582ad480f687bbeaf0025852ac4f020b07f20bb";
    hash = "sha256-LrQ8Gj46BFkKDr+KZ+DT/fnaS4uehXiX44D3N+/EqQg=";
  };
in
  "${src}/plugins/frontend-design/skills"
