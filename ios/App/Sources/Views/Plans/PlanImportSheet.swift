import AmmuttaCore
import SwiftUI

/// Previews a plan from a tapped `ammutta://plan` link before anything is saved, or says why
/// the link can't be read.
struct PlanImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ImportRequest

    var body: some View {
        NavigationStack {
            Form {
                switch request.result {
                case .success(let preview):
                    previewSections(preview)
                case .failure(let error):
                    Text(L10n.importError(error))
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(L10n.importTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .success(let preview) = request.result {
                        Button(L10n.importAdd) {
                            model.confirmImport(preview)
                            dismiss()
                        }
                        .accessibilityIdentifier("import.confirm")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func previewSections(_ preview: PlanImport) -> some View {
        Section {
            Text(preview.plan.name)
                .font(.title3.weight(.semibold))
            LabeledContent(L10n.planEstimated, value: L10n.approximately(Format.workoutDuration(preview.plan.estimatedSeconds)))
        }
        Section(L10n.planExercises) {
            ForEach(preview.plan.exercises) { exercise in
                let created = preview.newExercise(for: exercise)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(created?.name ?? model.name(of: exercise.exercise))
                            .font(.headline)
                        if created != nil {
                            Text(L10n.importNewBadge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: .capsule)
                        }
                    }
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
}
