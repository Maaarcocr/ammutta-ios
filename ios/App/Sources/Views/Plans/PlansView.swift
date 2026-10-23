import AmmuttaCore
import SwiftUI

struct PlansView: View {
    @Environment(AppModel.self) private var model
    @State private var newPlan: Plan?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                ForEach(model.plans) { plan in
                    NavigationLink(value: plan.id) {
                        PlanRow(plan: plan)
                    }
                    .accessibilityIdentifier("plans.row")
                }
            }
            .overlay {
                if model.plans.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.plansEmptyTitle, systemImage: "list.bullet.clipboard")
                    } description: {
                        Text(L10n.plansEmptyMessage)
                    } actions: {
                        Button {
                            startNewPlan()
                        } label: {
                            Text(L10n.plansNew)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(L10n.tabPlans)
            .navigationDestination(for: PlanID.self) { id in
                PlanDetailView(planID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startNewPlan()
                    } label: {
                        Label(L10n.plansNew, systemImage: "plus")
                    }
                    .accessibilityIdentifier("plans.add")
                }
            }
            .sheet(item: $newPlan) { plan in
                PlanEditorView(plan: plan, isNew: true)
            }
        }
        .sheet(item: $model.importRequest) { request in
            PlanImportSheet(request: request)
        }
    }

    private func startNewPlan() {
        newPlan = Plan(name: "", createdAt: .now)
    }
}

private struct PlanRow: View {
    @Environment(AppModel.self) private var model
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.name)
                .font(.headline)
            HStack(spacing: 6) {
                Text(L10n.exerciseCount(plan.exercises.count))
                if let last = model.lastPerformed(plan) {
                    Text(verbatim: "·")
                    Text(last, format: .relative(presentation: .named))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
