import Testing

@testable import Aloud

/// Finder's rules for a grid, on ids alone.
@Suite struct LibrarySelectionTests {
    let order = ["a", "b", "c", "d", "e"]

    @Test func aPlainClickSelectsOneAndAnchorsThere() {
        var s = LibrarySelection()
        s.click("b", .plain, in: order)
        s.click("d", .plain, in: order)
        #expect(s.ids == ["d"])
        #expect(s.anchor == "d")
    }

    @Test func shiftExtendsFromTheAnchorEitherWay() {
        var s = LibrarySelection()
        s.click("c", .plain, in: order)
        s.click("e", .shift, in: order)
        #expect(s.ids == ["c", "d", "e"])
        s.click("a", .shift, in: order)
        #expect(s.ids == ["a", "b", "c", "d", "e"])
        #expect(s.anchor == "c")
    }

    @Test func shiftWithNoAnchorIsAPlainClick() {
        var s = LibrarySelection()
        s.click("b", .shift, in: order)
        #expect(s.ids == ["b"])
        #expect(s.anchor == "b")
    }

    @Test func commandTogglesAndMovesTheAnchor() {
        var s = LibrarySelection()
        s.click("a", .plain, in: order)
        s.click("c", .command, in: order)
        #expect(s.ids == ["a", "c"])
        #expect(s.anchor == "c")
        s.click("a", .command, in: order)
        #expect(s.ids == ["c"])
        #expect(s.anchor == "a")
        s.click("e", .shift, in: order)
        #expect(s.ids == Set(order))
    }

    @Test func aSecondaryClickOutsideTheSelectionSelectsThatAlone() {
        var s = LibrarySelection()
        s.click("a", .plain, in: order)
        s.click("b", .command, in: order)
        s.secondaryClick("a")
        #expect(s.ids == ["a", "b"])
        s.secondaryClick("d")
        #expect(s.ids == ["d"])
    }

    @Test func aMarqueeStartsFromItsBaseOnEveryUpdate() {
        var s = LibrarySelection()
        s.click("a", .plain, in: order)
        s.marquee(crossed: ["c", "d"], additive: false)
        #expect(s.ids == ["c", "d"])
        s.marquee(crossed: ["d"], additive: false)
        #expect(s.ids == ["d"])
        s.endMarquee()
        s.click("a", .plain, in: order)
        s.marquee(crossed: ["c"], additive: true)
        s.marquee(crossed: ["e"], additive: true)
        #expect(s.ids == ["a", "e"])
    }

    @Test func selectAllClearAndPrune() {
        var s = LibrarySelection()
        s.selectAll(in: order)
        #expect(s.ids == Set(order))
        s.click("b", .plain, in: order)
        s.selectAll(in: order)
        s.prune(to: ["a", "c"])
        #expect(s.ids == ["a", "c"])
        #expect(s.anchor == nil)
        #expect(s.ordered(in: ["c", "a"]) == ["c", "a"])
        s.clear()
        #expect(s.isEmpty)
    }
}
