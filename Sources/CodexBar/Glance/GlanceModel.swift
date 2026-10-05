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
    /// Length of the quota window; lanes are labeled and ordered by it so every provider reads the same way.
    let windowMinutes: Int?
    /// Distinguishes lanes that share a window length, e.g. a model-scoped weekly limit.
    var qualifier: String?

    init(
        id: String,
        title: String,
        percent: Double,
        showsUsed: Bool,
        pacePercent: Double?,
        resetText: String?,
        windowMinutes: Int? = nil)
    {
        self.id = id
        self.title = title
        self.remaining = Self.clamp(showsUsed ? 100 - percent : percent)
        self.expectedRemaining = pacePercent.map { Self.clamp(showsUsed ? 100 - $0 : $0) }
        self.resetText = resetText
        self.windowMinutes = windowMinutes.flatMap { $0 > 0 ? $0 : nil } ?? Self.inferredMinutes(title: title)
    }

    /// Compact window label for the glance: "5h", "7d".
    var label: String {
        let base = self.windowMinutes.map(Self.compactDuration) ?? self.title.lowercased()
        return [base, self.qualifier].compactMap(\.self).joined(separator: " ")
    }

    /// Spelled-out window label for settings: "5-hour", "7-day".
    var longLabel: String {
        let base = self.windowMinutes.map(Self.longDuration) ?? self.title
        return [base, self.qualifier].compactMap(\.self).joined(separator: " ")
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

    private static func inferredMinutes(title: String) -> Int? {
        let lowered = title.lowercased()
        if lowered.contains("week") { return 7 * 24 * 60 }
        if lowered.contains("session") || lowered.contains("5-hour") || lowered.contains("5h") { return 5 * 60 }
        return nil
    }

    private static func compactDuration(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private static func longDuration(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440)-day" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
        return "\(minutes)-minute"
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
    /// How old the numbers are, shown quietly once they are no longer just-fetched ("12m ago").
    var ageText: String?

    /// Lanes are ordered shortest window first; lanes sharing a window length get a qualifier from their title.
    init(
        provider: UsageProvider,
        name: String,
        lanes: [GlanceLane],
        freshness: GlanceFreshness,
        ageText: String? = nil)
    {
        self.provider = provider
        self.name = name
        self.freshness = freshness
        self.ageText = ageText
        let ordered = lanes.enumerated().sorted { lhs, rhs in
            let left = lhs.element.windowMinutes ?? .max
            let right = rhs.element.windowMinutes ?? .max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
        var seen: Set<Int> = []
        self.lanes = ordered.map { lane in
            guard let minutes = lane.windowMinutes else { return lane }
            guard seen.insert(minutes).inserted else {
                var qualified = lane
                qualified.qualifier = Self.qualifier(from: lane.title)
                return qualified
            }
            return lane
        }
    }

    var id: String {
        self.provider.rawValue
    }

    var isStale: Bool {
        if case .stale = self.freshness { return true }
        return false
    }

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

    private static func qualifier(from title: String) -> String {
        let generic: Set = ["weekly", "week", "session", "limit", "usage", "5-hour", "hourly"]
        let words = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return words.first { !generic.contains($0) } ?? title.lowercased()
    }
}

struct GlanceSnapshot: Equatable {
    let providers: [GlanceProvider]

    static let empty = GlanceSnapshot(providers: [])

    var worstSeverity: GlanceSeverity {
        self.providers.map(\.severity).max() ?? .calm
    }
}
