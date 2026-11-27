import AppKit
import SwiftUI

/// Native macOS segmented control with equal-width segments filling its container edge-to-edge.
/// Uses `NSSegmentedControl` (`segmentDistribution = .fillEqually`) so macOS 26+ Liquid Glass
/// segments align flush with surrounding grouped card rows.
struct FullWidthSegmentedPicker<Value: Hashable>: NSViewRepresentable {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    func makeCoordinator() -> Coordinator {
        Coordinator(options: options, selection: $selection)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentStyle = .automatic
        control.segmentDistribution = .fillEqually
        control.controlSize = .regular
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        syncSelection(on: control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.options = options
        context.coordinator.selection = $selection
        if control.segmentCount != options.count {
            control.segmentCount = options.count
        }
        for (index, option) in options.enumerated() where control.label(forSegment: index) != option.title {
            control.setLabel(option.title, forSegment: index)
        }
        syncSelection(on: control)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width ?? intrinsic.width
        return CGSize(width: width, height: max(24, intrinsic.height))
    }

    private func syncSelection(on control: NSSegmentedControl) {
        if let index = options.firstIndex(where: { $0.value == selection }),
           control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var options: [(value: Value, title: String)]
        var selection: Binding<Value>

        init(options: [(value: Value, title: String)], selection: Binding<Value>) {
            self.options = options
            self.selection = selection
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let idx = sender.selectedSegment
            guard options.indices.contains(idx) else { return }
            selection.wrappedValue = options[idx].value
        }
    }
}

/// Behind-window translucency backdrop using AppKit's native `NSVisualEffectView`.
struct WindowBackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSVisualEffectView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }
}

/// Grouped section card surface (subtle adaptive fill + hairline border — NEVER glass,
/// following Apple's Liquid Glass HIG to avoid glass-on-glass stacking).
struct SectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let accentTint: Color?
    private let content: Content

    init(accentTint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accentTint = accentTint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .background {
                shape
                    .fill(cardFill)
                    .overlay {
                        if let accentTint {
                            shape.fill(accentTint.opacity(colorScheme == .dark ? 0.08 : 0.06))
                        }
                    }
            }
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 0.5)
            }
            .shadow(
                color: colorScheme == .dark ? .clear : Color.black.opacity(0.035),
                radius: 1.5,
                x: 0,
                y: 0.5
            )
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.065)
            : Color.white.opacity(0.66)
    }

    private var borderColor: Color {
        if let accentTint {
            return accentTint.opacity(colorScheme == .dark ? 0.28 : 0.24)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.085)
    }
}

/// Crisp uppercase/title section header aligned with grouped cards.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

/// Subtle inset hairline divider inside grouped cards.
struct CardDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.075))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }
}

/// Container that wraps interactive Liquid Glass controls in `GlassEffectContainer`
/// on macOS 26+ while passing through directly on macOS 14–25.
struct AdaptiveGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

/// Horizontal shake feedback for rejected hotkey input (pure `GeometryEffect`, no `@Animatable`).
struct HorizontalShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    var amplitude: CGFloat = 6
    var shakesPerUnit: CGFloat = 3

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offsetX = amplitude * sin(animatableData * .pi * 2 * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: offsetX, y: 0))
    }
}

// MARK: - Adaptive Liquid Glass View Modifiers (macOS 26+ -> macOS 14–25 fallback)

extension View {
    /// Applies `.buttonStyle(.glass)` / `.glassProminent` on macOS 26+, degrading cleanly
    /// to `.bordered` / `.borderedProminent` on macOS 14–25.
    @ViewBuilder
    func adaptiveGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// Applies an interactive Liquid Glass capsule on macOS 26+, falling back to
    /// `.regularMaterial` + subtle hairline border on macOS 14–25.
    @ViewBuilder
    func adaptiveGlassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        if #available(macOS 26, *) {
            let base: Glass = {
                var glass = Glass.regular
                if let tint {
                    glass = glass.tint(tint)
                }
                if interactive {
                    glass = glass.interactive()
                }
                return glass
            }()
            self.glassEffect(base, in: .capsule)
        } else {
            self
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    if let tint {
                        Capsule().fill(tint)
                    }
                }
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                }
        }
    }

    /// Applies a Liquid Glass rounded-rect keycap on macOS 26+, falling back to
    /// `.regularMaterial` + crisp hairline border on macOS 14–25.
    @ViewBuilder
    func adaptiveGlassKeycap(cornerRadius: CGFloat = 9, interactive: Bool = true) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            self
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5)
                }
        }
    }

    /// Attaches a `glassEffectID` on macOS 26+ for fluid morphing transitions.
    @ViewBuilder
    func adaptiveGlassEffectID<ID: Hashable & Sendable>(
        _ id: ID,
        in namespace: Namespace.ID
    ) -> some View {
        if #available(macOS 26, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Configures `glassEffectTransition` respecting Reduce Motion on macOS 26+.
    @ViewBuilder
    func adaptiveGlassTransition(reduceMotion: Bool) -> some View {
        if #available(macOS 26, *) {
            self.glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else {
            self
        }
    }
}
