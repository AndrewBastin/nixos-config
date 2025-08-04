# DWM Window Manager Universal Module
#
# Provides a minimal, customizable tiling window manager for X11 systems.
#
# What this module does:
# - Installs and configures DWM (Dynamic Window Manager)
# - Sets up X11 with configurable DPI settings
# - Configures LightDM display manager with optional auto-login
# - Provides customizable DWM configuration (colors, keybindings, layouts)
# - Installs supporting utilities (dmenu, st terminal, rofi launcher)
# - Applies dark GTK/Qt themes for consistent appearance
#
# Imports: None
#
# Platforms: NixOS, Home Manager
#
# Configuration options:
# - dwm.enable: Enable DWM window manager (default: true)
# - dwm.modKey: Modifier key - "mod1" (Alt) or "mod4" (Super/Windows) (default: "mod4")
# - dwm.fonts: List of fonts for DWM bar (default: ["monospace:size=12"])
# - dwm.terminal: Default terminal command (default: "st")
# - dwm.launcher: Application launcher command (default: "rofi -show drun")
# - dwm.autoLogin.enable: Enable automatic login (default: false)
# - dwm.autoLogin.user: User to auto-login (default: "")
# - dwm.dpi: X11 DPI setting for high-resolution displays (default: 96)
#
# Key features:
# - Minimal resource usage
# - Highly customizable through config.h
# - Multiple layout modes (tiling, floating, monocle)
# - Multi-monitor support via xrandr
# - Integrated with rofi for modern application launching
{
  options = { lib, ... }: {
    dwm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable DWM window manager";
      };
      
      modKey = lib.mkOption {
        type = lib.types.enum ["mod1" "mod4"];
        default = "mod4";
        description = "Modifier key - mod1 (Alt) or mod4 (Super/Windows)";
      };
      
      fonts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["monospace:size=12"];
        description = "List of fonts for DWM bar";
      };
      
      terminal = lib.mkOption {
        type = lib.types.str;
        default = "st";
        description = "Default terminal command";
      };
      
      launcher = lib.mkOption {
        type = lib.types.str;
        default = "rofi -show drun";
        description = "Application launcher command";
      };
      
      autoLogin = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable automatic login";
        };
        
        user = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "User to auto-login";
        };
      };
      
      dpi = lib.mkOption {
        type = lib.types.int;
        default = 96;
        description = "X11 DPI setting for high-resolution displays";
      };
    };
  };

  nixos = { pkgs, lib, universalConfig ? {}, ... }: 
    let
      cfg = universalConfig.dwm or {};
      modKey = if (cfg.modKey or "mod4") == "mod1" then "Mod1Mask" else "Mod4Mask";
      fonts = cfg.fonts or ["monospace:size=12"];
      terminal = cfg.terminal or "st";
      launcher = cfg.launcher or "rofi -show drun";
      dpi = cfg.dpi or 96;
      
      # Format fonts for C array
      fontsStr = lib.concatMapStringsSep ", " (f: ''"${f}"'') fonts;
    in
    lib.mkIf (cfg.enable or true) {
      # Enable X11 windowing system
      services.xserver.enable = true;
      
      # Configure keymap
      services.xserver.xkb = {
        layout = "us";
        variant = "";
      };
      
      # Set DPI for high resolution displays
      services.xserver.dpi = dpi;
      
      # Enable LightDM display manager
      services.xserver.displayManager.lightdm.enable = true;
      
      # Enable automatic login if configured
      services.displayManager.autoLogin = lib.mkIf (cfg.autoLogin.enable or false) {
        enable = true;
        user = cfg.autoLogin.user or "";
      };
      
      # Enable dwm window manager with custom configuration
      services.xserver.windowManager.dwm = {
        enable = true;
        package = pkgs.dwm.overrideAttrs (oldAttrs: {
          src = ./dwm-source;
          postPatch = ''
            cat > config.h << 'EOF'
/* See LICENSE file for copyright and license details. */

/* appearance */
static const unsigned int borderpx  = 1;        /* border pixel of windows */
static const unsigned int snap      = 32;       /* snap pixel */
static const int showbar            = 1;        /* 0 means no bar */
static const int topbar             = 0;        /* 0 means bottom bar */
static const char *fonts[]          = { ${fontsStr} };
static const char dmenufont[]       = "${builtins.head fonts}";
static const char col_gray1[]       = "#222222";
static const char col_gray2[]       = "#444444";
static const char col_gray3[]       = "#bbbbbb";
static const char col_gray4[]       = "#eeeeee";
static const char col_cyan[]        = "#005577";
static const char col_orange[]      = "#ff7700";
static const char col_red[]         = "#cc0000";
static const char *colors[][3]      = {
	/*               fg         bg         border   */
	[SchemeNorm] = { col_gray3, col_gray1, col_gray2 },
	[SchemeSel]  = { col_gray4, col_cyan,  col_cyan  },
	[SchemeStatus] = { col_gray3, col_gray1, "#000000" }, /* status bar */
	[SchemeTagsSel] = { col_gray4, col_cyan, col_cyan }, /* selected tag */
	[SchemeTagsNorm] = { col_gray3, col_gray1, col_gray2 }, /* unselected tag */
	[SchemeInfoSel] = { col_gray4, col_gray2, "#000000" }, /* selected window title */
	[SchemeInfoNorm] = { col_gray3, col_gray1, "#000000" }, /* unselected window title/layout */
};

/* tagging */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

static const Rule rules[] = {
	/* xprop(1):
	 *	WM_CLASS(STRING) = instance, class
	 *	WM_NAME(STRING) = title
	 */
	/* class      instance    title       tags mask     isfloating   monitor */
	{ "Gimp",     NULL,       NULL,       0,            1,           -1 },
	{ "Firefox",  NULL,       NULL,       1 << 8,       0,           -1 },
};

/* layout(s) */
static const float mfact     = 0.55; /* factor of master area size [0.05..0.95] */
static const int nmaster     = 1;    /* number of clients in master area */
static const int resizehints = 1;    /* 1 means respect size hints in tiled resizals */
static const int lockfullscreen = 1; /* 1 will force focus on the fullscreen window */

static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "[]=",      tile },    /* first entry is default */
	{ "><>",      NULL },    /* no layout function means floating behavior */
	{ "[M]",      monocle },
};

/* key definitions */
#define MODKEY ${modKey}
#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

/* helper for spawning shell commands in the pre dwm-5.0 fashion */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* commands */
static char dmenumon[2] = "0"; /* component of dmenucmd, manipulated in spawn() */
static const char *dmenucmd[] = { "dmenu_run", "-m", dmenumon, "-fn", dmenufont, "-nb", col_gray1, "-nf", col_gray3, "-sb", col_cyan, "-sf", col_gray4, NULL };
static const char *termcmd[]  = { "${terminal}", NULL };
static const char *ghosttycmd[] = { "ghostty", NULL };
static const char *roficmd[] = { "rofi", "-show", "drun", NULL };

static const Key keys[] = {
	/* modifier                     key        function        argument */
	{ MODKEY,                       XK_p,      spawn,          {.v = dmenucmd } },
	{ MODKEY|ShiftMask,             XK_Return, spawn,          {.v = termcmd } },
	{ MODKEY,                       XK_t,      spawn,          {.v = ghosttycmd } },
	{ MODKEY,                       XK_Return, spawn,          {.v = roficmd } },
	{ MODKEY,                       XK_b,      togglebar,      {0} },
	{ MODKEY,                       XK_j,      focusstack,     {.i = +1 } },
	{ MODKEY,                       XK_k,      focusstack,     {.i = -1 } },
	{ MODKEY,                       XK_i,      incnmaster,     {.i = +1 } },
	{ MODKEY,                       XK_d,      incnmaster,     {.i = -1 } },
	{ MODKEY,                       XK_h,      setmfact,       {.f = -0.05} },
	{ MODKEY,                       XK_l,      setmfact,       {.f = +0.05} },
	{ MODKEY|ShiftMask,             XK_Return, zoom,           {0} },
	{ MODKEY,                       XK_Tab,    view,           {0} },
	{ MODKEY|ShiftMask,             XK_c,      killclient,     {0} },
	{ MODKEY|ShiftMask,             XK_t,      setlayout,      {.v = &layouts[0]} },
	{ MODKEY,                       XK_f,      setlayout,      {.v = &layouts[1]} },
	{ MODKEY,                       XK_m,      setlayout,      {.v = &layouts[2]} },
	{ MODKEY,                       XK_space,  setlayout,      {0} },
	{ MODKEY|ShiftMask,             XK_space,  togglefloating, {0} },
	{ MODKEY,                       XK_0,      view,           {.ui = ~0 } },
	{ MODKEY|ShiftMask,             XK_0,      tag,            {.ui = ~0 } },
	{ MODKEY,                       XK_comma,  focusmon,       {.i = -1 } },
	{ MODKEY,                       XK_period, focusmon,       {.i = +1 } },
	{ MODKEY|ShiftMask,             XK_comma,  tagmon,         {.i = -1 } },
	{ MODKEY|ShiftMask,             XK_period, tagmon,         {.i = +1 } },
	TAGKEYS(                        XK_1,                      0)
	TAGKEYS(                        XK_2,                      1)
	TAGKEYS(                        XK_3,                      2)
	TAGKEYS(                        XK_4,                      3)
	TAGKEYS(                        XK_5,                      4)
	TAGKEYS(                        XK_6,                      5)
	TAGKEYS(                        XK_7,                      6)
	TAGKEYS(                        XK_8,                      7)
	TAGKEYS(                        XK_9,                      8)
	{ MODKEY|ShiftMask,             XK_q,      quit,           {0} },
};

/* button definitions */
/* click can be ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle, ClkClientWin, or ClkRootWin */
static const Button buttons[] = {
	/* click                event mask      button          function        argument */
	{ ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
	{ ClkLtSymbol,          0,              Button3,        setlayout,      {.v = &layouts[2]} },
	{ ClkWinTitle,          0,              Button2,        zoom,           {0} },
	{ ClkStatusText,        0,              Button2,        spawn,          {.v = termcmd } },
	{ ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
	{ ClkClientWin,         MODKEY,         Button2,        togglefloating, {0} },
	{ ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
	{ ClkTagBar,            0,              Button1,        view,           {0} },
	{ ClkTagBar,            0,              Button3,        toggleview,     {0} },
	{ ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
	{ ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
};
EOF
          '';
        });
      };
      
      # Environment variables for theming and DPI
      environment.variables = {
        QT_QPA_PLATFORMTHEME = "qt5ct";
        GTK_THEME = "Adwaita:dark";
        GTK_APPLICATION_PREFER_DARK_THEME = "1";
        GDK_SCALE = if dpi > 96 then "1.5" else "1";
        GDK_DPI_SCALE = "1";
        QT_SCALE_FACTOR = if dpi > 96 then "1.5" else "1";
      };
    };

  home = { pkgs, lib, universalConfig ? {}, ... }: 
    let
      cfg = universalConfig.dwm or {};
    in
    lib.mkIf (cfg.enable or true) {
      home.packages = with pkgs; [
        dmenu       # Application launcher for dwm
        st          # Simple terminal (default for dwm)
        rofi        # Application launcher
        xorg.xrandr # Multi-monitor support
        xclip       # Clipboard support for X11
        xdg-utils   # For opening files/URLs
        
        # Theme packages
        gnome-themes-extra        # Includes Adwaita themes
        papirus-icon-theme        # Popular icon theme
        adwaita-icon-theme       # Default GNOME icons
        
        # For Qt theming
        libsForQt5.qt5ct         # Qt5 configuration tool
        kdePackages.qt6ct        # Qt6 configuration tool
        libsForQt5.qtstyleplugin-kvantum  # Kvantum style plugin
        
        (writeShellScriptBin "xrandr-auto" ''
          xrandr --output Virtual-1 --auto
        '')
      ];
    };
}
