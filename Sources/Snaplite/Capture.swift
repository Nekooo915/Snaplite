import AppKit

enum CaptureMode {
    case region, window
}

enum Capture {
    /// Run a capture matching the user's current settings. Designed to be
    /// callable from any thread; hops to a background queue internally so
    /// the UI never blocks on `screencapture`.
    static func run(mode: CaptureMode, config: Config) {
        DispatchQueue.global(qos: .userInitiated).async {
            performCapture(mode: mode, config: config)
        }
    }

    private static func performCapture(mode: CaptureMode, config: Config) {
        // We always need *some* path because `screencapture -i` writes a
        // file. If the user disabled "save to file", we use a temp path
        // and delete after copying to clipboard.
        let targetURL: URL
        if config.saveToFile {
            let dir = URL(fileURLWithPath: config.saveDir, isDirectory: true)
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            targetURL = dir.appendingPathComponent(timestampedFilename())
        } else {
            targetURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("snaplite-\(ProcessInfo.processInfo.processIdentifier).png")
        }

        let success = invokeScreencapture(mode: mode, output: targetURL)
        guard success else {
            // User cancelled (ESC), or the binary errored — either way we
            // have nothing to do. Don't surface anything noisy.
            return
        }

        if config.copyToClipboard {
            if !Clipboard.copyImage(at: targetURL) {
                NSLog("[snaplite] clipboard copy failed for \(targetURL.path)")
            }
        }
        if config.saveToFile {
            NSLog("[snaplite] saved: \(targetURL.path)")
        } else {
            try? FileManager.default.removeItem(at: targetURL)
        }
    }

    /// Returns true iff the file ended up on disk (i.e. the user actually
    /// completed a selection).
    private static func invokeScreencapture(mode: CaptureMode, output: URL) -> Bool {
        // screencapture refuses to overwrite when the user cancels, so we
        // detect "did the user complete a snip?" by checking for file
        // existence afterwards. Make sure no stale file lingers.
        try? FileManager.default.removeItem(at: output)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var args = ["-x", "-i"]                  // silent, interactive
        if mode == .window { args.append("-W") } // start in window-pick mode
        args.append(output.path)
        process.arguments = args

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[snaplite] failed to launch screencapture: \(error)")
            return false
        }
        return FileManager.default.fileExists(atPath: output.path)
    }

    private static func timestampedFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "snap-\(f.string(from: Date())).png"
    }
}
