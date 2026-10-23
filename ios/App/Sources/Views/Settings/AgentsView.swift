import StoreKit
import SwiftUI
import UIKit

/// The AI agents add-on: a subscription pitch until subscribed, then the connected agents, a
/// guided way to connect another, and the subscription.
struct AgentsView: View {
    let agents: AgentConnector

    var body: some View {
        Group {
            if agents.isSubscribed {
                AgentsList(agents: agents)
            } else {
                AgentsSubscribeView(agents: agents)
            }
        }
        .navigationTitle(L10n.settingsAgents)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { agents.activate() }
    }
}

/// StoreKit's subscription screen with our own header. Purchases carry this phone's connector
/// account, so the server can tell whose subscription it is.
private struct AgentsSubscribeView: View {
    let agents: AgentConnector

    var body: some View {
        SubscriptionStoreView(productIDs: [AgentSubscription.productID]) {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text(L10n.agentsPitchTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(L10n.agentsPitchBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.agentsFeatureRead, systemImage: "chart.line.uptrend.xyaxis")
                    Label(L10n.agentsFeatureWrite, systemImage: "list.bullet.clipboard")
                    Label(L10n.agentsFeaturePrivate, systemImage: "lock")
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .storeButton(.visible, for: .restorePurchases, .redeemCode)
        .inAppPurchaseOptions { _ in
            guard let token = agents.accountToken else { return [] }
            return [.appAccountToken(token)]
        }
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(let verification)) = result {
                agents.transactionArrived(verification.jwsRepresentation)
                if case .verified(let transaction) = verification { await transaction.finish() }
            }
        }
    }
}

private struct AgentsList: View {
    let agents: AgentConnector

    var body: some View {
        List {
            Section {
                ForEach(agents.connectedAgents) { agent in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                            Text(L10n.agentsConnectedDate(agent.connectedAt))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkle")
                    }
                }
                ConnectAgentButton(agents: agents)
            } header: {
                Text(L10n.agentsConnectedHeader)
            } footer: {
                if agents.isOffline {
                    Text(L10n.agentsOffline)
                } else if let lastSynced = agents.lastSynced {
                    Text(L10n.agentsSynced(lastSynced))
                }
            }
            Section(L10n.agentsSubscription) {
                LabeledContent(L10n.settingsAgents, value: L10n.agentsSubscriptionActive)
                ManageSubscriptionButton()
            }
            Section {
                if !agents.connectedAgents.isEmpty {
                    Button(L10n.agentsDisconnect, role: .destructive) {
                        agents.disconnectAgents()
                    }
                    .accessibilityIdentifier("agents.disconnect")
                }
                TurnOffButton(agents: agents)
            }
        }
        .refreshable {
            agents.refresh()
            await agents.settled()
        }
    }
}

private struct ConnectAgentButton: View {
    let agents: AgentConnector
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label(L10n.agentsConnect, systemImage: "plus")
        }
        .accessibilityIdentifier("agents.connect")
        .sheet(isPresented: $showing) {
            ConnectAgentSheet(agents: agents)
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

/// Deleting the data on the server can't be undone, so it asks first.
private struct TurnOffButton: View {
    let agents: AgentConnector
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(L10n.agentsTurnOff, role: .destructive) { confirming = true }
            .alert(L10n.agentsTurnOffTitle, isPresented: $confirming) {
                Button(L10n.agentsTurnOffConfirm, role: .destructive) {
                    agents.turnOffAndDeleteData()
                    dismiss()
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.agentsTurnOffMessage)
            }
    }
}

/// Connecting an agent, step by step: the address to add, then a fresh code to type. The sheet
/// watches for the agent to sign in and confirms by itself.
private struct ConnectAgentSheet: View {
    let agents: AgentConnector
    @Environment(\.dismiss) private var dismiss
    /// Bumped by "New code" to fetch another one.
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            Group {
                if case .connected(let name) = agents.pairingStatus {
                    ConnectedView(name: name) { dismiss() }
                } else {
                    steps
                }
            }
            .navigationTitle(L10n.agentsConnect)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if agents.pairingStatus == .waiting || agents.pairingStatus == .expired {
                        Button(L10n.cancel) { dismiss() }
                    }
                }
            }
        }
        .task(id: attempt) {
            await agents.startPairing()
            await agents.watchPairing()
        }
        .sensoryFeedback(.success, trigger: agents.pairingStatus) { _, status in
            if case .connected = status { true } else { false }
        }
    }

    private var steps: some View {
        List {
            if let url = agents.connectorURL {
                Section {
                    Text(url.absoluteString)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    HStack {
                        CopyButton(title: L10n.agentsCopyShort, value: url.absoluteString)
                            .accessibilityIdentifier("agents.copyAddress")
                        ShareLink(item: url) {
                            Label(L10n.agentsShare, systemImage: "square.and.arrow.up")
                        }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text(L10n.agentsStep1)
                } footer: {
                    Text(L10n.agentsStep1Hint)
                }
            }
            Section {
                codeCard
            } header: {
                Text(L10n.agentsStep2)
            }
            if agents.pairing != nil, agents.pairingStatus == .waiting {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.agentsWaiting)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var codeCard: some View {
        VStack(spacing: 10) {
            if let pairing = agents.pairing {
                let expired = agents.pairingStatus == .expired
                Text(verbatim: "\(pairing.code.prefix(4)) \(pairing.code.dropFirst(4))")
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .foregroundStyle(expired ? .secondary : .primary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("agents.code")
                if expired {
                    Text(L10n.agentsExpired)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(L10n.agentsNewCode) { attempt += 1 }
                        .buttonStyle(.bordered)
                } else {
                    HStack(spacing: 4) {
                        Text(L10n.agentsExpiresIn)
                        Text(timerInterval: min(Date.now, pairing.expiresAt)...pairing.expiresAt, countsDown: true)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    CopyButton(title: L10n.agentsCopyCode, value: pairing.code)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("agents.copyCode")
                }
            } else if agents.pairingFailed {
                Text(L10n.agentsPairingFailed)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(L10n.agentsNewCode) { attempt += 1 }
                    .buttonStyle(.bordered)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct ConnectedView: View {
    let name: String
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(L10n.agentsConnectedTitle(name))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(L10n.agentsConnectedBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: done) {
                Text(L10n.done)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("agents.done")
        }
        .padding()
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
