import AmmuttaCore
import SwiftUI

/// The first tab: your plans as cards (open one to start it), plus a play button in the
/// navigation bar for an empty workout.
struct PlansView: View {
    @Environment(AppModel.self) private var model
    /// The plan editor, for a new plan or one picked from a card's menu.
    @State private var editor: PlanEditorRequest?
    @State private var deleting: Plan?
    @State private var confirmingDelete = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                plans
                    .padding()
            }
            .navigationTitle(L10n.tabStart)
            .navigationDestination(for: PlanID.self) { id in
                PlanDetailView(planID: id)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    StartEmptyWorkoutButton()
                    Button(action: newPlan) {
                        Label(L10n.plansNew, systemImage: "plus")
                    }
                    .accessibilityIdentifier("plans.add")
                }
            }
            .sheet(item: $editor) { request in
                PlanEditorView(plan: request.plan, isNew: request.isNew)
            }
            .alert(L10n.planDeleteTitle, isPresented: $confirmingDelete, presenting: deleting) { plan in
                Button(L10n.delete, role: .destructive) { model.delete(plan) }
                    .accessibilityIdentifier("plans.confirmDelete")
                Button(L10n.cancel, role: .cancel) {}
            }
        }
        .sheet(item: $model.importRequest) { request in
            PlanImportSheet(request: request)
        }
    }

    private func newPlan() {
        editor = PlanEditorRequest(plan: Plan(name: "", createdAt: .now), isNew: true)
    }

    @ViewBuilder private var plans: some View {
        if model.plans.isEmpty {
            ContentUnavailableView {
                Label(L10n.plansEmptyTitle, systemImage: "list.bullet.clipboard")
            } description: {
                Text(L10n.plansEmptyMessage)
            } actions: {
                Button(action: newPlan) {
                    Text(L10n.plansNew)
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.plansHeader)
                    .font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(model.plans) { plan in
                        PlanCard(
                            plan: plan,
                            edit: { editor = PlanEditorRequest(plan: plan, isNew: false) },
                            delete: {
                                deleting = plan
                                confirmingDelete = true
                            }
                        )
                    }
                }
            }
        }
    }
}

/// Starts a workout without a plan, after asking, so a stray tap doesn't start one.
private struct StartEmptyWorkoutButton: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        Button {
            confirming = true
        } label: {
            Label(L10n.plansStartEmpty, systemImage: "play.fill")
        }
        .accessibilityIdentifier("plans.startEmpty")
        .alert(L10n.plansStartEmptyTitle, isPresented: $confirming) {
            Button(L10n.plansStartEmptyConfirm) { model.startEmptyWorkout() }
                .accessibilityIdentifier("plans.confirmStartEmpty")
            Button(L10n.cancel, role: .cancel) {}
        }
    }
}

/// What the plan editor sheet opens with.
private struct PlanEditorRequest: Identifiable {
    let plan: Plan
    let isNew: Bool
    var id: PlanID { plan.id }
}

/// A plan as a card: its name, its exercises and when it was last done. Tapping it opens the
/// plan (to start it); the … menu edits, duplicates or deletes it.
private struct PlanCard: View {
    @Environment(AppModel.self) private var model
    let plan: Plan
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        NavigationLink(value: plan.id) {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // Room for the … menu on top of the card.
                    .padding(.trailing, 36)
                Text(plan.exercises.map { model.name(of: $0.exercise) }.formatted(.list(type: .and)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let last = model.lastPerformed(plan) {
                    Label {
                        Text(last, format: .relative(presentation: .named))
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plans.row")
        .overlay(alignment: .topTrailing) {
            Menu {
                Button(action: edit) {
                    Label(L10n.edit, systemImage: "pencil")
                }
                .accessibilityIdentifier("plans.edit")
                Button {
                    model.duplicate(plan)
                } label: {
                    Label(L10n.planDuplicate, systemImage: "plus.square.on.square")
                }
                .accessibilityIdentifier("plans.duplicate")
                Button(role: .destructive, action: delete) {
                    Label(L10n.delete, systemImage: "trash")
                }
                .accessibilityIdentifier("plans.delete")
            } label: {
                Label(L10n.plansOptions, systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityIdentifier("plans.menu")
            .padding(4)
        }
    }
}
