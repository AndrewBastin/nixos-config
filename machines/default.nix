{
  violet = {
    system = "x86_64-linux";

    nixos = {
      hardwareConfiguration = import ./violet/hardware-configuration.nix;

      additionalModules = [
        ./violet/extraConfiguration.nix
      ];
    };
  };

  uwu = {
    system = "aarch64-darwin";

    darwin = {
      modules = [
        ./uwu/configuration.nix
      ];
    };
  };

  winry = {
    system = "aarch64-darwin";

    darwin = {
      modules = [
        ./winry/configuration.nix
      ];
    };
  };
}
