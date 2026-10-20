import SwiftUI
import ThumbsOutCore

/// Design tokens. Colour is semantic: green = an agent is working, amber = grace period,
/// indigo = lid-closed mode, grey = idle.
enum Theme {
    static let working = Color(red: 0.19, green: 0.78, blue: 0.40)
    static let grace = Color(red: 1.0, green: 0.62, blue: 0.05)
    static let lid = Color.indigo
    static let running = Color.blue
    static let idle = Color.secondary

    static let panelWidth: CGFloat = 340
    static let panelPadding: CGFloat = 14
    static let tileRadius: CGFloat = 12
    static let tilePadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 10

    static let tileFill = Color.primary.opacity(0.055)
    static let tileStroke = Color.primary.opacity(0.07)

    static func color(for decision: AwakeDecision) -> Color {
        switch decision {
        case .agentsActive, .manual: working
        case .gracePeriod: grace
        case .sleepAllowed: idle
        }
    }

    static func color(for status: AgentStatus) -> Color {
        switch status {
        case .working: working
        case .running: running
        case .installed, .notFound: idle
        }
    }
}

extension Font {
    static let heroTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let panelTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let tileTitle = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let statValue = Font.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()
    static let sectionLabel = Font.system(size: 10, weight: .semibold).smallCaps()
}

/// A rounded, softly filled surface used for every block in the panel.
struct TileBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.tilePadding)
            .background(Theme.tileFill, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .strokeBorder(Theme.tileStroke, lineWidth: 0.5)
            )
    }
}

extension View {
    func tile() -> some View { modifier(TileBackground()) }
}

/// The app's badge: a thumbs-up on a tinted rounded square.
struct ThumbBadge: View {
    let color: Color
    var size: CGFloat = 40
    var isFilled = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: isFilled ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: color.opacity(0.35), radius: size * 0.15, y: size * 0.05)
    }
}

/// Icon-only button with a designed hover state.
struct IconButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : isHovering ? 0.09 : 0))
            )
            .contentShape(Circle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Title, optional subtitle and a trailing switch: the standard row inside a tile.
struct SwitchRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var tint: Color = Theme.working

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.tileTitle)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            AppSwitch(title: title, isOn: $isOn, tint: tint)
        }
        .accessibilityElement(children: .combine)
    }
}

extension EnvironmentValues {
    /// Set by the debug snapshot renderer: native switches only show their colour while the app is
    /// frontmost, so offscreen captures draw a replica instead.
    @Entry var rendersStaticControls = false
}

/// A switch that's native in the app and drawn by hand in offscreen captures.
struct AppSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var tint: Color = Theme.working
    var isSmall = false

    @Environment(\.rendersStaticControls) private var rendersStatic

    var body: some View {
        if rendersStatic {
            let width: CGFloat = isSmall ? 32 : 38
            let height: CGFloat = isSmall ? 18 : 22
            Capsule()
                .fill(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Color.primary.opacity(0.14)))
                .frame(width: width, height: height)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                        .padding(2)
                }
                .accessibilityLabel(title)
        } else {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(isSmall ? .small : .regular)
                .tint(tint)
        }
    }
}

/// A labelled switch row for grouped forms, using `AppSwitch` so captures look right too.
struct FormSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var tint: Color = Theme.working

    @Environment(\.rendersStaticControls) private var rendersStatic

    var body: some View {
        if rendersStatic {
            LabeledContent(title) { AppSwitch(title: title, isOn: $isOn, tint: tint) }
        } else {
            Toggle(title, isOn: $isOn).tint(tint)
        }
    }
}
