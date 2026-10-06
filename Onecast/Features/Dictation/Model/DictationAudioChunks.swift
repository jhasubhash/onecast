import Foundation

enum DictationAudioChunks {
    static func ranges(in samples: [Float], maximum: Int) -> [Range<Int>] {
        precondition(maximum > 0)
        var ranges = [Range<Int>]()
        var start = 0
        while start < samples.count {
            var end = min(start + maximum, samples.count)
            if end < samples.count, end - start >= 3200 {
                end = quietPoint(in: samples, within: max(start, end - 48_000)..<end)
            }
            ranges.append(start..<end)
            start = end
        }
        return ranges
    }

    /// The middle of the quietest 200 ms in `range`, latest on a tie; `range` spans at least 200 ms.
    static func quietPoint(in samples: [Float], within range: Range<Int>) -> Int {
        let window = 3200
        precondition(range.count >= window && range.upperBound <= samples.count)
        var quietest: Float = .infinity
        var point = range.upperBound
        for offset in stride(from: range.lowerBound, through: range.upperBound - window, by: 160) {
            let energy = samples[offset..<(offset + window)].reduce(Float.zero) { $0 + $1 * $1 }
            if energy <= quietest { quietest = energy; point = offset + window / 2 }
        }
        return point
    }
}
