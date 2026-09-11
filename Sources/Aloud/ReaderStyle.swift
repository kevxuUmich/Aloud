import AppKit
import SwiftUI

/// The reader's typeface: two of the system's own designs, so every size and weight
/// is the Mac's and nothing is bundled. Only the prose takes it; titles, cards and
/// controls keep the app's type.
enum ReaderTypeface: String, CaseIterable {
    case sans, serif

    /// The `UserDefaults` key the reader and the View menu share through `@AppStorage`.
    static let key = "readerTypeface"
    static let standard: ReaderTypeface = .sans

    var name: String {
        switch self {
        case .sans: "Sans"
        case .serif: "Serif"
        }
    }

    var design: NSFontDescriptor.SystemDesign {
        switch self {
        case .sans: .default
        case .serif: .serif
        }
    }

    /// The stored value, or the default when the store holds nothing or a name this
    /// build does not know.
    static func stored(_ raw: String) -> ReaderTypeface { ReaderTypeface(rawValue: raw) ?? standard }
}

/// Light, dark, or whatever the Mac is set to. Set from inside the reader, and applied
/// to the whole window rather than the reader alone, so the library behind it does
/// not clash on the way back out.
enum Appearance: String, CaseIterable {
    case system, light, dark

    static let key = "appearance"
    static let standard: Appearance = .system

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Nil is SwiftUI's "follow the system".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func stored(_ raw: String) -> Appearance { Appearance(rawValue: raw) ?? standard }
}
