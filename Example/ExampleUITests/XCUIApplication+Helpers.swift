import XCTest

private enum EnvironmentKey {
    static let disableTextPersistance = "disableTextPersistance"
}

extension XCUIApplication {
    var textView: XCUIElement? {
        return scrollViews.children(matching: .textView).element
    }

    func tap(at point: CGPoint) {
        let normalized = coordinate(withNormalizedOffset: .zero)
        let offset = CGVector(dx: point.x, dy: point.y)
        let coordinate = normalized.withOffset(offset)
        coordinate.tap()
    }

    func disablingTextPersistance() -> Self {
        var newLaunchEnvironment = launchEnvironment
        newLaunchEnvironment[EnvironmentKey.disableTextPersistance] = "1"
        launchEnvironment = newLaunchEnvironment
        return self
    }
}
