# NOTE: This is a nix-darwin configuration module, as opposed to a nixos configuration module
{ flake, nvim, ... }: 
{
  nix.settings.experimental-features = "nix-command flakes";

  environment.systemPackages = [
    nvim
  ];



  system.configurationRevision = flake.rev or flake.dirtyRev or null;
  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";
}
