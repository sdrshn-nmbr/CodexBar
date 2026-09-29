import CodexBarCore
import Darwin
import Foundation

/// Keeps the idle footprint near the live UI state after refresh bursts.
///
/// CodexBar's cost scan decodes large histories and memoizes them in process (~200 MB for long Claude histories),
/// then the allocator keeps freed pages resident. Since the glance scans cost at most daily, relief drops the
/// decoded artifacts (rebuilt from disk on the next scan) and returns free pages to the system. It runs off the
/// main thread once refreshes settle and on a slow timer.
@MainActor
final class GlanceMemoryRelief {
    private var debounceTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private let logger = CodexBarLog.logger(LogCategories.app)

    static let settleDelay: Duration = .seconds(20)
    static let interval: Duration = .seconds(300)

    func start() {
        self.timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled else { return }
                self?.relieve(reason: "interval")
            }
        }
        self.noteActivity()
    }

    func stop() {
        self.debounceTask?.cancel()
        self.timerTask?.cancel()
    }

    /// Call when refreshed data arrives; relief runs once activity has been quiet for `settleDelay`.
    func noteActivity() {
        self.debounceTask?.cancel()
        self.debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.relieve(reason: "settled")
        }
    }

    private func relieve(reason: String) {
        let logger = self.logger
        Task.detached(priority: .utility) {
            CostUsageMemoryRelease.releaseClaudeArtifacts()
            await CostUsageMemoryRelease.releaseCodexArtifacts()
            let released = malloc_zone_pressure_relief(nil, 0)
            logger.debug(
                "Glance memory relief",
                metadata: ["reason": reason, "releasedBytes": "\(released)"])
        }
    }
}
