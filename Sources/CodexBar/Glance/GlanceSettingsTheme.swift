import CodexBarCore
import SwiftUI

/// Settings styling for the glance fork. Upstream settings views consult `isActive` at a handful of seams
/// (window root, backing materials, icon chips, section headers, usage rows); everything else inherits
/// through the environment, so upstream settings changes keep flowing in unmodified.
enum GlanceSettingsTheme {
    @MainActor static var isActive = false
}

/// Solid ink in place of a translucent settings material while the glance theme is active.
struct GlanceSettingsBacking<Material: View>: View {
    @ViewBuilder let material: () -> Material

    var body: some View {
        if GlanceSettingsTheme.isActive {
            GlanceStyle.ink
        } else {
            self.material()
        }
    }
}

private struct GlanceSettingsRootStyle: ViewModifier {
    func body(content: Content) -> some View {
        if GlanceSettingsTheme.isActive {
            content
                .environment(\.colorScheme, .dark)
                .tint(GlanceStyle.primary)
                .background(GlanceStyle.ink)
        } else {
            content
        }
    }
}

extension View {
    func glanceSettingsRoot() -> some View {
        self.modifier(GlanceSettingsRootStyle())
    }
}

/// Monochrome sidebar glyph replacing the colored System Settings-style chip.
struct GlanceSettingsGlyph: View {
    let systemImage: String
    let side: CGFloat

    var body: some View {
        Image(systemName: self.systemImage)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(GlanceStyle.secondary)
            .frame(width: self.side, height: self.side)
            .accessibilityHidden(true)
    }
}

struct GlanceSettingsSectionTitle: View {
    let title: String

    var body: some View {
        Text(self.title.uppercased())
            .font(GlanceStyle.label(10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(GlanceStyle.secondary)
    }
}

/// A usage lane in the settings detail, drawn with the same numerals, bar, and pace tick as the glance card.
struct GlanceSettingsLaneRow: View {
    let lane: GlanceLane
    let title: String
    let resetText: String?
    let metaText: String?
    let detailText: String?

    var body: some View {
        let severity = GlanceSeverity(lane: self.lane)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.title.uppercased())
                    .font(GlanceStyle.label(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(GlanceStyle.secondary)
                Spacer(minLength: 8)
                if let resetText {
                    Text(resetText)
                        .font(GlanceStyle.label(10))
                        .foregroundStyle(GlanceStyle.faint)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .center, spacing: 14) {
                GlancePercent(value: self.lane.remaining, size: 22, color: GlanceStyle.tint(severity))
                    .frame(width: 60, alignment: .leading)
                GlanceBar(lane: self.lane, severity: severity)
            }
            ForEach([self.metaText, self.detailText].compactMap(\.self), id: \.self) { line in
                Text(line)
                    .font(GlanceStyle.label(10))
                    .foregroundStyle(GlanceStyle.faint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }
}

