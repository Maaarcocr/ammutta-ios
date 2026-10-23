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
                ConnectionsSection(heartRate: model.heartRate, health: model.health, agents: model.agents)
                Section {
                    Button(L10n.settingsLanguage) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section(L10n.settingsAbout) {
                    LabeledContent(L10n.settingsVersion, value: version)
                }
            }
            .navigationTitle(L10n.tabSettings)
        }
    }
}

/// Everything Ammutta connects to: the heart-rate sensor, Apple Health and AI agents.
private struct ConnectionsSection: View {
    let heartRate: any HeartRateSource
    @Bindable var health: HealthSync
    let agents: AgentConnector
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            NavigationLink {
                HeartRateSensorView()
            } label: {
                LabeledContent {
                    Text(heartRate.sensorName ?? L10n.sensorNone)
                } label: {
                    Label(L10n.sensorTitle, systemImage: "heart")
                }
            }
            .accessibilityIdentifier("settings.heartRate")
            if health.isAvailable {
                Toggle(isOn: $health.isEnabled) {
                    Label(L10n.settingsHealthSync, systemImage: "heart.text.square")
                }
                .accessibilityIdentifier("settings.healthSync")
                if health.isEnabled, !health.isAuthorized {
                    Button(L10n.healthOpenSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
            if agents.isAvailable {
                NavigationLink {
                    AgentsView(agents: agents)
                } label: {
                    LabeledContent {
                        Text(agentsSummary)
                    } label: {
                        Label(L10n.settingsAgents, systemImage: "sparkles")
                    }
                }
                .accessibilityIdentifier("settings.agents")
            }
        } header: {
            Text(L10n.settingsConnections)
        } footer: {
            if health.isAvailable, health.isEnabled, !health.isAuthorized {
                Text(L10n.healthNotAllowed)
            }
        }
    }

    private var agentsSummary: String {
        guard agents.isEnabled, agents.isSubscribed else { return L10n.agentsOff }
        return agents.connectedAgents.isEmpty ? L10n.agentsOn : L10n.agentsConnectedCount(agents.connectedAgents.count)
    }
}
