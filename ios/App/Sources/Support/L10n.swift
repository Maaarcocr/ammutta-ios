import AmmuttaCore
import SwiftUI

/// Every user-facing string in the app. Keys live in Localizable.xcstrings (English and
/// Italian); `scripts/check-strings.py` fails CI when a key here is missing a translation,
/// or when a view passes a raw string literal instead of going through this file.
enum L10n {
    // MARK: Tabs
    static var tabPlans: LocalizedStringKey { "tab.plans" }
    static var tabExercises: LocalizedStringKey { "tab.exercises" }
    static var tabHistory: LocalizedStringKey { "tab.history" }
    static var tabSettings: LocalizedStringKey { "tab.settings" }

    // MARK: Common
    static var cancel: LocalizedStringKey { "common.cancel" }
    static var save: LocalizedStringKey { "common.save" }
    static var done: LocalizedStringKey { "common.done" }
    static var delete: LocalizedStringKey { "common.delete" }
    static var edit: LocalizedStringKey { "common.edit" }
    static var more: LocalizedStringKey { "common.more" }
    static var ok: LocalizedStringKey { "common.ok" }
    static func fraction(_ part: Int, _ total: Int) -> String { String(localized: "common.fraction \(part) \(total)") }
    static var errorTitle: LocalizedStringKey { "error.title" }
    static var errorMessage: LocalizedStringKey { "error.message" }

    // MARK: Plans
    static var plansNew: LocalizedStringKey { "plans.new" }
    static var plansEmptyTitle: LocalizedStringKey { "plans.empty.title" }
    static var plansEmptyMessage: LocalizedStringKey { "plans.empty.message" }
    static func exerciseCount(_ count: Int) -> String { String(localized: "plan.exerciseCount \(count)") }
    static var planLastPerformed: LocalizedStringKey { "plan.lastPerformed" }
    static var planEstimated: LocalizedStringKey { "plan.estimated" }
    static func approximately(_ duration: String) -> String { String(localized: "plan.approximately \(duration)") }
    static var planExercises: LocalizedStringKey { "plan.exercises" }
    static var planStart: LocalizedStringKey { "plan.start" }
    static var planDuplicate: LocalizedStringKey { "plan.duplicate" }
    static func copyName(_ name: String) -> String { String(localized: "plan.copyName \(name)") }
    static var planDeleteTitle: LocalizedStringKey { "plan.delete.title" }
    static var planMissing: LocalizedStringKey { "plan.missing" }
    static func restValue(_ duration: String) -> String { String(localized: "plan.restValue \(duration)") }
    static var planShareLink: LocalizedStringKey { "plan.shareLink" }

    // MARK: Plan links
    static var plansImportLink: LocalizedStringKey { "plans.importLink" }
    static var importTitle: LocalizedStringKey { "import.title" }
    static var importPlaceholder: LocalizedStringKey { "import.placeholder" }
    static var importPaste: LocalizedStringKey { "import.paste" }
    static var importPreview: LocalizedStringKey { "import.preview" }
    static var importAdd: LocalizedStringKey { "import.add" }
    static var importNewBadge: LocalizedStringKey { "import.newBadge" }
    static var plansSharePrompt: LocalizedStringKey { "plans.sharePrompt" }
    static func promptFormat(_ repsKeys: String, _ timedKeys: String) -> String {
        String(localized: "prompt.format \(repsKeys) \(timedKeys)")
    }
    static func promptOwnExercises(_ list: String) -> String { String(localized: "prompt.ownExercises \(list)") }
    static var promptKindReps: String { String(localized: "prompt.kind.reps") }
    static var promptKindTimed: String { String(localized: "prompt.kind.timed") }
    static var promptUnitKilograms: String { String(localized: "prompt.unit.kg") }
    static var promptUnitPounds: String { String(localized: "prompt.unit.lb") }
    static var promptReply: String { String(localized: "prompt.reply") }
    static func importError(_ error: PlanLink.ParseError) -> String {
        switch error {
        case .notAPlanLink: String(localized: "import.error.notLink")
        case .tooLong: String(localized: "import.error.tooLong")
        case .unsupportedVersion: String(localized: "import.error.version")
        case .invalidUnit: String(localized: "import.error.unit")
        case .missingName: String(localized: "import.error.name")
        case .nameTooLong: String(localized: "import.error.nameTooLong")
        case .noExercises: String(localized: "import.error.noExercises")
        case .tooManyExercises: String(localized: "import.error.tooManyExercises")
        case .invalidExercise(let position): String(localized: "import.error.exercise \(position)")
        }
    }

    // MARK: Plan editor
    static var planEditorNewTitle: LocalizedStringKey { "planEditor.newTitle" }
    static var planEditorEditTitle: LocalizedStringKey { "planEditor.editTitle" }
    static var planEditorName: LocalizedStringKey { "planEditor.name" }
    static var planEditorAddExercise: LocalizedStringKey { "planEditor.addExercise" }
    static var rest: LocalizedStringKey { "exerciseEditor.rest" }
    static var sets: LocalizedStringKey { "exerciseEditor.sets" }
    static var applyToAll: LocalizedStringKey { "exerciseEditor.applyToAll" }

    // MARK: Sets
    static var addSet: LocalizedStringKey { "set.add" }
    static func setNumber(_ number: Int) -> String { String(localized: "set.number \(number)") }
    static var weight: LocalizedStringKey { "set.weight" }
    static var duration: LocalizedStringKey { "set.duration" }
    static var reps: LocalizedStringKey { "set.repsLabel" }
    static var repsText: String { String(localized: "set.repsLabel") }
    static func weightIn(_ unit: String) -> String { String(localized: "set.weightIn \(unit)") }
    static var secondsLabel: String { String(localized: "set.secondsLabel") }
    static func repsCount(_ count: Int) -> String { String(localized: "set.reps \(count)") }
    static func setsCount(_ count: Int) -> String { String(localized: "set.count \(count)") }
    static func repsWeight(_ count: Int, _ weight: String) -> String { String(localized: "set.repsWeight \(count) \(weight)") }
    static var skipped: LocalizedStringKey { "set.skipped" }
    static var notDone: LocalizedStringKey { "set.notDone" }
    static var unitKg: String { String(localized: "unit.kg") }
    static var unitLb: String { String(localized: "unit.lb") }
    static var unitKgName: LocalizedStringKey { "unit.kg.name" }
    static var unitLbName: LocalizedStringKey { "unit.lb.name" }

    // MARK: Exercises
    static var pickerTitle: LocalizedStringKey { "picker.title" }
    static var exercisesNew: LocalizedStringKey { "exercises.new" }
    static var exercisesCustom: LocalizedStringKey { "exercises.custom" }
    static var exercisesBuiltIn: LocalizedStringKey { "exercises.builtIn" }
    static var customLabel: String { String(localized: "exercise.customLabel") }
    static var exerciseKind: LocalizedStringKey { "exercise.kind" }
    static var kindReps: LocalizedStringKey { "kind.reps" }
    static var kindDuration: LocalizedStringKey { "kind.duration" }
    static var kindRepsText: String { String(localized: "kind.reps") }
    static var kindDurationText: String { String(localized: "kind.duration") }
    static var exerciseEquipment: LocalizedStringKey { "exercise.equipment" }
    static var exerciseMuscles: LocalizedStringKey { "exercise.muscles" }
    static var exerciseTechnique: LocalizedStringKey { "exercise.technique" }
    static var exerciseLast: LocalizedStringKey { "exercise.last" }
    static var exerciseHistory: LocalizedStringKey { "exercise.history" }
    static var exerciseNoHistory: LocalizedStringKey { "exercise.noHistory" }
    static var exerciseName: LocalizedStringKey { "exercise.name" }
    static var exerciseDuplicate: LocalizedStringKey { "exercise.duplicate" }
    static var exerciseDeleted: String { String(localized: "exercise.deleted") }
    static var exerciseDeleteTitle: LocalizedStringKey { "exercise.delete.title" }
    static var exerciseEditTitle: LocalizedStringKey { "exerciseEditor.editTitle" }

    // MARK: History
    static var historyEmpty: LocalizedStringKey { "history.empty" }
    static var historyDeleteTitle: LocalizedStringKey { "history.delete.title" }

    // MARK: Workout
    static var workoutFinish: LocalizedStringKey { "workout.finish" }
    static var workoutDiscard: LocalizedStringKey { "workout.discard" }
    static var workoutDiscardTitle: LocalizedStringKey { "workout.discard.title" }
    static var workoutSkipSet: LocalizedStringKey { "workout.skipSet" }
    static var workoutRemoveSet: LocalizedStringKey { "workout.removeSet" }
    static func lastTime(_ value: String) -> String { String(localized: "workout.last \(value)") }
    static var workoutLogSet: LocalizedStringKey { "workout.logSet" }
    static var workoutStartTimer: LocalizedStringKey { "workout.startTimer" }
    static var workoutStopTimer: LocalizedStringKey { "workout.stopTimer" }
    static var workoutLogged: LocalizedStringKey { "workout.logged" }
    static var increase: LocalizedStringKey { "workout.increase" }
    static var decrease: LocalizedStringKey { "workout.decrease" }
    static var timerRest: LocalizedStringKey { "timer.rest" }
    static var timerWork: LocalizedStringKey { "timer.work" }
    static var timerSkip: LocalizedStringKey { "timer.skip" }
    static var timerMinus: LocalizedStringKey { "timer.minus15" }
    static var timerPlus: LocalizedStringKey { "timer.plus15" }

    // MARK: Timer alerts (Lock Screen notifications)
    static var alertRestTitle: String { String(localized: "alert.rest.title") }
    static var alertRestBody: String { String(localized: "alert.rest.body") }
    static func alertNextSet(_ exercise: String, _ set: Int) -> String { String(localized: "alert.rest.next \(exercise) \(set)") }
    static var alertWorkTitle: String { String(localized: "alert.work.title") }
    static func alertWorkBody(_ exercise: String) -> String { String(localized: "alert.work.body \(exercise)") }
    static var alertsOff: LocalizedStringKey { "workout.alertsOff" }

    // MARK: Live Activity
    static func activitySetOf(_ set: Int, _ total: Int) -> String { String(localized: "activity.setOf \(set) \(total)") }
    static var activityAllDone: String { String(localized: "activity.allDone") }
    static var timerRestText: String { String(localized: "timer.rest") }
    static var timerWorkText: String { String(localized: "timer.work") }
    static var openSettings: LocalizedStringKey { "workout.openSettings" }

    // MARK: Summary
    static var summaryTitle: LocalizedStringKey { "summary.title" }
    static var summaryDuration: LocalizedStringKey { "summary.duration" }
    static var summarySets: LocalizedStringKey { "summary.sets" }
    static var summaryVolume: LocalizedStringKey { "summary.volume" }
    static var summaryHeartRate: LocalizedStringKey { "summary.heartRate" }
    static var summaryHeartRateAverage: LocalizedStringKey { "summary.heartRateAverage" }
    static var summaryHeartRateMax: LocalizedStringKey { "summary.heartRateMax" }
    static var chartTime: String { String(localized: "chart.time") }
    static var chartHeartRate: String { String(localized: "chart.heartRate") }

    // MARK: Settings
    static var settingsWorkout: LocalizedStringKey { "settings.workout" }
    static var settingsWeightUnit: LocalizedStringKey { "settings.weightUnit" }
    static var settingsDefaultRest: LocalizedStringKey { "settings.defaultRest" }
    static var settingsHeartRate: LocalizedStringKey { "settings.heartRate" }
    static var settingsSensor: LocalizedStringKey { "settings.sensor" }
    static var settingsHealth: LocalizedStringKey { "settings.health" }
    static var settingsHealthSync: LocalizedStringKey { "settings.healthSync" }
    static var healthNotAllowed: LocalizedStringKey { "health.notAllowed" }
    static var healthOpenSettings: LocalizedStringKey { "health.openSettings" }
    static var settingsLanguage: LocalizedStringKey { "settings.language" }
    static var settingsAbout: LocalizedStringKey { "settings.about" }
    static var settingsVersion: LocalizedStringKey { "settings.version" }
    static var settingsTagline: LocalizedStringKey { "settings.tagline" }

    // MARK: Heart rate
    static func bpm(_ value: Int) -> String { String(localized: "heartRate.bpm \(value)") }
    static func heartRateValue(_ value: Int) -> String { String(localized: "heartRate.value \(value)") }
    static var heartRateUnavailable: String { String(localized: "heartRate.unavailable") }
    static var sensorTitle: LocalizedStringKey { "sensor.title" }
    static var sensorMine: LocalizedStringKey { "sensor.mine" }
    static var sensorNearby: LocalizedStringKey { "sensor.nearby" }
    static var sensorForget: LocalizedStringKey { "sensor.forget" }
    static var sensorBluetoothOff: LocalizedStringKey { "sensor.bluetoothOff" }
    static var sensorDenied: LocalizedStringKey { "sensor.denied" }
    static var sensorOpenSettings: LocalizedStringKey { "sensor.openSettings" }
    static var sensorUnsupported: LocalizedStringKey { "sensor.unsupported" }
    static var sensorConnected: String { String(localized: "sensor.connected") }
    static var sensorSearching: String { String(localized: "sensor.searching") }
    static var sensorNone: String { String(localized: "sensor.none") }
    static var sensorUnnamed: String { String(localized: "sensor.unnamed") }
}
