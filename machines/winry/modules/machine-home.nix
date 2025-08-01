# Machine-specific home configuration for winry
{
  home = { pkgs, ... }: {
    home.packages = with pkgs; [
      nh
      nix-output-monitor
      aria2
    ];
  };
}