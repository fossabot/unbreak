#!/usr/bin/env python3
"""ccfix — repair shell commands mangled by Claude Code's terminal hard-wrap.

Claude Code's TUI renderer inserts real newline characters at the terminal wrap
column (instead of letting the terminal soft-wrap). Copying a long command then
drags those newlines along, and pasting into a shell executes it prematurely.

This tool rejoins ONLY the lines that were broken at the wrap column, so
intentional structure (heredocs, trailing `\\` continuations, one-operator-per-
line layouts) is preserved. If wrap detection can't find a column, it falls back
to a conservative space-join of obviously-continued lines.

Usage:
    ccfix.py                  # read from clipboard (pbpaste), write to clipboard
    ccfix.py "broken cmd"     # clean the argument, print + copy
    pbpaste | ccfix.py -      # read stdin, write stdout (no clipboard touch)
    ccfix.py --join-all       # aggressive: collapse every wrap into one line

Flags:
    -                 read stdin / write stdout instead of clipboard
    --join-all        aggressive mode (freyjay-style full join)
    --width N         force the wrap column instead of auto-detecting
    --no-copy         print result but don't write to clipboard
"""

from __future__ import annotations

import sys
import time
import hashlib
import subprocess
from collections import Counter

# A line is only considered a wrap candidate if it's at least this long. Stops
# us from collapsing short, deliberately multi-line commands.
MIN_WRAP_WIDTH = 40

# Watch mode only acts when the frontmost app is one of these — i.e. you copied
# from a terminal where Claude Code runs, not from a browser or editor.
TERMINAL_BUNDLE_IDS = {
    "com.cmuxterm.app",        # cmux (this machine's terminal)
    "com.mitchellh.ghostty",   # Ghostty standalone
    "com.googlecode.iterm2",   # iTerm2
    "com.apple.Terminal",      # Apple Terminal
}

# Second gate for watch mode: only rewrite text that actually looks like a
# shell command, so wrapped prose copied from a pager doesn't get flattened.
SHELL_SIGNALS = ("/", "--", "&&", "||", " | ", "$(", ";", "=", "sudo ", "http")


def read_clipboard() -> str:
    return subprocess.run(["pbpaste"], capture_output=True, text=True).stdout


def write_clipboard(text: str) -> None:
    subprocess.run(["pbcopy"], input=text, text=True)


def detect_wrap_width(lines) -> int | None:
    """Find the column the terminal wrapped at.

    Hard-wrapped lines all hit the same length (the wrap column). We take the
    most common length among non-final lines, preferring the widest on ties.
    Returns None if nothing looks like a consistent wrap.
    """
    lengths = [len(l) for l in lines[:-1] if len(l) >= MIN_WRAP_WIDTH]
    if not lengths:
        return None
    counts = Counter(lengths)
    # Most frequent length wins; ties broken toward the wider column.
    width = max(counts, key=lambda k: (counts[k], k))
    # A single wrap produces exactly one line at `width`; still valid.
    return width


def is_explicit_continuation(line: str) -> bool:
    """A trailing backslash is an intentional, already-pasteable continuation."""
    return line.rstrip().endswith("\\")


def clean_wrap_aware(text: str, forced_width: int | None) -> str:
    # Normalize CRLF, drop a single trailing newline so it isn't seen as a line.
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    had_trailing_nl = text.endswith("\n")
    lines = text.split("\n")
    if had_trailing_nl:
        lines = lines[:-1]
    if len(lines) <= 1:
        return text

    width = forced_width if forced_width else detect_wrap_width(lines)
    if width is None:
        # Nothing detected — leave it; aggressive mode is opt-in.
        return text

    out = []
    buf = lines[0]
    for nxt in lines[1:]:
        # buf filled the terminal width and wasn't an explicit continuation →
        # the break is a wrap artifact; rejoin with no separator.
        if len(buf) >= width and not is_explicit_continuation(buf):
            buf += nxt
        else:
            out.append(buf)
            buf = nxt
    out.append(buf)
    result = "\n".join(out)
    return result + "\n" if had_trailing_nl else result


def clean_join_all(text: str) -> str:
    """Aggressive: collapse every newline (+ surrounding whitespace) to a single
    space, preserving spacing around shell operators. Mirrors the freyjay tool."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    parts = [p.strip() for p in text.split("\n")]
    parts = [p for p in parts if p]
    joined = " ".join(parts)
    # Tidy doubled spaces that the join may introduce around operators.
    while "  " in joined:
        joined = joined.replace("  ", " ")
    return joined


def frontmost_bundle_id() -> str | None:
    """Bundle id of the frontmost app, via lsappinfo (no special permission)."""
    front = subprocess.run(
        ["lsappinfo", "front"], capture_output=True, text=True
    ).stdout.strip()
    if not front:
        return None
    out = subprocess.run(
        ["lsappinfo", "info", "-only", "bundleid", front],
        capture_output=True,
        text=True,
    ).stdout
    # Format: "CFBundleIdentifier"="com.cmuxterm.app"
    if "=" in out:
        return out.split("=", 1)[1].strip().strip('"').strip()
    return None


def looks_like_shell(text: str) -> bool:
    return any(sig in text for sig in SHELL_SIGNALS)


def watch(interval: float, allow: set[str]) -> int:
    """Poll the clipboard; rewrite ONLY when both gates pass:
    (1) frontmost app is a known terminal, (2) text wrap-merged into a
    shell-looking command. Our own writes are recorded so we never loop."""
    sys.stderr.write(
        "ccfix --watch: scoped to %s (interval %.1fs). Ctrl-C to stop.\n"
        % (", ".join(sorted(allow)), interval)
    )
    last_hash = None
    while True:
        clip = read_clipboard()
        h = hashlib.sha1(clip.encode("utf-8", "replace")).hexdigest()
        if h != last_hash:
            last_hash = h
            bundle = frontmost_bundle_id()
            if bundle in allow:
                cleaned = clean_wrap_aware(clip, None)
                if cleaned != clip and looks_like_shell(cleaned):
                    write_clipboard(cleaned)
                    last_hash = hashlib.sha1(
                        cleaned.encode("utf-8", "replace")
                    ).hexdigest()
                    sys.stderr.write("ccfix --watch: fixed a wrapped command\n")
        time.sleep(interval)


def main() -> int:
    args = sys.argv[1:]
    use_stdio = "-" in args
    join_all = "--join-all" in args
    no_copy = "--no-copy" in args
    forced_width = None

    if "--watch" in args:
        interval = 0.4
        if "--interval" in args:
            j = args.index("--interval")
            try:
                interval = float(args[j + 1])
            except (IndexError, ValueError):
                print("ccfix: --interval needs a number", file=sys.stderr)
                return 2
        return watch(interval, TERMINAL_BUNDLE_IDS)

    if "--width" in args:
        i = args.index("--width")
        try:
            forced_width = int(args[i + 1])
            del args[i : i + 2]
        except (IndexError, ValueError):
            print("ccfix: --width needs an integer", file=sys.stderr)
            return 2

    positional = [a for a in args if not a.startswith("-")]

    if positional:
        source = positional[0]
    elif use_stdio:
        source = sys.stdin.read()
    else:
        source = read_clipboard()

    if not source.strip():
        print("ccfix: nothing to clean (empty input)", file=sys.stderr)
        return 1

    result = clean_join_all(source) if join_all else clean_wrap_aware(source, forced_width)

    if use_stdio:
        sys.stdout.write(result)
        if not result.endswith("\n"):
            sys.stdout.write("\n")
    else:
        if not no_copy:
            write_clipboard(result)
        sys.stderr.write("ccfix: cleaned %d line(s) → %d line(s)%s\n" % (
            source.count("\n") + 1,
            result.count("\n") + 1,
            "" if no_copy else " (copied to clipboard)",
        ))
        print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
