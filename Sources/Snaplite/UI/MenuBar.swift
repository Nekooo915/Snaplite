import AppKit
import SnapliteCore

/// Pure AppKit menu bar status item with a vector template icon and a lazy NSMenu
/// rebuilt only when the user clicks the icon.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let preferences: Preferences
    private let onCapture: @MainActor () -> Void
    private let onOpenFolder: @MainActor () -> Void
    private let onOpenSettings: @MainActor () -> Void
    private let onOpenPermission: @MainActor () -> Void
    private let onQuit: @MainActor () -> Void

    private var statusItem: NSStatusItem?
    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        return menu
    }()

    init(
        preferences: Preferences,
        onCapture: @escaping @MainActor () -> Void,
        onOpenFolder: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void,
        onOpenPermission: @escaping @MainActor () -> Void,
        onQuit: @escaping @MainActor () -> Void
    ) {
        self.preferences = preferences
        self.onCapture = onCapture
        self.onOpenFolder = onOpenFolder
        self.onOpenSettings = onOpenSettings
        self.onOpenPermission = onOpenPermission
        self.onQuit = onQuit
        super.init()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.image = Self.makeTemplateIcon()
                button.imagePosition = .imageOnly
                button.toolTip = Strings.current().appTitle
            }
            item.menu = menu
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let strings = Strings.current()

        if !Permission.isGranted {
            let permItem = makeMenuItem(
                title: strings.menuPermissionRequired,
                action: #selector(handleOpenPermission),
                symbolName: "exclamationmark.triangle"
            )
            menu.addItem(permItem)
            menu.addItem(.separator())
        }

        let (keyEquivalent, modifierMask) = HotkeyDisplay.menuKeyEquivalent(for: preferences.hotkey)
        let captureItem = makeMenuItem(
            title: strings.menuCaptureArea,
            action: #selector(handleCapture),
            keyEquivalent: keyEquivalent,
            modifierMask: modifierMask,
            symbolName: "viewfinder"
        )
        menu.addItem(captureItem)

        if preferences.outputMode != .copy {
            let folderItem = makeMenuItem(
                title: strings.menuOpenFolder,
                action: #selector(handleOpenFolder),
                symbolName: "folder"
            )
            menu.addItem(folderItem)
        }

        menu.addItem(.separator())

        let settingsItem = makeMenuItem(
            title: strings.menuSettings,
            action: #selector(handleOpenSettings),
            keyEquivalent: ",",
            modifierMask: [.command],
            symbolName: "gearshape"
        )
        menu.addItem(settingsItem)

        let quitItem = makeMenuItem(
            title: strings.menuQuit,
            action: #selector(handleQuit),
            keyEquivalent: "q",
            modifierMask: [.command]
        )
        menu.addItem(quitItem)
    }

    // MARK: - Menu Helpers

    private func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [],
        symbolName: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask
        item.target = self
        if let symbolName,
           let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            symbol.isTemplate = true
            item.image = symbol
        }
        return item
    }

    @objc private func handleOpenPermission() {
        onOpenPermission()
    }

    @objc private func handleCapture() {
        onCapture()
    }

    @objc private func handleOpenFolder() {
        onOpenFolder()
    }

    @objc private func handleOpenSettings() {
        onOpenSettings()
    }

    @objc private func handleQuit() {
        onQuit()
    }

    // MARK: - 18pt Vector Template Icon

    /// Draws Snaplite's "drag corners" motif — two rounded corner brackets around a
    /// translucent capture pane — centered inside an 18×18 pt template image.
    /// Geometry is authored y-down (SVG) and mirrored here into AppKit's
    /// unflipped space (y' = 18 - y).
    private static func makeTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            // Pane: rect (6, 6, 6, 6) rx 1 at 38% alpha (symmetric, so unchanged by the flip).
            NSColor.black.withAlphaComponent(0.38).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 6, y: 6, width: 6, height: 6),
                xRadius: 1,
                yRadius: 1
            ).fill()

            NSColor.black.setStroke()
            let corners = NSBezierPath()
            corners.lineWidth = 2
            corners.lineCapStyle = .round
            corners.lineJoinStyle = .round

            // Stroke centerlines sit on x/y = 3 and 15 so the 2 pt strokes cover
            // whole pixels (2…4, 14…16) at both @1x and @2x.
            // Top-left: M3 8.6 V4.4 Q3 3 4.4 3 H8.6
            corners.move(to: NSPoint(x: 3, y: 9.4))
            corners.line(to: NSPoint(x: 3, y: 13.6))
            corners.curve(to: NSPoint(x: 4.4, y: 15), controlPoint: NSPoint(x: 3, y: 15))
            corners.line(to: NSPoint(x: 8.6, y: 15))

            // Bottom-right: M15 9.4 V13.6 Q15 15 13.6 15 H9.4
            corners.move(to: NSPoint(x: 15, y: 8.6))
            corners.line(to: NSPoint(x: 15, y: 4.4))
            corners.curve(to: NSPoint(x: 13.6, y: 3), controlPoint: NSPoint(x: 15, y: 3))
            corners.line(to: NSPoint(x: 9.4, y: 3))
            corners.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = Strings.current().appTitle
        return image
    }
}
