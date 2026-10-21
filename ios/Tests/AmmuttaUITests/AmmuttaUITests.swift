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
