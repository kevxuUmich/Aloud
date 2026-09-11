import AppKit
import SwiftUI
import Testing

@testable import Aloud

@Suite struct ReaderStyleTests {
    /// A stored name this build does not know falls back rather than crashing.
    @Test func aStaleTypefaceIsTheDefault() {
        #expect(ReaderTypeface.stored("serif") == .serif)
        #expect(ReaderTypeface.stored("mono") == .sans)
        #expect(ReaderTypeface.stored("") == .sans)
    }
    @Test func aStaleAppearanceIsTheSystems() {
        #expect(Appearance.stored("dark") == .dark)
        #expect(Appearance.stored("sepia") == .system)
        #expect(Appearance.system.colorScheme == nil)
        #expect(Appearance.light.colorScheme == .light)
    }
    @Test func everyChoiceHasAName() {
        #expect(ReaderTypeface.allCases.map(\.name) == ["Sans", "Serif"])
        #expect(Appearance.allCases.map(\.name) == ["System", "Light", "Dark"])
    }
}
