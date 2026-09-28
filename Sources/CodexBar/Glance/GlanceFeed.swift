import CodexBarCore
import Foundation
import Observation

/// Publishes a new glance snapshot only when CodexBar's store changes or a reset countdown crosses a minute.
/// Unchanged projections are dropped, so SwiftUI redraws exactly when the visible data changes.
@MainActor
@Observable
final class GlanceFeed {
    private(set) var snapshot: GlanceSnapshot = .empty
    private(set) var revision = 0

    @ObservationIgnored private let source: @MainActor () -> GlanceSnapshot
    /// Fires on every observed store change, including ones that leave the glance unchanged (e.g. cost scans).
    @ObservationIgnored var onStoreActivity: (@MainActor () -> Void)?
    @ObservationIgnored private var rebuildScheduled = false
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private let logger = CodexBarLog.logger(LogCategories.app)

    /// `source` must read only observable state; any read it performs becomes a rebuild trigger.
    init(source: @escaping @MainActor () -> GlanceSnapshot) {
        self.source = source
        self.rebuild()
        self.startMinuteClock()
    }

    func stop() {
        self.clockTask?.cancel()
        self.clockTask = nil
    }

    private func rebuild() {
        let next = withObservationTracking {
            self.source()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRebuild()
            }
        }
        self.onStoreActivity?()
        guard next != self.snapshot else { return }
        self.snapshot = next
        self.revision &+= 1
    }

    private func scheduleRebuild() {
        guard !self.rebuildScheduled else { return }
        self.rebuildScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.rebuildScheduled = false
            self.rebuild()
        }
    }

    private func startMinuteClock() {
        self.clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let now = Date().timeIntervalSinceReferenceDate
                let untilNextMinute = 60 - now.truncatingRemainder(dividingBy: 60) + 0.05
                do {
                    try await Task.sleep(for: .seconds(untilNextMinute))
                } catch {
                    return
                }
                guard let self else { return }
                self.rebuild()
            }
        }
        self.logger.debug("Glance minute clock started")
    }
}
