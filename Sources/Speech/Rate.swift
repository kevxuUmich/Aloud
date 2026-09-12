import Foundation

public enum Rate: Double, CaseIterable, Sendable, Hashable {
    case x05 = 0.5, x075 = 0.75, x1 = 1, x125 = 1.25, x15 = 1.5, x175 = 1.75, x2 = 2, x225 = 2.25,
        x25 = 2.5, x275 = 2.75, x3 = 3

    public var factor: Double { rawValue }

    public var label: String {
        let s = rawValue.formatted(
            .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
        return s + "x"
    }

    /// One step up the band, and the top stays the top: these are the arrow keys'
    /// steps, and a key held down should stop at the end rather than wrap to the other.
    public var faster: Rate {
        let all = Rate.allCases
        return all[min(all.firstIndex(of: self)! + 1, all.count - 1)]
    }

    public var slower: Rate {
        let all = Rate.allCases
        return all[max(all.firstIndex(of: self)! - 1, 0)]
    }

    /// AVSpeechUtterance rate: 0.5 is the default and 1.0 the maximum.
    /// Below 1x the mapping is proportional; above it, 1x to 3x spans default to maximum.
    public var appleRate: Float {
        let d = 0.5
        if rawValue <= 1 { return Float(d * rawValue) }
        return Float(d + (1 - d) * (rawValue - 1) / 2)
    }
}
