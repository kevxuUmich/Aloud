import AloudUI
import Foundation

/// The reader's text size as an index into `Type.readerSizes`, with the one clamp and
/// the two steps the toolbar menu and the View menu both use.
enum ReaderSize {
    /// The `UserDefaults` key the reader and the View menu share through `@AppStorage`.
    static let key = "readerSizeIndex"
    static let names = ["Smallest", "Small", "Medium", "Large", "Largest"]
    static var last: Int { Type.readerSizes.count - 1 }

    /// `@AppStorage` hands back whatever is in defaults, including a value written by a
    /// build with a different number of sizes, so the index is clamped in one place.
    static func clamp(_ i: Int) -> Int { min(max(i, 0), last) }
    static func smaller(_ i: Int) -> Int { max(0, clamp(i) - 1) }
    static func larger(_ i: Int) -> Int { min(last, clamp(i) + 1) }
    static func name(_ i: Int) -> String { names[clamp(i)] }
}
