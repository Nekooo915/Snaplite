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

    /// Draws Snaplite's dashed selection frame with a solid top-left rounded anchor
    /// centered inside an 18×18 pt template image.
    private static func makeTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Solid rounded top-left anchor square (non-flipped: top is y = 15.75).
            let anchorRect = NSRect(x: 2.25, y: 11.25, width: 4.5, height: 4.5)
            NSBezierPath(roundedRect: anchorRect, xRadius: 1.0, yRadius: 1.0).fill()

            // Rounded corner L-brackets (top-right, bottom-right, bottom-left).
            let strokeWidth: CGFloat = 1.4
            let corners = NSBezierPath()
            corners.lineWidth = strokeWidth
            corners.lineCapStyle = .round
            corners.lineJoinStyle = .round

            // Top-right corner
            corners.move(to: NSPoint(x: 13.85, y: 15.05))
            corners.line(to: NSPoint(x: 15.05, y: 15.05))
            corners.line(to: NSPoint(x: 15.05, y: 13.85))

            // Bottom-right corner
            corners.move(to: NSPoint(x: 15.05, y: 4.15))
            corners.line(to: NSPoint(x: 15.05, y: 2.95))
            corners.line(to: NSPoint(x: 13.85, y: 2.95))

            // Bottom-left corner
            corners.move(to: NSPoint(x: 4.15, y: 2.95))
            corners.line(to: NSPoint(x: 2.95, y: 2.95))
            corners.line(to: NSPoint(x: 2.95, y: 4.15))
            corners.stroke()

            // Evenly spaced rounded dashes along all four edges.
            let dashThickness: CGFloat = 1.4
            let dashRadius: CGFloat = 0.55

            // Top edge (2 dashes between anchor and top-right bracket)
            for x in [7.82, 10.49] as [CGFloat] {
                let rect = NSRect(x: x, y: 14.35, width: 1.6, height: dashThickness)
                NSBezierPath(roundedRect: rect, xRadius: dashRadius, yRadius: dashRadius).fill()
            }

            // Left edge (2 dashes between bottom-left bracket and anchor)
            for y in [5.92, 8.59] as [CGFloat] {
                let rect = NSRect(x: 2.25, y: y, width: dashThickness, height: 1.6)
                NSBezierPath(roundedRect: rect, xRadius: dashRadius, yRadius: dashRadius).fill()
            }

            // Right edge (3 dashes between bottom-right and top-right brackets)
            for y in [5.875, 8.30, 10.725] as [CGFloat] {
                let rect = NSRect(x: 14.35, y: y, width: dashThickness, height: 1.4)
                NSBezierPath(roundedRect: rect, xRadius: dashRadius, yRadius: dashRadius).fill()
            }

            // Bottom edge (3 dashes between bottom-left and bottom-right brackets)
            for x in [5.875, 8.30, 10.725] as [CGFloat] {
                let rect = NSRect(x: x, y: 2.25, width: 1.4, height: dashThickness)
                NSBezierPath(roundedRect: rect, xRadius: dashRadius, yRadius: dashRadius).fill()
            }

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = Strings.current().appTitle
        return image
    }
}
