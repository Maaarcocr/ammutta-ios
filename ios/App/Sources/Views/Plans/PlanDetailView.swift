import AmmuttaCore
import SwiftUI

struct PlanDetailView: View {
    let planID: PlanID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Plan?
    @State private var confirmingDelete = false

    var body: some View {
        if let plan = model.plan(planID) {
            content(plan)
        } else {
            ContentUnavailableView(L10n.planMissing, systemImage: "questionmark.folder")
        }
    }

    private func content(_ plan: Plan) -> some View {
        List {
            Section {
                LabeledContent(L10n.planEstimated, value: L10n.approximately(Format.workoutDuration(plan.estimatedSeconds)))
                if let last = model.lastPerformed(plan) {
                    LabeledContent(L10n.planLastPerformed) {
                        Text(last, format: .relative(presentation: .named))
                    }
                }
            }
            Section(L10n.planExercises) {
                ForEach(plan.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name(of: exercise.exercise))
                            .font(.headline)
                        Text(Format.setsSummary(exercise.sets, unit: model.weightUnit))
                            .font(.subheadline)
                        Text(L10n.restValue(Format.clock(exercise.restSeconds)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(plan.name)
        .safeAreaInset(edge: .bottom) {
            Button {
                model.startWorkout(from: plan)
            } label: {
                Label(L10n.planStart, systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(Color("OnAccent"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .accessibilityIdentifier("plan.start")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.edit) { editing = plan }
            }
            ToolbarItem(placement: .secondaryAction) {
                if let url = model.shareURL(for: plan) {
                    ShareLink(item: url) {
                        Label(L10n.planShareLink, systemImage: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    model.duplicate(plan)
                } label: {
                    Label(L10n.planDuplicate, systemImage: "plus.square.on.square")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(L10n.delete, systemImage: "trash")
                }
            }
        }
        .sheet(item: $editing) { plan in
            PlanEditorView(plan: plan, isNew: false)
        }
        .confirmationDialog(L10n.planDeleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L10n.delete, role: .destructive) {
                model.delete(plan)
                dismiss()
            }
        }
    }
}
