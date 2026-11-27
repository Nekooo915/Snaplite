import Foundation
import Testing
@testable import SnapliteCore

@Suite("FileNamer")
struct FileNamerTests {
    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplite-filenamer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Formats base name as Snaplite yyyy-MM-dd at HH.mm.ss")
    func baseNameFormat() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 11
        components.day = 27
        components.hour = 9
        components.minute = 5
        components.second = 42
        let date = try #require(components.date)

        let stem = FileNamer.baseName(for: date, timeZone: try #require(TimeZone(secondsFromGMT: 0)))
        #expect(stem == "Snaplite 2026-11-27 at 09.05.42")
    }

    @Test("Resolves same-second collisions with (2), (3) without deleting existing files")
    func collisionResolution() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tz = try #require(TimeZone(secondsFromGMT: 0))
        let fixedDate = Date(timeIntervalSince1970: 1_795_776_342) // deterministic second

        let first = FileNamer.nextAvailableURL(in: dir, date: fixedDate, timeZone: tz)
        #expect(first.lastPathComponent == "\(FileNamer.baseName(for: fixedDate, timeZone: tz)).png")
        let sentinel1 = Data("first".utf8)
        try sentinel1.write(to: first)

        let second = FileNamer.nextAvailableURL(in: dir, date: fixedDate, timeZone: tz)
        #expect(second.lastPathComponent == "\(FileNamer.baseName(for: fixedDate, timeZone: tz)) (2).png")
        let sentinel2 = Data("second".utf8)
        try sentinel2.write(to: second)

        let third = FileNamer.nextAvailableURL(in: dir, date: fixedDate, timeZone: tz)
        #expect(third.lastPathComponent == "\(FileNamer.baseName(for: fixedDate, timeZone: tz)) (3).png")

        // Verify existing files were untouched.
        #expect(try Data(contentsOf: first) == sentinel1)
        #expect(try Data(contentsOf: second) == sentinel2)
    }

    @Test("Creates missing intermediate directories and validates writability")
    func ensureWritableDirectory() throws {
        let base = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let nested = base.appendingPathComponent("a/b/c", isDirectory: true)
        let resolved = try FileNamer.ensureWritableDirectory(at: nested.path)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir))
        #expect(isDir.boolValue)

        // Empty path fails.
        #expect(throws: FileNamerError.emptyPath) {
            _ = try FileNamer.ensureWritableDirectory(at: "   ")
        }

        // Existing regular file fails with notADirectory.
        let fileURL = base.appendingPathComponent("regular-file")
        try Data("x".utf8).write(to: fileURL)
        #expect(throws: FileNamerError.notADirectory(fileURL.path)) {
            _ = try FileNamer.ensureWritableDirectory(at: fileURL.path)
        }

        // Read-only directory fails with notWritable (when not running as root).
        if geteuid() != 0 {
            let readOnlyDir = base.appendingPathComponent("readonly", isDirectory: true)
            try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
            }
            #expect(throws: FileNamerError.notWritable(readOnlyDir.path)) {
                _ = try FileNamer.ensureWritableDirectory(at: readOnlyDir.path)
            }
        }
    }
}
