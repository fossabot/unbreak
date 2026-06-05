# PRD — Terminal copy-fix utility (working name: `ccfix`)

> Status: **Draft for build**. Name is a placeholder (see §11). This PRD is the
> product of a design discussion plus empirical artifact capture against a live
> Claude Code session. It supersedes the assumptions in the original `README.md`.

## 1. Problem

TUI coding agents that render output through a fixed-size character grid insert
**real newline characters** (and a left-margin gutter) into their output instead
of letting the terminal soft-wrap. When a user selects and copies a long line
(typically a shell command the agent told them to run), the copied text carries:

- hard line breaks at the wrap column, and
- the rendering gutter (leading spaces) on every line.

Pasting that into a shell runs the command prematurely or garbles it.

This is **renderer-side**, not terminal-side: because the newlines are literal,
a soft-wrap-aware terminal cannot rejoin them. Confirmed affected (same
mechanism, all grid-renderer TUIs):

- **Claude Code** (Ink/React) — primary target.
- **Gemini CLI** (Ink) — same family; open issue
  [google-gemini/gemini-cli#13688](https://github.com/google-gemini/gemini-cli/issues/13688).
- **Codex CLI** (Ratatui) — open issues
  [openai/codex#12200](https://github.com/openai/codex/issues/12200),
  [#8306](https://github.com/openai/codex/issues/8306).

Not affected (sidestep via OSC52 logical-copy or stream-to-scrollback): opencode,
Textual-based tools, Aider (prose). So the tool's reach is "grid-renderer agent
CLIs," not "all CLIs."

There is **no built-in fix**: `/copy` copies the whole answer *as rendered*
(gutter + wraps included); the requested `outputWrapping: "soft"` setting does not
exist; no hook can modify the clipboard. Until upstream ships a fix, a clipboard
post-processor is the only option. See §10 for obsolescence risk.

### Distinct value vs `/copy`
`/copy` grabs the entire response. This tool repairs **exactly the fragment the
user selected** (e.g. one bang command), which is the common real-world need.

## 2. Goals

- Repair a copied fragment so it pastes as a clean, runnable command.
- A hands-free **watch mode**: fix the clipboard automatically on copy, scoped so
  it only acts on agent-CLI command text — never normal copies.
- Be installable by anyone (no hardcoded usernames/paths), with a first-class
  install experience.
- Be stable and efficient enough to run continuously at login.

## 3. Non-goals (v1)

- **Cross-platform.** macOS only. The clipboard backend (`NSPasteboard`) and the
  frontmost-app gate (`NSWorkspace`) have no clean portable equivalent, and the
  whole premise is a mac terminal workflow.
- **Auto-paste.** Deferred to v2 (§9) — it needs Accessibility permission, a
  heavier ask than the watcher requires.
- **Parsing the agent's answer structure.** The tool only ever sees the
  clipboard; "copy a specific element" = the user's manual text selection.
- **Pinpointing the agent process** (vs the terminal). Not reliably possible; the
  clipboard isn't source-tagged and active-pane process sniffing is fragile and
  per-terminal. The gate is terminal-app + content heuristic (§7).

## 4. Platform & language decision

- **macOS only.**
- **Swift native binary.** Chosen over keeping the Python script because:
  - Polls `NSPasteboard.changeCount` (a cheap integer) instead of shelling out to
    `pbpaste` every tick; truly event-driven frontmost-app via `NSWorkspace`
    activation notifications.
  - Self-contained binary → trivial Homebrew formula, no Python-env pitfalls
    (the original depended on a fragile `/usr/bin/python3`).
- The existing Python `ccfix.py` serves as the reference implementation for the
  repair heuristic and as a source of test fixtures.

## 5. Empirical artifacts (ground truth)

Captured from a live Claude Code session with the watcher **disabled** (raw
clipboard). The repair algorithm (§6) is designed against these, not assumptions.

| # | Artifact | Example | Repair confidence |
|---|----------|---------|-------------------|
| 1 | Hard wrap at a **word boundary**; break replaces a space | `…\| .name' >` ⏎ `  /tmp/out.json` | High — rejoin with a single space |
| 2 | **+2 left gutter** on every line (relative indent preserved) | sent `  &&`, got `    &&` | High — dedent |
| 3 | **Partial first line** (selection starts inside/after gutter) | line 1 has 0–1 spaces, rest have 2+ | High — compute gutter from lines 2..n |
| 4 | **Unbreakable tokens not wrapped** (no space to break at) | 100-char URL stayed on one line | N/A — nothing to do |
| 5 | **Long-line-then-short-line merge** behind a padding run | `…dedent"   [pad]   fi` then ⏎ `  fi` | **Low — partly lossy (§6.4)** |
| 6 | **Intentional structure survives** | `\` continuations, heredoc body, internal `multiple    spaces` | Must be preserved untouched |

Note the old tool's double-space bug (`>  /tmp`): word-boundary wraps must rejoin
with exactly one space and collapse the duplicate.

## 6. Repair algorithm

Operates on a plain string (the clipboard contents). Per-tool "wrap profiles" are
pluggable; **v1 ships the Claude Code profile**, with Gemini/Codex as fast-follows.

### 6.1 Normalize
- CRLF/CR → LF. Preserve a single trailing newline decision for output parity.

### 6.2 De-gutter (dedent, robust to partial line 1)
- `G` = minimum leading-whitespace width over **non-blank lines 2..n** (line 1 is
  excluded because it is frequently partially selected).
- Remove `G` columns from lines 2..n; remove `min(indent₁, G)` from line 1.
- This strips the rendering gutter while **preserving relative indentation**
  (verified against Case 6 nesting).

### 6.3 Rejoin wrapped lines
- A newline is a **wrap** (rejoin) when the preceding line is "full" — its length
  is at/near the detected wrap column `W` — and it does **not** end in an explicit
  continuation token (`\`, `&&`, `||`, `|`, trailing `(`/`,` etc.).
- Rejoin word-boundary wraps with a **single space**; collapse an accidental
  double space at the seam.
- `W` detection: most-common length among full, non-final lines (per original
  heuristic), or `--width N` override.
- Lines ending in explicit continuations and short lines are left as separate
  lines → heredocs, `\` layouts, and one-operator-per-line survive (Case 6 items
  3/4 in §5).

### 6.4 Merge-artifact split (best-effort, opt-in safe)
- Detect a line whose length exceeds `W` and contains a run of `≥k` spaces
  followed by more shell-like tokens → likely a lost newline hidden by padding.
- Split at the run. **Known limitation:** indistinguishable in general from
  intentional alignment (e.g. heredoc internal spacing), and the original line's
  indent is unrecoverable. Therefore:
  - only trigger when the run pushes past `W` **and** the tail looks like separate
    statements;
  - never apply inside a detected heredoc body;
  - always reversible via `--no-copy` preview and `--join-all`.
- This is the one artifact we **do not promise** to fix cleanly; documented as
  such.

### 6.5 Guarantees / tests
- **Idempotent**: running twice == running once.
- **Lossless on already-clean input**: a fragment with no artifacts is returned
  unchanged.
- **Structure-preserving**: §5 Cases 3/4 round-trip to their intended form.

## 7. Watch mode

Hands-free fix on copy. **Opt-in** (see §8). Two gates, both must pass:

1. **Frontmost app is an allowlisted terminal** (via `NSWorkspace`). Default
   allowlist: cmux, Ghostty, iTerm2, Apple Terminal — user-extensible (§8.3).
2. **Content looks like a wrapped shell command** (after repair it differs from
   the original *and* matches shell signals). Wrapped prose from a pager is left
   alone.

- Detection of clipboard change via `NSPasteboard.changeCount` (cheap, fast poll
  or notification-driven); our own writes are recorded to avoid a feedback loop.
- **In-place clipboard mutation** is the intended behavior (the whole point): when
  it acts, the wrapped version is replaced. Documented prominently.
- Runs at login via a launchd LaunchAgent that the installer generates per-user
  (no hardcoded path/username/label — fixes the original personalized plist).
- Bundle id / label: generic reverse-DNS (final value pending name, §11), **not**
  a personal identifier.

## 8. Installation & CLI surface

### 8.1 CLI (one-shot)
- `ccfix`               — fix clipboard in place (default)
- `ccfix "text"`        — fix an argument
- `ccfix -`             — stdin → stdout (never touches clipboard)
- `ccfix --no-copy`     — print result, don't write clipboard (preview)
- `ccfix --join-all`    — aggressive full-collapse fallback
- `ccfix --width N`     — force the wrap column

### 8.2 Setup wizard (the "first-class install experience")
- `ccfix setup` — interactive wizard: detect terminals, pick the allowlist, and
  prompt "enable the auto-fix watcher at login? [y/N]".
- `ccfix setup --enable-agent` — non-interactive/forced for scripted installs.
- `ccfix install-agent` / `ccfix uninstall-agent` — manage the LaunchAgent
  through the tool (no hand-copying plists).
- Watcher is **off until the user opts in** — `brew install` alone only puts the
  CLI on PATH and prints a caveat.

### 8.3 Config
- `~/.config/ccfix/config.toml`: terminal allowlist, poll interval, default wrap
  profile. Env overrides (e.g. `CCFIX_TERMINALS`).
- Logs: `~/Library/Logs/ccfix.log` (not world-writable `/tmp`).

## 9. Distribution

- **Primary: Homebrew tap.** Public repo `<handle>/homebrew-tap` with
  `Formula/ccfix.rb`. No account/approval beyond a GitHub account.
  - `brew install <handle>/tap/ccfix`
  - `brew services start ccfix` (or the wizard) — Homebrew generates the per-user
    launchd plist, eliminating hardcoded path/username.
  - Formula builds from source (needs Xcode Command Line Tools); pre-built
    **bottles** are a later optimization.
- **Fallback: `curl … | bash` installer** hosted on GitHub for users without
  Homebrew; templates the LaunchAgent at install time.
- **Not pursuing**: pip/pipx (Python-env pain, and we're going native), and
  Claude Code plugin (plugins can't run a persistent OS clipboard watcher — a
  hook only rewrites the on-screen render, never the clipboard).
- **Release flow**: tagged GitHub release → tarball + SHA-256 → bump
  `version` + `sha256` in the formula. Explicit `version` so users only update on
  a bump.
- **homebrew-core** (`brew install ccfix`, no tap) is a *later* goal — it requires
  a PR and a notability bar (~75 stars / 30 forks-or-watchers, stable release,
  OSS license). Start with the tap.

## 10. Risks

- **Upstream obsolescence**: if Anthropic ships `outputWrapping: "soft"`, the tool
  loses its reason to exist. Mitigation: keep it small and low-maintenance; the
  multi-tool reach (Gemini/Codex) hedges single-vendor risk.
- **Merge-artifact (§6.4)** is partly lossy and heuristic — documented limitation,
  with escape hatches.
- **Watch-mode false positives**: copying a wrapped command from a pager in an
  allowlisted terminal could fire. The content gate makes this uncommon; in-place
  mutation means the original is gone when it acts (documented).

## 11. Open items

- **Name** (deliberately deferred): leaning toward a terminal/multi-tool-oriented
  name now that scope spans Claude Code + Gemini CLI + Codex CLI, rather than a
  Claude-specific one. `ccfix` is a placeholder throughout this PRD; final name
  fixes the binary, tap repo, bundle id, and config dir.
- **Terminal confirmation**: capture was on (presumed) cmux; artifacts are
  renderer-side so this shouldn't change the design, but worth confirming and
  cross-testing iTerm2 / Terminal.app / Ghostty during QA.

## 12. v2 / future

- **Auto-paste** the fixed command (synthesize ⌘V) — requires Accessibility
  permission; separate opt-in.
- **Gemini CLI & Codex CLI wrap profiles** (Codex adds +2 continuation indent that
  breaks heredocs; Gemini adds leading spaces + hidden chars — both need profile
  entries beyond Claude's).
- **Bottles** for tap installs; eventual **homebrew-core** submission.

## 13. Testing strategy

- Fixture corpus: raw mangled captures (watcher off) per tool × the §5 case types
  (long wrap, inline, multi-line `\`, heredoc, long token, nested+merge).
- Assert: idempotence, lossless on clean input, structure preservation, correct
  single-space rejoin, gutter removal with relative-indent preservation.
- Cross-terminal QA matrix: cmux, Ghostty, iTerm2, Apple Terminal.
