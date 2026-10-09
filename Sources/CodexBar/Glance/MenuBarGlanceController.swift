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

private struct DropdownView: View {
    let feed: GlanceFeed
    let actions: GlanceActions

    var body: some View {
        GlanceCard(snapshot: self.feed.snapshot, surface: .menuBar, actions: self.actions)
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(GlanceStyle.ink)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(GlanceStyle.hairline, lineWidth: 1)))
            .environment(\.colorScheme, .dark)
            .fixedSize()
    }
}

/// Menu bar fallback for displays without a notch: a glyph in the status bar and a dropdown card on click.
@MainActor
final class MenuBarGlanceController: NSObject {
    private let feed: GlanceFeed
    private let actions: GlanceActions
    private var statusItem: NSStatusItem?
    private var glyphHost: NSView?
    private var dropdown: GlancePanel?
    private var dismissMonitor: Any?
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
        guard let button = self.statusItem?.button, let window = button.window else { return }
        let host = FirstClickHostingView(rootView: DropdownView(feed: self.feed, actions: self.dismissingActions()))
        let size = host.fittingSize
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = window.screen?.visibleFrame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let frame = NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height)
        let panel = GlancePanel(contentRect: frame, level: .popUpMenu)
        panel.hasShadow = true
        panel.contentView = host
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        self.dropdown = panel
        self.dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown,
            .rightMouseDown,
        ]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeDropdown() }
        }
    }

    private func closeDropdown() {
        if let monitor = self.dismissMonitor {
            NSEvent.removeMonitor(monitor)
            self.dismissMonitor = nil
        }
        self.dropdown?.orderOut(nil)
        self.dropdown = nil
    }

    private func dismissingActions() -> GlanceActions {
        GlanceActions(
            refresh: self.actions.refresh,
            show: { [weak self] surface in
                self?.closeDropdown()
                self?.actions.show(surface)
            },
            openSettings: { [weak self] in
                self?.closeDropdown()
                self?.actions.openSettings()
            },
            quit: self.actions.quit)
    }
}
