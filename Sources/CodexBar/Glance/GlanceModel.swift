import CodexBarCore
import Foundation

/// One quota window reduced to what the glance surfaces render. Values are always "remaining", regardless of the
/// user's used/remaining preference, so the glance reads the same way everywhere.
struct GlanceLane: Equatable, Identifiable {
    let id: String
    let title: String
    let remaining: Double
    let expectedRemaining: Double?
    let resetText: String?

    init(id: String, title: String, percent: Double, showsUsed: Bool, pacePercent: Double?, resetText: String?) {
        self.id = id
        self.title = title
        self.remaining = Self.clamp(showsUsed ? 100 - percent : percent)
        self.expectedRemaining = pacePercent.map { Self.clamp(showsUsed ? 100 - $0 : $0) }
        self.resetText = resetText
    }

    /// Remaining quota is below where steady use would leave it.
    var isAheadOfPace: Bool {
        guard let expectedRemaining else { return false }
        return self.remaining + 0.5 < expectedRemaining
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }
}

enum GlanceSeverity: Int, Comparable {
    case calm
    case watch
    case low

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(lane: GlanceLane?) {
        guard let lane else {
            self = .calm
            return
        }
        if lane.remaining < 10 {
            self = .low
        } else if lane.remaining < 25 || (lane.isAheadOfPace && lane.remaining < 50) {
            self = .watch
        } else {
            self = .calm
        }
    }
}

enum GlanceFreshness: Equatable {
    case live
    case refreshing
    /// Showing last known data because the latest refresh failed.
    case stale(String)
    case problem(String)
}

struct GlanceProvider: Equatable, Identifiable {
    let provider: UsageProvider
    let name: String
    let lanes: [GlanceLane]
    let freshness: GlanceFreshness

    var id: String { self.provider.rawValue }

    /// The lane closest to running out decides what the glance shows.
    var binding: GlanceLane? {
        self.lanes.min { $0.remaining < $1.remaining }
    }

    var secondaryLanes: [GlanceLane] {
        guard let binding else { return [] }
        return self.lanes.filter { $0.id != binding.id }
    }

    var severity: GlanceSeverity {
        GlanceSeverity(lane: self.binding)
    }
}

struct GlanceSnapshot: Equatable {
    let providers: [GlanceProvider]

    static let empty = GlanceSnapshot(providers: [])

    var worstSeverity: GlanceSeverity {
        self.providers.map(\.severity).max() ?? .calm
    }
}

extension GlanceProvider {
    init(model: UsageMenuCardView.Model) {
        let lanes = model.metrics.map { metric in
            GlanceLane(
                id: metric.id,
                title: metric.title,
                percent: metric.percent,
                showsUsed: metric.percentStyle == .used,
                pacePercent: metric.pacePercent,
                resetText: metric.resetText)
        }
        // A source error with fresh fallback data is a settings concern, not a glance concern.
        let freshness: GlanceFreshness = if let lastKnown = model.lastKnownUsageText {
            .stale(lastKnown)
        } else if lanes.isEmpty {
            model.subtitleStyle == .loading ? .refreshing : .problem(model.placeholder ?? model.subtitleText)
        } else {
            .live
        }
        self.init(provider: model.provider, name: model.providerName, lanes: lanes, freshness: freshness)
    }
}

extension UsageStore {
    /// Projects the same menu-card models CodexBar renders, so glance numbers never diverge from the full app.
    func glanceSnapshot(now: Date = Date()) -> GlanceSnapshot {
        let providers = self.enabledFirstPartyProvidersForDisplay().map { provider in
            GlanceProvider(model: self.menuCardModel(for: provider, context: .menu, now: now))
        }
        return GlanceSnapshot(providers: providers)
    }
}
