import AppKit
import CodexBarCore
import Observation
import SwiftUI

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_: NSPoint) -> NSView? { nil }
}

private struct MenuBarGlyph: View {
    let feed: GlanceFeed

    var body: some View {
        HStack(spacing: 8) {
            ForEach(self.feed.snapshot.providers.prefix(2)) { provider in
                GlanceEar(
                    provider: provider,
                    numeralSize: 11,
                    ringDiameter: 11,
                    calm: Color.primary,
                    track: Color.primary.opacity(0.22))
            }
        }
        .padding(.horizontal, 4)
        .fixedSize()
    }
}

/// Menu bar fallback for displays without a notch: a glyph in the status bar and a dropdown card on click.
@MainActor
final class MenuBarGlanceController: NSObject, NSMenuDelegate {
    private let feed: GlanceFeed
    private let actions: GlanceActions
    private var statusItem: NSStatusItem?
    private var glyphHost: NSView?
    private var dropdown: NSMenu?
    private let logger = CodexBarLog.logger(LogCategories.app)

    init(feed: GlanceFeed, actions: GlanceActions) {
        self.feed = feed
        self.actions = actions
    }

    var isShowing: Bool {
        self.statusItem != nil
    }

    func show() {
        guard self.statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "CodexBar.Glance"
        guard let button = item.button else {
            self.logger.error("Glance status item has no button")
            return
        }
        let host = PassthroughHostingView(rootView: MenuBarGlyph(feed: self.feed))
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])
        button.target = self
        button.action = #selector(self.handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("CodexBar usage")
        self.statusItem = item
        self.glyphHost = host
        #if DEBUG
        if ProcessInfo.processInfo.environment["CODEXBAR_GLANCE_OPEN_MENU"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.toggleDropdown() }
        }
        #endif
    }

    func hide() {
        self.closeDropdown()
        if let item = self.statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.statusItem = nil
        self.glyphHost = nil
    }

    func toggleDropdown() {
        if self.dropdown != nil {
            self.closeDropdown()
        } else {
            self.openDropdown()
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            self.closeDropdown()
            self.showContextMenu(from: sender)
        } else {
            self.toggleDropdown()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(self.menuRefresh), keyEquivalent: "r").target = self
        if let target = GlanceSurface.menuBar.switchTarget {
            menu.addItem(withTitle: target.showTitle, action: #selector(self.menuShowInNotch), keyEquivalent: "")
                .target = self
        }
        menu.addItem(withTitle: "Settings…", action: #selector(self.menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CodexBar", action: #selector(self.menuQuit), keyEquivalent: "q").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func menuRefresh() { self.actions.refresh() }
    @objc private func menuShowInNotch() { self.actions.show(.notch) }
    @objc private func menuSettings() { self.actions.openSettings() }
    @objc private func menuQuit() { self.actions.quit() }

    private func openDropdown() {
        guard self.statusItem?.button != nil else { return }
        let host = NSHostingView(rootView: GlanceMenuBarView(feed: self.feed, actions: self.dismissingActions()))
        host.sizingOptions = [.intrinsicContentSize]
        host.setFrameSize(host.fittingSize)
        let menuItem = NSMenuItem()
        menuItem.view = host
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(menuItem)
        self.dropdown = menu
        let opener = Timer(timeInterval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let menu = self.dropdown, let item = self.statusItem else { return }
                item.menu = menu
                item.button?.performClick(nil)
                item.menu = nil
            }
        }
        RunLoop.main.add(opener, forMode: .common)
    }

    private func closeDropdown() {
        self.dropdown?.cancelTracking()
        self.dropdown = nil
    }

    func menuDidClose(_ menu: NSMenu) {
        guard self.dropdown === menu else { return }
        self.dropdown = nil
    }

    private func dismissingActions() -> GlanceActions {
        GlanceActions(
            refresh: self.actions.refresh,
            show: { [weak self] surface in
                self?.closeDropdown()
                DispatchQueue.main.async { self?.actions.show(surface) }
            },
            openSettings: { [weak self] in
                self?.closeDropdown()
                DispatchQueue.main.async { self?.actions.openSettings() }
            },
            quit: self.actions.quit)
    }
}
