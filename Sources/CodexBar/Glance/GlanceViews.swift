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

struct GlanceProviderRow: View {
    let provider: GlanceProvider

    /// Fixed columns so labels, numbers, bars, and reset times line up across every provider.
    static let labelWidth: CGFloat = 22
    static let valueWidth: CGFloat = 52
    static let resetWidth: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(self.provider.name.uppercased())
                    .font(GlanceStyle.label(10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(GlanceStyle.secondary)
                if case let .stale(message) = self.provider.freshness {
                    Circle().fill(GlanceStyle.amber).frame(width: 5, height: 5).help(message)
                }
            }
            if self.provider.lanes.isEmpty {
                Text(Self.emptyText(self.provider.freshness))
                    .font(GlanceStyle.label(11))
                    .foregroundStyle(GlanceStyle.secondary)
                    .lineLimit(2)
            } else {
                VStack(spacing: 9) {
                    ForEach(self.provider.lanes) { lane in
                        GlanceLaneRow(lane: lane)
                    }
                }
            }
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

/// One quota window: window length, remaining percent, bar with pace tick, time until reset.
struct GlanceLaneRow: View {
    let lane: GlanceLane

    var body: some View {
        let severity = GlanceSeverity(lane: self.lane)
        HStack(alignment: .center, spacing: 10) {
            Text(self.lane.label)
                .font(GlanceStyle.numerals(11))
                .foregroundStyle(GlanceStyle.faint)
                .lineLimit(1)
                .frame(width: GlanceProviderRow.labelWidth, alignment: .leading)
            GlancePercent(value: self.lane.remaining, size: 20, color: GlanceStyle.tint(severity))
                .frame(width: GlanceProviderRow.valueWidth, alignment: .leading)
            GlanceBar(lane: self.lane, severity: severity)
            Text(self.lane.resetText ?? "")
                .font(GlanceStyle.label(10))
                .foregroundStyle(GlanceStyle.faint)
                .lineLimit(1)
                .monospacedDigit()
                .frame(width: GlanceProviderRow.resetWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(self.lane.longLabel) window, \(Int(self.lane.remaining.rounded())) percent left"
                + (self.lane.resetText.map { ", resets in \($0)" } ?? ""))
    }
}

struct GlanceCard: View {
    let snapshot: GlanceSnapshot
    let actions: GlanceActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if self.snapshot.providers.isEmpty {
                Text("No providers enabled")
                    .font(GlanceStyle.label(11))
                    .foregroundStyle(GlanceStyle.secondary)
                    .padding(.vertical, 14)
            }
            ForEach(Array(self.snapshot.providers.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    Rectangle().fill(GlanceStyle.hairline).frame(height: 1).padding(.vertical, 12)
                }
                GlanceProviderRow(provider: provider)
            }
            HStack(spacing: 14) {
                Spacer()
                GlanceIconButton(symbol: "arrow.clockwise", help: "Refresh", action: self.actions.refresh)
                GlanceIconButton(symbol: "slider.horizontal.3", help: "Details & settings", action: self.actions.openSettings)
                GlanceIconButton(symbol: "power", help: "Quit", action: self.actions.quit)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

struct GlanceIconButton: View {
    let symbol: String
    let help: String
    let action: @MainActor () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(self.hovering ? GlanceStyle.primary : GlanceStyle.faint)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(self.help)
        .onHover { self.hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: self.hovering)
    }
}

/// The collapsed glance for one provider: ring plus number, sized to sit beside the notch or in the menu bar.
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
    }
}
