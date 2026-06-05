# ccfix

> Working name. Repairs terminal-wrapped clipboard commands from grid-renderer
> agent CLIs (Claude Code, Gemini CLI, Codex CLI) so they paste as clean,
> runnable shell commands. macOS only.

See [`docs/PRDv2.md`](docs/PRDv2.md) for the full product spec; [`docs/PRD.md`](docs/PRD.md)
is the prior draft. Earlier prototypes live in [`archive/`](archive/).

## Why

TUI agents render through a fixed character grid and insert **real newlines** plus
a left-margin gutter into long lines. Copying a wrapped shell command carries hard
breaks and leading spaces, so pasting garbles or prematurely runs it. This tool
repairs exactly the copied fragment. (Background: PRD v2 §1.)

## Layout

```
Sources/CCFixCore   pure, deterministic repair pipeline (PRD v2 §6)
Sources/ccfix       thin CLI shell (PRD v2 §8.1)
Tests/              swift-testing unit + property tests (PRD v2 §6.8, §13)
docs/               PRDs
archive/            reference Python implementation + original plist/README
```

## Develop

Requires the Swift toolchain (Xcode Command Line Tools).

```sh
make build      # swift build
make test       # swift test
make fmt        # format in place (needs swift-format)
make lint       # static analysis (needs swiftlint)
```

Optional tools:

```sh
brew install swift-format swiftlint
```

## Try it

```sh
pbpaste | swift run ccfix -      # repair clipboard text, print to stdout
swift run ccfix --help
```

## Status

Early scaffold. Implemented: normalize, de-gutter, and wrap-rejoin (PRD v2
§6.1–6.3). Not yet wired: heredoc protection (§6.4), merge-artifact split (§6.5),
non-Claude profiles (§6.6), the confidence/veto watcher gates (§7), and the setup
wizard / LaunchAgent (§8.2). See the `TODO(§…)` markers in `Sources/CCFixCore`.
