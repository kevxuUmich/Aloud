import AloudUI
import AppKit
import Foundation
import Speech
import SwiftUI

/// The voice picker. Grouped by language, the one being read first, with a preview on
/// every row; a pick takes at the next sentence and is remembered.
struct VoicePopover: View {
    var model: AppModel

    /// Grouping the whole installed set is not work for every render, and the set can
    /// only change while the popover is shut, so it is done once, as it opens.
    @State private var groups: [VoiceGroup] = []
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// What the list shows: the whole installed set, or what the field has narrowed it
    /// to. The filter is a pure function in `Speech`, so the rule is tested and the
    /// view only draws.
    private var shown: [VoiceGroup] { VoiceSearch.filter(groups, query: query) }

    /// The provider caches the installed set, and downloading a voice in System
    /// Settings while Aloud is running is exactly the moment that cache is wrong. Every
    /// opening asks the system again, which is cheap once and only once.
    private func load() {
        model.provider.refreshVoices()
        groups = VoiceGroups.group(
            model.provider.voices, currentLanguage: VoiceGroups.currentLanguage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Voice").font(Type.title)
            TextField("Search voices", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            // A filter that matched nothing says so. An installed set that is empty
            // before `load()` has run is not that, and would flash the words for a
            // frame, so the empty list keeps quiet.
            if shown.isEmpty, !groups.isEmpty {
                Text("No voices match")
                    .font(Type.caption)
                    .foregroundStyle(Ink.soft)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(shown) { g in
                        Section {
                            ForEach(g.voices) { v in
                                VoiceRow(
                                    name: v.name, region: v.regionName, quality: v.quality.label,
                                    isSelected: v.id == model.player.voice?.id,
                                    onPreview: { model.player.preview(v) },
                                    onPick: { model.pickVoice(v) })
                            }
                        } header: {
                            Text(g.name)
                                .font(Type.caption)
                                .foregroundStyle(Ink.soft)
                                .padding(.top, Space.m)
                        }
                    }
                }
            }
            Button("Get more voices...") {
                NSWorkspace.shared.open(Self.spokenContentSettings)
            }
            .buttonStyle(.link)
            // The question every reader asks once: Siri's voices are not in this list
            // and cannot be, so the list says so rather than looking incomplete. The
            // frame below is the measure; the copy needs no width of its own.
            Text(
                """
                Siri voices are not available to apps. Download Enhanced or Premium \
                voices under Accessibility, Spoken Content.
                """
            )
            .font(Type.caption)
            .foregroundStyle(Ink.soft)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.xl)
        .frame(width: Size.popoverWidth, height: Size.popoverHeight)
        .onAppear {
            load()
            searchFocused = true
        }
    }

    static let spokenContentSettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")!
}
