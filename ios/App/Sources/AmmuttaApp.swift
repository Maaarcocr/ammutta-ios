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
        let model = AppModel(store: store)
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
