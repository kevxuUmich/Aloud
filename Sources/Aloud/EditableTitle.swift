import AloudUI
import SwiftUI

/// The reader's title, beside the back button, and the way a document is renamed
/// from the reader: a click on it turns it into a field with the title selected,
/// Return or a click away commits, Escape puts the old title back. The same name
/// again, or none, is not a rename.
///
/// Before the title, for a note the panel wrote, is the icon of the app the text came
/// from: the one the bar shows beside the same title. It stays put while the title is
/// a field, so the title does not jump sideways as the rename begins and ends.
struct EditableTitle: View {
    let title: String
    var icon: NSImage? = nil
    /// True when the library's Rename asked for this title to be edited. The field
    /// opens on it and `onBegan` clears the request.
    let requested: Bool
    let onBegan: () -> Void
    let onRename: (String) -> Void
    @State private var editing = false
    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.xs) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Size.titleIcon, height: Size.titleIcon)
                    .accessibilityHidden(true)
            }
            content
        }
        .onChange(of: requested, initial: true) { _, now in
            guard now else { return }
            begin()
            onBegan()
        }
    }

    func begin() {
        draft = title
        editing = true
    }

    @ViewBuilder var content: some View {
        if editing {
            TextField("Title", text: $draft)
                .textFieldStyle(.plain)
                .font(Type.toolbarTitle)
                .frame(minWidth: Size.titleField, maxWidth: .infinity)
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit { commit() }
                // Escape: the field goes, and the focus it drops on the way out finds
                // `editing` already false, so nothing is committed.
                .onExitCommand { editing = false }
                .onChange(of: focused) { _, now in if !now, editing { commit() } }
                .accessibilityLabel("Title")
        } else {
            Button {
                begin()
            } label: {
                Text(title)
                    .font(Type.toolbarTitle)
                    .lineLimit(Type.singleLine)
                    .padding(.horizontal, Space.xs)
                    .background(hovering ? Ink.badge : .clear, in: .rect(cornerRadius: Radius.xs))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Rename")
            .accessibilityLabel("Title: \(title)")
            .accessibilityHint("Click to rename")
        }
    }

    func commit() {
        editing = false
        let new = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != title else { return }
        onRename(new)
    }
}
