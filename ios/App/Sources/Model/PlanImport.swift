import AmmuttaCore
import Foundation

enum AppTab: Hashable {
    case plans, exercises, history, settings
}

/// A plan from a link, resolved against this phone's exercises but not saved yet.
struct PlanImport {
    var plan: Plan
    /// Custom exercises the link needs that don't exist yet; created only on confirm.
    var newExercises: [CustomExercise]

    func newExercise(for exercise: PlanExercise) -> CustomExercise? {
        guard case .custom(let id) = exercise.exercise else { return nil }
        return newExercises.first { $0.id == id }
    }
}

struct ImportRequest: Identifiable {
    let id = UUID()
    /// nil while the user still has to paste a link.
    let result: Result<PlanImport, PlanLink.ParseError>?
}

extension AppModel {
    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == PlanLink.scheme else { return }
        let result: Result<PlanImport, PlanLink.ParseError>
        do throws(PlanLink.ParseError) {
            result = .success(resolve(try PlanLink.parse(url)))
        } catch {
            result = .failure(error)
        }
        // During a workout the workout screen covers everything: show the link after it closes.
        if session == nil {
            importRequest = ImportRequest(result: result)
        } else {
            deferredImport = ImportRequest(result: result)
        }
    }

    /// Called once the workout screen has closed.
    func showDeferredImport() {
        guard let deferredImport else { return }
        self.deferredImport = nil
        importRequest = deferredImport
    }

    func startPasteImport() {
        importRequest = ImportRequest(result: nil)
    }

    func preparePlanImport(from text: String) -> Result<PlanImport, PlanLink.ParseError> {
        do throws(PlanLink.ParseError) {
            return .success(resolve(try PlanLink.parse(text)))
        } catch {
            return .failure(error)
        }
    }

    /// Creates the missing custom exercises, then saves the plan.
    func confirmImport(_ preview: PlanImport) {
        for exercise in preview.newExercises {
            save(exercise)
        }
        save(preview.plan)
        importRequest = nil
        selectedTab = .plans
    }

    /// A prompt that teaches an AI assistant the link format, listing the built-in keys and
    /// this user's own exercises, in the user's weight unit.
    func planLinkPrompt() -> String {
        let reps = ExerciseCatalog.all.filter { $0.kind == .reps }.map(\.key).joined(separator: ", ")
        let timed = ExerciseCatalog.all.filter { $0.kind == .duration }.map(\.key).joined(separator: ", ")
        var paragraphs = [L10n.promptFormat(reps, timed)]
        let own = customExercises
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { "\($0.name) (\($0.kind == .reps ? L10n.promptKindReps : L10n.promptKindTimed))" }
        if !own.isEmpty {
            paragraphs.append(L10n.promptOwnExercises(own.joined(separator: ", ")))
        }
        paragraphs.append(weightUnit == .pounds ? L10n.promptUnitPounds : L10n.promptUnitKilograms)
        paragraphs.append(L10n.promptReply)
        return paragraphs.joined(separator: "\n\n")
    }

    func shareURL(for plan: Plan) -> URL? {
        let names = Dictionary(customExercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return PlanLink.url(for: plan, customNames: names, unit: weightUnit)
    }

    /// Built-in keys map to the catalog. Names match a built-in exercise (in the phone's language
    /// or English), then an existing custom exercise of the same kind; otherwise one is created.
    private func resolve(_ draft: PlanLink.Draft) -> PlanImport {
        var created: [CustomExercise] = []
        var exercises: [PlanExercise] = []
        for item in draft.exercises {
            let reference: ExerciseRef
            switch item.reference {
            case .builtIn(let key):
                reference = .builtIn(key: key)
            case .named(let name):
                let target = ExerciseNames.normalized(name)
                let builtIn = ExerciseCatalog.all.first { exercise in
                    exercise.kind == item.kind &&
                        (ExerciseNames.normalized(ExerciseText.name(exercise.key)) == target ||
                         ExerciseNames.normalized(ExerciseText.englishName(exercise.key)) == target)
                }
                let existing = (customExercises + created).first {
                    $0.kind == item.kind && ExerciseNames.normalized($0.name) == target
                }
                if let builtIn {
                    reference = builtIn.ref
                } else if let existing {
                    reference = existing.ref
                } else {
                    let exercise = CustomExercise(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: item.kind, createdAt: .now
                    )
                    created.append(exercise)
                    reference = exercise.ref
                }
            }
            exercises.append(PlanExercise(
                exercise: reference, kind: item.kind,
                restSeconds: item.restSeconds ?? defaultRestSeconds, sets: item.sets
            ))
        }
        return PlanImport(plan: Plan(name: draft.name, exercises: exercises, createdAt: .now), newExercises: created)
    }
}
