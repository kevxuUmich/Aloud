import Foundation

/// The app's settings, one typed accessor per key, so the app and Settings agree on names.
public enum Defaults {
    /// The one `nonisolated(unsafe)` in the app: the store the app itself reads and
    /// writes, settable so a host that keeps its settings elsewhere can point it there
    /// before anything reads. The tests leave it alone and use `overrideStore`.
    nonisolated(unsafe) public static var store = UserDefaults.standard
    /// A `UserDefaults` that can cross into a task local. The class is thread safe and
    /// documented as such, and is only missing the annotation, so this asserts what the
    /// framework already promises rather than papering over a race.
    public struct Store: @unchecked Sendable {
        public let defaults: UserDefaults
        public init(_ defaults: UserDefaults) { self.defaults = defaults }
    }

    /// A store for the duration of one task tree, which is how the tests get a
    /// throwaway suite without swapping the process-global out from under whatever
    /// else is running: suites run in parallel, and a global swapped mid-test is read
    /// by every other suite in the package. Nil everywhere but inside a test's
    /// `Defaults.$overrideStore.withValue(.init(suite)) { ... }`.
    @TaskLocal public static var overrideStore: Store?
    /// The store every accessor below reads and writes: the task's own if it has one,
    /// the app's otherwise.
    public static var current: UserDefaults { overrideStore?.defaults ?? store }
    public static var noteFolderPath: String? {
        get { current.string(forKey: "noteFolderPath") }
        set { current.set(newValue, forKey: "noteFolderPath") }
    }
    public static var voiceID: String? {
        get { current.string(forKey: "voiceID") }
        set { current.set(newValue, forKey: "voiceID") }
    }
    public static var rateFactor: Double? {
        get { current.object(forKey: "rateFactor") as? Double }
        set { current.set(newValue, forKey: "rateFactor") }
    }
    /// The pauses in seconds, nil until Settings writes one: the player's own
    /// standard is the default, the way `rateFactor` leaves the rate's to the player.
    public static var sentencePause: Double? {
        get { current.object(forKey: "sentencePause") as? Double }
        set { current.set(newValue, forKey: "sentencePause") }
    }
    public static var paragraphPause: Double? {
        get { current.object(forKey: "paragraphPause") as? Double }
        set { current.set(newValue, forKey: "paragraphPause") }
    }
    /// The player's level, nil until the slider is moved: full is the player's own default.
    public static var volume: Double? {
        get { current.object(forKey: "volume") as? Double }
        set { current.set(newValue, forKey: "volume") }
    }
    public static var skipCode: Bool {
        get { current.object(forKey: "skipCode") as? Bool ?? true }
        set { current.set(newValue, forKey: "skipCode") }
    }
    public static var showMenuBar: Bool {
        get { current.object(forKey: "showMenuBar") as? Bool ?? true }
        set { current.set(newValue, forKey: "showMenuBar") }
    }
    /// Whether the hotkey has asked for the Accessibility grant, which it does once:
    /// the system's prompt on every press would be a nag, and Settings has the button.
    public static var askedForSelection: Bool {
        get { current.bool(forKey: "askedForSelection") }
        set { current.set(newValue, forKey: "askedForSelection") }
    }
    public static var listView: Bool {
        get { current.bool(forKey: "listView") }
        set { current.set(newValue, forKey: "listView") }
    }
}
