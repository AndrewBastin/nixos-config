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
    };
    keybindings = {
      "ctrl+shift+t" = "launch --cwd=current --type=tab";
    };
    shellIntegration = {
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
  };
}
