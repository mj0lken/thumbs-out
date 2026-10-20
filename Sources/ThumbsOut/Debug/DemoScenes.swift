#if DEBUG
import SwiftUI
import ThumbsOutCore

/// Brand colours shared with the landing page (docs/site.css).
enum DemoPalette {
    static let paper = Color(red: 0.965, green: 0.953, blue: 0.925)
    static let ink = Color(red: 0.086, green: 0.075, blue: 0.059)
    static let wallpaperTop = Color(red: 0.86, green: 0.94, blue: 0.88)
    static let wallpaperBottom = Color(red: 0.86, green: 0.87, blue: 0.98)
}

/// A slice of macOS: wallpaper, menu bar with the thumb icon, the open panel, and a caption.
struct DemoCanvas: View {
    let controller: AwakeController
    let caption: String
    let step: String

    static let size = CGSize(width: 1100, height: 760)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [DemoPalette.wallpaperTop, DemoPalette.wallpaperBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            menuBar
            captionBlock
                .frame(width: 520, alignment: .leading)
                .padding(.leading, 64)
                .padding(.top, 250)
            MenuPanel(controller: controller) {}
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                .frame(width: Theme.panelWidth, height: 680, alignment: .top)
                .offset(x: Self.size.width - Theme.panelWidth - 120, y: 34)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private var menuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 13, weight: .semibold))
            Text("Cursor").font(.system(size: 13, weight: .bold))
            ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) {
                Text($0).font(.system(size: 13))
            }
            Spacer()
            Image(systemName: StatusPresentation.symbolName(
                for: controller.decision, lidSleepDisabled: controller.lidDecision.disablesLidSleep
            ))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(controller.decision.keepsAwake ? Theme.working : DemoPalette.ink)
            .frame(width: 30, height: 22)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
            Image(systemName: "battery.75percent").font(.system(size: 15))
            Text("Tue 15:42").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(DemoPalette.ink)
        .padding(.horizontal, 18)
        .frame(height: 26)
        .background(.white.opacity(0.55))
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.color(for: controller.decision) == Theme.idle ? DemoPalette.ink.opacity(0.5) : Theme.color(for: controller.decision))
                .textCase(.uppercase)
            Text(caption)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(DemoPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The 1280×640 image GitHub and social sites show when the repo or site is shared.
struct SocialPreview: View {
    let controller: AwakeController

    var body: some View {
        ZStack(alignment: .topLeading) {
            DemoPalette.paper
            Circle()
                .fill(Theme.working.opacity(0.16))
                .frame(width: 720, height: 720)
                .blur(radius: 60)
                .offset(x: 700, y: -160)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    ThumbBadge(color: Theme.working, size: 76)
                    Text("thumbs-out")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(DemoPalette.ink)
                }
                .padding(.bottom, 40)
                Text("Close the lid.\nYour agents keep going.")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(DemoPalette.ink)
                    .lineSpacing(2)
                    .padding(.bottom, 26)
                Text("Keeps your Mac awake while Claude Code, Codex,\nCursor and Antigravity run commands.")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(DemoPalette.ink.opacity(0.62))
                Spacer()
                Text("Free & open source · macOS menu bar app")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.working)
            }
            .padding(.leading, 72)
            .padding(.vertical, 64)

            MenuPanel(controller: controller) {}
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 30, y: 16)
                .scaleEffect(0.86, anchor: .topLeading)
                .rotationEffect(.degrees(3), anchor: .topLeading)
                .offset(x: 900, y: 70)
        }
        .frame(width: 1280, height: 640)
        .clipped()
    }
}
#endif
