import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import OpenOSKCore

@Suite struct KeyboardPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let size = CGSize(width: 850, height: 380)

    @Test func placesBelowWithoutCoveringField() {
        let field = CGRect(x: 700, y: 800, width: 400, height: 40)
        let origin = KeyboardPlacement.origin(near: field, keyboardSize: size, visibleFrame: screen)
        let keyboard = CGRect(origin: origin, size: size)
        #expect(!keyboard.intersects(field))
        #expect(keyboard.maxY < field.minY)
        #expect(screen.contains(keyboard))
    }
    @Test func placesAboveBottomField() {
        let field = CGRect(x: 40, y: 20, width: 300, height: 50)
        let keyboard = CGRect(origin: KeyboardPlacement.origin(near: field, keyboardSize: size, visibleFrame: screen), size: size)
        #expect(keyboard.minY > field.maxY)
        #expect(screen.contains(keyboard))
    }
    @Test func handlesNegativeDisplayCoordinates() {
        let display = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let field = CGRect(x: -100, y: 500, width: 80, height: 40)
        let keyboard = CGRect(origin: KeyboardPlacement.origin(near: field, keyboardSize: size, visibleFrame: display), size: size)
        #expect(display.contains(keyboard))
        #expect(!keyboard.intersects(field))
    }
    @Test func usesSideOfTallField() {
        let field = CGRect(x: 20, y: 20, width: 400, height: 1000)
        let keyboard = CGRect(origin: KeyboardPlacement.origin(near: field, keyboardSize: size, visibleFrame: screen), size: size)
        #expect(screen.contains(keyboard))
        #expect(!keyboard.intersects(field))
    }
}
