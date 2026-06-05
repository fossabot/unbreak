# ccfix

Repair shell commands that Claude Code mangles on copy-paste.

## The problem

Claude Code's terminal UI inserts **real newline characters** at the terminal
wrap column instead of letting the terminal soft-wrap. When you select and copy
a long command from Claude's output, those newlines come with it — and pasting
into a shell runs the command prematurely (each `\n` acts as Enter).

This is a known, architectural Claude Code bug, tracked in several issues that
are all closed/duplicated without a fix
([#26016](https://github.com/anthropics/claude-code/issues/26016),
[#22073](https://github.com/anthropics/claude-code/issues/22073),
[#43731](https://github.com/anthropics/claude-code/issues/43731),
[#24224](https://github.com/anthropics/claude-code/issues/24224) — a request for
an `outputWrapping: "soft"` setting that doesn't exist yet). There is **no
built-in setting, hook, output style, or skill** that fixes it — the `MessageDisplay`
hook only rewrites the on-screen render, never the clipboard. So a post-processor
is currently the only option.

`ccfix` is that post-processor. It's inspired by
[freyjay/claude-code-command-fix](https://github.com/freyjay/claude-code-command-fix)
but uses a smarter heuristic (below) and adds a hands-free clipboard watcher.

## How it's smarter than a blind join

The freyjay tool collapses *every* newline into a space. That repairs wrapped
commands but also flattens genuinely multi-line commands.

`ccfix` instead **detects the terminal wrap column** — hard-wrapped lines all hit
the same length — and rejoins *only* lines broken at that column, with no
inserted separator (the wrap split mid-content, so the original characters were
contiguous). Everything shorter than the wrap column is left alone, so these
survive untouched:

- trailing `\` line continuations
- heredocs and one-operator-per-line layouts (`&&` / `|` at line ends)
- short deliberately multi-line snippets

A `--join-all` fallback reproduces the blind-join behavior for the rare case
where wrap detection misses.

## Requirements

- macOS (uses `pbcopy` / `pbpaste` and `lsappinfo`)
- `/usr/bin/python3` (system Python 3.9+ is fine — no third-party packages)

## Usage

### One-shot (manual)

```fish
ccfix                    # clean the clipboard in place (pbpaste -> fix -> pbcopy)
ccfix "broken command"   # clean an argument
pbpaste | ccfix.py -     # stdin -> stdout, never touches the clipboard
ccfix --join-all         # aggressive full-collapse fallback
ccfix --width 80         # force the wrap column instead of auto-detecting
ccfix --no-copy          # print the result but don't write the clipboard
```

The `ccfix` shell function lives at `~/.config/fish/functions/ccfix.fish` and
just forwards to `ccfix.py`.

### Hands-free (watch mode)

```fish
ccfix --watch            # poll the clipboard and auto-fix; Ctrl-C to stop
ccfix --watch --interval 0.3   # custom poll interval (default 0.4s)
```

In watch mode the fix happens **on copy** — you never type anything. It only
rewrites the clipboard when **both** gates pass:

1. **Frontmost app is a terminal** where Claude Code runs. macOS doesn't tag the
   clipboard with its source app, so `ccfix` checks which app was frontmost at
   copy-time via `lsappinfo`. The allowlist (`TERMINAL_BUNDLE_IDS` in `ccfix.py`):
   `com.cmuxterm.app` (cmux), `com.mitchellh.ghostty`, `com.googlecode.iterm2`,
   `com.apple.Terminal`.
2. **The text wrap-merged into something shell-like** (`SHELL_SIGNALS` in
   `ccfix.py`). Wrapped prose copied from a pager merges but isn't shell-like, so
   it's left alone.

Copy a paragraph in a browser → ignored (gate 1). Copy normal multi-line text in
the terminal → ignored (gate 2). It only acts in the intersection.

## Run it at login (launchd)

Install the agent so the watcher starts automatically and restarts if it exits:

```sh
cp /Users/bartturczynski/Projects/claude-copy-fix/com.bartturczynski.ccfix-watch.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.bartturczynski.ccfix-watch.plist
```

Logs: `/tmp/ccfix-watch.log`.

Stop and remove:

```sh
launchctl unload ~/Library/LaunchAgents/com.bartturczynski.ccfix-watch.plist
rm ~/Library/LaunchAgents/com.bartturczynski.ccfix-watch.plist
```

> Run **one** watcher at a time. If the launchd agent is loaded, stop any
> foreground `ccfix --watch` you started by hand (two watchers aren't harmful —
> the second sees no change once the first has fixed the clipboard — but there's
> no reason to run both).

## Caveats

- **It's a post-processor**, not a real fix. The underlying bug is in Claude
  Code's renderer. The built-in `/copy` command is also worth knowing — it copies
  the source text of a response/block and sidesteps terminal wrapping entirely.
- **Polling has a sub-second window.** Watch mode polls every 0.4s; if you copy
  and instantly switch apps, the frontmost-app reading could be wrong. For
  event-driven detection with no polling, Hammerspoon's `hs.pasteboard.watcher`
  + `hs.application.frontmostApplication` is the robust alternative (extra
  dependency).
- **Scopes to the terminal, not literally the `claude` process.** Copying a
  wrap-broken-looking command from `less` in the same terminal would also fire;
  the content gate makes this uncommon.
- **Watch mode mutates the clipboard in place.** That's the point — but when it
  acts, the wrapped version is gone.
- **Wrap detection assumes no trailing-space padding** on wrapped lines (the
  typical case). If a paste comes out wrong, use `ccfix --join-all`.

## Files

| File | Purpose |
| --- | --- |
| `ccfix.py` | The tool: cleaning logic, one-shot modes, and `--watch`. |
| `~/.config/fish/functions/ccfix.fish` | `ccfix` shell function (forwards to `ccfix.py`). |
| `com.bartturczynski.ccfix-watch.plist` | launchd agent to run the watcher at login. |
