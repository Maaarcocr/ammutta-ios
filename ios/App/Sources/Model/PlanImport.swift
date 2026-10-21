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
        importRequest = ImportRequest(result: result)
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
