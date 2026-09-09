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
    /// only change while the popover is shut, so it is done once as it opens.
    @State private var groups: [VoiceGroup] = []

    /// `Locale.current.identifier` is underscored ("en_US"), and the grouping splits a
    /// BCP-47 tag on its dash, so the tag has to be asked for in that spelling.
    private func load() {
        groups = VoiceGroups.group(
            model.provider.voices, currentLanguage: Locale.current.identifier(.bcp47))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Voice").font(Type.title)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(groups) { g in
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
        }
        .padding(Space.xl)
        .frame(width: Size.popoverWidth, height: Size.popoverHeight)
        .onAppear(perform: load)
    }

    static let spokenContentSettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")!
}
