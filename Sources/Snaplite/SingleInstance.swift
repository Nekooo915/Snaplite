import Foundation
import Darwin

/// Single-instance enforcement via a Unix domain socket.
///
/// Mirrors the Rust build: a launching process tries to connect to a
/// known socket path. Connect-OK ⇒ a peer is already running, send "show"
/// and exit. Connect-fail ⇒ we are the first instance; bind the socket
/// and listen for future knocks.
///
/// macOS will *also* deliver `applicationShouldHandleReopen:` when the
/// user double-clicks an already-running .app (no second process spawns
/// at all in that case), and `AppDelegate` handles that natively. The
/// socket here is the belt-and-suspenders path for the rare case where
/// macOS *does* spawn a sibling, e.g. launching from `/usr/bin/open`
/// against a different bundle ID alias.
enum SingleInstance {
    private static let socketBasename = "instance.sock"

    /// Try to deliver "show" to a running instance. Returns true if
    /// forwarded — the caller should exit immediately.
    static func tryForwardToExisting() -> Bool {
        let path = socketPath()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            return false
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: bytes.count) { p in
                _ = bytes.withUnsafeBufferPointer { src in
                    memcpy(p, src.baseAddress, bytes.count)
                }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr -> Bool in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, len) == 0
            }
        }
        guard connected else {
            NSLog("[snaplite] no running instance at \(path); starting fresh")
            return false
        }
        let payload = Array("show".utf8)
        _ = payload.withUnsafeBytes { buf -> Int in
            Darwin.send(fd, buf.baseAddress, buf.count, 0)
        }
        NSLog("[snaplite] forwarded 'show' to existing instance")
        return true
    }

    /// Begin listening on the socket. Each "knock" calls `onKnock` on the
    /// main thread. Safe to call from `applicationDidFinishLaunching`.
    static func startListener(onKnock: @escaping () -> Void) {
        let path = socketPath()
        // A stale socket file from a crashed run blocks bind(). The
        // earlier `tryForwardToExisting` call already returned false (no
        // live peer), so unlinking it is safe.
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            NSLog("[snaplite] single-instance: socket() failed")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: bytes.count) { p in
                _ = bytes.withUnsafeBufferPointer { src in
                    memcpy(p, src.baseAddress, bytes.count)
                }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { ptr -> Bool in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, len) == 0
            }
        }
        guard bound, Darwin.listen(fd, 4) == 0 else {
            NSLog("[snaplite] single-instance: bind/listen failed at \(path)")
            close(fd)
            return
        }
        NSLog("[snaplite] single-instance: listening on \(path)")

        DispatchQueue.global(qos: .background).async {
            while true {
                let client = Darwin.accept(fd, nil, nil)
                guard client >= 0 else {
                    if errno == EINTR { continue }
                    break
                }
                var buf = [UInt8](repeating: 0, count: 16)
                _ = buf.withUnsafeMutableBufferPointer { ptr in
                    Darwin.recv(client, ptr.baseAddress, ptr.count, 0)
                }
                close(client)
                NSLog("[snaplite] single-instance: knock received")
                DispatchQueue.main.async(execute: onKnock)
            }
            close(fd)
        }
    }

    /// Best-effort cleanup on graceful exit.
    static func cleanup() {
        unlink(socketPath())
    }

    // MARK: - Path

    private static func socketPath() -> String {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Snaplite", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent(socketBasename).path
    }
}
