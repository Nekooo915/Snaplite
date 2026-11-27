import AppKit

/// Pure AppKit floating Liquid Glass completion/error banner.
/// Creates a transient non-activating NSPanel on demand and releases it completely after fade-out.
@MainActor
enum Toast {
    private enum Style {
        case success
        case error

        var symbolName: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.circle.fill"
            }
        }

        var symbolColor: NSColor {
            switch self {
            case .success: .systemGreen
            case .error: .systemRed
            }
        }
    }

    private static var currentPanel: NSPanel?
    private static var dismissWorkItem: DispatchWorkItem?

    static func showSuccess(_ text: String) {
        show(text, style: .success)
    }

    static func showError(_ text: String) {
        show(text, style: .error)
    }

    static func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        if let panel = currentPanel {
            panel.orderOut(nil)
            currentPanel = nil
        }
    }

    // MARK: - Private

    private static func show(_ text: String, style: Style) {
        dismiss()

        let contentView = makeContentView(text: text, style: style)
        let fittingSize = contentView.fittingSize
        let height: CGFloat = max(34, ceil(fittingSize.height))
        let width: CGFloat = min(320, max(120, ceil(fittingSize.width)))
        let panelSize = NSSize(width: width, height: height)

        let panelFrame = targetFrame(for: panelSize)
        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = wrapInGlassContainer(contentView, size: panelSize)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion {
            var startFrame = panelFrame
            startFrame.origin.y += 6
            panel.setFrame(startFrame, display: false)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        currentPanel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(panelFrame, display: true)
            }
        }

        let workItem = DispatchWorkItem { [weak panel] in
            Task { @MainActor in
                guard let panel, currentPanel === panel else { return }
                fadeOut(panel)
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + 1.2, execute: workItem)
    }

    private static func fadeOut(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                if currentPanel === panel {
                    currentPanel = nil
                }
            }
        })
    }

    private static func makeContentView(text: String, style: Style) -> NSView {
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: style.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            iconView.image = symbol
        }
        iconView.contentTintColor = style.symbolColor

        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [iconView, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 16)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private static func wrapInGlassContainer(_ contentView: NSView, size: NSSize) -> NSView {
        let frame = NSRect(origin: .zero, size: size)
        let cornerRadius = size.height / 2

        if #available(macOS 26, *) {
            let glassView = NSGlassEffectView(frame: frame)
            glassView.style = .regular
            glassView.cornerRadius = cornerRadius
            contentView.translatesAutoresizingMaskIntoConstraints = true
            contentView.frame = frame
            contentView.autoresizingMask = [.width, .height]
            glassView.contentView = contentView
            return glassView
        } else {
            let effectView = NSVisualEffectView(frame: frame)
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = cornerRadius
            effectView.layer?.masksToBounds = true
            effectView.layer?.borderWidth = 0.5
            effectView.layer?.borderColor = NSColor.separatorColor.cgColor

            effectView.addSubview(contentView)
            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
                contentView.topAnchor.constraint(equalTo: effectView.topAnchor),
                contentView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
            ])
            return effectView
        }
    }

    private static func targetFrame(for size: NSSize) -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = round(visible.midX - size.width / 2)
        let y = round(visible.maxY - size.height - 14)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}
