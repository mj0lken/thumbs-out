import AppKit
import SwiftUI
import ThumbsOutCore

/// The thumbs-out mark: a standard thumbs-up, drawn as an outline. Geometry lives on a 24-unit
/// icon grid (y down) and is shared by the badge, the menu bar glyph and the app icon.
/// docs/favicon.svg and the site use the same paths.
enum ThumbMark {
    /// The cuff, to the left of the hand.
    static let cuff = Path(roundedRect: CGRect(x: 2.2, y: 10.2, width: 3.6, height: 11), cornerRadius: 1)

    /// The hand: thumb up, fingers curled to the right.
    static let hand: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 7.4, y: 21.2))
        path.addLine(to: CGPoint(x: 7.4, y: 11.2))
        path.addLine(to: CGPoint(x: 11, y: 3.6))
        path.addCurve(to: CGPoint(x: 13.5, y: 4.2), control1: CGPoint(x: 11.6, y: 2.4), control2: CGPoint(x: 13.5, y: 2.7))
        path.addLine(to: CGPoint(x: 13, y: 9.6))
        path.addLine(to: CGPoint(x: 19, y: 9.6))
        path.addCurve(to: CGPoint(x: 20.9, y: 12.2), control1: CGPoint(x: 20.3, y: 9.6), control2: CGPoint(x: 21.3, y: 10.9))
        path.addLine(to: CGPoint(x: 19, y: 19.5))
        path.addCurve(to: CGPoint(x: 16.8, y: 21.2), control1: CGPoint(x: 18.7, y: 20.6), control2: CGPoint(x: 17.8, y: 21.2))
        path.closeSubpath()
        return path
    }()

    static let outline: Path = {
        var path = cuff
        path.addPath(hand)
        return path
    }()

    /// The drawing's extent on the grid, used to centre it.
    static let bounds = CGRect(x: 2.2, y: 2.4, width: 18.7, height: 18.8)

    /// Maps the grid into `rect`, centred, with the drawing taking `fraction` of the rect's width.
    static func transform(into rect: CGRect, fraction: CGFloat) -> CGAffineTransform {
        let scale = rect.width * fraction / max(bounds.width, bounds.height)
        return CGAffineTransform(translationX: rect.midX - bounds.midX * scale, y: rect.midY - bounds.midY * scale)
            .scaledBy(x: scale, y: scale)
    }
}

/// The outlined thumbs-up, scaled into the view's frame.
struct ThumbMarkShape: Shape {
    var part: Path = ThumbMark.outline
    var fraction: CGFloat = 0.56

    func path(in rect: CGRect) -> Path {
        part.applying(ThumbMark.transform(into: rect, fraction: fraction))
    }
}

/// The app's badge: night background with the outlined thumb in the colour of the current state.
struct ThumbBadge: View {
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Theme.night)
            ThumbMarkShape()
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.052, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .compositingGroup() // One shadow for the whole mark, not one per layer.
        .shadow(color: Theme.night.opacity(0.25), radius: size * 0.12, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

/// Template images for the menu bar: an outline while the Mac may sleep, filled while it's kept
/// awake, and a small dot when lid-closed mode is holding it awake.
@MainActor
enum MenuBarGlyph {
    private static var cache: [String: NSImage] = [:]

    static func image(for decision: AwakeDecision, lidSleepDisabled: Bool) -> NSImage {
        let filled = decision.keepsAwake
        let key = "\(filled)-\(lidSleepDisabled)"
        if let cached = cache[key] { return cached }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let transform = ThumbMark.transform(into: CGRect(origin: .zero, size: size), fraction: 0.86)
            if filled {
                // Cuff and hand are separate shapes, so the gap between them stays visible.
                context.addPath(ThumbMark.cuff.applying(transform).cgPath)
                context.addPath(ThumbMark.hand.applying(transform).cgPath)
                context.fillPath()
            } else {
                context.addPath(ThumbMark.outline.applying(transform).cgPath)
                context.setLineWidth(1.3)
                context.setLineJoin(.round)
                context.strokePath()
            }
            if lidSleepDisabled {
                // The thumb leaves the top-right corner empty; the dot sits there.
                context.fillEllipse(in: CGRect(x: 13, y: 1, width: 4.5, height: 4.5))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = filled ? "thumbs-out: keeping your Mac awake" : "thumbs-out: sleep allowed"
        cache[key] = image
        return image
    }
}
