import AppKit
import CodexBarCore
import Observation
import SwiftUI

@MainActor
@Observable
final class NotchState {
    var isExpanded = false
    var notchWidth: CGFloat = 180
    var notchHeight: CGFloat = 32
    var visibleSize: CGSize = .zero

    static let earWidth: CGFloat = 50
    static let flare: CGFloat = 7
    static let expandedWidth: CGFloat = 372

    var collapsedWidth: CGFloat { self.notchWidth + Self.earWidth * 2 }
    var bodyWidth: CGFloat { self.isExpanded ? max(self.collapsedWidth, Self.expandedWidth) : self.collapsedWidth }
}

/// Notch silhouette: square top that flares into the menu bar, rounded bottom corners.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var flare: CGFloat

    var animatableData: CGFloat {
        get { self.bottomRadius }
        set { self.bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let t = self.flare
        let r = min(self.bottomRadius, (w - 2 * t) / 2, h / 2)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
        path.addLine(to: CGPoint(x: t, y: h - r))
        path.addQuadCurve(to: CGPoint(x: t + r, y: h), control: CGPoint(x: t, y: h))
        path.addLine(to: CGPoint(x: w - t - r, y: h))
        path.addQuadCurve(to: CGPoint(x: w - t, y: h - r), control: CGPoint(x: w - t, y: h))
        path.addLine(to: CGPoint(x: w - t, y: t))
        path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - t, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct NotchSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct NotchRootView: View {
    let feed: GlanceFeed
    let state: NotchState
    let actions: GlanceActions

    var body: some View {
        let providers = self.feed.snapshot.providers
        let expanded = self.state.isExpanded
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    GlanceEar(provider: providers.first)
                        .frame(width: NotchState.earWidth)
                    Spacer(minLength: self.state.notchWidth)
                    GlanceEar(provider: providers.dropFirst().first)
                        .frame(width: NotchState.earWidth)
                }
                .frame(height: self.state.notchHeight)
                .opacity(expanded ? 0 : 1)
                if expanded {
                    GlanceCard(snapshot: self.feed.snapshot, actions: self.actions)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .frame(width: self.state.bodyWidth)
            .padding(.horizontal, NotchState.flare)
            .background(
                NotchShape(bottomRadius: expanded ? 24 : 10, flare: NotchState.flare)
                    .fill(GlanceStyle.ink)
                    .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 18, y: 8))
            .background(GeometryReader { proxy in
                Color.clear.preference(key: NotchSizeKey.self, value: proxy.size)
            })
            .clipped()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(GlanceStyle.expand, value: expanded)
        .onPreferenceChange(NotchSizeKey.self) { size in
            self.state.visibleSize = size
        }
        .environment(\.colorScheme, .dark)
    }
}

final class GlancePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect, level: NSWindow.Level) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = level
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
}

/// Glance panels never become key, so their controls must act on the first click.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}

/// Owns the floating notch panel. Hover expands it; leaving collapses it. Collapsed, it passes every click through.
@MainActor
final class NotchPanelController {
    private let feed: GlanceFeed
    private let actions: GlanceActions
    private let state = NotchState()
    private var panel: GlancePanel?
    private var monitors: [Any] = []
    private var collapseWorkItem: DispatchWorkItem?
    private let logger = CodexBarLog.logger(LogCategories.app)

    private static let panelContentHeight: CGFloat = 320

    init(feed: GlanceFeed, actions: GlanceActions) {
        self.feed = feed
        self.actions = actions
    }

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }

    var isShowing: Bool { self.panel != nil }

    func show(on screen: NSScreen) {
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        self.state.notchWidth = max(80, screen.frame.width - leftWidth - rightWidth)
        self.state.notchHeight = screen.safeAreaInsets.top
        let width = max(self.state.collapsedWidth, NotchState.expandedWidth) + NotchState.flare * 2 + 40
        let height = self.state.notchHeight + Self.panelContentHeight
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        let panel = self.panel ?? self.makePanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.ignoresMouseEvents = !self.state.isExpanded
        panel.orderFrontRegardless()
        self.panel = panel
        self.installMonitors()
        self.logger.info(
            "Notch glance shown",
            metadata: ["notchWidth": "\(Int(self.state.notchWidth))", "notchHeight": "\(Int(self.state.notchHeight))"])
    }

    func hide() {
        self.removeMonitors()
        self.panel?.orderOut(nil)
        self.panel = nil
        self.state.isExpanded = false
    }

    func toggle() {
        self.setExpanded(!self.state.isExpanded)
    }

    private func makePanel(frame: NSRect) -> GlancePanel {
        let panel = GlancePanel(contentRect: frame, level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3))
        let host = FirstClickHostingView(rootView: NotchRootView(feed: self.feed, state: self.state, actions: self.actions))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    private func setExpanded(_ expanded: Bool) {
        guard self.state.isExpanded != expanded else { return }
        self.collapseWorkItem?.cancel()
        self.state.isExpanded = expanded
        self.panel?.ignoresMouseEvents = !expanded
    }

    /// Screen rect currently drawn by the notch body, in global coordinates.
    private func activeRect() -> NSRect? {
        guard let panel else { return nil }
        let frame = panel.frame
        let size = self.state.visibleSize == .zero
            ? CGSize(width: self.state.collapsedWidth + NotchState.flare * 2, height: self.state.notchHeight)
            : self.state.visibleSize
        let rect = NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        return rect.insetBy(dx: -4, dy: -4)
    }

    private func handleMouse(at point: NSPoint) {
        guard let rect = self.activeRect() else { return }
        if rect.contains(point) {
            self.collapseWorkItem?.cancel()
            self.collapseWorkItem = nil
            self.setExpanded(true)
        } else if self.state.isExpanded, self.collapseWorkItem == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.collapseWorkItem = nil
                    self?.setExpanded(false)
                }
            }
            self.collapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }

    private func installMonitors() {
        guard self.monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.handleMouse(at: location) }
        }) {
            self.monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.handleMouse(at: location) }
            return event
        }) {
            self.monitors.append(local)
        }
    }

    private func removeMonitors() {
        for monitor in self.monitors {
            NSEvent.removeMonitor(monitor)
        }
        self.monitors.removeAll()
    }
}
