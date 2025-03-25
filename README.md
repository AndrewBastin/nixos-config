# Andrew's NixOS configuration

This is the configuration I use to configure my NixOS environment. This configuration configures some essential programs I use and set up my desktop shell setup using Hyprland and Waybar.

> [!NOTE]
> This config will perpetually be in a state of being 'in-progress' and not complete, please only use this as a reference for your own config and do not use it outright, I give no guarantees this will work or be maintained in the future. See LICENSE for more info


### Setting this up in a new NixOS system

```sh
# Clone the repo to ~/nixos-config
git clone https://github.com/AndrewBastin/nixos-config ~/nixos-config

# Backup existing NixOS config
sudo mv /etc/nixos /etc/nixos-bk

# Link ~/nixos-config to /etc/nixos
sudo ln -s ~/nixos-config /etc/nixos

# Apply the changes
sudo nixos-rebuild switch
```

### Neovim
My Neovim config is setup using [Nixvim](https://github.com/nix-community/nixvim) and it is exported in the flake as `nvim`.
You can run my neovim configuration in your system by running:
```sh
nix run github:AndrewBastin/nixos-config#nvim
```
