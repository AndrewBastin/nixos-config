{
  violet = {
    system = "x86_64-linux";

    hardwareConfiguration = import ./violet/hardware-configuration.nix;

    additionalModules = [
      ./violet/extraConfiguration.nix
    ];
  };
}
