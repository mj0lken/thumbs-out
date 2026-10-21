import AppKit
import SwiftUI
import ThumbsOutCore

/// Turns a click on what went wrong, an optional line of text and thumbs-out's own diagnostics into
/// a pre-filled GitHub issue. Everything that goes into the issue is shown here first, and nothing
/// leaves the Mac until the user submits the issue in their browser.
struct ReportProblemView: View {
    let controller: AwakeController
    let close: () -> Void

    @State private var diagnostics: DiagnosticsCollector.Result?
    @State private var kind: ProblemKind?
    @State private var summary = ""
    @State private var notice: Notice?
    @Environment(\.appearsActive) private var appearsActive

    /// Off for snapshots, which pass their diagnostics in.
    private let collectsLive: Bool

    private struct Notice: Equatable {
        let text: String
        var isError = false
    }

    init(
        controller: AwakeController,
        diagnostics: DiagnosticsCollector.Result? = nil,
        kind: ProblemKind? = nil,
        close: @escaping () -> Void
    ) {
        self.controller = controller
        self.close = close
        collectsLive = diagnostics == nil
        _diagnostics = State(initialValue: diagnostics)
        _kind = State(initialValue: kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header
                kindPicker
                summaryField
                included
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 16)

            Divider()
            bottomBar
        }
        .frame(width: 600, height: 800)
        .background(.background)
        .tint(Theme.working)
        // On open, and again whenever the window comes back to the front, so "Right now" is current.
        .task(id: appearsActive) {
            guard collectsLive, appearsActive || diagnostics == nil else { return }
            diagnostics = await DiagnosticsCollector.collect(from: controller)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.grace.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Report a Bug").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Pick what went wrong and add a line if you like. thumbs-out fills in the rest and opens a ready-to-submit GitHub issue.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What went wrong?").font(.tileTitle)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(ProblemKind.allCases, id: \.self) { option in
                    ProblemChip(kind: option, isSelected: kind == option) {
                        withAnimation(.snappy(duration: 0.18)) { kind = kind == option ? nil : option }
                    }
                }
            }
        }
    }

    private var summaryField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Anything else?").font(.tileTitle)
                Text("Optional").font(.caption).foregroundStyle(.tertiary)
            }
            TextEditor(text: $summary)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .frame(height: 76)
                .overlay(alignment: .topLeading) {
                    if summary.isEmpty {
                        Text((kind ?? .other).prompt)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                            .id(kind)
                            .transition(.opacity)
                    }
                }
                .background(Theme.tileFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.tileStroke, lineWidth: 0.5)
                )
                .accessibilityLabel("Anything else?")
        }
    }

    private var included: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Added to the issue").font(.tileTitle)
                if let report = diagnostics?.report {
                    Text("\(report.sections.reduce(0) { $0 + $1.facts.count }) details from this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if diagnostics == nil { ProgressView().controlSize(.small) }
            }
            ScrollView {
                if let diagnostics {
                    DiagnosticsPreview(report: diagnostics.report.redacted(by: DiagnosticsCollector.redactor))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.tilePadding)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Theme.tileFill, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .strokeBorder(Theme.tileStroke, lineWidth: 0.5)
            )

            Label {
                Text("Only thumbs-out's own version, settings, setup, detections and log. Your home folder shows as ~ and your name as <user>; what you type goes in as written. Nothing leaves this Mac until you submit the issue on GitHub.")
            } icon: {
                Image(systemName: "lock.shield").foregroundStyle(Theme.workingInk)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let crashes = diagnostics?.crashReports, !crashes.isEmpty {
                crashReportsNote(crashes)
            }
        }
    }

    private func crashReportsNote(_ crashes: [CrashReport]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.grace)
            Text("thumbs-out crashed \(crashes.count == 1 ? "once" : "\(crashes.count) times"). Crash reports aren't added; drag them into the issue to share them.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(crashes.map(\.url))
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Theme.grace.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Copy Report", action: copyReport)
            if let notice {
                Text(notice.text)
                    .font(.callout)
                    .foregroundStyle(notice.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            Spacer(minLength: 8)
            Button("Cancel", action: close)
                .keyboardShortcut(.cancelAction)
            Button("Open GitHub Issue…", action: openIssue)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.workingInk)
        }
        .disabled(diagnostics == nil)
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .animation(.easeOut(duration: 0.15), value: notice)
    }

    // MARK: Actions

    private var report: IssueReport? {
        guard var report = diagnostics?.report else { return nil }
        report.kind = kind
        report.summary = summary
        return report
    }

    private func copyReport() {
        guard let report else { return }
        copyToClipboard(report.markdown(redactor: DiagnosticsCollector.redactor))
        notice = Notice(text: "Copied. Paste it into a new issue at github.com/\(GitHubIssueLink.repository).")
    }

    private func openIssue() {
        guard let report else { return }
        let (url, fit) = GitHubIssueLink.bestFit(for: report, redactor: DiagnosticsCollector.redactor)
        if fit == .needsPaste { copyToClipboard(report.markdown(redactor: DiagnosticsCollector.redactor)) }
        guard NSWorkspace.shared.open(url) else {
            notice = Notice(text: "Couldn't open your browser. Use Copy Report instead.", isError: true)
            return
        }
        notice = switch fit {
        case .complete: Notice(text: "Opened in your browser, filled in. Check it, then click Create.")
        case .trimmedLog(let omitted): Notice(text: "Opened without the \(omitted) oldest log lines, to keep the link short.")
        case .needsPaste: Notice(text: "Too long for a link, so it's on your clipboard: paste it into the issue.")
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// One quick answer to "what went wrong?". Clicking it again clears the choice.
private struct ProblemChip: View {
    let kind: ProblemKind
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : .secondary)
                    .frame(width: 18)
                Text(kind.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Self.shape.fill(fill))
            .overlay(Self.shape.strokeBorder(isSelected ? accent : Theme.tileStroke, lineWidth: isSelected ? 1.5 : 0.5))
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The bright brand green is hard to read on white; light mode uses the darker ink.
    private var accent: Color { colorScheme == .dark ? Theme.working : Theme.workingInk }

    private var fill: Color {
        if isSelected { return Theme.working.opacity(colorScheme == .dark ? 0.2 : 0.14) }
        return Color.primary.opacity(isHovering ? 0.09 : 0.055)
    }
}

private extension ProblemKind {
    var symbol: String {
        switch self {
        case .didNotKeepAwake: "moon.zzz"
        case .wontLetSleep: "sun.max"
        case .agentNotDetected: "eye.slash"
        case .lidClosed: "laptopcomputer"
        case .quitUnexpectedly: "xmark.octagon"
        case .other: "ellipsis.bubble"
        }
    }
}

/// The report as it will appear in the issue, already redacted.
struct DiagnosticsPreview: View {
    let report: IssueReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(report.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title).font(.sectionLabel).foregroundStyle(.secondary)
                    ForEach(Array(section.facts.enumerated()), id: \.offset) { _, fact in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(fact.label)
                                .foregroundStyle(.secondary)
                                .frame(width: 168, alignment: .leading)
                            Text(fact.value)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                    }
                }
            }
            if !report.log.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Log (this run)").font(.sectionLabel).foregroundStyle(.secondary)
                    Text(report.log.joined(separator: "\n"))
                        .font(.caption2.monospaced())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }
}
