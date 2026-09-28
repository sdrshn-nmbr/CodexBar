import AppKit
import CodexBarCore
import SwiftUI

// The only glance file that depends on upstream app-layer types (UsageStore, menu-card models, StatusItemController,
// SettingsPane). When an upstream sync fails to compile, the fix belongs here; every other glance file speaks only
// Glance* types and CodexBarCore.

/// Glance presentation over CodexBar's own controller. The wrapped controller keeps refresh, login, and settings
/// behavior; only its status items are hidden. The glance chooses the notch when the Mac has one, else the menu bar.
@MainActor
final class GlanceController: StatusItemControlling {
    /// Cost history decodes large local logs; the glance never shows it, so scan it at most daily.
    /// Manual refresh still forces a scan.
    static let costHistoryInterval: TimeInterval = 24 * 60 * 60

    let legacy: StatusItemController
    private let feed: GlanceFeed
    private let memoryRelief = GlanceMemoryRelief()
    private var notch: NotchPanelController!
    private var menuBar: MenuBarGlanceController!
    private var settingsOpenHandler: (@MainActor (SettingsPane?) -> Void)?
    private var screenObserver: NSObjectProtocol?
    private let logger = CodexBarLog.logger(LogCategories.app)

    // swiftlint:disable:next function_parameter_count
    static func makeController(
        store: UsageStore,
        settings: SettingsStore,
        account: AccountInfo,
        updater: UpdaterProviding,
        selection: PreferencesSelection,
        managedCodexAccountCoordinator: ManagedCodexAccountCoordinator,
        codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator)
        -> StatusItemControlling
    {
        StatusItemController.hidesStatusItems = true
        GlanceSettingsTheme.isActive = ProcessInfo.processInfo.environment["CODEXBAR_GLANCE_SETTINGS_THEME"] != "0"
        UsageStore.minimumTokenFetchTTL = Self.costHistoryInterval
        let legacy = StatusItemController(
            store: store,
            settings: settings,
            account: account,
            updater: updater,
            preferencesSelection: selection,
            managedCodexAccountCoordinator: managedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: codexAccountPromotionCoordinator)
        return GlanceController(legacy: legacy, store: store)
    }

    init(legacy: StatusItemController, store: UsageStore) {
        self.legacy = legacy
        GlanceFonts.registerIfNeeded()
        self.feed = GlanceFeed(source: { [weak store] in store?.glanceSnapshot() ?? .empty })
        self.feed.onStoreActivity = { [memoryRelief] in memoryRelief.noteActivity() }
        self.memoryRelief.start()
        let actions = GlanceActions(
            refresh: { [weak legacy] in legacy?.refreshNow() },
            // Glance panels never activate the app (the old NSMenu did implicitly). Without activation, Stage
            // Manager files the settings window into its side strip instead of bringing it forward.
            openSettings: { [weak self] in
                NSApp.activate()
                self?.settingsOpenHandler?(nil)
            },
            quit: { NSApp.terminate(nil) })
        self.notch = NotchPanelController(feed: self.feed, actions: actions)
        self.menuBar = MenuBarGlanceController(feed: self.feed, actions: actions)
        self.placeSurfaces()
        self.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            MainActor.assumeIsolated { self?.placeSurfaces() }
        }
    }

    private func placeSurfaces() {
        // Development overrides: "menubar" forces the fallback surface, "none" hides both for side-by-side runs.
        let surfaceOverride = ProcessInfo.processInfo.environment["CODEXBAR_GLANCE_SURFACE"]
        if surfaceOverride == "none" {
            self.notch.hide()
            self.menuBar.hide()
            return
        }
        let forceMenuBar = surfaceOverride == "menubar"
        if !forceMenuBar, let screen = NotchPanelController.notchScreen() {
            self.menuBar.hide()
            self.notch.show(on: screen)
        } else {
            self.notch.hide()
            self.menuBar.show()
            self.logger.info("No notch display; glance using menu bar")
        }
    }

    func setSettingsOpenHandler(_ handler: @escaping @MainActor (SettingsPane?) -> Void) {
        self.settingsOpenHandler = handler
        // Development aid for screenshotting settings: CODEXBAR_GLANCE_OPEN_SETTINGS=general|<provider id>.
        if let requested = ProcessInfo.processInfo.environment["CODEXBAR_GLANCE_OPEN_SETTINGS"] {
            let named: [String: SettingsPane] = [
                "general": .general, "usageSpend": .usageSpend, "notifications": .notifications,
                "menuBar": .menuBar, "menu": .menu, "advanced": .advanced, "about": .about,
            ]
            let pane = named[requested] ?? UsageProvider(rawValue: requested).map { SettingsPane.provider($0.instanceID) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { handler(pane) }
        }
        self.legacy.setSettingsOpenHandler(handler)
    }

    func openMenuFromShortcut() {
        if self.notch.isShowing {
            self.notch.toggle()
        } else {
            self.menuBar.toggleDropdown()
        }
    }

    func runLoginFlowFromSettings(provider: UsageProvider) async {
        await self.legacy.runLoginFlowFromSettings(provider: provider)
    }

    func celebrationOriginPoint(for provider: UsageProvider?) -> CGPoint? {
        nil
    }

    func trimRebuildableCachesForMemoryPressure() -> MemoryPressureCacheTrimSummary {
        self.legacy.trimRebuildableCachesForMemoryPressure()
    }

    #if DEBUG
    func seedRebuildableCachesForMemoryPressureProof() {
        self.legacy.seedRebuildableCachesForMemoryPressureProof()
    }
    #endif

    func prepareForAppShutdown() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        self.feed.stop()
        self.memoryRelief.stop()
        self.notch.hide()
        self.menuBar.hide()
        self.legacy.prepareForAppShutdown()
    }
}

// MARK: - Upstream projection

extension GlanceProvider {
    init(model: UsageMenuCardView.Model) {
        let lanes = model.metrics.map(GlanceLane.init(metric:))
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

extension GlanceLane {
    init(metric: UsageMenuCardView.Model.Metric) {
        self.init(
            id: metric.id,
            title: metric.title,
            percent: metric.percent,
            showsUsed: metric.percentStyle == .used,
            pacePercent: metric.pacePercent,
            resetText: metric.resetText)
    }
}

/// Settings usage row: glance-styled lanes for progress metrics, upstream rendering for everything else.
struct GlanceSettingsMetricRow<Fallback: View>: View {
    let metric: UsageMenuCardView.Model.Metric
    let title: String
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        if GlanceSettingsTheme.isActive,
           ProviderDetailView<EmptyView>.metricInlinePresentation(self.metric) == .progress
        {
            let presentation = self.metric.linePresentation(title: self.title)
            GlanceSettingsLaneRow(
                lane: GlanceLane(metric: self.metric),
                title: self.title,
                resetText: presentation.resetText,
                metaText: presentation.metaText,
                detailText: self.metric.detailText)
        } else {
            self.fallback()
        }
    }
}
