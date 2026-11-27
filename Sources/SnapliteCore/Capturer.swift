import AppKit

/// Runs macOS interactive area/window capture via `/usr/sbin/screencapture -i -x`
/// without blocking any GCD thread and with zero image bytes entering Snaplite in `.copy` mode.
@MainActor
public final class Capturer {
    private var inFlight: Process?
    private let permissionCheck: @MainActor () -> Bool
    private let pasteboard: NSPasteboard
    private let stringsProvider: @MainActor () -> Strings

    /// Invoked when Screen Recording permission is missing.
    public var onPermissionRequired: (@MainActor () -> Void)?

    /// Invoked when a capture completes. `URL` is non-nil for `.save` and `.both`, nil for `.copy`.
    public var onSuccess: (@MainActor (OutputMode, URL?) -> Void)?

    /// Invoked with a concise localized message when capture cannot start or fails to prepare storage.
    public var onError: (@MainActor (String) -> Void)?

    /// True while an interactive `screencapture` session is active.
    public var isCapturing: Bool {
        inFlight != nil
    }

    public init(
        permissionCheck: @escaping @MainActor () -> Bool = { Permission.isGranted },
        pasteboard: NSPasteboard = .general,
        stringsProvider: @escaping @MainActor () -> Strings = { Strings.current() }
    ) {
        self.permissionCheck = permissionCheck
        self.pasteboard = pasteboard
        self.stringsProvider = stringsProvider
    }

    /// Starts a capture using the current values in `preferences`.
    public func capture(using preferences: Preferences) {
        capture(mode: preferences.outputMode, saveDir: preferences.saveDir)
    }

    /// Starts an interactive capture with the given `mode` and destination directory.
    /// Re-entrant calls while a capture is already running are ignored.
    public func capture(mode: OutputMode, saveDir: String) {
        guard inFlight == nil else { return }

        guard permissionCheck() else {
            onPermissionRequired?()
            return
        }

        switch mode {
        case .copy:
            startCopyOnlyCapture()
        case .save, .both:
            startFileCapture(mode: mode, saveDir: saveDir)
        }
    }

    /// Terminates an in-flight capture process if one is running.
    public func cancel() {
        inFlight?.terminate()
    }

    // MARK: - Private

    private func startCopyOnlyCapture() {
        let beforeChangeCount = pasteboard.changeCount
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-c"]
        process.terminationHandler = { [weak self] finishedProcess in
            let exitCode = finishedProcess.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = nil
                guard exitCode == 0, self.pasteboard.changeCount != beforeChangeCount else {
                    return
                }
                self.onSuccess?(.copy, nil)
            }
        }

        launch(process)
    }

    private func startFileCapture(mode: OutputMode, saveDir: String) {
        let dirURL: URL
        do {
            dirURL = try FileNamer.ensureWritableDirectory(at: saveDir)
        } catch {
            onError?(stringsProvider().errorSaveFolderUnavailable)
            return
        }

        let targetURL = FileNamer.nextAvailableURL(in: dirURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", targetURL.path]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlight = nil
                guard FileManager.default.fileExists(atPath: targetURL.path) else {
                    // User cancelled with Esc — silent no-op.
                    return
                }
                if mode == .both {
                    _ = Pasteboard.writePNG(contentsOf: targetURL, to: self.pasteboard)
                }
                self.onSuccess?(mode, targetURL)
            }
        }

        launch(process)
    }

    private func launch(_ process: Process) {
        inFlight = process
        do {
            try process.run()
        } catch {
            inFlight = nil
            onError?(stringsProvider().errorCaptureFailed)
        }
    }
}
