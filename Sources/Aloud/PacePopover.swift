import AloudUI
import Speech
import SwiftUI

/// Speed and the two pauses as sliders, opened from the speed button and the tune
/// button beside it. The speed slider steps through `Rate`'s cases rather than a
/// continuous band, because the rate the player speaks at is one of those cases; the
/// pauses are the seconds Settings offers, on the same band and step. The value at the
/// row's right is the slider's only label: the ends said 0.5x and 3x once, and the
/// row was the busier for it.
struct PacePopover: View {
    var model: AppModel

    private var rateIndex: Binding<Double> {
        Binding(
            get: { Double(Rate.allCases.firstIndex(of: model.player.rate) ?? 0) },
            set: { model.setRate(Rate.allCases[Int($0.rounded())]) })
    }

    private func pause(_ key: WritableKeyPath<Pauses, Duration>) -> Binding<Double> {
        Binding(
            get: { model.player.pauses[keyPath: key].seconds },
            set: { seconds in
                var p = model.player.pauses
                p[keyPath: key] = .seconds(seconds)
                model.setPauses(p)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Pace").font(Type.title)
            row("Speed", value: model.player.rate.label) {
                Slider(value: rateIndex, in: 0...Double(Rate.allCases.count - 1), step: 1) {
                    Text("Speed")
                }
            }
            row("After a sentence", value: Pauses.label(model.player.pauses.sentence)) {
                Slider(value: pause(\.sentence), in: Pauses.range, step: Pauses.step) {
                    Text("After a sentence")
                }
            }
            row("After a line break", value: Pauses.label(model.player.pauses.paragraph)) {
                Slider(value: pause(\.paragraph), in: Pauses.range, step: Pauses.step) {
                    Text("After a line break")
                }
            }
        }
        .padding(Space.l)
        .frame(width: Size.popoverWidth)
    }

    /// A caption with the value at its right, and the slider under it. The slider's
    /// own label is kept for accessibility and hidden from view, since the caption
    /// already says it.
    @ViewBuilder
    private func row<S: View>(_ name: String, value: String, @ViewBuilder slider: () -> S)
        -> some View
    {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(name).font(Type.caption)
                Spacer()
                Text(value).font(Type.caption).foregroundStyle(Ink.soft).monospacedDigit()
            }
            slider().labelsHidden()
        }
    }
}
