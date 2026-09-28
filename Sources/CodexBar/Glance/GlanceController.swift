import AppKit
import CodexBarCore

/// Glance presentation over CodexBar's own controller. The wrapped controller keeps refresh, login, and settings
/// behavior; only its status items are hidden. The glance chooses the notch when the Mac has one, else the menu bar.
@MainActor
final class GlanceController: StatusItemControlling {
    let legacy: StatusItemController
    private let feed: GlanceFeed
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
        self.feed = GlanceFeed(store: store)
        let actions = GlanceActions(
            refresh: { [weak legacy] in legacy?.refreshNow() },
            openSettings: { [weak self] in self?.settingsOpenHandler?(nil) },
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
        let forceMenuBar = ProcessInfo.processInfo.environment["CODEXBAR_GLANCE_SURFACE"] == "menubar"
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
        self.notch.hide()
        self.menuBar.hide()
        self.legacy.prepareForAppShutdown()
    }
}
