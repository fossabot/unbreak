import CCFixCore
import Clipboard
import Foundation
import Watch

#if canImport(AppKit)
import AppKit
#endif

// One-shot CLI surface (PRD v2 §8.1) plus the opt-in watch daemon (§7). The
// setup wizard and LaunchAgent management (§8.2) are not wired up yet.

let helpText = """
    ccfix — repair terminal-wrapped clipboard commands (PRD v2 §8.1)

    USAGE:
      ccfix                       fix clipboard in place (default)
      ccfix "text"                fix an argument, write result to clipboard
      ccfix -                     stdin -> stdout (never touches clipboard)
      ccfix --no-copy             print result, do not write clipboard (preview)
      ccfix --join-all            aggressive full-collapse fallback
      ccfix --width N             force the wrap column
      ccfix --split-padding-artifacts
                                  enable the lossy merge-artifact split (§6.5)

    WATCH MODE (opt-in, §7) — fixes the clipboard hands-free on copy, but ONLY
    when every gate passes (allowlisted terminal frontmost, plain text, small,
    repaired, strong shell signal, no structure-risk veto):
      ccfix --watch               run the fix-on-copy daemon (mutates clipboard)
      ccfix --dry-run-watch       run the daemon log-only — never mutates (§7.2)
    """

var options = RepairOptions()
var noCopy = false
var readStdin = false
var watch = false
var dryRunWatch = false
var literal: String?

let args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    let arg = args[i]
    switch arg {
    case "-":
        readStdin = true
    case "--no-copy":
        noCopy = true
    case "--watch":
        watch = true
    case "--dry-run-watch":
        dryRunWatch = true
    case "--join-all":
        options.joinAll = true
    case "--split-padding-artifacts":
        options.splitPaddingArtifacts = true
    case "--width":
        i += 1
        if i < args.count, let n = Int(args[i]) { options.forcedWidth = n }
    case "-h", "--help":
        print(helpText)
        exit(0)
    default:
        if !arg.hasPrefix("-") { literal = arg }
    }
    i += 1
}

// Watch mode short-circuits the one-shot path: it runs the daemon and blocks on
// the run loop until the process is terminated.
if watch || dryRunWatch {
    #if canImport(AppKit)
    let watcher = Watcher.system()
    let session = WatchSession(
        watcher: watcher,
        log: FileLog.defaultLog(),
        options: .init(dryRun: dryRunWatch, repair: options)
    )
    _ = session  // retained for the lifetime of the process
    watcher.start()
    let mode = dryRunWatch ? "dry-run (log-only)" : "active (mutating)"
    FileHandle.standardError.write(
        Data("ccfix: watch mode \(mode); logging to ~/Library/Logs/ccfix.log\n".utf8)
    )
    RunLoop.main.run()
    exit(0)
    #else
    FileHandle.standardError.write(Data("ccfix: watch mode requires macOS\n".utf8))
    exit(1)
    #endif
}

func clipboardString() -> String? {
    #if canImport(AppKit)
    NSPasteboard.general.string(forType: .string)
    #else
    nil
    #endif
}

func writeClipboard(_ value: String) {
    #if canImport(AppKit)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
    #endif
}

let input: String
if readStdin {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    input = String(bytes: data, encoding: .utf8) ?? ""
} else if let literal {
    input = literal
} else {
    input = clipboardString() ?? ""
}

let result = Repair.repair(input, options: options)

if readStdin {
    FileHandle.standardOutput.write(Data(result.text.utf8))
} else if noCopy {
    print(result.text)
} else {
    writeClipboard(result.text)
}
