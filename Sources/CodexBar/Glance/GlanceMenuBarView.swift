import SwiftUI

struct GlanceMenuBarView: View {
    let feed: GlanceFeed
    let actions: GlanceActions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if self.feed.snapshot.providers.isEmpty {
                Text(L("No providers selected"))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                Grid(alignment: .topLeading, horizontalSpacing: 22, verticalSpacing: 18) {
                    ForEach(
                        Array(stride(from: 0, to: self.feed.snapshot.providers.count, by: 2)),
                        id: \.self)
                    { index in
                        GridRow {
                            ForEach(self.feed.snapshot.providers.dropFirst(index).prefix(2)) { provider in
                                MenuBarProvider(provider: provider, openSettings: self.actions.openSettings)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button(action: self.actions.refresh) {
                    Label(L("Refresh"), systemImage: "arrow.clockwise")
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .contentShape(Capsule())
                }
                .modifier(MenuBarGlassControl())
                Spacer(minLength: 0)
                if let target = GlanceSurface.menuBar.switchTarget {
                    Button { self.actions.show(target) } label: {
                        Image(systemName: "macbook")
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .modifier(MenuBarGlassControl())
                    .help(target.showTitle)
                    .accessibilityLabel(target.showTitle)
                }
                Button(action: self.actions.openSettings) {
                    Image(systemName: "gearshape")
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .modifier(MenuBarGlassControl())
                .help(L("Settings..."))
                .accessibilityLabel(L("Settings..."))
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(14)
        .frame(width: 352)
        .font(.system(size: 12))
        .focusEffectDisabled()
    }
}

private struct MenuBarGlassControl: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.buttonStyle(.plain)
        }
    }
}

private struct MenuBarProvider: View {
    let provider: GlanceProvider
    let openSettings: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Button(self.provider.name, action: self.openSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .help("Open \(self.provider.name) settings")
                Spacer(minLength: 0)
                if case let .stale(message) = self.provider.freshness {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                        .help(message)
                        .accessibilityLabel(message)
                } else if let age = self.provider.ageText {
                    Text(age).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if self.provider.lanes.isEmpty {
                Text(self.emptyMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(self.provider.lanes) { lane in
                        MenuBarQuota(lane: lane)
                    }
                }
                .opacity(self.provider.isStale ? 0.5 : 1)
            }
        }
    }

    private var emptyMessage: String {
        switch self.provider.freshness {
        case .refreshing: "Updating…"
        case let .problem(message), let .stale(message): message
        case .live: "No usage limits reported"
        }
    }
}

private struct MenuBarQuota: View {
    let lane: GlanceLane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(Int(self.lane.remaining.rounded()), format: .number)
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: self.lane.remaining))
                Text("%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                if self.lane.isAheadOfPace, GlanceSeverity(lane: self.lane) == .calm {
                    Circle().fill(.orange).frame(width: 4, height: 4)
                        .help(L("over pace"))
                }
            }
            .foregroundStyle(self.color)
            HStack(spacing: 4) {
                Text(self.lane.label)
                if let reset = self.lane.resetText {
                    Text(reset).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 10).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(self.reduceMotion ? nil : .smooth(duration: 0.2), value: self.lane.remaining)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(self.lane.longLabel) window, \(Int(self.lane.remaining.rounded())) percent left"
                + (self.lane.resetText.map { ", resets in \($0)" } ?? ""))
    }

    private var color: Color {
        switch GlanceSeverity(lane: self.lane) {
        case .calm: .primary
        case .watch: .orange
        case .low: .red
        }
    }
}
