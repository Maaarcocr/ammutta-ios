import XCTest

/// End-to-end flows. Elements are found by accessibility identifier, never by text, so the
/// same tests run in English and Italian. Screenshots are kept in the result bundle and
/// exported by CI, which is how the app is reviewed without a Mac.
final class AmmuttaUITests: XCTestCase {
    @MainActor
    func testCreatePlanRunWorkoutAndReviewHistory() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-weightUnit", "kg"]
        app.launch()
        capture("01-plans-empty")

        element(app, "plans.add").tap()
        let name = app.textFields["planEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        name.tap()
        name.typeText("Push\n")

        element(app, "planEditor.addExercise").tap()
        let firstExercise = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "picker.")).firstMatch
        XCTAssertTrue(firstExercise.waitForExistence(timeout: 30))
        capture("02-exercise-picker")
        firstExercise.tap()

        let save = element(app, "planEditor.save")
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        capture("03-plan-editor")
        save.tap()

        let row = element(app, "plans.row")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        capture("04-plans")
        row.tap()

        let start = element(app, "plan.start")
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        capture("05-plan-detail")
        start.tap()

        let log = element(app, "workout.log")
        XCTAssertTrue(log.waitForExistence(timeout: 30))
        capture("06-workout")
        log.tap()

        let skip = element(app, "timer.skip")
        XCTAssertTrue(skip.waitForExistence(timeout: 30))
        capture("07-rest-timer")
        skip.tap()

        element(app, "workout.finish").tap()
        let done = element(app, "summary.done")
        XCTAssertTrue(done.waitForExistence(timeout: 30))
        capture("08-summary")
        done.tap()

        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(element(app, "history.row").waitForExistence(timeout: 30))
        capture("09-history")

        app.tabBars.buttons.element(boundBy: 1).tap()
        capture("10-exercises")

        app.tabBars.buttons.element(boundBy: 3).tap()
        capture("11-settings")
    }

    @MainActor
    func testTimedSetCountdownAndStop() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-seed-sample-plan", "-weightUnit", "kg"]
        app.launch()

        let row = element(app, "plans.row")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        element(app, "plan.start").tap()

        // Log the three bench press sets, skipping each rest.
        for _ in 0..<3 {
            let log = element(app, "workout.log")
            XCTAssertTrue(log.waitForExistence(timeout: 30))
            log.tap()
            let skip = element(app, "timer.skip")
            if skip.waitForExistence(timeout: 10) { skip.tap() }
        }

        let startTimer = element(app, "workout.start")
        XCTAssertTrue(startTimer.waitForExistence(timeout: 30))
        startTimer.tap()
        XCTAssertTrue(element(app, "workout.stop").waitForExistence(timeout: 30))
        capture("12-timed-set")
        element(app, "workout.stop").tap()
        XCTAssertTrue(element(app, "timer.skip").waitForExistence(timeout: 30))
    }

    @MainActor
    func testOpeningAPlanLinkShowsAPreviewAndAddsThePlan() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-weightUnit", "kg"]
        app.launch()

        let link = "ammutta://plan?v=1&name=Link%20Day&e=barbell-bench-press:3x5@80:180" +
            "&e=Band%20Pull-Apart:3x15:60&e=plank:2x45s:60"
        app.open(try XCTUnwrap(URL(string: link)))

        let confirm = element(app, "import.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        capture("13-plan-link-preview")
        confirm.tap()

        XCTAssertTrue(element(app, "plans.row").waitForExistence(timeout: 30))
        capture("14-plan-link-imported")
    }

    /// Discarding asks with a centered alert, then closes the workout.
    @MainActor
    func testDiscardingAWorkoutAsksFirst() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-seed-sample-plan", "-weightUnit", "kg"]
        app.launch()

        let row = element(app, "plans.row")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        element(app, "plan.start").tap()

        let more = element(app, "workout.more")
        XCTAssertTrue(more.waitForExistence(timeout: 30))
        more.tap()
        let discard = element(app, "workout.discard")
        XCTAssertTrue(discard.waitForExistence(timeout: 30))
        discard.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 30))
        capture("17-discard-alert")
        alert.buttons.matching(identifier: "workout.confirmDiscard").firstMatch.tap()

        // Back on the plan, ready to start again.
        XCTAssertTrue(element(app, "plan.start").waitForExistence(timeout: 30))
    }

    /// Big weights are typed, not reached by pressing + dozens of times.
    @MainActor
    func testTypingAWeightDuringAWorkout() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-seed-sample-plan", "-weightUnit", "kg"]
        app.launch()

        let row = element(app, "plans.row")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        element(app, "plan.start").tap()

        let weight = app.textFields.matching(identifier: "set.weight").firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 30))
        weight.tap()
        // Tapping empties the field, so typing replaces the old 60 kg.
        weight.typeText("120")
        element(app, "keyboard.done").tap()

        XCTAssertEqual(weight.value as? String, "120")
        capture("16-typed-weight")
    }

    @MainActor
    func testSharingAPlanLinkOpensTheShareSheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-seed-sample-plan", "-weightUnit", "kg"]
        app.launch()

        let row = element(app, "plans.row")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        let share = element(app, "plan.share")
        XCTAssertTrue(share.waitForExistence(timeout: 30))
        share.tap()

        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testBuiltInExerciseShowsMusclesAndTechnique() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-weightUnit", "kg"]
        app.launch()

        app.tabBars.buttons.element(boundBy: 1).tap()
        let exercise = element(app, "exercises.builtIn")
        XCTAssertTrue(exercise.waitForExistence(timeout: 30))
        exercise.tap()

        XCTAssertTrue(app.staticTexts.matching(identifier: "exercise.muscles").firstMatch.waitForExistence(timeout: 30))
        capture("18-exercise-detail")
    }

    /// The sensor screen and the live reading, with a fake sensor (UI tests never use Bluetooth).
    @MainActor
    func testHeartRateSensorAndLiveReading() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-fake-heart-rate", "-seed-sample-plan", "-weightUnit", "kg"]
        app.launch()

        app.tabBars.buttons.element(boundBy: 3).tap()
        let sensorRow = element(app, "settings.heartRate")
        XCTAssertTrue(sensorRow.waitForExistence(timeout: 30))
        sensorRow.tap()
        XCTAssertTrue(element(app, "sensor.forget").waitForExistence(timeout: 30))
        XCTAssertTrue(element(app, "sensor.discovered").exists)
        capture("19-heart-rate-sensor")

        app.tabBars.buttons.element(boundBy: 0).tap()
        let row = element(app, "plans.row")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        element(app, "plan.start").tap()
        XCTAssertTrue(element(app, "workout.log").waitForExistence(timeout: 30))
        capture("20-workout-heart-rate")

        element(app, "workout.finish").tap()
        XCTAssertTrue(element(app, "summary.done").waitForExistence(timeout: 30))
        capture("21-summary-heart-rate")
    }

    @MainActor
    func testTurningOnAppleHealthSync() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-weightUnit", "kg"]
        app.launch()

        app.tabBars.buttons.element(boundBy: 3).tap()
        let toggle = app.switches.matching(identifier: "settings.healthSync").firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 30))
        // The row contains the actual switch control; tapping the row's label does nothing.
        let control = toggle.switches.firstMatch
        (control.exists ? control : toggle).tap()
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1")
        capture("22-apple-health")
    }

    /// The AI agents flow with a fake connector: Settings row, the agents screen, the connect
    /// sheet (code, copy, waiting) and the confirmation, then the agent in the list.
    @MainActor
    func testConnectingAnAIAgent() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-weightUnit", "kg"]
        app.launch()

        app.tabBars.buttons.element(boundBy: 3).tap()
        let row = element(app, "settings.agents")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        capture("23-settings-connections")
        row.tap()

        let connect = element(app, "agents.connect")
        XCTAssertTrue(connect.waitForExistence(timeout: 30))
        capture("24-ai-agents")
        connect.tap()

        let code = app.staticTexts.matching(identifier: "agents.code").firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 30))
        XCTAssertTrue(code.label.contains("K7M2"), code.label)
        capture("25-connect-agent")
        element(app, "agents.copyCode").tap()
        element(app, "agents.copyAddress").tap()

        // The fake connector reports the code as used about 18 seconds after showing it.
        let done = element(app, "agents.done")
        XCTAssertTrue(done.waitForExistence(timeout: 60))
        capture("26-agent-connected")
        done.tap()

        XCTAssertTrue(app.staticTexts["Claude"].waitForExistence(timeout: 30))
        XCTAssertTrue(element(app, "agents.disconnect").exists)
        capture("27-agents-list")
    }

    /// An empty workout: add an exercise, log a set, then keep it as a new plan.
    @MainActor
    func testStartingAnEmptyWorkoutAndSavingItAsAPlan() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-weightUnit", "kg"]
        app.launch()

        let startEmpty = element(app, "plans.startEmpty")
        XCTAssertTrue(startEmpty.waitForExistence(timeout: 30))
        startEmpty.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 30))
        capture("27b-start-empty-alert")
        alert.buttons.matching(identifier: "plans.confirmStartEmpty").firstMatch.tap()

        let add = element(app, "workout.addExercise")
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        capture("28-empty-workout")
        add.tap()
        let firstExercise = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "picker.")).firstMatch
        XCTAssertTrue(firstExercise.waitForExistence(timeout: 30))
        firstExercise.tap()

        XCTAssertTrue(element(app, "workout.exerciseMenu").waitForExistence(timeout: 30))
        element(app, "workout.finish").tap()

        let save = element(app, "summary.saveAsPlan")
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        capture("29-summary-save-as-plan")
        save.tap()
        let name = app.textFields["planEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        name.tap()
        name.typeText("Legs\n")
        element(app, "planEditor.save").tap()

        let done = element(app, "summary.done")
        XCTAssertTrue(done.waitForExistence(timeout: 30))
        XCTAssertTrue(save.waitForNonExistence(timeout: 30), "the button turns into a saved label")
        done.tap()
        XCTAssertTrue(element(app, "plans.row").waitForExistence(timeout: 30))
    }

    /// Changing a plan's workout: replace, remove, add and reorder exercises, then update the plan.
    @MainActor
    func testChangingExercisesDuringAWorkoutAndUpdatingThePlan() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-seed-sample-plan", "-weightUnit", "kg"]
        app.launch()

        let row = element(app, "plans.row")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        element(app, "plan.start").tap()

        let firstExercise = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "picker.")).firstMatch
        let menu = element(app, "workout.exerciseMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        let replace = element(app, "workout.replaceExercise")
        XCTAssertTrue(replace.waitForExistence(timeout: 30))
        capture("30-exercise-menu")
        replace.tap()
        XCTAssertTrue(firstExercise.waitForExistence(timeout: 30))
        firstExercise.tap()

        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        let remove = element(app, "workout.removeExercise")
        XCTAssertTrue(remove.waitForExistence(timeout: 30))
        remove.tap()

        let add = element(app, "workout.addExercise")
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        add.tap()
        XCTAssertTrue(firstExercise.waitForExistence(timeout: 30))
        firstExercise.tap()

        let more = element(app, "workout.more")
        XCTAssertTrue(more.waitForExistence(timeout: 30))
        more.tap()
        let reorder = element(app, "workout.reorder")
        XCTAssertTrue(reorder.waitForExistence(timeout: 30))
        reorder.tap()
        let reorderDone = element(app, "reorder.done")
        XCTAssertTrue(reorderDone.waitForExistence(timeout: 30))
        capture("31-reorder-exercises")
        reorderDone.tap()

        element(app, "workout.finish").tap()
        let update = element(app, "summary.updatePlan")
        XCTAssertTrue(update.waitForExistence(timeout: 30))
        update.tap()
        XCTAssertTrue(update.waitForNonExistence(timeout: 30), "the button turns into an updated label")
        capture("32-plan-updated")
        element(app, "summary.done").tap()
        // Back on the plan the workout started from.
        XCTAssertTrue(element(app, "plan.start").waitForExistence(timeout: 30))
    }

    /// The Start Workout screen's plan cards: duplicate, edit and delete (which asks first).
    @MainActor
    func testPlanCardMenu() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-seed-sample-plan", "-weightUnit", "kg"]
        app.launch()

        let cards = app.buttons.matching(identifier: "plans.row")
        let menu = element(app, "plans.menu")
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        capture("33-start-workout")
        menu.tap()
        let duplicate = element(app, "plans.duplicate")
        XCTAssertTrue(duplicate.waitForExistence(timeout: 30))
        duplicate.tap()
        XCTAssertTrue(cards.element(boundBy: 1).waitForExistence(timeout: 30))

        menu.tap()
        let edit = element(app, "plans.edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 30))
        edit.tap()
        let save = element(app, "planEditor.save")
        XCTAssertTrue(save.waitForExistence(timeout: 30))
        save.tap()

        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        let delete = element(app, "plans.delete")
        XCTAssertTrue(delete.waitForExistence(timeout: 30))
        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 30))
        alert.buttons.matching(identifier: "plans.confirmDelete").firstMatch.tap()
        XCTAssertTrue(cards.element(boundBy: 1).waitForNonExistence(timeout: 30))
    }

    /// Every element the tests tap is a button (list rows with NavigationLink included).
    /// Querying buttons only is much cheaper than `descendants(matching: .any)`, which
    /// timed out on slow CI simulators.
    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
