import Foundation

public enum Format {
    public static func clock(_ d: Duration) -> String {
        let total = max(0, Int(d.components.seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h):" + String(format: "%02d:%02d", m, s)
        }
        return "\(m):" + String(format: "%02d", s)
    }
    /// A level from 0 to 1 as the card says it: "60%".
    public static func percent(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }
    public static func minutes(_ d: Duration) -> String {
        let m = max(1, Int((Double(max(0, d.components.seconds)) / 60).rounded()))
        return m == 1 ? "1 min" : "\(m) min"
    }
}
