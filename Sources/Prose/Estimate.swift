import Foundation

public enum Estimate {
    public static let wordsPerMinute = 160.0
    public static func duration(words: Int, factor: Double) -> Duration {
        guard words > 0 else { return .zero }
        let seconds = Double(words) / wordsPerMinute * 60 / factor
        return .seconds(seconds)
    }
    public static func words(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
