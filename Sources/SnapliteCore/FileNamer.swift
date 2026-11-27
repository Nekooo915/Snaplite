import Foundation
import os

/// Errors thrown while preparing the screenshot destination directory.
public enum FileNamerError: Error, Equatable, Sendable {
    case emptyPath
    case notADirectory(String)
    case notWritable(String)
    case creationFailed(String)
}

/// Generates collision-free screenshot filenames (`Snaplite yyyy-MM-dd at HH.mm.ss.png`)
/// and ensures the destination directory exists and is writable.
public enum FileNamer {
    private static let formatterLock = OSAllocatedUnfairLock<DateFormatter>(initialState: {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }())

    /// Formats the base filename stem without extension, e.g. `"Snaplite 2026-11-27 at 14.05.09"`.
    public static func baseName(
        for date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let timestamp = formatterLock.withLock { formatter -> String in
            formatter.timeZone = timeZone
            return formatter.string(from: date)
        }
        return "Snaplite \(timestamp)"
    }

    /// Returns a URL inside `directory` that does not currently exist on disk.
    /// Appends ` (2)`, ` (3)`, … on same-second collisions and never deletes or overwrites files.
    public static func nextAvailableURL(
        in directory: URL,
        date: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) -> URL {
        let stem = baseName(for: date, timeZone: timeZone)
        let first = directory.appendingPathComponent("\(stem).png")
        if !fileManager.fileExists(atPath: first.path) {
            return first
        }

        var suffix = 2
        while suffix <= 9_999 {
            let candidate = directory.appendingPathComponent("\(stem) (\(suffix)).png")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
        return directory.appendingPathComponent("\(stem) (\(UUID().uuidString)).png")
    }

    /// Ensures `path` exists as a writable directory, creating intermediate directories if needed.
    public static func ensureWritableDirectory(
        at path: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FileNamerError.emptyPath
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw FileNamerError.notADirectory(expanded)
            }
        } else {
            do {
                try fileManager.createDirectory(
                    atPath: expanded,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw FileNamerError.creationFailed(expanded)
            }
        }

        guard fileManager.isWritableFile(atPath: expanded) else {
            throw FileNamerError.notWritable(expanded)
        }

        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}
