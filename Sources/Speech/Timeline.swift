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

    public func elapsed(at index: Int) -> Duration {
        guard !starts.isEmpty else { return .zero }
        return starts[min(max(index, 0), starts.count - 1)]
    }

    public static func seconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
