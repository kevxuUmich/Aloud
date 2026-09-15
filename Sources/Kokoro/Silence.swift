import Foundation

/// The silence the model renders around every piece of speech: about 0.35 s before the
/// first word and 0.4 s after the last, measured on 2026-09-15 across forty sentences of
/// a real document at 1.75x. Left in, every seam between two chunks of one sentence was
/// a 0.75 s stop, and the pause between two sentences was that on top of the one the
/// reader set. So every render is trimmed to its speech, and the silences the reader
/// hears are the ones the app chooses: the seam beat and the reader's own pause.
enum Silence {
    /// Below this a sample is silence. The model's own silence is within a few
    /// thousandths of zero, and the quietest speech sits well above it.
    static let threshold: Float = 0.002
    /// How much of the surrounding silence stays on each side of the speech, in samples
    /// at 24 kHz: 30 ms, enough that no onset or decay is clipped.
    static let margin = 720

    /// `samples` cut down to the speech in them, with up to `margin` samples of the
    /// silence around it kept on each side. All silence comes back empty.
    static func trim(_ samples: [Float], threshold: Float = threshold, margin: Int = margin) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) >= threshold }),
            let last = samples.lastIndex(where: { abs($0) >= threshold })
        else { return [] }
        return Array(samples[max(0, first - margin)...min(samples.count - 1, last + margin)])
    }
}
