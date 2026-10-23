import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            // Icons only, so every tab is the same size; VoiceOver still reads each name.
            Tab(value: AppTab.plans) {
                PlansView()
            } label: {
                TabIcon(title: L10n.tabStart, systemImage: "list.bullet.clipboard")
            }
            Tab(value: AppTab.exercises) {
                ExercisesView()
            } label: {
                TabIcon(title: L10n.tabExercises, systemImage: "dumbbell")
            }
            Tab(value: AppTab.history) {
                HistoryView()
            } label: {
                TabIcon(title: L10n.tabHistory, systemImage: "clock.arrow.circlepath")
            }
            Tab(value: AppTab.settings) {
                SettingsView()
            } label: {
                TabIcon(title: L10n.tabSettings, systemImage: "gearshape")
            }
        }
        // The only presentation on the root. The plan-link sheet belongs to the Start Workout screen:
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

/// A tab bar icon without a visible title; the title is its VoiceOver label.
private struct TabIcon: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .accessibilityLabel(title)
    }
}
