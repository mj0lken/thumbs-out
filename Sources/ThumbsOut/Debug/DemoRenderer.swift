#if DEBUG
import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import ThumbsOutCore
import UniformTypeIdentifiers

/// `ThumbsOut --render-demo <dir>` stages a short story with the real menu bar panel and writes
/// demo.mp4 (landing page), demo.gif (README), demo-poster.png and social-preview.png.
@MainActor
enum DemoRenderer {
    private struct Scene {
        let step: String
        let caption: String
        let state: (Date) -> AwakeController.DemoState
        /// Grace-period minutes left at the start and end of the scene, to animate the countdown.
        var graceMinutes: (from: Double, to: Double)?
    }

    private static let fps: Int32 = 20
    private static let holdSeconds = 2.2
    private static let fadeFrames = 8
    private static let videoSize = CGSize(width: 1650, height: 1140)
    private static let gifSize = CGSize(width: 720, height: 497)

    /// `--render-site <dir>`: the panel in each tour state, the app icon and the social preview.
    static func renderSiteAssets(controller: AwakeController) async {
        guard let directory = outputDirectory(flag: "--render-site") else { return }
        await controller.rescanAgents()

        let others = [
            SleepBlocker(processName: "Music", reasons: ["com.apple.audio.BuiltInSpeakerDevice"], keepsDisplayOn: false),
            SleepBlocker(processName: "Zoom", reasons: ["Meeting in progress"], keepsDisplayOn: true),
        ]
        let states: [(String, Int, Double?)] = [("idle", 0, nil), ("working", 1, nil), ("grace", 4, 3.4), ("lid", 3, nil)]
        do {
            for (name, index, graceMinutes) in states {
                let now = Date()
                var state = scenes[index].state(now)
                if let graceMinutes { state.decision = .gracePeriod(until: now.addingTimeInterval(graceMinutes * 60)) }
                if name != "idle" { state.blockers = others }
                controller.applyDemo(state)
                let panel = MenuPanel(controller: controller) {}
                    .background(Color(white: 0.965), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(1)
                if let image = SnapshotRenderer.bitmap(of: panel, transparent: true)?.cgImage {
                    try writePNG(image, to: directory.appendingPathComponent("panel-\(name).png"))
                }
            }
            for (name, decision, lid) in [("menubar-idle", AwakeDecision.sleepAllowed, false),
                                          ("menubar-awake", AwakeDecision.agentsActive([.claudeCode]), false),
                                          ("menubar-lid", AwakeDecision.agentsActive([.claudeCode]), true)] {
                let glyph = MenuBarGlyph.image(for: decision, lidSleepDisabled: lid)
                if let cg = glyph.cgImage(forProposedRect: nil, context: nil, hints: [.ctm: AffineTransform(scale: 4)]) {
                    try writePNG(cg, to: directory.appendingPathComponent("\(name).png"))
                }
            }
            if let icon = SnapshotRenderer.bitmap(of: AppIconArt(), transparent: true)?.cgImage {
                try writePNG(scaled(icon, CGSize(width: 1024, height: 1024)), to: directory.appendingPathComponent("app-icon-1024.png"))
            }
            try writeSocialPreview(controller: controller, to: directory)
        } catch {
            FileHandle.standardError.write(Data("Site rendering failed: \(error)\n".utf8))
            SnapshotRenderer.finish(status: 1)
        }
        SnapshotRenderer.finish(status: 0)
    }

    static func runIfRequested(controller: AwakeController) async {
        guard let directory = outputDirectory(flag: "--render-demo") else { return }
        await controller.rescanAgents()

        var videoFrames: [(CGImage, Int)] = []
        var gifFrames: [(CGImage, Double)] = []
        var previous: (video: CGImage, gif: CGImage)?
        var poster: CGImage?

        for (index, scene) in scenes.enumerated() {
            let shots = render(scene, controller: controller)
            if index == 1 { poster = shots.first }
            guard let first = shots.first else { continue }
            if let previous {
                for frame in 1...fadeFrames {
                    let t = CGFloat(frame) / CGFloat(fadeFrames + 1)
                    videoFrames.append((blend(previous.video, first, t, videoSize), 1))
                    if frame % 3 == 0 {
                        gifFrames.append((blend(scaled(previous.video, gifSize), scaled(first, gifSize), t, gifSize), 0.08))
                    }
                }
            }
            let framesPerShot = max(1, Int(holdSeconds * Double(fps)) / shots.count)
            for shot in shots {
                videoFrames.append((shot, framesPerShot))
                gifFrames.append((scaled(shot, gifSize), Double(framesPerShot) / Double(fps)))
            }
            previous = (shots.last!, shots.last!)
        }

        do {
            try await writeMP4(videoFrames, size: videoSize, to: directory.appendingPathComponent("demo.mp4"))
            try writeGIF(gifFrames, to: directory.appendingPathComponent("demo.gif"))
            if let poster { try writePNG(poster, to: directory.appendingPathComponent("demo-poster.png")) }
            try writeSocialPreview(controller: controller, to: directory)
        } catch {
            FileHandle.standardError.write(Data("Demo rendering failed: \(error)\n".utf8))
            SnapshotRenderer.finish(status: 1)
        }
        SnapshotRenderer.finish(status: 0)
    }

    /// The directory after `flag` on the command line, created if needed.
    static func outputDirectory(flag: String) -> URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Claude Code working (green) next to Cursor open but idle (blue).
    private static func writeSocialPreview(controller: AwakeController, to directory: URL) throws {
        controller.applyDemo(scenes[1].state(Date()))
        if let social = SnapshotRenderer.bitmap(of: SocialPreview(controller: controller))?.cgImage {
            try writePNG(scaled(social, CGSize(width: 1280, height: 640)), to: directory.appendingPathComponent("social-preview.png"))
        }
    }

    // MARK: Storyboard

    private static var scenes: [Scene] {
        let claude = DetectedCommand(agent: .claudeCode, pid: 1, summary: "npm test")
        let cursor = DetectedCommand(agent: .cursor, pid: 2, summary: "cargo build --release")
        let running: Set<Agent> = [.claudeCode, .cursor]
        return [
            Scene(step: "Idle", caption: "Agents idle.\nYour Mac can sleep.") { now in
                .init(decision: .sleepAllowed, commands: [], running: running, lidActive: false,
                      stats: stats(todayMinutes: 134, weekMinutes: 580, currentMinutes: nil, now: now))
            },
            Scene(step: "Working", caption: "Claude Code runs a command.\nYour Mac stays awake.") { now in
                .init(decision: .agentsActive([.claudeCode]), commands: [claude], running: running, lidActive: false,
                      stats: stats(todayMinutes: 135, weekMinutes: 581, currentMinutes: 1, now: now))
            },
            Scene(step: "Two agents", caption: "Cursor joins in.\nBoth are covered.") { now in
                .init(decision: .agentsActive([.claudeCode, .cursor]), commands: [claude, cursor], running: running,
                      lidActive: false, stats: stats(todayMinutes: 138, weekMinutes: 584, currentMinutes: 4, now: now))
            },
            Scene(step: "Lid closed", caption: "Close the lid.\nThey keep going.") { now in
                .init(decision: .agentsActive([.claudeCode, .cursor]), commands: [claude, cursor], running: running,
                      lidActive: true, stats: stats(todayMinutes: 143, weekMinutes: 589, currentMinutes: 9, now: now))
            },
            Scene(step: "Grace period", caption: "Done. A grace period\ncovers the thinking time.", state: { now in
                .init(decision: .gracePeriod(until: now.addingTimeInterval(300)), commands: [], running: running,
                      lidActive: true, stats: stats(todayMinutes: 148, weekMinutes: 594, currentMinutes: 14, now: now))
            }, graceMinutes: (from: 5, to: 0.6)),
            Scene(step: "Sleep", caption: "Then your Mac\ncan sleep again.") { now in
                .init(decision: .sleepAllowed, commands: [], running: running, lidActive: false,
                      stats: stats(todayMinutes: 153, weekMinutes: 599, currentMinutes: nil, now: now))
            },
        ]
    }

    /// Renders a scene: one image, or a short countdown sequence for the grace period.
    private static func render(_ scene: Scene, controller: AwakeController) -> [CGImage] {
        let steps = scene.graceMinutes == nil ? 1 : 10
        return (0..<steps).compactMap { index in
            let now = Date()
            var state = scene.state(now)
            if let grace = scene.graceMinutes {
                let minutes = grace.from + (grace.to - grace.from) * Double(index) / Double(steps - 1)
                state.decision = .gracePeriod(until: now.addingTimeInterval(minutes * 60))
            }
            controller.applyDemo(state)
            let canvas = DemoCanvas(controller: controller, caption: scene.caption, step: scene.step)
            return SnapshotRenderer.bitmap(of: canvas, settle: 0.15)?.cgImage.map { scaled($0, videoSize) }
        }
    }

    /// Builds stats whose today / 7-day / current-stretch numbers match the story.
    static func stats(todayMinutes: Int, weekMinutes: Int, currentMinutes: Int?, now: Date) -> AwakeStats {
        var stats = AwakeStats()
        func stretch(start: Date, minutes: Int, endsAwake: Bool) {
            for minute in 0...minutes {
                let tick = start.addingTimeInterval(Double(minute) * 60)
                stats = stats.recording(keepsAwake: endsAwake || minute < minutes, at: tick,
                                        uptime: tick.timeIntervalSince1970, maxCountedGap: 90)
            }
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let current = currentMinutes ?? 0
        stretch(start: today.addingTimeInterval(-2 * 86_400 + 9 * 3_600), minutes: weekMinutes - todayMinutes, endsAwake: false)
        stretch(start: today.addingTimeInterval(9 * 3_600), minutes: todayMinutes - current, endsAwake: false)
        if let currentMinutes {
            stretch(start: now.addingTimeInterval(-Double(currentMinutes) * 60), minutes: currentMinutes, endsAwake: true)
        }
        return stats
    }

    // MARK: Image helpers

    private static func context(_ size: CGSize) -> CGContext? {
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        context?.interpolationQuality = .high
        return context
    }

    static func scaled(_ image: CGImage, _ size: CGSize) -> CGImage {
        guard let context = context(size) else { return image }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? image
    }

    private static func blend(_ from: CGImage, _ to: CGImage, _ t: CGFloat, _ size: CGSize) -> CGImage {
        guard let context = context(size) else { return to }
        context.draw(from, in: CGRect(origin: .zero, size: size))
        context.setAlpha(t)
        context.draw(to, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? to
    }

    // MARK: Encoding

    private static func writeMP4(_ frames: [(CGImage, Int)], size: CGSize, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_500_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        var index: Int64 = 0
        for (image, count) in frames {
            guard let pool = adaptor.pixelBufferPool, let buffer = pixelBuffer(image, size: size, pool: pool) else { continue }
            for _ in 0..<count {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                adaptor.append(buffer, withPresentationTime: CMTime(value: index, timescale: fps))
                index += 1
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    private static func pixelBuffer(_ image: CGImage, size: CGSize, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }

    private static func writeGIF(_ frames: [(CGImage, Double)], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for (image, delay) in frames {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay,
                ],
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
#endif
