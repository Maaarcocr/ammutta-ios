import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView {
            Tab(L10n.tabPlans, systemImage: "list.bullet.clipboard") {
                PlansView()
            }
            Tab(L10n.tabExercises, systemImage: "dumbbell") {
                ExercisesView()
            }
            Tab(L10n.tabHistory, systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }
            Tab(L10n.tabSettings, systemImage: "gearshape") {
                SettingsView()
            }
        }
        .fullScreenCover(item: $model.session) { session in
            WorkoutView(session: session)
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.session?.refresh() }
        }
        .alert(L10n.errorTitle, isPresented: $model.showingError) {
            Button(L10n.ok) {}
        } message: {
            Text(L10n.errorMessage)
        }
    }
}
