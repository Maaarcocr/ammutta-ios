import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab(L10n.tabPlans, systemImage: "list.bullet.clipboard", value: AppTab.plans) {
                PlansView()
            }
            Tab(L10n.tabExercises, systemImage: "dumbbell", value: AppTab.exercises) {
                ExercisesView()
            }
            Tab(L10n.tabHistory, systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab(L10n.tabSettings, systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        // The only presentation on the root. The plan-link sheet belongs to the Plans screen:
        // two presentations on one view stopped the workout screen from appearing.
        .fullScreenCover(item: $model.session, onDismiss: { model.showDeferredImport() }) { session in
            WorkoutView(session: session)
                .environment(model)
        }
        .onOpenURL { url in
            model.handleOpenURL(url)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.session?.refresh()
                model.health.run()
                model.agents.refresh()
            }
        }
        .alert(L10n.errorTitle, isPresented: $model.showingError) {
            Button(L10n.ok) {}
        } message: {
            Text(L10n.errorMessage)
        }
    }
}
