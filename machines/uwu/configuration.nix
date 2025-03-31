# NOTE: This is a nix-darwin configuration module, as opposed to a nixos configuration module
{ flake, nvim, pkgs-unstable, ... }: 
{
  
  # uwu runs Determinate Nix, which manages stuff on nix-darwin's behalf
  nix.enable = false;

  environment.systemPackages = [
    nvim
    pkgs-unstable.claude-code
  ];

  environment.variables.EDITOR = "nvim";


  system.configurationRevision = flake.rev or flake.dirtyRev or null;
  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";
}
