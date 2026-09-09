import Foundation

public enum Rate: Double, CaseIterable, Sendable, Hashable {
    case x075 = 0.75, x1 = 1, x125 = 1.25, x15 = 1.5, x175 = 1.75, x2 = 2, x25 = 2.5, x3 = 3

    public var factor: Double { rawValue }

    public var label: String {
        let s = rawValue.formatted(
            .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
        return s + "x"
    }

    public var next: Rate {
        let all = Rate.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + 1) % all.count]
    }

    /// AVSpeechUtterance rate: 0.5 is the default and 1.0 the maximum.
    /// Below 1x the mapping is proportional; above it, 1x to 3x spans default to maximum.
    public var appleRate: Float {
        let d = 0.5
        if rawValue <= 1 { return Float(d * rawValue) }
        return Float(d + (1 - d) * (rawValue - 1) / 2)
    }
}
