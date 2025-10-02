# Machine-specific home configuration for winry
{
  home = { pkgs, pkgs-unstable, ... }: {
    home.packages = with pkgs; [
      nh
      nix-output-monitor
      aria2
      pkgs-unstable.cursor-cli
    ];
  };
}
