{ fetchFromGitHub }:
let
  src = fetchFromGitHub {
    owner = "AndrewBastin";
    repo = "gh-scout";
    rev = "7bbfa2529514dc3641905e452d0ff68f513d4b39";
    hash = "sha256-XivUPqFqkeOXBj34sQHJcJqBkxACf/kVCx65MHw8zK0=";
  };
in
  "${src}/skills"
