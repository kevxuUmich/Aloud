import Foundation

/// Which items in the library are selected, and the rules Finder's grid keeps: a click
/// selects one, Shift extends from the last plain click to it, Command toggles it, a
/// marquee takes what it crosses. Ids and an order, nothing of the view, so the rules
/// can be checked without a window.
struct LibrarySelection: Equatable {
    /// How a click arrived. Command wins when both keys are down, as it does in Finder.
    enum Click: Equatable { case plain, shift, command }

    private(set) var ids: Set<String> = []
    /// Where a Shift range starts: the last item clicked without Shift.
    private(set) var anchor: String?
    /// The selection a marquee began over, kept so each drag update starts from it
    /// rather than from what the last update left.
    private var marqueeBase: Set<String>?

    var isEmpty: Bool { ids.isEmpty }
    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// The selected ids in the library's own order, for the actions that take a list.
    func ordered(in order: [String]) -> [String] { order.filter(ids.contains) }

    mutating func click(_ id: String, _ click: Click, in order: [String]) {
        switch click {
        case .plain:
            ids = [id]
            anchor = id
        case .command:
            if ids.contains(id) {
                ids.remove(id)
                // The anchor moves to the item toggled, as Finder's does, so a Shift
                // click afterwards ranges from here.
                anchor = id
            } else {
                ids.insert(id)
                anchor = id
            }
        case .shift:
            guard let anchor, let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: id)
            else {
                ids = [id]
                self.anchor = id
                return
            }
            ids.formUnion(order[min(a, b)...max(a, b)])
        }
    }

    /// A right click on an item outside the selection selects it alone first, so the
    /// menu acts on what was clicked; inside the selection it leaves it as it is.
    mutating func secondaryClick(_ id: String) {
        guard !ids.contains(id) else { return }
        ids = [id]
        anchor = id
    }

    /// A marquee's frame moved. `crossed` is what it covers now; with Shift or Command
    /// held when it began, what was selected before stays selected under it.
    mutating func marquee(crossed: Set<String>, additive: Bool) {
        let base = marqueeBase ?? (additive ? ids : [])
        marqueeBase = base
        ids = base.union(crossed)
    }

    mutating func endMarquee() { marqueeBase = nil }

    mutating func selectAll(in order: [String]) { ids = Set(order) }

    mutating func clear() {
        ids = []
        anchor = nil
    }

    /// Items that are no longer in the library, deleted or moved, leave the selection.
    mutating func prune(to order: [String]) {
        let present = Set(order)
        ids = ids.intersection(present)
        if let anchor, !present.contains(anchor) { self.anchor = nil }
    }
}
