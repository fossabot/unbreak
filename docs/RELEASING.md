# Releasing ccfix (PRD v2 §9)

Distribution is a **Homebrew tap** (primary) with a `curl … | bash` **fallback**
([`install.sh`](../install.sh)). Both build from source — no bottles yet (§12).

Throughout, replace the `OWNER` placeholder with the real GitHub handle. It
appears in [`Formula/ccfix.rb`](../Formula/ccfix.rb) (`homepage`, `url`) and in
`install.sh` (`CCFIX_REPO` default). The tap lives in a **separate** repo,
`OWNER/homebrew-tap`, with the formula at `Formula/ccfix.rb`.

## One-time tap setup

1. Create a public repo `OWNER/homebrew-tap`.
2. Copy `Formula/ccfix.rb` into it at `Formula/ccfix.rb`.
3. Users then install with:

   ```sh
   brew install OWNER/tap/ccfix
   ```

   `brew install` only puts the CLI on `PATH`; the watcher is off until the user
   opts in (`brew services start ccfix` or `ccfix setup`). The formula's
   `caveats` says so.

## Cutting a release

1. **Tag and push** from the source repo:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

2. **Get the tarball digest.** GitHub serves a source tarball per tag:

   ```sh
   curl -fsSL https://github.com/OWNER/ccfix/archive/refs/tags/v0.1.0.tar.gz \
     | shasum -a 256
   ```

3. **Bump the formula** in `OWNER/homebrew-tap` — change `version`, `url`, and
   `sha256` together. The explicit `version` means users only update on a bump,
   not on every `brew update`.

4. **Verify locally** before pushing the formula:

   ```sh
   brew install --build-from-source ./Formula/ccfix.rb
   brew test ccfix          # runs the stdin-repair test block
   brew style ./Formula/ccfix.rb
   ```

5. **Commit + push** the formula bump to the tap repo.

## Fallback installer

For users without Homebrew, `install.sh` fetches the tagged tarball, builds
`-c release`, and installs the binary. It keeps the watcher off unless
`--enable-watch` is passed:

```sh
curl -fsSL https://raw.githubusercontent.com/OWNER/ccfix/main/install.sh | bash
```

The LaunchAgent is never templated with a hardcoded path: when enabled, the
binary's own `ccfix install-agent` resolves its absolute path and writes the
per-user plist (§7.4, §8.2).

## Later (§12)

- **Bottles** for tap installs (skip the per-user source build).
- **homebrew-core** submission once notability clears the self-submission bar
  (≥90 forks / ≥90 watchers / ≥225 stars, a stable release, and an OSS license).
