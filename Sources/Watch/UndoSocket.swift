import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// The on-disk location of the undo control socket (PRD v2 §7.1).
///
/// `~/Library/Application Support/unbreak/undo.sock`, with the parent directory
/// locked to `0700` so only the user can connect. A Unix domain socket path is
/// bounded by `sockaddr_un.sun_path` (104 bytes on Darwin) — short home paths fit
/// comfortably, but the bind/connect helpers guard the limit rather than trust it.
public enum UndoSocketPath {
    /// The default socket URL under the user's Application Support directory.
    public static func defaultURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent("Library/Application Support/unbreak/undo.sock")
    }

    /// Create the socket's parent directory (if needed) and lock it to `0700`.
    public static func prepareDirectory(for url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }
}

/// Errors raised while standing up or tearing down the listen socket. The client
/// surfaces a connect failure as a value (`UndoOutcome.noDaemon`) rather than an
/// error, since "no running watcher" is an ordinary outcome of `unbreak undo`.
public enum UndoSocketError: Error, Equatable {
    /// The socket path would overflow `sun_path` (104 bytes incl. terminator).
    case pathTooLong(Int)
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
}

/// The maximum bytes the socket path may occupy (leaving room for the NUL).
private let sunPathLimit = 103

/// Build a `sockaddr_un` for `path`, copying the UTF-8 bytes into `sun_path`.
private func makeUndoSockaddr(path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
        rawPtr.withMemoryRebound(to: UInt8.self, capacity: capacity) { dst in
            for index in 0..<bytes.count { dst[index] = bytes[index] }
            dst[bytes.count] = 0
        }
    }
    return addr
}

/// Read one framed request/response: bytes up to and including the first newline,
/// or until EOF / `maxBytes`. Blocking — the undo exchange is one tiny frame each
/// way, so a single read almost always suffices; the loop just makes it robust.
private func readUndoFrame(_ fd: Int32, maxBytes: Int) -> Data {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 256)
    while buffer.count < maxBytes {
        let want = min(chunk.count, maxBytes - buffer.count)
        let read = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, want) }
        guard read > 0 else { break }
        buffer.append(contentsOf: chunk[0..<read])
        if chunk[0..<read].contains(UndoProtocol.newline) { break }
    }
    return buffer
}

/// Write every byte of `data`, looping over partial writes. Returns false on a
/// write error / unexpected EOF.
@discardableResult
private func writeUndoAll(_ fd: Int32, _ data: Data) -> Bool {
    let count = data.count
    guard count > 0 else { return true }
    return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
        guard let base = raw.baseAddress else { return false }
        var written = 0
        while written < count {
            let n = Darwin.write(fd, base + written, count - written)
            guard n > 0 else { return false }
            written += n
        }
        return true
    }
}

/// A real socket file descriptor adapted to `UndoConnection` (PRD v2 §7.1).
final class FileDescriptorConnection: UndoConnection {
    private let fd: Int32
    private var isClosed = false

    init(fd: Int32) {
        self.fd = fd
    }

    func readFrame(maxBytes: Int) -> Data {
        readUndoFrame(fd, maxBytes: maxBytes)
    }

    func writeFrame(_ data: Data) {
        writeUndoAll(fd, data)
    }

    func close() {
        guard !isClosed else { return }
        Darwin.close(fd)
        isClosed = true
    }
}

/// The Unix-domain-socket listener that exposes the undo channel to `unbreak undo`
/// (PRD v2 §7.1).
///
/// The daemon is the server: it owns the rollback buffer in memory, and the
/// restore must run through *its* `Clipboard` (see `RollbackService`). The
/// listener is driven by a `DispatchSource` read source attached to the `.main`
/// queue, so `accept` + restore + reply all run on the main thread where the
/// clipboard writes already live — no cross-thread clipboard access, no locking.
///
/// Connections are one-shot: accept, read the request, write the response, close.
///
/// `@unchecked Sendable`: confined to the daemon's main run loop. `start()` is
/// called once on the main thread and the event handler runs on `.main`.
public final class UndoSocketServer: @unchecked Sendable {
    private let socketURL: URL
    private let server: UndoServer
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    public init(socketURL: URL, server: UndoServer) {
        self.socketURL = socketURL
        self.server = server
    }

    /// Bind + listen on the socket and start accepting on the main queue. Throws if
    /// the socket cannot be created/bound (the caller logs it and runs on without
    /// undo support). Unlinks any stale socket file before binding.
    public func start() throws {
        try UndoSocketPath.prepareDirectory(for: socketURL)
        let fd = try Self.makeListeningSocket(at: socketURL.path)
        listenFD = fd

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        readSource.setEventHandler { [weak self] in
            self?.acceptOne()
        }
        readSource.setCancelHandler {
            Darwin.close(fd)
        }
        source = readSource
        readSource.resume()
    }

    /// Stop accepting and remove the socket file.
    public func stop() {
        source?.cancel()
        source = nil
        unlink(socketURL.path)
        listenFD = -1
    }

    /// Accept a single pending connection and service it. A failed `accept` is
    /// ignored — the source will fire again if more connections are queued.
    private func acceptOne() {
        let connectionFD = accept(listenFD, nil, nil)
        guard connectionFD >= 0 else { return }
        server.serve(FileDescriptorConnection(fd: connectionFD))
    }

    /// Create, bind (unlink-first), and listen on the UDS at `path`.
    static func makeListeningSocket(at path: String) throws -> Int32 {
        guard path.utf8.count <= sunPathLimit else {
            throw UndoSocketError.pathTooLong(path.utf8.count)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UndoSocketError.socketFailed(errno) }

        // Remove any stale socket left by a crashed/killed daemon before binding.
        unlink(path)

        var addr = makeUndoSockaddr(path: path)
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(fd)
            throw UndoSocketError.bindFailed(code)
        }
        guard listen(fd, 4) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw UndoSocketError.listenFailed(code)
        }
        return fd
    }
}

/// The result of an `unbreak undo` round-trip (PRD v2 §7.1).
public enum UndoOutcome: Equatable, Sendable {
    /// The daemon restored the pre-fix clipboard.
    case restored
    /// The daemon's buffer was empty — nothing to undo.
    case empty
    /// No running watcher to undo through (connect failed).
    case noDaemon
    /// The exchange failed; carries a short diagnostic.
    case error(String)
}

/// The `unbreak undo` client: connect to the daemon's socket, send `{command:undo}`,
/// and report the daemon's status (PRD v2 §7.1).
///
/// A connect failure is reported as `.noDaemon` (the watcher is not running),
/// which the CLI turns into actionable guidance rather than a stack trace.
public struct UndoClient: Sendable {
    private let socketURL: URL

    public init(socketURL: URL = UndoSocketPath.defaultURL()) {
        self.socketURL = socketURL
    }

    public func requestUndo() -> UndoOutcome {
        let path = socketURL.path
        guard path.utf8.count <= sunPathLimit else {
            return .error("socket path too long")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .error("socket() failed") }
        defer { Darwin.close(fd) }

        var addr = makeUndoSockaddr(path: path)
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
        }
        // ENOENT / ECONNREFUSED both mean "no daemon listening here" — an ordinary
        // outcome, not an error.
        guard connected == 0 else { return .noDaemon }

        guard let frame = try? UndoProtocol.encode(UndoRequest()) else {
            return .error("could not encode request")
        }
        guard writeUndoAll(fd, frame) else { return .error("could not send request") }

        let responseData = readUndoFrame(fd, maxBytes: UndoProtocol.maxFrameBytes)
        guard let response = try? UndoProtocol.decode(UndoResponse.self, from: responseData) else {
            return .error("malformed response from daemon")
        }
        switch response.status {
        case .restored: return .restored
        case .empty: return .empty
        case .error: return .error("the daemon could not service the undo")
        }
    }
}
