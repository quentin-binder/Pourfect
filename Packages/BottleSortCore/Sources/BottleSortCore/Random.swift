/// SplitMix64: tiny, fast, seedable PRNG. Same seed → same sequence on every
/// platform and Swift version (unlike `SystemRandomNumberGenerator`).
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in 0..<n (multiply-high; bias is negligible for small n).
    public mutating func nextInt(below n: Int) -> Int {
        precondition(n > 0)
        return Int(next().multipliedFullWidth(by: UInt64(n)).high)
    }

    /// Fisher–Yates shuffle with a fixed algorithm, so results never change
    /// across Swift versions (the stdlib's `shuffle(using:)` makes no such promise).
    public mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            array.swapAt(i, nextInt(below: i + 1))
        }
    }
}
