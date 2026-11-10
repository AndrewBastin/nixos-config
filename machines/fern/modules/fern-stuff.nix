{
  home = { pkgs, pkgs-unstable, ... }: {
    home.packages = with pkgs; [
      nh
      firefox
      pkgs-unstable.thunderbird
      pkgs-unstable.slack
      # Chromium-drawn frames (titleBarStyle "hidden") reserve a shadow inset, Hyprland
      # forces server-side decorations, and the inset gets baked into the popup's min/max
      # size: the miniplayer ends up 20px too big with black strips. Native frame instead.
      (pkgs-unstable.cider-2.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.asar ];
        postInstall = (old.postInstall or "") + ''
          asar extract $out/lib/cider/resources/app.asar ./cider-build
          substituteInPlace ./cider-build/.vite/build/events-*.js \
            --replace-fail 'titleBarStyle:i.get("inlinetitlebar")==="1"||u?"hidden":"default"' \
                           'titleBarStyle:process.platform==="darwin"&&(i.get("inlinetitlebar")==="1"||u)?"hidden":"default"'
          asar pack ./cider-build $out/lib/cider/resources/app.asar
          rm -rf ./cider-build
        '';
      }))
      pkgs-unstable.obsidian
      pkgs-unstable.vlc
      pkgs-unstable.signal-desktop
      (pkgs.callPackage ../../../packages/paradev/package.nix {})
    ];
  };

  nixos = { pkgs, ... }: {
    virtualisation.docker.enable = true;

    # Expose the NVIDIA GPU to Docker containers via CDI (for CUDA workloads).
    hardware.nvidia-container-toolkit.enable = true;

    # Save VRAM across suspend (nvidia-suspend/resume); without it GPU apps (Hex's model)
    # wake up with their memory gone. nixos-hardware's p14s module doesn't set it (#348).
    hardware.nvidia.powerManagement.enable = true;

    users.users.andrew.extraGroups = [ "docker" "libvirtd" "dialout" ];

    virtualisation.libvirtd.enable = true;
    programs.virt-manager.enable = true;
    
    programs.steam.enable = true;

    # Allow OpenVPN Plugins
    networking.networkmanager.plugins = with pkgs; [
      networkmanager-openvpn
    ];
  };
}
