import Foundation

/// The app's settings, one typed accessor per key, so the app and Settings agree on names.
public enum Defaults {
    /// The one `nonisolated(unsafe)` in the app: the store is a settable global so the
    /// tests can swap in a throwaway `UserDefaults(suiteName:)` instead of writing the
    /// user's real preferences. Only the tests ever write it, and only before they read.
    nonisolated(unsafe) public static var store = UserDefaults.standard
    public static var noteFolderPath: String? {
        get { store.string(forKey: "noteFolderPath") }
        set { store.set(newValue, forKey: "noteFolderPath") }
    }
    public static var voiceID: String? {
        get { store.string(forKey: "voiceID") }
        set { store.set(newValue, forKey: "voiceID") }
    }
    public static var rateFactor: Double? {
        get { store.object(forKey: "rateFactor") as? Double }
        set { store.set(newValue, forKey: "rateFactor") }
    }
    /// The pauses in seconds, nil until Settings writes one: the player's own
    /// standard is the default, the way `rateFactor` leaves the rate's to the player.
    public static var sentencePause: Double? {
        get { store.object(forKey: "sentencePause") as? Double }
        set { store.set(newValue, forKey: "sentencePause") }
    }
    public static var paragraphPause: Double? {
        get { store.object(forKey: "paragraphPause") as? Double }
        set { store.set(newValue, forKey: "paragraphPause") }
    }
    public static var skipCode: Bool {
        get { store.object(forKey: "skipCode") as? Bool ?? true }
        set { store.set(newValue, forKey: "skipCode") }
    }
    public static var showMenuBar: Bool {
        get { store.object(forKey: "showMenuBar") as? Bool ?? true }
        set { store.set(newValue, forKey: "showMenuBar") }
    }
    public static var listView: Bool {
        get { store.bool(forKey: "listView") }
        set { store.set(newValue, forKey: "listView") }
    }
}
