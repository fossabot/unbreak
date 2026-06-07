# Homebrew formula for unbreak (PRD v2 §9).
#
# Lives in the tap repo `bart-turczynski/homebrew-tap` as `Formula/unbreak.rb`, so
# users install with:
#
#   brew install bart-turczynski/tap/unbreak
#
# Builds from source (needs the Swift toolchain from the Xcode Command Line
# Tools); pre-built bottles are a later optimization (§12). On each tagged
# release, bump `version`, `url`, and `sha256` together (see docs/RELEASING.md) so
# users only update on an explicit bump.
class Unbreak < Formula
  desc "Repair terminal-wrapped clipboard commands from TUI coding agents"
  homepage "https://github.com/bart-turczynski/unbreak"
  # Source tarball for the tagged release. `version` is explicit so users update
  # only on a bump, not on every tap refresh.
  url "https://github.com/bart-turczynski/unbreak/archive/refs/tags/v0.1.0.tar.gz"
  version "0.1.0"
  # Digest of the v0.1.0 source tarball (see docs/RELEASING.md):
  #   curl -fsSL .../v0.1.0.tar.gz | shasum -a 256
  sha256 "65c8915d341e8b8ad5678d9e156143af87360ffc6a9f3780695849db522cdcb3"
  license "MIT"

  depends_on :macos

  def install
    # Self-contained SwiftPM package (no external deps): a release build with the
    # sandbox disabled so SwiftPM can write its build products.
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/unbreak"
  end

  # `brew services start unbreak` generates the per-user launchd plist — no
  # hardcoded path or username (§9). The watcher only mutates the clipboard when
  # every §7 gate passes.
  service do
    run [opt_bin/"unbreak", "--watch"]
    run_type :immediate
    keep_alive true
    log_path var/"log/unbreak.watch.log"
    error_log_path var/"log/unbreak.watch.log"
  end

  def caveats
    <<~EOS
      The clipboard watcher is OFF until you opt in — `brew install` only puts the
      CLI on your PATH. Turn it on with either:

        brew services start unbreak     # run the watcher at login (launchd)

      or the guided setup, which detects your terminals and writes a config first:

        unbreak setup

      One-shot use never needs the watcher:

        pbpaste | unbreak -             # repair clipboard text, print to stdout

      To remove everything unbreak wrote (login watcher, logs, undo socket, config)
      before `brew uninstall unbreak`, run:

        unbreak uninstall               # `brew uninstall` alone leaves this state behind
    EOS
  end

  test do
    # Exercise the core repair path over stdin: §6.1 normalize must strip ANSI
    # escapes (the stdin->stdout surface never touches the real clipboard).
    assert_equal "git status",
      pipe_output("#{bin}/unbreak -", "\e[31mgit status\e[0m\n").strip
  end
end
