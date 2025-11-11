# We use Nixvim to configure the neovim instance.
# Inputs to this function:
#  - nixvim: This should generally be the nixvim-flake structure for the system you are targeting.
#    For example,
#    --
#    inputs.nixvim-flake.url = "github:nix-community/nixvim";
#    outputs = { nixvim-flake, ... }:
#       # ... Get stuff like nixpkgs, system, etc. import ./nvim.nix { 
#          nixvim = (import nixvim-flake).legacyPackages."${system}";
#       };
#    --
# NOTE: This is expected to be built with pkgs pointing to nixos-unstable nixpkgs

{
  nixvim,
  pkgs,
  noLSP ? false,
  noAmp ? false, # Whether to not add suppport for Amp CLI (https://ampcode.com)
  ...
}:
  nixvim.makeNixvim {

    extraPlugins = [
      pkgs.vimPlugins.claudecode-nvim
    ] ++ pkgs.lib.optionals (!noAmp) [
      pkgs.vimPlugins.amp-nvim
    ];

    extraConfigLua = /* lua */ ''
      require('claudecode').setup({})
    '' + pkgs.lib.optionalString (!noAmp) /* lua */ ''
      require('amp').setup({ auto_start = true, log_level = "info" })
    '';

    colorschemes.kanagawa = {
      enable = true;
      settings.theme = "dragon";
    };

    opts = {
      confirm = true;
      number = true;
      relativenumber = true;

      shiftwidth = 2;
      shiftround = true;
      tabstop = 2;
      splitright = true;
      expandtab = true;
      wrap = false;
    };

    dependencies.gcc.enable = true;

    plugins = {
      web-devicons.enable = true;

      lualine = {
        enable = true;
        settings = {
          sections.lualine_c = [
            {
              __unkeyed-1 = "filename";
              path = 1;
            }
          ];

          options = {
            section_separators = {
              left = "";
              right = "";
            };

            component_separators = {
              left = "";
              right = "";
            };
          };
        };
      };

      # https://github.com/folke/snacks.nvim
      snacks = {
        enable = true;
        settings = {
          bigfile = { # Disable syntax highlighting and LSP when file is too big for preventing perf issues
            enable = true;
            notify = true;
          };
        };
      };

      fzf-lua.enable = true;
      neo-tree.enable = true;
      noice.enable = true;
      gitsigns.enable = true;
      diffview.enable = true;
      which-key.enable = true;
      nvim-surround.enable = true;
      neoconf.enable = true;

      blink-cmp = {
        enable = true;

        settings = {
          sources = {
            default = [
              "lsp"
              "buffer"
              "path"
            ];
          };

          appearance.kind_icons = {
            Copilot = "";
            Class = "󱡠";
            Color = "󰏘";
            Constant = "󰏿";
            Constructor = "󰒓";
            Enum = "󰦨";
            EnumMember = "󰦨";
            Event = "󱐋";
            Field = "󰜢";
            File = "󰈔";
            Folder = "󰉋";
            Function = "󰊕";
            Interface = "󱡠";
            Keyword = "󰻾";
            Method = "󰊕";
            Module = "󰅩";
            Operator = "󰪚";
            Property = "󰖷";
            Reference = "󰬲";
            Snippet = "󱄽";
            Struct = "󱡠";
            Text = "󰉿";
            TypeParameter = "󰬛";
            Unit = "󰪚";
            Value = "󰦨";
            Variable = "󰆦";
          };
        };

      };

      gitblame = {
        enable = true;

        settings = {
          delay = 0;
          virtual_text_column = 70;
        };
      };


      dashboard = {
        enable = true;

        settings = {
          theme = "hyper";
          config = {
            header = [
              "  /$$$$$$                  /$$                                           /$$    /$$ /$$              "
              " /$$__  $$                | $$                                          | $$   | $$|__/              "
              ''| $$  \ $$ /$$$$$$$   /$$$$$$$  /$$$$$$   /$$$$$$  /$$  /$$  /$$        | $$   | $$ /$$ /$$$$$$/$$$$ ''
              ''| $$$$$$$$| $$__  $$ /$$__  $$ /$$__  $$ /$$__  $$| $$ | $$ | $$ /$$$$$$|  $$ / $$/| $$| $$_  $$_  $$''
              ''| $$__  $$| $$  \ $$| $$  | $$| $$  \__/| $$$$$$$$| $$ | $$ | $$|______/ \  $$ $$/ | $$| $$ \ $$ \ $$''
              ''| $$  | $$| $$  | $$| $$  | $$| $$      | $$_____/| $$ | $$ | $$          \  $$$/  | $$| $$ | $$ | $$''
              ''| $$  | $$| $$  | $$|  $$$$$$$| $$      |  $$$$$$$|  $$$$$/$$$$/           \  $/   | $$| $$ | $$ | $$''
              ''|__/  |__/|__/  |__/ \_______/|__/       \_______/ \_____/\___/             \_/    |__/|__/ |__/ |__/''
            ];

            shortcut = [
              { desc = "_"; }
            ];

            footer.__raw = "{}";

            packages.enable = false;
            project.enable = false;

            mru = {
              cwd_only = true;
            };
          };
        };
      };

      mini = {
        enable = true;

        modules = {
          hipatterns = {
            # Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
            fixme = {
              pattern = "%f[%w]()FIXME()%f[%W]";
              group = "MiniHipatternsFixme";
            };
            hack = {
              pattern = "%f[%w]()HACK()%f[%W]";
              group = "MiniHipatternsHack";
            };
            todo = {
              pattern = "%f[%w]()TODO()%f[%W]";
              group = "MiniHipatternsTodo";
            };
            note = {
              pattern = "%f[%w]()NOTE()%f[%W]";
              group = "MiniHipatternsNote";
            };

            # Highlight hex color strings (`#rrggbb`) using that color
            hex_color.__raw = "require('mini.hipatterns').gen_highlighter.hex_color()";
          };

          indentscope = {};

          cursorword = {};

          animate = {
            cursor.enable = false;
          };

          comment = {
            mappings = {
              comment = "<leader>c";
              comment_line = "<leader>cc";
              comment_visual = "<leader>c";
              textobject = "<leader>c";
            };
          };

          bracketed = {
            # NOTE: ]<Uppercased Suffix> and [<Uppercased Suffix> moves to the first and the last jumps for each category

            # ]c and [c to jump to next and previous comments
            comment    = { suffix = "c"; options = {}; };
            # ]mc and [mc to jump to next and previous merge conflict markers
            conflict   = { suffix = "mc"; options = {}; };
            # ]d and [d to jump to next and previous lines with diagnostics
            diagnostic = { suffix = "d"; options = {}; };
            # ]i and [i to jump to next and previous lines with indent changes
            indent     = { suffix = "i"; options = {}; };
            # ]q and [q to jump to next and previous entries in the quickfix list
            quickfix   = { suffix = "q"; options = {}; };
            # ]t and [t to jump to next and previous nodes in treesitter
            treesitter = { suffix = "t"; options = {}; };
          };

          jump = {
            mappings = {
              forward = "f";
              backward = "F";
              forward_till = "t";
              backward_till = "T";
              repeat_jump = ";";
            };
          };
        };
      };


      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          auto_install = true;
        };
      };

      lsp = if noLSP then { enable = false; } else {
        enable = true;
        servers = {
          rust_analyzer = {
            enable = true;

            # Better let rust-analyzer use the project (or global) given Rustc and Cargo
            installCargo = false;
            installRustc = false;
          };
          ts_ls.enable = true;
          nixd.enable = true;
          gopls.enable = true;
          elixirls.enable = true;
          jsonls.enable = true;
          pyright.enable = true;
          dockerls.enable = true;
          docker_compose_language_service.enable = true;
          bashls.enable = true;
          qmlls.enable = true;
          zls.enable = true;
        };

        keymaps = {
          lspBuf = {
            "K" = "hover";
            "gd" = "definition";
            "gD" = "references";
            "gi" = "implementation";
            "gt" = "type_definition";
            "<c-k>" = "signature_help";
            "<leader>cr" = "rename";
          };
          diagnostic = {
            "<leader>xd" = "open_float";
            "<leader>xn" = "goto_next";
            "<leader>xp" = "goto_prev";
          };
        };
      };
    };

    globals.mapleader = " ";

    keymaps =
      let
        # A helper function to neatly define keymaps with less verbosity
        silentNMap =
          key: description: action:
          { 
            mode = "n";
            key = key;
            options.silent = true;
            options.desc = description;
            action = action;
          };
      in
        [
          (silentNMap "<leader>e"         "Toggle File Viewer"                  "<cmd>Neotree toggle<CR>")
          (silentNMap "<leader>f"         "Fuzzy Find Files"                    "<cmd>lua require('fzf-lua').files()<CR>")
          (silentNMap "<leader><leader>"  "Fuzzy Find Git Files"                "<cmd>lua require('fzf-lua').git_files()<CR>")
          (silentNMap "<leader>d"         "Fuzzy Find (Document Diagnostics)"   "<cmd>lua require('fzf-lua').diagnostics_document()<CR>")
          (silentNMap "<leader>s"         "Fuzzy Find (Document Symbols)"       "<cmd>lua require('fzf-lua').lsp_document_symbols()<CR>")
          (silentNMap "<leader>S"         "Fuzzy Find (Workspace Symbols)"      "<cmd>lua require('fzf-lua').lsp_workspace_symbols()<CR>")
          (silentNMap "<leader>gl"        "Fuzzy Find (Lines)"                  "<cmd>lua require('fzf-lua').lines()<CR>")
          (silentNMap "<leader>bb"        "Fuzzy Find (Buffers)"                "<cmd>lua require('fzf-lua').buffers()<CR>")
          (silentNMap "<leader>gp"        "Fuzzy Find (Project Grep)"           "<cmd>lua require('fzf-lua').live_grep()<CR>")
          (silentNMap "<leader>ca"        "LSP Code Actions"                    "<cmd>lua require('fzf-lua').lsp_code_actions()<CR>")
          (silentNMap "<leader>cf"        "Change filetype"                     "<cmd>lua require('fzf-lua').filetypes()<CR>")
          (silentNMap "<leader>Gc"        "Git commits of this file"            "<cmd>lua require('fzf-lua').git_bcommits()<CR>")
          (silentNMap "<leader>GG"        "Git status"                          "<cmd>lua require('fzf-lua').git_status()<CR>")
          (silentNMap "<leader>Gdo"       "Open Diff view"                      "<cmd>DiffviewOpen<CR>")
          (silentNMap "<leader>Gdc"       "Close Diff view"                     "<cmd>DiffviewClose<CR>")
          (silentNMap "<leader>a"         "Toggle AI Chat"                      "<cmd>CodeCompanionChat Toggle<CR>")
        ];
  }

