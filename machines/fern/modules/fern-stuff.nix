{
  home = { pkgs, pkgs-unstable, ... }: {
    home.packages = with pkgs; [
      dino
      firefox
      pkgs-unstable.slack
      pkgs-unstable.cider-2
    ];
  };
}
