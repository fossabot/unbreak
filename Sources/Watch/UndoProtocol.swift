import Foundation

/// The `ccfix undo` IPC request (PRD v2 §7.1).
///
/// Sent by the `ccfix undo` client to the running daemon. Intentionally minimal:
/// a single command verb. Clipboard content **never** crosses the wire — the
/// restore is performed daemon-side — keeping the channel consistent with the
/// content-safety contract (§7.3).
public struct UndoRequest: Codable, Equatable, Sendable {
    /// The only verb the channel carries today; modelled as an enum so an
    /// unrecognized command from a newer/older client fails to decode (→ `.error`)
    /// rather than being silently misread.
    public enum Command: String, Codable, Sendable {
        case undo
    }

    public var command: Command

    public init(command: Command = .undo) {
        self.command = command
    }
}

/// The daemon's response to an `UndoRequest` (PRD v2 §7.1).
public struct UndoResponse: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// The buffered original was written back to the clipboard.
        case restored
        /// Nothing to undo — the buffer was empty (no recent auto-fix, or it was
        /// already cleared by a newer copy / a prior undo).
        case empty
        /// The daemon could not service the request (malformed/oversized frame).
        case error
    }

    public var status: Status

    public init(status: Status) {
        self.status = status
    }
}

/// Newline-delimited-JSON codec for the undo channel (PRD v2 §7.1).
///
/// One JSON object per frame, terminated by a single `\n`, capped at
/// `maxFrameBytes`. The cap is a safety bound on a channel that only ever carries
/// a one-word command and a one-word status — it guards the reader against a
/// peer that never sends a newline.
public enum UndoProtocol {
    /// Hard ceiling on a single frame (including the trailing newline). The real
    /// frames are a few dozen bytes; this is slack, not a target.
    public static let maxFrameBytes = 1024

    /// The frame delimiter (`\n`).
    static let newline: UInt8 = 0x0A

    public enum CodecError: Error, Equatable {
        /// The encoded frame exceeded `maxFrameBytes`.
        case frameTooLarge(Int)
        /// The frame was empty / had no JSON payload before the newline.
        case emptyFrame
        /// The JSON payload did not decode into the expected type.
        case malformed
    }

    /// Encode a value to a single newline-terminated JSON frame, enforcing the
    /// size cap. Keys are sorted so a round-trip is byte-stable (test-friendly).
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(newline)
        guard data.count <= maxFrameBytes else {
            throw CodecError.frameTooLarge(data.count)
        }
        return data
    }

    /// Decode a value from a frame, tolerating a present-or-absent trailing
    /// newline (and any trailing whitespace a stream read may include).
    public static func decode<Value: Decodable>(
        _ type: Value.Type,
        from frame: Data
    ) throws -> Value {
        let trimmed = trimTrailingNewlines(frame)
        guard !trimmed.isEmpty else { throw CodecError.emptyFrame }
        do {
            return try JSONDecoder().decode(type, from: trimmed)
        } catch {
            throw CodecError.malformed
        }
    }

    /// Strip trailing `\n`/`\r` bytes so a framed read decodes cleanly.
    private static func trimTrailingNewlines(_ data: Data) -> Data {
        var end = data.endIndex
        while end > data.startIndex {
            let byte = data[data.index(before: end)]
            guard byte == newline || byte == 0x0D else { break }
            end = data.index(before: end)
        }
        return data.subdata(in: data.startIndex..<end)
    }
}
