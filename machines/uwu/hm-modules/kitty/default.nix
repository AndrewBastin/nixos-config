{
  fontSize ? null                                           # An overridable font size
}:

{
  pkgs,
  ...
}:

{
  programs.kitty = {
    enable = true;
    themeFile = "adwaita_darker";
    font = {
      package = pkgs.nerd-fonts.fira-code;
      name = "FiraCode Nerd Font Mono";
      size = fontSize;
    };
    settings = {
      cursor_trail = 1;
      macos_titlebar_color = "background";
      macos_quit_when_last_window_closed = "yes";
      macos_show_window_title_in = "window";
    };
    keybindings = {
      "ctrl+shift+t" = "launch --cwd=current --type=tab";
      "cmd+t" = "launch --cwd=current --type=tab";
    };
    shellIntegration = {
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
  };
}
