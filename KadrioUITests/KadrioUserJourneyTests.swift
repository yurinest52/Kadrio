import XCTest

final class KadrioUserJourneyTests: XCTestCase {
    @MainActor func testKadrioScreensAndEditingJourney() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.buttons["Continue"].waitForExistence(timeout: 3) {
            capture(app, "KadrioOnboarding")
            app.buttons["Continue"].tap()
            XCTAssertTrue(app.buttons["KadrioPaywallGetTokens"].waitForExistence(timeout: 5))
            capture(app, "KadrioPaywall")
            app.buttons["KadrioPaywallClose"].tap()
        }
        XCTAssertTrue(app.buttons["KadrioHomeAddPhoto"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.buttons["Clear history"].tap()
        app.alerts.buttons["Clear"].tap()
        app.buttons["Back"].tap()
        capture(app, "KadrioHome")
        openSinglePhotoEditor(app)
        app.buttons["Vivid"].tap()
        app.buttons["KadrioEditorClose"].tap()
        app.alerts.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["KadrioHomeAddPhoto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["3 tokens left"].exists)
        XCTAssertTrue(app.staticTexts["No works yet"].exists)
        app.buttons["KadrioHomeTokens"].tap()
        XCTAssertTrue(app.buttons["KadrioPaywallClose"].waitForExistence(timeout: 5))
        capture(app, "KadrioFullScreenPaywall")
        app.buttons["KadrioPaywallClose"].tap()
        XCTAssertTrue(app.buttons["KadrioHomeAddPhoto"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Clear history"].waitForExistence(timeout: 3))
        capture(app, "KadrioSettings")
        app.buttons["Get more"].tap()
        XCTAssertTrue(app.buttons["KadrioPaywallClose"].waitForExistence(timeout: 5))
        app.buttons["KadrioPaywallClose"].tap()
        XCTAssertTrue(app.buttons["KadrioHomeAddPhoto"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Clear history"].exists)
        app.buttons["Settings"].tap()
        app.buttons["Clear history"].tap()
        app.alerts.buttons["Cancel"].tap()
        app.buttons["Back"].tap()
        app.buttons["KadrioHomeTool-filters"].tap()
        XCTAssertTrue(app.buttons["KadrioSource-photoLibrary"].waitForExistence(timeout: 3))
        capture(app, "KadrioPhotoSource")
        app.buttons["KadrioSource-photoLibrary"].tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,' OR label BEGINSWITH 'Фото,'")).firstMatch
        if !photo.waitForExistence(timeout: 5) { print(app.debugDescription) }
        XCTAssertTrue(photo.exists)
        waitUntilHittable(photo)
        photo.tap()
        if app.buttons["Add"].exists { app.buttons["Add"].tap() }
        XCTAssertTrue(app.buttons["KadrioEditorSave"].waitForExistence(timeout: 10))
        app.buttons["Vivid"].tap()
        capture(app, "KadrioFilters")
        app.buttons["KadrioEditorTool-crop"].tap()
        app.buttons["4:5"].tap()
        app.buttons["Rotate"].tap()
        app.buttons["Flip"].tap()
        capture(app, "KadrioCrop")
        app.buttons["Undo"].tap()
        app.buttons["Redo"].tap()
        app.buttons["KadrioEditorTool-frames"].tap()
        app.buttons["Rounded"].tap()
        app.buttons["Frame color"].tap()
        XCTAssertTrue(app.textFields["HEX color"].waitForExistence(timeout: 3))
        capture(app, "KadrioFramePalette")
        app.buttons["Done"].tap()
        capture(app, "KadrioFrames")
        app.buttons["KadrioEditorSave"].tap()
        let permission = addUIInterruptionMonitor(withDescription: "Kadrio Photos permission") { alert in
            if alert.buttons["Allow Access to All Photos"].exists { alert.buttons["Allow Access to All Photos"].tap(); return true }
            if alert.buttons["Allow Photos to Be Added Only"].exists { alert.buttons["Allow Photos to Be Added Only"].tap(); return true }
            if alert.buttons["OK"].exists { alert.buttons["OK"].tap(); return true }
            return false
        }
        app.tap()
        XCTAssertTrue(app.staticTexts["Saved to Photos"].waitForExistence(timeout: 20))
        removeUIInterruptionMonitor(permission)
        capture(app, "KadrioSaved")
        app.buttons["KadrioEditorClose"].tap()
        XCTAssertTrue(app.buttons["Open saved photo"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Open saved photo"].waitForExistence(timeout: 5))
        capture(app, "KadrioPersistedWork")
        app.buttons["KadrioHomeTool-collage"].tap()
        app.buttons["KadrioSource-photoLibrary"].tap()
        let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,' OR label BEGINSWITH 'Фото,'"))
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 5))
        for index in 0..<4 { photos.element(boundBy: index).tap() }
        app.buttons.matching(NSPredicate(format: "label == 'Add' OR label BEGINSWITH 'Add (' OR label == 'Добавить' OR label BEGINSWITH 'Добавить ('")).firstMatch.tap()
        XCTAssertTrue(app.buttons["KadrioEditorSave"].waitForExistence(timeout: 10))
        app.buttons["Layout 3"].tap()
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.6)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.35)))
        capture(app, "KadrioCollage")
        app.buttons["KadrioEditorSave"].tap()
        XCTAssertTrue(app.staticTexts["1 tokens left"].waitForExistence(timeout: 15))
        app.buttons["KadrioEditorSave"].tap()
        XCTAssertTrue(app.staticTexts["0 tokens left"].waitForExistence(timeout: 15))
        app.buttons["KadrioEditorSave"].tap()
        XCTAssertTrue(app.buttons["KadrioPaywallGetTokens"].waitForExistence(timeout: 5))
        capture(app, "KadrioNoTokensPaywall")
        app.buttons["KadrioPaywallClose"].tap()
        XCTAssertTrue(app.buttons["KadrioHomeAddPhoto"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["KadrioEditorSave"].exists)
        XCTAssertTrue(app.buttons["0 tokens left"].exists)
        openSinglePhotoEditor(app)
        app.buttons["Warm"].tap()
        app.buttons["KadrioEditorSave"].tap()
        XCTAssertTrue(app.buttons["KadrioPaywallGetTokens"].waitForExistence(timeout: 5))
        app.buttons["KadrioPaywallGetTokens"].tap()
        XCTAssertTrue(app.buttons["KadrioEditorSave"].waitForExistence(timeout: 5))
        app.buttons["KadrioEditorSave"].tap()
        XCTAssertTrue(app.staticTexts["2 tokens left"].waitForExistence(timeout: 15))
        app.buttons["KadrioEditorClose"].tap()
        XCTAssertTrue(app.buttons["Open saved photo"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Open saved photo"].firstMatch.press(forDuration: 1)
        app.buttons["Delete"].tap()
        waitUntilHittable(app.alerts.buttons["Cancel"])
        app.alerts.buttons["Cancel"].tap()
        let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.alerts.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 3), .completed)
        app.buttons["Open saved photo"].firstMatch.press(forDuration: 1)
        app.buttons["Delete"].tap()
        waitUntilHittable(app.alerts.buttons["Delete"])
        app.alerts.buttons["Delete"].tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons.matching(identifier: "Open saved photo").count == 3 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        app.buttons["Settings"].tap()
        app.buttons["Clear history"].tap()
        app.alerts.buttons["Clear"].tap()
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["No works yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["3 tokens left"].exists)
        capture(app, "KadrioClearedHistory")
    }

    @MainActor func testKadrioFigmaCollageLayouts() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.buttons["Continue"].waitForExistence(timeout: 3) {
            app.buttons["Continue"].tap()
            app.buttons["KadrioPaywallClose"].tap()
        }
        XCTAssertTrue(app.buttons["KadrioHomeTokens"].waitForExistence(timeout: 5))
        let balance = app.buttons["KadrioHomeTokens"].label
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 3))
        app.buttons["Back"].tap()
        waitUntilHittable(app.buttons["KadrioHomeTool-collage"])
        app.buttons["KadrioHomeTool-collage"].tap()
        XCTAssertTrue(app.buttons["KadrioSource-photoLibrary"].waitForExistence(timeout: 3))
        capture(app, "KadrioDarkerPhotoSource")
        app.buttons["KadrioSource-photoLibrary"].tap()
        let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,' OR label BEGINSWITH 'Фото,'"))
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 5))
        for index in 0..<3 { waitUntilHittable(photos.element(boundBy: index)); photos.element(boundBy: index).tap() }
        app.buttons.matching(NSPredicate(format: "label == 'Add' OR label BEGINSWITH 'Add (' OR label == 'Добавить' OR label BEGINSWITH 'Добавить ('")).firstMatch.tap()
        XCTAssertTrue(app.buttons["KadrioEditorSave"].waitForExistence(timeout: 10))
        capture(app, "KadrioFigmaFeatureCollage")
        app.buttons["Layout 1"].tap()
        capture(app, "KadrioFigmaTwoColumns")
        app.buttons["Layout 3"].tap()
        capture(app, "KadrioFigmaTopCollage")
        app.buttons["Layout 4"].tap()
        let additional = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,' OR label BEGINSWITH 'Фото,'" )).firstMatch
        XCTAssertTrue(additional.waitForExistence(timeout: 5))
        waitUntilHittable(additional)
        additional.tap()
        if app.buttons["Add"].exists { app.buttons["Add"].tap() }
        XCTAssertTrue(app.buttons["KadrioEditorSave"].waitForExistence(timeout: 10))
        capture(app, "KadrioFigmaGridCollage")
        app.buttons["Layout 2"].tap()
        capture(app, "KadrioFigmaFeatureRestored")
        app.buttons["KadrioEditorTool-filters"].tap()
        capture(app, "KadrioFigmaFiltersIcon")
        app.buttons["KadrioEditorTool-frames"].tap()
        capture(app, "KadrioFigmaFramesIcon")
        app.buttons["KadrioEditorClose"].tap()
        app.alerts.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["KadrioHomeTokens"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["KadrioHomeTokens"].label, balance)
    }

    @MainActor private func openSinglePhotoEditor(_ app: XCUIApplication) {
        app.buttons["KadrioHomeTool-filters"].tap()
        XCTAssertTrue(app.buttons["KadrioSource-photoLibrary"].waitForExistence(timeout: 3))
        app.buttons["KadrioSource-photoLibrary"].tap()
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,' OR label BEGINSWITH 'Фото,'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        waitUntilHittable(photo)
        photo.tap()
        if app.buttons["Add"].exists { app.buttons["Add"].tap() }
        XCTAssertTrue(app.buttons["KadrioEditorSave"].waitForExistence(timeout: 10))
    }

    @MainActor private func waitUntilHittable(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
