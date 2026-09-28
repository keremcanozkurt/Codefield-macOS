//
//  CodefieldUITests.swift
//  CodefieldUITests
//
//  Created by Kerem Can Özkurt on 26.09.2026.
//

import XCTest

// Drives the real app with WebKit and real key events, on the fixture
// repository: app.ts → a.ts → b.ts → c.ts, plus an isolated lonely.ts.
final class CodefieldUITests: XCTestCase {
    private var app: XCUIApplication!

    private var web: XCUIElement { app.webViews.firstMatch }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-CodefieldUITestFixture"]
        app.launch()
        XCTAssertTrue(web.staticTexts["Overview"].waitForExistence(timeout: 30), "The workspace did not appear")
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: Escape

    func testEscapeLeavesImpactThenClearsSelection() {
        select("b.ts")
        web.buttons["Trace impact"].click()
        XCTAssertTrue(web.buttons["Exit impact"].waitForExistence(timeout: 5))

        pressEscape()
        XCTAssertTrue(web.buttons["Trace impact"].waitForExistence(timeout: 5))
        XCTAssertFalse(web.buttons["Exit impact"].exists)

        pressEscape()
        XCTAssertTrue(waitForDisappearance(web.buttons["Trace impact"]))
    }

    func testEscapeCancelsChoosingAPathBeforeTheSelection() {
        select("app.ts")
        web.buttons["Find path"].click()
        XCTAssertTrue(web.buttons["Cancel path"].waitForExistence(timeout: 5))

        pressEscape()
        XCTAssertTrue(web.buttons["Find path"].waitForExistence(timeout: 5))
        XCTAssertTrue(web.buttons["Trace impact"].exists)

        pressEscape()
        XCTAssertTrue(waitForDisappearance(web.buttons["Trace impact"]))
    }

    func testEscapeLeavesWorkspaceFullScreenBeforeAnythingElse() {
        select("b.ts")
        web.buttons["Trace impact"].click()
        web.buttons["Full screen"].click()
        XCTAssertTrue(web.buttons["Exit full screen"].waitForExistence(timeout: 5))

        pressEscape()
        XCTAssertTrue(web.buttons["Full screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(web.buttons["Exit impact"].exists, "Impact Mode should survive leaving full screen")
    }

    func testEscapeNeverLeavesNativeFullScreen() {
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Enter Full Screen"].click()
        XCTAssertTrue(waitForMenuItem("Exit Full Screen"))

        select("b.ts")
        pressEscape()
        XCTAssertTrue(waitForDisappearance(web.buttons["Trace impact"]))
        pressEscape()
        pressEscape()
        XCTAssertTrue(waitForMenuItem("Exit Full Screen"), "Escape in the workspace must not leave native full screen")

        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Exit Full Screen"].click()
    }

    func testWorkspaceFullScreenIsTheWindowsFullScreen() {
        web.buttons["Full screen"].click()
        XCTAssertTrue(web.buttons["Exit full screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForMenuItem("Exit Full Screen"), "Full screen should put the window into macOS full screen")

        web.buttons["Exit full screen"].click()
        XCTAssertTrue(waitForMenuItem("Enter Full Screen"))

        // Leaving through the window, not the page, ends the page's layout too.
        web.buttons["Full screen"].click()
        XCTAssertTrue(waitForMenuItem("Exit Full Screen"))
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Exit Full Screen"].click()
        XCTAssertTrue(web.buttons["Full screen"].waitForExistence(timeout: 5))
    }

    func testEscapeClosesTheFAQAndKeepsTheSelection() {
        select("b.ts")
        app.toolbars.buttons["FAQ"].click()
        XCTAssertTrue(app.staticTexts["Frequently asked questions"].waitForExistence(timeout: 5))

        pressEscape()
        XCTAssertTrue(waitForDisappearance(app.staticTexts["Frequently asked questions"]))
        XCTAssertTrue(web.buttons["Trace impact"].exists)
    }

    // MARK: Path Finder

    func testPathFinderFollowsImportsAndReverses() {
        select("app.ts")
        web.buttons["Find path"].click()
        XCTAssertTrue(web.buttons["Cancel path"].waitForExistence(timeout: 5))

        // While a destination is being chosen, picking a file completes the path.
        select("c.ts", expectInspector: false)
        XCTAssertTrue(text(beginningWith: "Path found").waitForExistence(timeout: 5))
        XCTAssertTrue(web.buttons["Exit path"].exists)
        for name in ["app.ts", "a.ts", "b.ts", "c.ts"] {
            XCTAssertTrue(web.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.exists, name)
        }

        // c.ts imports nothing, so nothing leads from it back to app.ts.
        web.buttons["Reverse"].click()
        XCTAssertTrue(text(beginningWith: "No directed dependency path found").waitForExistence(timeout: 5))

        web.buttons["Try the reverse direction"].click()
        XCTAssertTrue(text(beginningWith: "Path found").waitForExistence(timeout: 5))

        pressEscape()
        XCTAssertTrue(web.buttons["Find path"].waitForExistence(timeout: 5))
    }

    func testPathFinderReportsFilesWithNoPath() {
        select("app.ts")
        web.buttons["Find path"].click()
        select("lonely.ts", expectInspector: false)
        XCTAssertTrue(text(beginningWith: "No directed dependency path found").waitForExistence(timeout: 5))
    }

    // MARK: Windows

    func testNewWindowStartsEmptyAndLeavesTheFirstAlone() {
        select("b.ts")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Clone Git Repository…"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 2)
        XCTAssertTrue(web.buttons["Trace impact"].exists, "The first window keeps its selection")
    }

    // MARK: Helpers

    private func select(_ name: String, expectInspector: Bool = true) {
        app.typeKey("f", modifierFlags: .command)
        app.typeText(name)
        app.typeKey(.return, modifierFlags: [])
        if expectInspector {
            XCTAssertTrue(web.buttons["Trace impact"].waitForExistence(timeout: 5), "\(name) was not selected")
        }
    }

    private func pressEscape() {
        app.typeKey(.escape, modifierFlags: [])
    }

    private func text(beginningWith prefix: String) -> XCUIElement {
        web.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@", prefix, prefix)).firstMatch
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func waitForMenuItem(_ title: String) -> Bool {
        app.menuBars.menuBarItems["View"].click()
        let found = app.menuBars.menuItems[title].waitForExistence(timeout: 5)
        app.typeKey(.escape, modifierFlags: [])
        return found
    }
}
