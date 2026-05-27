#!/usr/bin/env python3
"""Kitty kitten: open a clicked file reference in nvim.

Works anywhere in the terminal, two ways:
- ctrl+click (mouse_map): detect a file reference under the click. Recognizes
  `path:line[:col]`, compiler `path(line[,col])`, and Python-traceback
  `"path", line N` formats, plus quoted, space-containing, and bare paths. The
  path is confirmed against the filesystem (longest existing match wins), so
  plain text works without any hyperlink and junk tokens are ignored.
- file:// hyperlink click (open-actions.conf): the URI carries only the path
  (many tools put the line number only in the visible text, not the URI), so we
  read the clicked screen line to recover the line/col.

Either way we then route to an existing nvim (same kitty OS window, cwd an
ancestor of the file) or open a new kitty tab running nvim inside an interactive
shell.
"""
import glob
import os
import re
import shlex
import socket
import subprocess

try:
    from kittens.tui.handler import result_handler
except ImportError:  # allow importing the pure helpers without kitty (tests)
    def result_handler(*a, **k):
        def deco(fn):
            return fn
        return deco


# Position-suffix patterns shared by mouse_map detection and OSC 8 parsing.
# Each captures group(1)=line and, where applicable, group(2)=col.
_SUFFIXES = (
    re.compile(r":(\d+)(?::(\d+))?"),       # path:L  or  path:L:C   (grep, rustc, ...)
    re.compile(r"\((\d+)(?:,(\d+))?\)"),    # path(L) or path(L,C)   (MSVC / .NET)
    re.compile(r",\s*line\s+(\d+)"),        # ..., line L            (Python traceback)
)

# How many whitespace-separated words to grow across when probing for a path.
_MAX_GROW = 8


def _words(line_text):
    """Return (start, end) spans of each maximal non-whitespace run in line_text."""
    return [(mt.start(), mt.end()) for mt in re.finditer(r"\S+", line_text)]


def _strip_wrappers(s):
    """Strip wrapping quotes/brackets and trailing punctuation from a path token.

    Leading '.' is preserved (relative paths like ./foo). Handles both matched
    wrappers ("foo", (foo)) and stray unmatched ones (file.py")."""
    s = s.strip()
    s = s.strip("\"'`")
    s = s.lstrip("([{<")
    s = s.rstrip(")]}>.,;:")
    return s


def parse_position(line_text, file_path):
    """Return (line, col) from the `<basename>:<line>[:<col>]` token in line_text.

    Used in OSC 8 mode, where kitty already gave us the path and we only need the
    position. line defaults to 1 when absent; col is None when absent. Both are
    clamped to a minimum of 1 when present (references never emit :0, but be
    defensive).
    """
    base = re.escape(os.path.basename(file_path))
    # Allow an optional closing quote between the basename and the suffix
    # (Python tracebacks render `"app.py", line 7`).
    patterns = (
        base + r"['\"]?" + r":(\d+)(?::(\d+))?",
        base + r"['\"]?" + r"\((\d+)(?:,(\d+))?\)",
        base + r"['\"]?" + r",\s*line\s+(\d+)",
    )
    for pat in patterns:
        mt = re.search(pat, line_text)
        if not mt:
            continue
        line = max(1, int(mt.group(1)))
        try:
            col = max(1, int(mt.group(2))) if mt.group(2) else None
        except IndexError:  # line-keyword pattern has no col group
            col = None
        return line, col
    return 1, None


def detect_reference(line_text, click_col, cwd):
    """Detect a clicked file reference in line_text (mouse_map mode).

    Tries suffix-anchored formats first (`:L:C`, `(L,C)`, `, line L`), splitting
    the position off the path and confirming the path against the filesystem;
    then falls back to a bare existing path under the click. Returns
    (abs_path, line, col) with the path resolved+existing and col None when
    absent, or None when nothing under the click resolves to a real file."""
    best = None  # (path_len, abs_path, line, col)
    for pat in _SUFFIXES:
        for mt in pat.finditer(line_text):
            line = max(1, int(mt.group(1)))
            try:
                col = max(1, int(mt.group(2))) if mt.group(2) else None
            except IndexError:  # line-keyword pattern has no col group
                col = None
            path_end = mt.start()
            res = _probe_left(line_text, path_end, cwd)
            if res is None:
                continue
            path_start, abs_path = res
            if path_start <= click_col < mt.end():
                plen = path_end - path_start
                if best is None or plen > best[0]:
                    best = (plen, abs_path, line, col)
    if best is not None:
        return best[1], best[2], best[3]

    bare = _probe_both(line_text, click_col, cwd)
    if bare is not None:
        return bare, 1, None
    return None


def resolve_path(raw_path, cwd):
    """Resolve raw_path to an absolute, normalized path. A relative path is joined
    against cwd (the clicked window's working directory)."""
    p = os.path.expanduser(raw_path)
    if os.path.isabs(p):
        return os.path.normpath(p)
    return os.path.normpath(os.path.join(cwd or "", p))


def _resolve_existing(line_text, start, end, cwd):
    """Strip wrappers off line_text[start:end], resolve against cwd, and return
    the absolute path if it exists on disk, else None."""
    raw = _strip_wrappers(line_text[start:end])
    if not raw:
        return None
    p = resolve_path(raw, cwd)
    return p if os.path.exists(p) else None


def _probe_left(line_text, path_end, cwd):
    """Find the longest existing path whose text ends at path_end, growing the
    left edge across whitespace word boundaries. Returns (start, abs_path) or
    None. Used in the suffix-anchored case, where path_end is just before a
    position suffix."""
    starts = sorted({s for (s, _e) in _words(line_text) if s < path_end},
                    reverse=True)[:_MAX_GROW]
    best = None  # (start, abs_path); smaller start == longer path
    for s in starts:
        p = _resolve_existing(line_text, s, path_end, cwd)
        if p is not None and (best is None or s < best[0]):
            best = (s, p)
    return best


def _probe_both(line_text, click_col, cwd):
    """Find the longest existing path spanning the clicked word, growing both
    edges across whitespace word boundaries. Returns abs_path or None. Used for
    bare paths (no position suffix)."""
    words = _words(line_text)
    idx = next((i for i, (s, e) in enumerate(words) if s <= click_col < e), None)
    if idx is None:
        return None
    starts = [words[i][0] for i in range(max(0, idx - _MAX_GROW), idx + 1)]
    ends = [words[j][1] for j in range(idx, min(len(words), idx + _MAX_GROW + 1))]
    best = None  # (length, abs_path)
    for s in starts:
        for e in ends:
            if s <= click_col < e:
                p = _resolve_existing(line_text, s, e, cwd)
                if p is not None and (best is None or (e - s) > best[0]):
                    best = (e - s, p)
    return best[1] if best else None


def is_ancestor_or_equal(candidate_dir, file_dir):
    """True if candidate_dir == file_dir or is an ancestor directory of it."""
    candidate = os.path.normpath(candidate_dir)
    target = os.path.normpath(file_dir)
    if candidate == target:
        return True
    return target.startswith(candidate + os.sep)


def pick_closest(candidates, file_dir):
    """candidates: list of (cwd, pid). Return the pid whose cwd is the closest
    ancestor-or-equal of file_dir (longest matching path), or None."""
    best_pid = None
    best_len = -1
    for cwd, pid in candidates:
        if is_ancestor_or_equal(cwd, file_dir):
            n = len(os.path.normpath(cwd))
            if n > best_len:
                best_len = n
                best_pid = pid
    return best_pid


def _msgpack(obj):
    """Minimal msgpack encoder for the value types we send to nvim's RPC socket
    (ints, str, list). Avoids a heavyweight `nvim --server` client spawn."""
    if isinstance(obj, bool):  # before int, since bool is an int subclass
        return b"\xc3" if obj else b"\xc2"
    if isinstance(obj, int):
        if 0 <= obj < 0x80:
            return bytes([obj])
        if -0x20 <= obj < 0:
            return bytes([obj & 0xff])
        if 0 <= obj <= 0xFFFFFFFF:
            return b"\xce" + obj.to_bytes(4, "big")
        return b"\xd2" + (obj & 0xFFFFFFFF).to_bytes(4, "big")
    if isinstance(obj, str):
        b = obj.encode("utf-8")
        n = len(b)
        if n < 0x20:
            return bytes([0xA0 | n]) + b
        if n < 0x100:
            return b"\xd9" + bytes([n]) + b
        if n < 0x10000:
            return b"\xda" + n.to_bytes(2, "big") + b
        return b"\xdb" + n.to_bytes(4, "big") + b
    if isinstance(obj, (list, tuple)):
        n = len(obj)
        if n < 0x10:
            head = bytes([0x90 | n])
        elif n < 0x10000:
            head = b"\xdc" + n.to_bytes(2, "big")
        else:
            head = b"\xdd" + n.to_bytes(4, "big")
        return head + b"".join(_msgpack(x) for x in obj)
    raise TypeError("unsupported msgpack type: %r" % (obj,))


# Opens path in the current window and moves the cursor. The path comes in as an
# RPC argument (a[1]), so no escaping is needed at the transport level; fnameescape
# handles the Ex command. `hide` keeps a modified current buffer instead of erroring.
_NVIM_OPEN_LUA = (
    "local a = {...} "
    "vim.cmd('hide edit ' .. vim.fn.fnameescape(a[1])) "
    "vim.fn.cursor(a[2], a[3])"
)


def _nvim_open_via_socket(sock_path, path, line, col):
    """Open path at line/col in a running nvim by sending one msgpack-RPC request
    directly to its socket — no `nvim` subprocess, so it's fast (~1ms). Sent as a
    request (not a notification) and we wait for the reply, otherwise nvim can tear
    the channel down before processing it."""
    msg = _msgpack([0, 0, "nvim_exec_lua", [_NVIM_OPEN_LUA, [path, line, col or 1]]])
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(2)  # a live local nvim replies in ~ms; bound any freeze
        s.connect(sock_path)
        s.sendall(msg)
        s.recv(256)  # wait for the response so the request is actually processed
    finally:
        s.close()


def remote_open_expr(path, line, col):
    """Build the `nvim --remote-expr` that opens `path` in the *current* window and
    moves the cursor to line/col, as one atomic server-side `execute([...])` (so the
    edit and the cursor move can't race). `hide` keeps a modified current buffer
    instead of erroring; `fnameescape` plus a VimL string literal (single quotes
    doubled) make arbitrary paths safe."""
    vim_path = "'" + path.replace("'", "''") + "'"
    return "execute(['hide edit '.fnameescape(%s), 'call cursor(%d, %d)'])" % (
        vim_path, line, col or 1)


def _socket_pid(sock_path):
    """Extract the pid embedded in an nvim socket name (`nvim.<pid>.0`)."""
    parts = os.path.basename(sock_path).split(".")
    try:
        return int(parts[1])
    except (IndexError, ValueError):
        return None


def _ppid_of(pid):
    """Parent pid of `pid` from /proc, or None. (comm may contain spaces/parens,
    so parse after the final ')'.)"""
    try:
        with open("/proc/%d/stat" % pid) as f:
            return int(f.read().rsplit(")", 1)[1].split()[1])
    except Exception:
        return None


def nvim_socket_for_pid(pid, runtime_dir):
    """Return an nvim auto-listen socket (`${XDG_RUNTIME_DIR}/nvim.<pid>.0`) for
    the nvim whose kitty-visible foreground pid is `pid`, or None.

    nvim forks a child that actually binds the socket (named after the *child*
    pid), while kitty reports the parent as the window's foreground process. So
    accept a socket whose pid equals `pid` (no-fork case) or whose parent is `pid`.
    """
    if not runtime_dir:
        return None
    socks = sorted(glob.glob(os.path.join(runtime_dir, "nvim.*.0")))
    for s in socks:  # exact match first (no-fork / older nvim)
        if _socket_pid(s) == pid:
            return s
    for s in socks:  # else a child of the foreground process (forked server)
        spid = _socket_pid(s)
        if spid is not None and _ppid_of(spid) == pid:
            return s
    return None


def _is_nvim(cmdline):
    return bool(cmdline) and os.path.basename(cmdline[0]) in ("nvim", "nvim.bin")


def _find_reusable_nvim(src_window, file_dir, boss):
    """Return (window, pid) of a reusable nvim in src's OS window, or (None, None)."""
    candidates = []   # (cwd, pid)
    by_pid = {}       # pid -> window
    for w in boss.window_id_map.values():
        if w.os_window_id != src_window.os_window_id:
            continue
        try:
            procs = w.child.foreground_processes
        except Exception:
            continue
        for proc in procs:
            if _is_nvim(proc.get("cmdline")) and proc.get("cwd"):
                candidates.append((proc["cwd"], proc["pid"]))
                by_pid[proc["pid"]] = w
    pid = pick_closest(candidates, file_dir)
    if pid is None:
        return None, None
    return by_pid[pid], pid


def _open_in_existing(pid, line, col, path, window, boss):
    sock = nvim_socket_for_pid(pid, os.environ.get("XDG_RUNTIME_DIR"))
    if not sock:
        return False
    # Open in the existing nvim's current window (no new tab) and move the cursor
    # via a direct msgpack-RPC socket write — fast enough (~ms) to run inline on
    # kitty's main thread, so no background thread is needed (threads doing I/O in
    # kitty's process can destabilize it). Fall back to the `nvim --server` client
    # only if the socket call fails.
    try:
        _nvim_open_via_socket(sock, path, line, col)
    except Exception:
        try:
            subprocess.run(
                ["nvim", "--server", sock, "--remote-expr",
                 remote_open_expr(path, line, col)],
                timeout=5, check=False)
        except Exception:
            return False
    boss.set_active_window(window, switch_os_window_if_needed=True)
    return True


def _open_new_window(line, col, path, file_dir, boss):
    # Open in a new kitty TAB, running nvim inside an interactive shell so quitting
    # nvim drops back to a usable shell prompt instead of closing the tab.
    shell = os.environ.get("SHELL") or "/bin/sh"
    nvim_cmd = "nvim %s -- %s" % (
        shlex.quote("+call cursor(%d, %d)" % (line, col or 1)), shlex.quote(path))
    inner = "%s; exec %s" % (nvim_cmd, shlex.quote(shell))
    boss.launch("--type=tab", "--cwd=%s" % file_dir, shell, "-c", inner)


def _route(src, path, line, col, boss):
    """Open `path` at line/col, reusing a matching nvim or opening a new window."""
    file_dir = os.path.dirname(path)
    window, pid = _find_reusable_nvim(src, file_dir, boss)
    if window is not None and _open_in_existing(pid, line, col, path, window, boss):
        return
    _open_new_window(line, col, path, file_dir, boss)


def main(args):
    # All work happens in handle_result (no_ui=True); main is required but unused.
    pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    src = boss.window_id_map.get(target_window_id)
    if src is None:
        return

    # OSC 8 mode: triggered from open-actions.conf, which passes the absolute file
    # path. Recover line/col from the clicked screen row.
    if len(args) >= 2:
        path = args[1]
        line, col = 1, None
        mp = src.current_mouse_position()
        if mp is not None:
            line_text = str(src.screen.visual_line(mp["cell_y"]) or "")
            line, col = parse_position(line_text, path)
        _route(src, path, line, col, boss)
        return

    # mouse_map mode: triggered from a ctrl+click. Parse the reference out of the
    # clicked text ourselves, so this works even without an OSC 8 hyperlink.
    mp = src.current_mouse_position()
    ref = None
    if mp is not None:
        line_text = str(src.screen.visual_line(mp["cell_y"]) or "")
        cwd = src.child.current_cwd or src.child.cwd or ""
        ref = detect_reference(line_text, mp["cell_x"], cwd)
    if ref is None:
        # Not a file reference: fall back to opening a hyperlink under the mouse,
        # if any (kitty's default click-on-link behaviour).
        src.mouse_handle_click("link")
        return
    path, line, col = ref  # path is already absolute and confirmed to exist
    _route(src, path, line, col, boss)
