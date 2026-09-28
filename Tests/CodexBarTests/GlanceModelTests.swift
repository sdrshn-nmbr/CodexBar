import CodexBarCore
import Testing
@testable import CodexBar

struct GlanceModelTests {
    @Test
    func `used and remaining display styles project to the same remaining quota and pace`() {
        let used = GlanceLane(id: "weekly", title: "Weekly", percent: 12, showsUsed: true, pacePercent: 27, resetText: nil)
        let left = GlanceLane(id: "weekly", title: "Weekly", percent: 88, showsUsed: false, pacePercent: 73, resetText: nil)
        #expect(used == left)
        #expect(used.remaining == 88)
        #expect(used.expectedRemaining == 73)
    }

    @Test
    func `binding lane is the one closest to running out`() {
        let provider = GlanceProvider(
            provider: .claude,
            name: "Claude",
            lanes: [
                GlanceLane(id: "primary", title: "Session", percent: 100, showsUsed: false, pacePercent: nil, resetText: nil),
                GlanceLane(id: "secondary", title: "Weekly", percent: 79, showsUsed: false, pacePercent: 9, resetText: nil),
            ],
            freshness: .live)
        #expect(provider.binding?.id == "secondary")
        #expect(provider.secondaryLanes.map(\.id) == ["primary"])
    }

    @Test
    func `severity escalates on low quota and on burning ahead of pace`() {
        let low = GlanceLane(id: "a", title: "A", percent: 8, showsUsed: false, pacePercent: nil, resetText: nil)
        let ahead = GlanceLane(id: "b", title: "B", percent: 40, showsUsed: false, pacePercent: 60, resetText: nil)
        let calm = GlanceLane(id: "c", title: "C", percent: 40, showsUsed: false, pacePercent: 30, resetText: nil)
        #expect(GlanceSeverity(lane: low) == .low)
        #expect(GlanceSeverity(lane: ahead) == .watch)
        #expect(GlanceSeverity(lane: calm) == .calm)
    }
}

