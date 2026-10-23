import Testing

@testable import OpenOSKCore

@Suite struct LayoutTests {
    @Test func bundledLayoutsLoad() {
        let ids = LayoutStore.bundledLayouts().map(\.id)
        #expect(ids.contains("qwertz-de"))
        #expect(ids.contains("qwerty-us"))
        #expect(ids.contains("thai-kedmanee"))
    }

    @Test func qwertzLayoutStructure() throws {
        let layout = try #require(LayoutStore.layout(id: "qwertz-de"))
        #expect(layout.rows.count == 5)
        #expect(layout.maxRowUnits > 10)

        let allKeys = layout.rows.flatMap { $0 }
        #expect(allKeys.contains { $0.base == "ü" })
        #expect(allKeys.contains { $0.modifier == .shift })
        #expect(allKeys.contains { $0.special == .space })
    }

    @Test func keyOutputLayers() {
        let key = Key(base: "7", shift: "/", alt: "|", shiftAlt: "\\")
        #expect(key.output(shifted: false, alted: false) == "7")
        #expect(key.output(shifted: true, alted: false) == "/")
        #expect(key.output(shifted: false, alted: true) == "|")
        #expect(key.output(shifted: true, alted: true) == "\\")
    }

    @Test func autoShiftUppercasesLetters() {
        #expect(Key(base: "a").output(shifted: true, alted: false) == "A")
        #expect(Key(base: "ü").output(shifted: true, alted: false) == "Ü")
    }

    @Test func keyKind() {
        #expect(Key(base: "a").kind != nil)
        if case .modifier(let modifier)? = Key(modifier: .shift).kind {
            #expect(modifier == .shift)
        } else {
            Issue.record("Expected modifier kind")
        }
        if case .special(let special)? = Key(special: .delete).kind {
            #expect(special == .delete)
        } else {
            Issue.record("Expected special kind")
        }
    }
}
