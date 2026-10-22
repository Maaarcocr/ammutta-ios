import AmmuttaCore
import StoreKit
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
            if agents.isEnabled, !agents.isSubscribed {
                SubscribeButton(agents: agents)
                RedeemCodeButton(agents: agents)
            }
            if agents.isEnabled, agents.isSubscribed, let url = agents.connectorURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.agentsAddress)
                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                CopyButton(title: L10n.agentsCopy, value: url.absoluteString)
                    .accessibilityIdentifier("agents.copyAddress")
                if let code = agents.pairingCode {
                    LabeledContent(L10n.agentsCode) {
                        Text(code)
                            .font(.title3.monospaced())
                            .textSelection(.enabled)
                            .accessibilityIdentifier("agents.code")
                    }
                    CopyButton(title: L10n.agentsCopyCode, value: code)
                        .accessibilityIdentifier("agents.copyCode")
                }
                Button(L10n.agentsGetCode) {
                    agents.requestPairingCode()
                }
                .accessibilityIdentifier("agents.getCode")
                Button(L10n.agentsDisconnect, role: .destructive) {
                    agents.disconnectAgents()
                }
                ManageSubscriptionButton()
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

/// Opens the App Store subscription screen. Purchases carry this phone's connector account, so
/// the server can tell whose subscription it is.
private struct SubscribeButton: View {
    let agents: AgentConnector
    @State private var showing = false

    var body: some View {
        Button(L10n.agentsSubscribe) { showing = true }
            .accessibilityIdentifier("agents.subscribe")
            .sheet(isPresented: $showing) {
                SubscriptionStoreView(productIDs: [AgentSubscription.productID])
                    .storeButton(.visible, for: .restorePurchases)
                    .inAppPurchaseOptions { _ in
                        guard let token = agents.accountToken else { return [] }
                        return [.appAccountToken(token)]
                    }
                    .onInAppPurchaseCompletion { _, result in
                        if case .success(.success(let verification)) = result {
                            agents.transactionArrived(verification.jwsRepresentation)
                            if case .verified(let transaction) = verification { await transaction.finish() }
                            showing = false
                        }
                    }
                    .onDisappear { agents.refresh() }
            }
    }
}

/// Apple's offer-code sheet: codes from App Store Connect can give free or discounted months.
private struct RedeemCodeButton: View {
    let agents: AgentConnector
    @State private var showing = false

    var body: some View {
        Button(L10n.agentsRedeem) { showing = true }
            .offerCodeRedemption(isPresented: $showing) { _ in
                agents.refresh()
            }
    }
}

private struct ManageSubscriptionButton: View {
    @State private var showing = false

    var body: some View {
        Button(L10n.agentsManage) { showing = true }
            .manageSubscriptionsSheet(isPresented: $showing)
    }
}

/// Copies a value and says so: the label turns into "Copied" with a checkmark for a moment.
private struct CopyButton: View {
    let title: LocalizedStringKey
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Label(copied ? L10n.agentsCopied : title, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }
}
