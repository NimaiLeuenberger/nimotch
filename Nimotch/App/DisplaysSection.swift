import SwiftUI

/// Settings → General → Displays: one switch per connected display.
struct DisplaysSection: View {
    let displays: NotchDisplays

    var body: some View {
        Section {
            ForEach(displays.connected) { display in
                Toggle(isOn: Binding(
                    get: { displays.isEnabled(display) },
                    set: { displays.setEnabled($0, for: display) }
                )) {
                    HStack(spacing: 10) {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(display.name)
                            Text(display.hasNotch ? "Uses the notch" : "Shows a small pill at the top center")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if displays.connected.allSatisfy({ !displays.isEnabled($0) }) {
                Text("nimotch is hidden on every display. Turn one on, or reach Settings through the menu bar icon.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Displays")
        } footer: {
            Text("Displays that aren't connected keep their setting for next time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
