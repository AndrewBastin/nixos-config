-- jjui config for the ONE jjui Emacs spawns (`SPC G G' -> `jjui-emacs', the
-- wrapper in ../default.nix that points JJUI_CONFIG_DIR here).  A `jjui'
-- started any other way never reads this file and stays stock.
--
-- `d' opens the diff as an Emacs buffer (`my/jjui-diff', lisp/vc.el) instead of
-- in jjui's pager.  $EMACS_SOCKET_NAME is already exported by ghostel, so a
-- bare `emacsclient' reaches the Emacs that owns this terminal.

local function emacs_diff(file)
  local rev = context.change_id() or revisions.current()
  if not rev then
    flash({ text = "no revision selected", error = true })
    return
  end
  local root, err = jj("workspace", "root")
  if err then
    flash({ text = "jj workspace root: " .. err, error = true })
    return
  end
  -- ponytail: Lua's %q is elisp string syntax for everything but a newline
  -- inside a path (elisp drops it).  Escape by hand if that ever matters.
  local form = string.format("(my/jjui-diff %q %q%s)", (root:gsub("%s+$", "")), rev,
                             file and string.format(" %q", file) or "")
  -- `jj util exec', not exec_shell: no shell to quote for, and no handing the
  -- terminal over for a command that returns instantly.
  local _, eerr = jj("util", "exec", "--", "emacsclient", "-e", form)
  if eerr then
    flash({ text = "emacsclient: " .. eerr, error = true })
  end
end

function setup(config)
  config.action("emacs-diff", function() emacs_diff(nil) end,
                { key = "d", scope = "revisions", desc = "diff (emacs)" })
  config.action("emacs-diff-file", function() emacs_diff(context.file()) end,
                { key = "d", scope = "revisions.details", desc = "diff (emacs)" })
end
