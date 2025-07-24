{...}:

{
  homebrew = {
    enable = true;

    onActivation.cleanup = "zap";

    taps = [];

    brews = [];

    masApps = {
      "Things 3" = 904280696;
      "Wireguard" = 1451685025;
    };

    casks = [
      "anytype"
      "claude"
      "grandperspective"
      "handbrake"
      "iina"
      "coconutbattery"
      "beekeeper-studio"
      "google-chrome"
      "firefox"
      "obsidian"
      "orbstack"
      "slack"
      "vlc"
      "whatsapp"
      "zen"
      "granola"
      "notion"
      "aldente"
      "cloudflare-warp"
    ];
  };
}
