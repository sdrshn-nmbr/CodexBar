import CodexBarCore
import SwiftUI

struct GlanceActions {
    var refresh: @MainActor () -> Void
    var openSettings: @MainActor () -> Void
    var quit: @MainActor () -> Void
}

/// A thin arc of remaining quota with a tick where steady use would put it.
struct GlanceRing: View {
    let lane: GlanceLane?
    let severity: GlanceSeverity
    var diameter: CGFloat = 14
    var lineWidth: CGFloat = 2
    var calm: Color = GlanceStyle.primary
    var track: Color = GlanceStyle.track

    var body: some View {
        let fraction = (self.lane?.remaining ?? 0) / 100
        ZStack {
            Circle().stroke(self.track, lineWidth: self.lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    self.severity == .calm ? self.calm : GlanceStyle.tint(self.severity),
                    style: StrokeStyle(lineWidth: self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: self.diameter, height: self.diameter)
        .animation(GlanceStyle.settle, value: fraction)
    }
}

/// Horizontal remaining bar; the pace tick shows where steady use would leave you right now.
struct GlanceBar: View {
    let lane: GlanceLane
    let severity: GlanceSeverity
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(GlanceStyle.track).frame(height: self.height)
                Capsule()
                    .fill(GlanceStyle.tint(self.severity))
                    .frame(width: max(self.height, width * self.lane.remaining / 100), height: self.height)
            }
            .overlay(alignment: .leading) {
                // Pace tick: where steady use would leave the quota right now. Drawn as an overlay so it never
                // changes the bar's thickness.
                if let expected = self.lane.expectedRemaining {
                    Rectangle()
                        .fill(GlanceStyle.primary.opacity(0.7))
                        .frame(width: 1, height: self.height + 5)
                        .offset(x: width * expected / 100 - 0.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: self.height + 5)
        .animation(GlanceStyle.settle, value: self.lane.remaining)
    }
}

struct GlancePercent: View {
    let value: Double
    let size: CGFloat
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(String(Int(self.value.rounded())))
                .font(GlanceStyle.numerals(self.size))
                .foregroundStyle(self.color)
                .contentTransition(.numericText(value: self.value))
            Text("%")
                .font(GlanceStyle.numerals(self.size * 0.46))
                .foregroundStyle(GlanceStyle.faint)
        }
        .animation(GlanceStyle.settle, value: self.value)
    }
}

/// Expanded glance: one column per provider, one stat per quota window, split by a hairline.
struct GlanceCard: View {
    let snapshot: GlanceSnapshot
    let actions: GlanceActions

    var body: some View {
        Group {
            if self.snapshot.providers.isEmpty {
                Text("No providers enabled")
                    .font(GlanceStyle.label(11))
                    .foregroundStyle(GlanceStyle.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(self.snapshot.providers.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 {
                            Rectangle().fill(GlanceStyle.hairline).frame(width: 1).padding(.horizontal, 18)
                        }
                        GlanceProviderColumn(provider: provider, openSettings: self.actions.openSettings)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Refresh") { self.actions.refresh() }
            Button("Settings…") { self.actions.openSettings() }
            Divider()
            Button("Quit CodexBar") { self.actions.quit() }
        }
    }
}

struct GlanceProviderColumn: View {
    let provider: GlanceProvider
    let openSettings: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button(action: self.openSettings) {
                    Text(self.provider.name.uppercased())
                        .font(GlanceStyle.label(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(GlanceStyle.secondary)
                }
                .buttonStyle(.plain)
                .help("Open \(self.provider.name) settings")
                Spacer(minLength: 4)
                self.freshnessBadge
            }
            if self.provider.lanes.isEmpty {
                Text(Self.emptyText(self.provider.freshness))
                    .font(GlanceStyle.label(11))
                    .foregroundStyle(GlanceStyle.secondary)
                    .lineLimit(2)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(self.provider.lanes) { lane in
                        GlanceStat(lane: lane)
                    }
                }
                .opacity(self.provider.isStale ? 0.45 : 1)
            }
        }
    }

    @ViewBuilder private var freshnessBadge: some View {
        if case let .stale(message) = self.provider.freshness {
            // Old numbers stay visible but are never presented as live.
            HStack(spacing: 4) {
                Circle().fill(GlanceStyle.amber).frame(width: 4, height: 4)
                Text(message).foregroundStyle(GlanceStyle.amber.opacity(0.85))
            }
            .font(GlanceStyle.label(10))
            .lineLimit(1)
        } else if let ageText = self.provider.ageText {
            Text(ageText)
                .font(GlanceStyle.label(10))
                .foregroundStyle(GlanceStyle.faint)
                .lineLimit(1)
        }
    }

    private static func emptyText(_ freshness: GlanceFreshness) -> String {
        switch freshness {
        case .refreshing: "Updating…"
        case let .problem(message), let .stale(message): message
        case .live: "No usage limits reported"
        }
    }
}

/// One quota window: big remaining percent, then window length and time until reset.
/// An amber dot marks a window being used faster than steady pace, which the bars' tick used to show.
struct GlanceStat: View {
    let lane: GlanceLane

    var body: some View {
        let severity = GlanceSeverity(lane: self.lane)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                GlancePercent(value: self.lane.remaining, size: 26, color: GlanceStyle.tint(severity))
                if self.lane.isAheadOfPace, severity == .calm {
                    Circle()
                        .fill(GlanceStyle.amber)
                        .frame(width: 4, height: 4)
                        .padding(.leading, 3)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 14 }
                        .help("Using this limit faster than steady pace")
                }
            }
            HStack(spacing: 5) {
                Text(self.lane.label)
                    .font(GlanceStyle.numerals(10))
                    .foregroundStyle(GlanceStyle.secondary)
                if let reset = self.lane.resetText {
                    Text(reset)
                        .font(GlanceStyle.label(10))
                        .foregroundStyle(GlanceStyle.faint)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(self.lane.longLabel) window, \(Int(self.lane.remaining.rounded())) percent left"
                + (self.lane.resetText.map { ", resets in \($0)" } ?? "")
                + (self.lane.isAheadOfPace ? ", ahead of pace" : ""))
    }
}

struct GlanceEar: View {
    let provider: GlanceProvider?
    var numeralSize: CGFloat = 12
    var ringDiameter: CGFloat = 12
    var calm: Color = GlanceStyle.primary
    var track: Color = GlanceStyle.track

    var body: some View {
        let severity = self.provider?.severity ?? .calm
        HStack(spacing: 5) {
            GlanceRing(
                lane: self.provider?.binding,
                severity: severity,
                diameter: self.ringDiameter,
                lineWidth: 1.8,
                calm: self.calm,
                track: self.track)
            if let binding = self.provider?.binding {
                Text(String(Int(binding.remaining.rounded())))
                    .font(GlanceStyle.numerals(self.numeralSize))
                    .foregroundStyle(severity == .calm ? self.calm : GlanceStyle.tint(severity))
                    .contentTransition(.numericText(value: binding.remaining))
                    .animation(GlanceStyle.settle, value: binding.remaining)
            }
        }
        .opacity(self.provider?.isStale == true ? 0.4 : 1)
    }
}
