import CCFixCore
import Foundation

#if canImport(AppKit)
import AppKit
#endif

// Minimal one-shot CLI surface (PRD v2 §8.1). The setup wizard, LaunchAgent
// management, and watch mode (§7, §8.2) are not wired up yet.

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
    """

var options = RepairOptions()
var noCopy = false
var readStdin = false
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
    input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
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
