{
  home = { pkgs, pkgs-unstable, ... }: {
    home.packages = with pkgs; [
      nh
      dino
      firefox
      pkgs-unstable.slack
      pkgs-unstable.cider-2
    ];
  };
}
