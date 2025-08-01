# Machine-specific home configuration for uwu
{
  home = { pkgs, pkgs-unstable, ... }: {
    home.packages = with pkgs; [
      nh
      nix-output-monitor
      pkgs-unstable.numi
    ];
  };
}