# Things to think about when setting up Aerospace:
#  1. If you are seeing windows not being hidden correctly, check if the windows have a good corner to tuck stuff in, see: https://nikitabobko.github.io/AeroSpace/guide#proper-monitor-arrangement

{ lib, pkgs, ... }:

{
  # Install autoraise for focus-follows-mouse functionality
  home.packages = with pkgs; [ autoraise ];
  # Create helper scripts for hyprsplit-style workspace emulation
  home.file.".local/bin/aerospace-workspace.sh" = {
    text = lib.readFile ./scripts/aerospace-workspace.sh;
    executable = true;
  };

  home.file.".local/bin/aerospace-move-to-workspace.sh" = {
    text = lib.readFile ./scripts/aerospace-move-to-workspace.sh;
    executable = true;
  };

  home.file.".local/bin/aerospace-move-monitor.sh" = {
    text = lib.readFile ./scripts/aerospace-move-monitor.sh;
    executable = true;
  };

  home.file.".local/bin/aerospace-grab-rogue-windows.sh" = {
    text = lib.readFile ./scripts/aerospace-grab-rogue-windows.sh;
    executable = true;
  };

  # AutoRaise management script
  home.file.".local/bin/aerospace-autoraise.sh" = {
    text = /* bash */ ''
      #!/bin/bash
      PIDFILE="$HOME/.cache/aerospace-autoraise.pid"
      
      case "$1" in
        start)
          if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
            echo "AutoRaise already running"
            exit 0
          fi
          ${lib.getExe pkgs.autoraise} &
          echo $! > "$PIDFILE"
          echo "AutoRaise started with PID $(cat "$PIDFILE")"
          ;;
        stop)
          if [ -f "$PIDFILE" ]; then
            PID=$(cat "$PIDFILE")
            if kill -0 "$PID" 2>/dev/null; then
              kill "$PID"
              echo "AutoRaise stopped (PID $PID)"
            fi
            rm -f "$PIDFILE"
          else
            # Fallback: kill any autoraise process
            pkill -f autoraise || true
            echo "AutoRaise stopped (fallback)"
          fi
          ;;
        *)
          echo "Usage: $0 {start|stop}"
          exit 1
          ;;
      esac
    '';
    executable = true;
  };

  # AeroSpace window manager configuration
  programs.aerospace = {
    enable = true;
    userSettings = {
      # Start AeroSpace at login
      start-at-login = true;
      
      # Start autoraise after aerospace startup
      after-startup-command = [
        "exec-and-forget ~/.local/bin/aerospace-autoraise.sh start"
      ];
      
      # Mouse follows focus (closest we can get to focus-follows-mouse for now)
      on-focused-monitor-changed = ["move-mouse monitor-lazy-center"];
      on-focus-changed = ["move-mouse window-lazy-center"];
      
      # Disable built-in macOS spaces since we're using AeroSpace workspaces
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;
      
      # Basic layout configuration
      default-root-container-layout = "tiles";
      accordion-padding = 30;
      
      # Generic workspace-to-monitor assignments (supports up to 4 monitors)
      # Monitor positions are determined by sorted monitor IDs
      workspace-to-monitor-force-assignment = {
        # Monitor 1 (first in sorted order): workspaces 1-10
        "1" = 1; "2" = 1; "3" = 1; "4" = 1; "5" = 1;
        "6" = 1; "7" = 1; "8" = 1; "9" = 1; "10" = 1;
        
        # Monitor 2 (second in sorted order): workspaces 11-20  
        "11" = 2; "12" = 2; "13" = 2; "14" = 2; "15" = 2;
        "16" = 2; "17" = 2; "18" = 2; "19" = 2; "20" = 2;
        
        # Monitor 3 (third in sorted order): workspaces 21-30
        "21" = 3; "22" = 3; "23" = 3; "24" = 3; "25" = 3;
        "26" = 3; "27" = 3; "28" = 3; "29" = 3; "30" = 3;
        
        # Monitor 4 (fourth in sorted order): workspaces 31-40
        "31" = 4; "32" = 4; "33" = 4; "34" = 4; "35" = 4;
        "36" = 4; "37" = 4; "38" = 4; "39" = 4; "40" = 4;
      };
      
      # Key mappings - using Alt/Option as main modifier
      mode.main.binding = {
        # Window focus movement (Alt + arrow keys)
        "alt-left" = "focus left";
        "alt-down" = "focus down";
        "alt-up" = "focus up";
        "alt-right" = "focus right";
        
        # Window movement between monitors with fallback (Alt + Shift + left/right)
        "alt-shift-left" = "exec-and-forget ~/.local/bin/aerospace-move-monitor.sh left";
        "alt-shift-right" = "exec-and-forget ~/.local/bin/aerospace-move-monitor.sh right";
        
        # Window movement within monitor (Alt + Shift + up/down)  
        "alt-shift-down" = "move down";
        "alt-shift-up" = "move up";
        
        # Hyprsplit-style workspace switching (Alt + 1-9,0) with monitor offset
        "alt-1" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 1";
        "alt-2" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 2";
        "alt-3" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 3";
        "alt-4" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 4";
        "alt-5" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 5";
        "alt-6" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 6";
        "alt-7" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 7";
        "alt-8" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 8";
        "alt-9" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 9";
        "alt-0" = "exec-and-forget ~/.local/bin/aerospace-workspace.sh 0";
        
        # Move windows to workspaces with monitor offset (Alt + Shift + 1-9,0)
        "alt-shift-1" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 1";
        "alt-shift-2" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 2";
        "alt-shift-3" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 3";
        "alt-shift-4" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 4";
        "alt-shift-5" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 5";
        "alt-shift-6" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 6";
        "alt-shift-7" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 7";
        "alt-shift-8" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 8";
        "alt-shift-9" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 9";
        "alt-shift-0" = "exec-and-forget ~/.local/bin/aerospace-move-to-workspace.sh 0";
        
        # Window management
        "alt-space" = "fullscreen";
        "alt-shift-space" = "layout floating tiling"; # toggle floating
        
        # Grab rogue windows from disconnected monitors (similar to Hyprland's Super+Shift+G)
        "alt-shift-g" = "exec-and-forget ~/.local/bin/aerospace-grab-rogue-windows.sh";
        
        # Application launchers
        # TODO: Probably move this out to the main home.nix and be passed in here as an arg
        "alt-t" = "exec-and-forget open -a kitty -n"; # Terminal
        "alt-f" = "exec-and-forget open -a 'Zen Browser'";  # Browser
        "alt-e" = "exec-and-forget open -a Finder";   # File manager
      };
    };
  };
}
