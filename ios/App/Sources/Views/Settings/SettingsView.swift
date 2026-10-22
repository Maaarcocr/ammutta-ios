import AmmuttaCore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section(L10n.settingsWorkout) {
                    Picker(L10n.settingsWeightUnit, selection: $model.weightUnit) {
                        Text(L10n.unitKgName).tag(WeightUnit.kilograms)
                        Text(L10n.unitLbName).tag(WeightUnit.pounds)
                    }
                    Stepper(value: $model.defaultRestSeconds, in: Limits.restSeconds, step: 15) {
                        LabeledContent(L10n.settingsDefaultRest, value: Format.clock(model.defaultRestSeconds))
                    }
                }
                Section(L10n.settingsHeartRate) {
                    NavigationLink {
                        HeartRateSensorView()
                    } label: {
                        LabeledContent(L10n.settingsSensor, value: model.heartRate.sensorName ?? L10n.sensorNone)
                    }
                    .accessibilityIdentifier("settings.heartRate")
                }
                if model.health.isAvailable {
                    HealthSection(health: model.health)
                }
                if model.agents.isAvailable {
                    AgentsSection(agents: model.agents)
                }
                Section {
                    Button(L10n.settingsLanguage) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section(L10n.settingsAbout) {
                    LabeledContent(L10n.settingsVersion, value: version)
                    Text(model.agents.isEnabled ? L10n.settingsTaglineConnected : L10n.settingsTagline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.tabSettings)
        }
    }
}

private struct HealthSection: View {
    @Bindable var health: HealthSync
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Toggle(L10n.settingsHealthSync, isOn: $health.isEnabled)
                .accessibilityIdentifier("settings.healthSync")
            if health.isEnabled, !health.isAuthorized {
                Button(L10n.healthOpenSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text(L10n.settingsHealth)
        } footer: {
            if health.isEnabled, !health.isAuthorized {
                Text(L10n.healthNotAllowed)
            }
        }
    }
}

private struct AgentsSection: View {
    @Bindable var agents: AgentConnector

    var body: some View {
        Section {
            Toggle(L10n.agentsToggle, isOn: $agents.isEnabled)
                .accessibilityIdentifier("settings.agents")
            if agents.isEnabled, let url = agents.connectorURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.agentsAddress)
                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button(L10n.agentsCopy) {
                    UIPasteboard.general.url = url
                }
                if let code = agents.pairingCode {
                    LabeledContent(L10n.agentsCode) {
                        Text(code)
                            .font(.title3.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("agents.code")
                    }
                }
                Button(L10n.agentsGetCode) {
                    agents.requestPairingCode()
                }
                .accessibilityIdentifier("agents.getCode")
                Button(L10n.agentsDisconnect, role: .destructive) {
                    agents.disconnectAgents()
                }
            }
        } header: {
            Text(L10n.settingsAgents)
        } footer: {
            if agents.isEnabled, agents.isOffline {
                Text(L10n.agentsOffline)
            } else if agents.isEnabled, agents.pairingCode != nil {
                Text(L10n.agentsCodeNote)
            }
        }
    }
}
