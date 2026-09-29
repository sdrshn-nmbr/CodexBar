import SwiftUI

/// Where the glance lives. Stored in the app's defaults so it survives restarts and automatic updates.
enum GlanceSurface: String, CaseIterable, Identifiable {
    case notch
    case menuBar

    static let defaultsKey = "glanceSurface"

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .notch: "Notch"
        case .menuBar: "Menu bar"
        }
    }

    static var stored: GlanceSurface {
        UserDefaults.standard.string(forKey: self.defaultsKey).flatMap(GlanceSurface.init(rawValue:)) ?? .notch
    }
}

/// Calls back when the stored surface changes, whether written by Settings or by `defaults write`.
final class GlanceSurfaceObserver: NSObject {
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        super.init()
        UserDefaults.standard.addObserver(self, forKeyPath: GlanceSurface.defaultsKey, options: [.new], context: nil)
    }

    func invalidate() {
        UserDefaults.standard.removeObserver(self, forKeyPath: GlanceSurface.defaultsKey)
    }

    override func observeValue(
        forKeyPath _: String?,
        of _: Any?,
        change _: [NSKeyValueChangeKey: Any]?,
        context _: UnsafeMutableRawPointer?)
    {
        let onChange = self.onChange
        Task { @MainActor in onChange() }
    }
}

/// Settings → General row. Macs without a notch display always use the menu bar.
struct GlanceSurfaceSettingsRow: View {
    @AppStorage(GlanceSurface.defaultsKey) private var surface: GlanceSurface = .notch

    var body: some View {
        Picker(selection: self.$surface) {
            ForEach(GlanceSurface.allCases) { option in
                Text(option.title).tag(option)
            }
        } label: {
            SettingsRowLabel("Show usage in", subtitle: "Displays without a notch always use the menu bar.")
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}
