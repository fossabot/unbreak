# QA run-through — CLAU-vmpxtwus

Battery of varied real Claude Code TUI captures fed through `unbreak` to surface
repair edge cases. Date: 2026-06-10.

## Setup / method

- **Watcher disabled** for the whole run (`brew services stop unbreak`) so captures
  are raw, un-repaired bytes.
- The Homebrew binary on PATH is **stale `0.1.3`** — it predates the quote-bar
  reflow (§6.2, commit `8903f50`). All QA ran against a **fresh `swift build -c
  release`** binary (`/tmp/ub` → `.build/release/unbreak`).
- Capture mechanics confirmed:
  - **Blockquote (`>`)** renders with the `  ▎ ` (U+258E) gutter → exercises the
    §6.2 reflow path. Glyph verified as `e2 96 8e`.
  - **Code block** renders with a flat **2-space** gutter (invisible on screen,
    present in copied bytes) — no `▎`.
- Per case: `pbpaste > cap.in; ub - < cap.in > cap.out; ub - < cap.out` (idempotence).

## Results by category

| # | Category | Cases | Verdict |
|---|----------|-------|---------|
| 1 | Quote-bar box (`▎`, §6.2) | prose, multi-para, short/wide bullets, numbered, nested, code-in-box, long-code, mixed | ✅ all clean & idempotent; **F1** on equal-width code lines |
| 2 | Long shell commands | pipe/&&, backslash-cont, subshell, quoted-spaces, env-vars, merge-split | ✅ 2b/2e/2f; **F2** (2-line), **F3** (uneven multi-line) |
| 3 | Heredocs | `<<-EOF` indented body + internal spaces | ✅ round-trips untouched |
| 4 | Code blocks | Python nested indentation | ❌ **F6** (de-gutter flattens) |
| 5 | Markdown | table, task list, (bullets/nested via cat 1) | ❌ **F5** (table smush); ✅ task list |
| 6 | Unicode/width (§6.1) | CJK + emoji-ZWJ family + flags + combining + VS | ✅ zero corruption, exact codepoints |
| 7 | Unbreakable tokens | 230-char URL (JWT/sha) | ❌ **F4** (space injected → corruption) |
| 8 | Structured text | unified diff, tree, stack trace | ✅ de-guttered, structure intact (F5 covers uniform box-drawing) |
| 9 | Reflow stress | varied/short-last-line | covered by F3 + category 1 reflow cases |

## Findings (all children of CLAU-vmpxtwus)

| ID | Issue | Sev | One-liner |
|----|-------|-----|-----------|
| F1 | CLAU-jelhxutz | med | §6.2 quote-bar reflow over-joins two near-equal-width *commands* in a bar block |
| F2 | CLAU-umzcppan | high | Command wrapping into exactly **2 lines** is never auto-rejoined (detectWidth needs ≥2 non-final lines) |
| F3 | CLAU-rtzoinwb | high | Multi-line wraps don't rejoin unless wrapped lines are **exactly** equal width (too strict vs `isFull` ±2) |
| F4 | CLAU-ajqigmcx | high | Hard-wrapped **URL/hash/base64** corrupted by **injected spaces** on rejoin (§5 Case 4) |
| F5 | CLAU-fplzfldz | med | One-shot **smushes box-drawing tables** / uniform-width structure into one line (no structure guard in `rejoin`) |
| F6 | CLAU-vqcljzus | high | De-gutter **flattens code indentation** when line 1 is the outermost scope (violates §6.8 lossless-on-clean) |

Note: F4/F5/F6 are **one-shot** mangles; watch-mode gates correctly skip these
(safe-corpus suite stays green — 253/253). F1/F2/F3 are repair-core logic gaps.

## Observations

- **O1** (CLAU-xfmisple, low) — a leading blank line from a drag-selection passes
  through untouched; also perturbs de-gutter `G` (see 2b: continuation indent kept
  at 2 vs flattened to 0). Candidate "trim leading/trailing blank lines" fix.
- **O2** (not filed — renderer behavior, not unbreak's) — the renderer drops the
  blank line after an indented code block, so the following prose sits directly
  under the code; unbreak faithfully preserves the adjacency.
- **O3** (CLAU-dcvwyrud, low) — a single-line capture is not de-guttered at all
  (`degutter`/`rejoin` require ≥2 lines), so a lone copied command keeps its
  2-space gutter. Harmless for shell execution.

## Regression tests (this session)

- `Tests/CorpusTests/Fixtures/known-issues/F{1..6}-*.{in,expected}` — each bug's real
  capture paired with the form repair *should* produce once fixed.
- `Tests/CorpusTests/KnownIssueTests.swift` — asserts each pair inside
  `withKnownIssue(<CLAU id>)`: CI stays green now, and fails the moment a gap is
  fixed (prompting promotion to a plain `#expect`).
- `Tests/CorpusTests/Fixtures/repair/claude-code/quote-bar-unicode.{in,expected}` —
  GREEN lock: §6.2 reflow over wide CJK + emoji-ZWJ + flags, no corruption
  (auto-asserted by `GoldenRepairTests`).
- Full suite: `255 tests / 31 suites passed, 6 known issues`.

## Version status (as of this session)

Latest release tag `v0.1.3` == the installed Homebrew binary. The §6.2 quote-bar
feature (`8903f50`) is on `main` but **unreleased**. F2–F6 are pre-existing (already
in 0.1.3); F1 is new with §6.2. Recommendation: fix the high-severity gaps (F4
first, then F2/F3/F6), then cut one **0.2.0** shipping §6.2 + the fixes together —
rather than releasing §6.2 with the gaps open.

## Cross-cutting theme

The wrap-column detector (`detectWidth`) is the root of F2/F3/F4: it demands an
**exactly repeated** width among ≥2 non-final lines. Real word-wraps vary in width
(→ F3 under-join), 2-line wraps have only one non-final line (→ F2 under-join), and
no-space tokens break at the *exact* column repeatedly so they DO match and then get
space-corrupted (→ F4). A tolerance-based clustering (matching `isFull`'s ±2) plus a
mid-token "join without space" rule and a structure guard would address most of the
corpus at once.
