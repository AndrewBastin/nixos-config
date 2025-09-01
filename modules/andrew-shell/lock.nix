# NOTE: This is a home manager module
{...}:

{
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        no_fade_in = false;
        grace = 1;
        disable_loading_bar = false;
        hide_cursor = true;
        ignore_empty_input = true;
        text_trim = false;
      };

      background = {
          monitor = "";
          path = "screenshot";
          blur_passes = 2;
          contrast = 0.8916;
          brightness = 0.7172;
          vibrancy = 0.1696;
          vibrancy_darkness = 0;
      };

      # TIME HR
      label = [
        {
          monitor = "";
          text = ''cmd[update:1000] echo -e "$(date +"%I")"'';
          color = "rgba(255, 255, 255, 1)";
          shadow_pass = 2;
          shadow_size = 3;
          shadow_color = "rgb(0,0,0)";
          shadow_boost = 1.2;
          font_size = 150;
          font_family = "JetBrains Mono Nerd Font Mono Bold";
          position = "0, -250";
          halign = "center";
          valign = "top";
        }

        # TIME 
        {
          monitor = "";
          text = ''cmd[update:1000] echo -e "$(date +"%M")"'';
          color = "rgba(255, 255, 255, 1)";
          font_size = 150;
          font_family = "JetBrains Mono Nerd Font Mono Bold";
          position = "0, -420";
          halign = "center";
          valign = "top";
        }

        # DATE
        {
          monitor = "";
          text = ''cmd[update:1000] echo -e "$(date +"%e %B, %A %Y")"'';
          color = "rgba(255, 255, 255, 1)";
          font_size = 17;
          font_family = "JetBrains Mono Nerd Font Mono Bold";
          position = "0, -130";
          halign = "center";
          valign = "center";
        }

        # Uptime
        {
          monitor = "";
          text = ''cmd[update:5000] echo "Battery at $(cat /sys/class/power_supply/BAT0/capacity)% ($(cat /sys/class/power_supply/BAT0/status))"'';
          font_size = 14;
          font_family = "JetBrains Mono Nerd Font Mono";
          position = "0, -0.005";
          halign = "center";
          valign = "bottom";
        }
      ];

      # INPUT
      input-field = {
          monitor = "";
          outline_thickness = 0;
          outer_color = "rgba(0, 0, 0, 0)";
          dots_size = 0.1;
          dots_spacing = 1;
          dots_center = true;
          inner_color = "rgba(0, 0, 0, 0)";
          font_color = "rgba(200, 200, 200, 1)";
          fade_on_empty = false;
          font_family = "JetBrains Mono Nerd Font Mono";
          placeholder_text = "<span> $USER</span>";
          hide_input = false;
          position = "0, -470";
          halign = "center";
          valign = "center";
          zindex = 10;
      };
    };
  };
}

