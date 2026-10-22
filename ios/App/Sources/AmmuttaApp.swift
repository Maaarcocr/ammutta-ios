import AmmuttaPersistence
import SwiftUI

@main
struct AmmuttaApp: App {
    @State private var model: AppModel

    init() {
        // Composition root: the only place that builds the store and app model.
        let arguments = ProcessInfo.processInfo.arguments
        let uiTesting = arguments.contains("-ui-testing")
        let store: AmmuttaStore
        do {
            store = try AmmuttaStore(inMemory: uiTesting)
        } catch {
            fatalError("Could not open the Ammutta database: \(error)")
        }
        // UI tests must not raise the notification permission prompt.
        let alerts: any TimerAlerting = uiTesting ? DisabledAlerting() : NotificationAlerting()
        let activityPresenter: any WorkoutActivityPresenting = uiTesting ? DisabledActivityPresenter() : LiveActivityPresenter()
        // UI tests never touch Bluetooth; -fake-heart-rate shows a connected sensor.
        let heartRate: any HeartRateSource = if uiTesting {
            arguments.contains("-fake-heart-rate") ? FakeHeartRateSource(sensorName: "Fitbit Air", readingOnStart: 128) : FakeHeartRateSource()
        } else {
            BluetoothHeartRateSource()
        }
        let health: any HealthSyncing = uiTesting ? FakeHealthSync() : HealthKitSync()
        // The agent connector's address comes from the build (AMMUTTA_AGENT_SERVER_HOST); empty hides the feature.
        let agentHost = Bundle.main.object(forInfoDictionaryKey: "AmmuttaAgentServerHost") as? String ?? ""
        let agentServer: (any AgentServer)? = uiTesting ? FakeAgentServer() : (agentHost.isEmpty ? nil : HTTPAgentServer(host: agentHost))
        let agentAccounts: any AgentAccountStore = uiTesting ? MemoryAgentAccountStore() : KeychainAgentAccountStore()
        let model = AppModel(
            store: store, alerts: alerts, activityPresenter: activityPresenter, heartRate: heartRate,
            healthService: health, agentServer: agentServer, agentAccounts: agentAccounts
        )
        model.load()
        if uiTesting, arguments.contains("-seed-sample-plan") {
            model.seedSamplePlan()
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
