import AloudUI
import AppKit
import SwiftUI

/// The library's selection and what the marquee needs to make one: where every item
/// is, in the library's own space, and the frame being dragged out. One per library
/// view, so a folder's selection goes with the folder when the reader leaves it.
@Observable @MainActor final class LibraryState {
    var selection = LibrarySelection()
    /// Each item's frame in the `LibraryState.space` coordinate space, kept up to date
    /// by the items themselves.
    var frames: [String: CGRect] = [:]
    /// The marquee while it is being dragged, in the same space.
    var marquee: CGRect?

    nonisolated static let space = "library"

    /// The click a mouse event is, from the keys held with it. Command wins over
    /// Shift, as it does in Finder.
    static func click(for event: NSEvent?) -> LibrarySelection.Click {
        let flags = event?.modifierFlags ?? []
        if flags.contains(.command) { return .command }
        if flags.contains(.shift) { return .shift }
        return .plain
    }
}

/// An item of the library: a click selects it, a double click opens it, and its frame
/// is reported so a marquee can find it.
struct SelectableItem: ViewModifier {
    let id: String
    let state: LibraryState
    let order: [String]
    let open: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .onTapGesture {
                // The event is read rather than the gesture counted: a counted double
                // tap holds the first click back until it knows, and Finder's
                // selection does not wait.
                let event = NSApp.currentEvent
                if event?.clickCount == 2 {
                    open()
                } else {
                    state.selection.click(id, LibraryState.click(for: event), in: order)
                }
            }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(LibraryState.space))
            } action: {
                state.frames[id] = $0
            }
            .onDisappear { state.frames[id] = nil }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open", open)
    }
}

/// The library's container: a drag across it is a marquee, drawn as it goes, that
/// selects what it crosses. A click on empty space clears the selection.
struct Marquee: ViewModifier {
    let state: LibraryState
    /// The point the drag began at and whether Shift or Command was held then, kept
    /// through the drag so the frame is anchored and the keys are read once.
    @State private var start: (point: CGPoint, additive: Bool)?

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture { state.selection.clear() }
            .gesture(
                DragGesture(
                    minimumDistance: Size.marqueeThreshold, coordinateSpace: .named(LibraryState.space)
                )
                .onChanged { value in
                    if start == nil {
                        let flags = NSApp.currentEvent?.modifierFlags ?? []
                        start = (value.startLocation, flags.contains(.shift) || flags.contains(.command))
                    }
                    guard let start else { return }
                    let frame = CGRect(
                        origin: start.point, size: .zero
                    ).union(CGRect(origin: value.location, size: .zero))
                    state.marquee = frame
                    let crossed = Set(state.frames.filter { $0.value.intersects(frame) }.keys)
                    state.selection.marquee(crossed: crossed, additive: start.additive)
                }
                .onEnded { _ in
                    start = nil
                    state.marquee = nil
                    state.selection.endMarquee()
                }
            )
            .overlay(alignment: .topLeading) {
                if let m = state.marquee {
                    Rectangle()
                        .fill(Ink.marqueeFill)
                        .stroke(Ink.marqueeStroke, lineWidth: Size.hairline)
                        .frame(width: m.width, height: m.height)
                        .offset(x: m.minX, y: m.minY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: LibraryState.space)
    }
}

extension View {
    func selectable(_ id: String, in state: LibraryState, order: [String], open: @escaping () -> Void)
        -> some View
    {
        modifier(SelectableItem(id: id, state: state, order: order, open: open))
    }

    func marquee(_ state: LibraryState) -> some View { modifier(Marquee(state: state)) }
}
