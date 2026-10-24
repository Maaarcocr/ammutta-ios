import AmmuttaCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
                Section(L10n.settingsData) {
                    ExportBackupRow()
                    RestoreBackupButton()
                    ImportHistoryButton()
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

/// Shares a JSON file with everything, to keep a copy or move to another phone.
private struct ExportBackupRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let data = try? model.backup().encoded() {
            ShareLink(item: BackupFile(data: data), preview: SharePreview(L10n.settingsBackupName)) {
                Label(L10n.settingsExportBackup, systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("settings.exportBackup")
        }
    }
}

/// Picks a backup file, then asks before replacing everything with it.
private struct RestoreBackupButton: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var backup: AmmuttaBackup?
    @State private var confirming = false
    @State private var unreadable = false

    var body: some View {
        Button {
            picking = true
        } label: {
            Label(L10n.settingsRestoreBackup, systemImage: "arrow.counterclockwise")
        }
        .accessibilityIdentifier("settings.restoreBackup")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result, let data = PickedFile.data(at: url),
                  let read = try? AmmuttaBackup.decode(data)
            else {
                unreadable = true
                return
            }
            backup = read
            confirming = true
        }
        .alert(L10n.settingsRestoreTitle, isPresented: $confirming, presenting: backup) { backup in
            Button(L10n.settingsRestoreConfirm, role: .destructive) { model.restore(backup) }
            Button(L10n.cancel, role: .cancel) {}
        } message: { _ in
            Text(L10n.settingsRestoreMessage)
        }
        .alert(L10n.settingsFileError, isPresented: $unreadable) {}
    }
}

/// Picks a Strong or Hevy CSV export and adds its workouts to history.
private struct ImportHistoryButton: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var added = 0
    @State private var showingResult = false
    @State private var unreadable = false

    var body: some View {
        Button {
            picking = true
        } label: {
            Label(L10n.settingsImportHistory, systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("settings.importHistory")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result, let data = PickedFile.data(at: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  let workouts = try? HistoryCSV.parse(text, unit: model.weightUnit, timeZone: .current)
            else {
                unreadable = true
                return
            }
            added = model.importHistory(workouts)
            showingResult = true
        }
        .alert(L10n.settingsImported(added), isPresented: $showingResult) {}
        .alert(L10n.settingsFileError, isPresented: $unreadable) {}
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
