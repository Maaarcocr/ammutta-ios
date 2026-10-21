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
        .fullScreenCover(item: $model.session) { session in
            WorkoutView(session: session)
                .environment(model)
        }
        // During a workout the import sheet is presented from the workout screen instead.
        .sheet(item: Binding(
            get: { model.session == nil ? model.importRequest : nil },
            set: { model.importRequest = $0 }
        )) { request in
            PlanImportSheet(request: request)
                .environment(model)
        }
        .onOpenURL { url in
            model.handleOpenURL(url)
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
