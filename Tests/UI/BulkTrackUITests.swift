import XCTest

final class BulkTrackUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
    }
    func testFoodLoggingEditingAndKeyboard() {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Today"; image.lifetime = .keepAlways; add(image)
        app.buttons["Log food"].tap()
        let meal = app.textFields["Food name"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap(); meal.typeText("Test lunch")
        let calories = app.textFields["Calories"]
        calories.tap(); calories.typeText("650")
        let done = app.buttons["Done editing. Hide keyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 3)); done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.navigationBars["Add food"].buttons["Add"].tap()
        app.tabBars.buttons["Nutrition"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Test lunch").firstMatch.waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "Test lunch").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit food"].waitForExistence(timeout: 3))
        app.navigationBars["Edit food"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["650 Cal logged"].exists || app.staticTexts["650"].exists)
    }
    func testWorkoutResumeRestAndFinish() {
        app.tabBars.buttons["Training"].tap()
        let start = app.buttons["Start Workout A"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
        let log = app.buttons["Log set"]
        XCTAssertTrue(log.waitForExistence(timeout: 5)); log.tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 3))
        app.navigationBars["Workout A"].buttons["Close"].tap()
        let resume = app.buttons["Resume workout"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3)); resume.tap()
        XCTAssertTrue(app.staticTexts["1 set recorded · 0 of 1 exercise complete"].waitForExistence(timeout: 3))
        app.swipeUp()
        let finish = app.buttons["Finish workout"]
        if !finish.isHittable { app.swipeUp() }
        finish.tap()
        app.buttons["Finish and log gym visit"].tap()
        XCTAssertTrue(app.staticTexts["Visit logged"].waitForExistence(timeout: 5))
    }
    func testCustomExerciseLogging() {
        app.tabBars.buttons["Training"].tap()
        app.buttons["Log any exercise"].tap()
        let save = app.navigationBars["Log exercise"].buttons["Save"]
        XCTAssertFalse(save.isEnabled)
        let name = app.textFields["Exercise name"]
        name.tap(); name.typeText("Hammer curls")
        let weight = app.textFields["Weight · lb"]
        weight.tap(); weight.typeText("25")
        let reps = app.textFields["Reps"]
        reps.tap(); reps.typeText("12")
        app.buttons["Done editing. Hide keyboard"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(save.isEnabled); save.tap()
        let history = app.buttons["Exercise log"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        let entry = app.buttons.containing(.staticText, identifier: "Hammer curls").firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "25.0 lb × 12 reps")).firstMatch.exists)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Edit set"].waitForExistence(timeout: 3))
    }
    func testLargeTextAndDarkAppearance() {
        app.terminate()
        app.launchArguments += ["-ui-test-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Log food"].waitForExistence(timeout: 5))
        for title in ["Nutrition", "Training", "Progress", "Today"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
        }
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Today – large text and dark"; image.lifetime = .keepAlways; add(image)
    }
    func testSettingsAndWeightEntry() {
        app.buttons["Settings and goals"].tap()
        XCTAssertTrue(app.buttons["Edit profile & daily goals"].waitForExistence(timeout: 5))
        app.buttons["Edit profile & daily goals"].tap()
        let automatic = app.switches["automaticResting"]
        for _ in 0..<4 {
            if automatic.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(automatic.waitForExistence(timeout: 3), app.debugDescription)
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["Resting Calories / day"].waitForExistence(timeout: 3), app.debugDescription)
        app.navigationBars["Profile"].buttons["Cancel"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.swipeUp()
        app.buttons["Log weight"].tap()
        XCTAssertTrue(app.navigationBars["Log weight"].waitForExistence(timeout: 5))
        app.navigationBars["Log weight"].buttons["Save"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.staticTexts["Body weight"].waitForExistence(timeout: 3))
    }
}
