import Foundation
import Prose

public struct Timeline: Sendable {
    public let starts: [Duration]
    public let total: Duration

    public init(script: Script, rate: Rate) {
        var acc: Duration = .zero
        var starts: [Duration] = []
        for s in script.sentences {
            starts.append(acc)
            acc += Estimate.duration(words: Estimate.words(in: s.text), factor: rate.factor)
        }
        self.starts = starts
        self.total = acc
    }

    public func index(at time: Duration) -> Int {
        guard !starts.isEmpty else { return 0 }
        if time <= .zero { return 0 }
        var i = starts.count - 1
        while i > 0, starts[i] > time { i -= 1 }
        return i
    }

    /// The estimate for one sentence: the gap to the next start, or to the end.
    public func duration(at index: Int) -> Duration {
        guard !starts.isEmpty else { return .zero }
        let i = min(max(index, 0), starts.count - 1)
        let end = i + 1 < starts.count ? starts[i + 1] : total
        return end - starts[i]
    }

    public func elapsed(at index: Int) -> Duration {
        guard !starts.isEmpty else { return .zero }
        return starts[min(max(index, 0), starts.count - 1)]
    }

    public static func seconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}

/// The same conversion as `Timeline.seconds(_:)`, reachable from a `Duration` itself.
/// Public because Now Playing wants seconds and the app targets read it.
extension Duration {
    public var seconds: Double { Timeline.seconds(self) }
}
