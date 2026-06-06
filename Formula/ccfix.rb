# Homebrew formula for ccfix (PRD v2 §9, working name — see §11).
#
# Lives in the tap repo `<handle>/homebrew-tap` as `Formula/ccfix.rb`, so users
# install with:
#
#   brew install <handle>/tap/ccfix
#
# Builds from source (needs the Swift toolchain from the Xcode Command Line
# Tools); pre-built bottles are a later optimization (§12). On each tagged
# release, bump `version`, `url`, and `sha256` together (see docs/RELEASING.md) so
# users only update on an explicit bump.
class Ccfix < Formula
  desc "Repair terminal-wrapped clipboard commands from TUI coding agents"
  homepage "https://github.com/OWNER/ccfix"
  # Source tarball for the tagged release. `version` is explicit so users update
  # only on a bump, not on every tap refresh.
  url "https://github.com/OWNER/ccfix/archive/refs/tags/v0.1.0.tar.gz"
  version "0.1.0"
  # Placeholder — replace with the tarball's real digest on release:
  #   shasum -a 256 ccfix-0.1.0.tar.gz
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on :macos

  def install
    # Self-contained SwiftPM package (no external deps): a release build with the
    # sandbox disabled so SwiftPM can write its build products.
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/ccfix"
  end

  # `brew services start ccfix` generates the per-user launchd plist — no
  # hardcoded path or username (§9). The watcher only mutates the clipboard when
  # every §7 gate passes.
  service do
    run [opt_bin/"ccfix", "--watch"]
    run_type :immediate
    keep_alive true
    log_path var/"log/ccfix.watch.log"
    error_log_path var/"log/ccfix.watch.log"
  end

  def caveats
    <<~EOS
      The clipboard watcher is OFF until you opt in — `brew install` only puts the
      CLI on your PATH. Turn it on with either:

        brew services start ccfix     # run the watcher at login (launchd)

      or the guided setup, which detects your terminals and writes a config first:

        ccfix setup

      One-shot use never needs the watcher:

        pbpaste | ccfix -             # repair clipboard text, print to stdout
    EOS
  end

  test do
    # Exercise the core repair path over stdin: §6.1 normalize must strip ANSI
    # escapes (the stdin->stdout surface never touches the real clipboard).
    assert_equal "git status",
      pipe_output("#{bin}/ccfix -", "\e[31mgit status\e[0m\n").strip
  end
end
