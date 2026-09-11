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
    /// The handpicked list, each beside the installed voice it names or beside
    /// nothing. Resolved with the groups, from the same read of the installed set.
    @State private var recommended: [RecommendedEntry] = []
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
        let voices = model.provider.voices
        groups = VoiceGroups.group(voices, currentLanguage: VoiceGroups.currentLanguage)
        recommended = RecommendedVoices.resolve(voices)
    }

    /// A voice that is not installed is picked in System Settings, where Apple keeps
    /// the download; the popover can only take the reader there.
    private func download() {
        NSWorkspace.shared.open(Self.spokenContentSettings)
    }

    /// The handpicked list, above the language sections. A search is a search of the
    /// installed set, and the list is not that, so it steps aside while the field has
    /// text in it.
    @ViewBuilder private var recommendedSection: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !recommended.isEmpty {
            Section {
                ForEach(recommended) { e in
                    let r = e.recommendation
                    VoiceRow(
                        name: r.name, region: e.voice?.regionName ?? r.regionName,
                        quality: r.quality.label, badge: r.sizeLabel,
                        isSelected: e.voice != nil && e.voice?.id == model.player.voice?.id,
                        isInstalled: e.isInstalled,
                        onPreview: { if let v = e.voice { model.player.preview(v) } },
                        onPick: {
                            if let v = e.voice { model.pickVoice(v) } else { download() }
                        })
                }
                // The note is for the reader who has none of them yet; once one is
                // installed the arrow on the rest says enough on its own.
                if !recommended.contains(where: \.isInstalled) {
                    Text(Self.downloadNote)
                        .font(Type.caption)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Recommended")
                    .font(Type.caption)
                    .foregroundStyle(Ink.soft)
            }
        }
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
                    recommendedSection
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

    /// Shown under the recommended list while none of it is installed: the one
    /// sentence that turns an arrow into a plan.
    static let downloadNote =
        "None of these are installed yet. Click one to download it free in System Settings, "
        + "then come back here to pick it."

    static let spokenContentSettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")!
}
