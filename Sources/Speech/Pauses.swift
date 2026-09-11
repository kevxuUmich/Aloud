import Foundation

/// The silences the player leaves between sentences. Both are absolute rather than a
/// share of the sentence: a beat is a beat at any speed, which is why the timeline
/// counts them outside the rate.
public struct Pauses: Sendable, Hashable {
    /// After a sentence that another sentence follows on the same line.
    public var sentence: Duration
    /// After a sentence that ends a paragraph, in place of the sentence pause rather
    /// than on top of it: the longer beat is the paragraph's.
    public var paragraph: Duration

    public init(sentence: Duration, paragraph: Duration) {
        self.sentence = sentence
        self.paragraph = paragraph
    }

    /// What the app ships with, and what the player falls back to.
    public static let standard = Pauses(sentence: .milliseconds(200), paragraph: .milliseconds(300))
    /// No silence at all, for a timeline that is only the words.
    public static let none = Pauses(sentence: .zero, paragraph: .zero)

    /// The band Settings offers, in seconds, and the step it moves by.
    public static let range: ClosedRange<Double> = 0...2
    public static let step: Double = 0.05

    public static func label(_ d: Duration) -> String {
        d.seconds.formatted(
            .number.precision(.fractionLength(1...2)).locale(Locale(identifier: "en_US_POSIX")))
            + " s"
    }
}
