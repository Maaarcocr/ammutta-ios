import AmmuttaCore
import SwiftUI
import UIKit

/// Previews a plan link before anything is saved. Opened by tapping an `ammutta://plan` link,
/// or from Plans to paste one.
struct PlanImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: Result<PlanImport, PlanLink.ParseError>?

    init(request: ImportRequest) {
        _result = State(initialValue: request.result)
    }

    private var preview: PlanImport? {
        if case .success(let preview) = result { return preview }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    previewSections(preview)
                } else {
                    pasteSection
                }
            }
            .navigationTitle(L10n.importTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let preview {
                        Button(L10n.importAdd) {
                            model.confirmImport(preview)
                            dismiss()
                        }
                        .accessibilityIdentifier("import.confirm")
                    } else {
                        Button(L10n.importPreview) { result = model.preparePlanImport(from: text) }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("import.preview")
                    }
                }
            }
        }
    }

    private var pasteSection: some View {
        Section {
            TextField(L10n.importPlaceholder, text: $text, axis: .vertical)
                .lineLimit(3...8)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("import.text")
            Button {
                if let pasted = UIPasteboard.general.string {
                    text = pasted
                    result = model.preparePlanImport(from: pasted)
                }
            } label: {
                Label(L10n.importPaste, systemImage: "doc.on.clipboard")
            }
        } footer: {
            if case .failure(let error) = result {
                Text(L10n.importError(error))
                    .foregroundStyle(.red)
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
