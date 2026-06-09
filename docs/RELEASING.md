# Releasing unbreak (PRD v2 §9)

Distribution is a **Homebrew tap** (primary) with a `curl … | bash` **fallback**
([`install.sh`](../install.sh)). Tap installs use a prebuilt **bottle** so users
need no Swift toolchain; the `curl` fallback still builds from source.

The GitHub handle is `bart-turczynski`. It appears in
[`Formula/unbreak.rb`](../Formula/unbreak.rb) (`homepage`, `url`) and in
`install.sh` (`UNBREAK_REPO` default). The tap lives in a **separate** repo,
`bart-turczynski/homebrew-tap`, with the formula at `Formula/unbreak.rb`.

## One-time tap setup

1. Create a public repo `bart-turczynski/homebrew-tap`.
2. Copy `Formula/unbreak.rb` into it at `Formula/unbreak.rb`.
3. Users then install with:

   ```sh
   brew install bart-turczynski/tap/unbreak
   ```

   `brew install` only puts the CLI on `PATH`; the watcher is off until the user
   opts in (`brew services start unbreak` or `unbreak setup`). The formula's
   `caveats` says so.

## Cutting a release

The source-tarball `sha256` must match the tag *before* the bottle is built, so
the formula bump comes first, then the tag, then the workflow fills in the bottle.

1. **Bump the source fields** in [`Formula/unbreak.rb`](../Formula/unbreak.rb).
   First compute the digest of the tag's source tarball (GitHub generates one per
   tag — push the tag, or compute against the commit you're about to tag):

   ```sh
   curl -fsSL https://github.com/bart-turczynski/unbreak/archive/refs/tags/v0.1.2.tar.gz \
     | shasum -a 256
   ```

   Change `version`, `url`, and `sha256` together. The explicit `version` means
   users only update on a bump, not on every `brew update`. Commit.

2. **Tag and push:**

   ```sh
   git tag v0.1.2
   git push origin v0.1.2
   ```

3. **The release workflow** ([`.github/workflows/release.yml`](../.github/workflows/release.yml))
   fires on the tag. It builds the bottle on the `macos-26` runner, uploads the
   `*.bottle.tar.gz` as a release asset, and prints the ready-to-paste `bottle do`
   block (with the real cellar tag + `sha256`) to the **job summary**.

4. **Wire the bottle into the formula.** Copy the generated block over the
   placeholder `bottle do` in `Formula/unbreak.rb`, and bump the `root_url` tag to
   the new version. Mirror the whole formula into the tap repo
   `bart-turczynski/homebrew-tap` at `Formula/unbreak.rb` (this is the copy users
   install from).

5. **Verify** a clean bottle install from the tap:

   ```sh
   brew uninstall unbreak 2>/dev/null || true
   brew install bart-turczynski/tap/unbreak   # should download the bottle, not compile
   brew test unbreak                          # runs the stdin-repair test block
   brew style ./Formula/unbreak.rb
   ```

   To force-check the source path still works (the bottle's build recipe + the
   no-bottle fallback): `brew install --build-from-source ./Formula/unbreak.rb`.

> **Architectures & OS coverage.** The bottle is built on the Apple-Silicon
> `macos-26` runner, so it serves `arm64`. Homebrew only reuses a bottle on a
> macOS release **at or newer than** the bottle's own tag — never older. So the
> workflow relabels the tahoe-built bottle to the *oldest* supported tag,
> `arm64_ventura` (matching `Package.swift` `.macOS(.v13)`); one file then serves
> macOS 13+ on Apple Silicon. Intel (`x86_64`) users currently fall back to the
> source build; add an `x86_64` bottle (cross-build or a universal `lipo`) if the
> team needs it.

## Fallback installer

For users without Homebrew, `install.sh` fetches the tagged tarball, builds
`-c release`, and installs the binary. It keeps the watcher off unless
`--enable-watch` is passed:

```sh
curl -fsSL https://raw.githubusercontent.com/bart-turczynski/unbreak/main/install.sh | bash
```

The LaunchAgent is never templated with a hardcoded path: when enabled, the
binary's own `unbreak install-agent` resolves its absolute path and writes the
per-user plist (§7.4, §8.2).

## Later (§12)

- **Intel / universal bottle** so `x86_64` Macs skip the source build too.
- **homebrew-core** submission once notability clears the self-submission bar
  (≥90 forks / ≥90 watchers / ≥225 stars, a stable release, and an OSS license).
