import AppKit
import SwiftUI
import ThumbsOutCore

/// The thumbs-out mark: a classic thumbs-up seen from the knuckle side, with the four knuckles
/// stacked down the front of the fist. Geometry lives in a 100×100 box (y down) and is shared by
/// the badge, the menu bar glyph and the app icon. docs/favicon.svg and the site use the same shapes.
enum ThumbMark {
    /// The thumb leans 8° forward around this point.
    private static let lean = CGAffineTransform(translationX: 39, y: 30).rotated(by: .pi / 22.5).translatedBy(x: -39, y: -30)

    /// The fist, cut off by the bottom of the badge, with four knuckle bumps on its front edge.
    static let fist: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 24, y: 104))
        path.addLine(to: CGPoint(x: 24, y: 54))
        path.addQuadCurve(to: CGPoint(x: 36, y: 42), control: CGPoint(x: 24, y: 42))
        path.addLine(to: CGPoint(x: 66, y: 42))
        path.addQuadCurve(to: CGPoint(x: 66, y: 57), control: CGPoint(x: 74, y: 49.5))
        path.addQuadCurve(to: CGPoint(x: 66, y: 72), control: CGPoint(x: 75, y: 64.5))
        path.addQuadCurve(to: CGPoint(x: 66, y: 87), control: CGPoint(x: 75, y: 79.5))
        path.addCurve(to: CGPoint(x: 66, y: 104), control1: CGPoint(x: 77.3, y: 87), control2: CGPoint(x: 77.3, y: 104))
        path.closeSubpath()
        return path
    }()

    static let thumb = Path(roundedRect: CGRect(x: 26, y: 2, width: 26, height: 56), cornerRadius: 13).applying(lean)
    static let nail = Path(roundedRect: CGRect(x: 31, y: 6, width: 16, height: 18), cornerRadius: 7).applying(lean)

    /// The creases between the curled fingers.
    static let fingers: Path = {
        var path = Path()
        for y in [57.0, 72.0, 87.0] {
            path.move(to: CGPoint(x: 44, y: y))
            path.addLine(to: CGPoint(x: 64, y: y))
        }
        return path
    }()

    /// Fist and thumb merged into one outline, for single-colour uses like the menu bar.
    static let silhouette = Path(fist.cgPath.union(thumb.cgPath))
}

/// Scales one part of the mark from its 100-unit box into the view's frame.
struct ThumbMarkShape: Shape {
    let part: Path

    func path(in rect: CGRect) -> Path {
        part.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 100))
    }
}

/// The app's badge: night background, with the hand in the colour of the current state.
struct ThumbBadge: View {
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        let badge = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        let line = StrokeStyle(lineWidth: size * 0.035, lineCap: .round)
        ZStack {
            badge.fill(Theme.night)
            ZStack {
                ThumbMarkShape(part: ThumbMark.fist).fill(color)
                ThumbMarkShape(part: ThumbMark.fingers).stroke(Theme.night.opacity(0.3), style: line)
                // A night outline separates the thumb from the fist.
                ThumbMarkShape(part: ThumbMark.thumb).stroke(Theme.night, style: line)
                ThumbMarkShape(part: ThumbMark.thumb).fill(color)
                ThumbMarkShape(part: ThumbMark.nail).fill(.white.opacity(0.7))
            }
            .clipShape(badge)
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
            let bounds = ThumbMark.silhouette.boundingRect
            let scale = 16.5 / max(bounds.width, bounds.height)
            let transform = CGAffineTransform(translationX: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -bounds.minX, y: -bounds.minY)
            if filled {
                context.addPath(ThumbMark.fist.applying(transform).cgPath)
                context.fillPath()
                // Cut a thin gap around the thumb so it reads apart from the fist.
                let thumb = ThumbMark.thumb.applying(transform).cgPath
                context.setBlendMode(.clear)
                context.setLineWidth(1.6)
                context.addPath(thumb)
                context.strokePath()
                context.setBlendMode(.normal)
                context.addPath(thumb)
                context.fillPath()
            } else {
                context.addPath(ThumbMark.silhouette.applying(transform).cgPath)
                context.setLineWidth(1.4)
                context.setLineJoin(.round)
                context.strokePath()
            }
            if lidSleepDisabled {
                // The glyph leaves the top-right corner empty; the dot sits there.
                context.fillEllipse(in: CGRect(x: 12.5, y: 1, width: 5, height: 5))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = filled ? "thumbs-out: keeping your Mac awake" : "thumbs-out: sleep allowed"
        cache[key] = image
        return image
    }
}
