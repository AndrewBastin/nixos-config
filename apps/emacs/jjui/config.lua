-- jjui config for the ONE jjui Emacs spawns (`SPC G G' -> `jjui-emacs', the
-- wrapper in ../default.nix that points JJUI_CONFIG_DIR here).  A `jjui'
-- started any other way never reads this file and stays stock.
--
-- `d' opens the diff as an Emacs buffer instead of in jjui's pager; `enter' on a
-- file in the details pane opens that file as of the selected revision.  Both
-- land in lisp/vc.el (`my/jjui-diff', `my/jjui-find-file').  $EMACS_SOCKET_NAME is already exported by ghostel, so a
-- bare `emacsclient' reaches the Emacs that owns this terminal.

-- Call the elisp function FN as (FN ROOT REV [FILE]) in the owning Emacs.
local function emacs_call(fn, file)
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
  -- An elisp error comes back as the VALUE (a printed string, so it starts with
  -- a quote), not via emacsclient's exit status: jjui shows nothing at all for
  -- a command that fails with only stdout, which is what `*ERROR*: ...' is.
  local form = string.format("(condition-case e (%s %q %q%s) (error (error-message-string e)))",
                             fn, (root:gsub("%s+$", "")), rev,
                             file and string.format(" %q", file) or "")
  -- `jj util exec', not exec_shell: no shell to quote for, and no handing the
  -- terminal over for a command that returns instantly.
  local out, eerr = jj("util", "exec", "--", "emacsclient", "-e", form)
  if eerr then
    flash({ text = "emacsclient: " .. eerr, error = true })
  elseif out and out:sub(1, 1) == '"' then
    flash({ text = out:gsub("%s+$", ""):sub(2, -2), error = true })
  end
end

function setup(config)
  config.action("emacs-diff", function() emacs_call("my/jjui-diff", nil) end,
                { key = "d", scope = "revisions", desc = "diff (emacs)" })
  config.action("emacs-diff-file", function() emacs_call("my/jjui-diff", context.file()) end,
                { key = "d", scope = "revisions.details", desc = "diff (emacs)" })
  config.action("emacs-find-file", function() emacs_call("my/jjui-find-file", context.file()) end,
                { key = "enter", scope = "revisions.details", desc = "open at revision (emacs)" })
end
