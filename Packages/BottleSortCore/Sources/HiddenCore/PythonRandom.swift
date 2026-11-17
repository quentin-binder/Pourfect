import Foundation

/// CPython's `random.Random` (Mersenne Twister MT19937) for integer seeds, bit for bit: `random()`,
/// `getrandbits`, `uniform`, `shuffle` and `sample` give the same results as Python 3.9+'s for the same seed.
/// The hidden-object placement rules were tuned with the art pipeline's `layout.py`; using its generator lets the
/// tests compare whole layouts against it (`HiddenPoC`), and the app's rounds use it too so one stream drives both.
public struct PythonRandom: Sendable {
    private var mt = [UInt32](repeating: 0, count: 624)
    private var index = 624

    /// `random.Random(seed)` for a non-negative integer seed.
    public init(seed: UInt64) {
        var key: [UInt32] = []
        var n = seed
        while n > 0 {
            key.append(UInt32(truncatingIfNeeded: n))
            n >>= 32
        }
        if key.isEmpty { key = [0] }
        initByArray(key)
    }

    private mutating func initGenrand(_ s: UInt32) {
        mt[0] = s
        for i in 1..<624 {
            mt[i] = 1_812_433_253 &* (mt[i - 1] ^ (mt[i - 1] >> 30)) &+ UInt32(i)
        }
        index = 624
    }

    private mutating func initByArray(_ key: [UInt32]) {
        initGenrand(19_650_218)
        var i = 1, j = 0
        for _ in 0..<max(624, key.count) {
            mt[i] = (mt[i] ^ ((mt[i - 1] ^ (mt[i - 1] >> 30)) &* 1_664_525)) &+ key[j] &+ UInt32(j)
            i += 1; j += 1
            if i >= 624 { mt[0] = mt[623]; i = 1 }
            if j >= key.count { j = 0 }
        }
        for _ in 0..<623 {
            mt[i] = (mt[i] ^ ((mt[i - 1] ^ (mt[i - 1] >> 30)) &* 1_566_083_941)) &- UInt32(i)
            i += 1
            if i >= 624 { mt[0] = mt[623]; i = 1 }
        }
        mt[0] = 0x8000_0000
        index = 624
    }

    private mutating func twist() {
        for k in 0..<624 {
            let y = (mt[k] & 0x8000_0000) | (mt[(k + 1) % 624] & 0x7FFF_FFFF)
            mt[k] = mt[(k + 397) % 624] ^ (y >> 1) ^ ((y & 1) == 0 ? 0 : 0x9908_B0DF)
        }
        index = 0
    }

    /// One 32-bit output (`genrand_uint32`).
    public mutating func nextUInt32() -> UInt32 {
        if index >= 624 { twist() }
        var y = mt[index]
        index += 1
        y ^= y >> 11
        y ^= (y << 7) & 0x9D2C_5680
        y ^= (y << 15) & 0xEFC6_0000
        y ^= y >> 18
        return y
    }

    /// `random()`: 53-bit float in [0, 1).
    public mutating func random() -> Double {
        let a = Double(nextUInt32() >> 5), b = Double(nextUInt32() >> 6)
        return (a * 67_108_864.0 + b) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// `getrandbits(k)` for 0 ≤ k ≤ 32.
    public mutating func getrandbits(_ k: Int) -> UInt32 {
        precondition((0...32).contains(k))
        if k == 0 { return 0 }
        return nextUInt32() >> UInt32(32 - k)
    }

    /// `_randbelow(n)`: rejection sampling on `n.bit_length()` bits (n < 2³²).
    public mutating func randbelow(_ n: Int) -> Int {
        precondition(n > 0 && n <= Int(UInt32.max))
        let k = Int.bitWidth - n.leadingZeroBitCount
        var r = Int(getrandbits(k))
        while r >= n { r = Int(getrandbits(k)) }
        return r
    }

    /// `uniform(a, b)` = a + (b − a) · random().
    public mutating func uniform(_ a: Double, _ b: Double) -> Double { a + (b - a) * random() }

    /// `shuffle(x)` in place.
    public mutating func shuffle<T>(_ x: inout [T]) {
        guard x.count > 1 else { return }
        for i in stride(from: x.count - 1, through: 1, by: -1) {
            x.swapAt(i, randbelow(i + 1))
        }
    }

    /// `sample(population, k)` (both of CPython's strategies: the pool for small populations, the set otherwise).
    public mutating func sample<T>(_ population: [T], _ k: Int) -> [T] {
        let n = population.count
        precondition(k >= 0 && k <= n)
        var setsize = 21
        if k > 5 {
            setsize += Int(pow4(Int((log(Double(k * 3)) / log(4.0)).rounded(.up))))
        }
        var result: [T] = []
        result.reserveCapacity(k)
        if n <= setsize {
            var pool = population
            for i in 0..<k {
                let j = randbelow(n - i)
                result.append(pool[j])
                pool[j] = pool[n - i - 1]
            }
        } else {
            var selected = Set<Int>()
            for _ in 0..<k {
                var j = randbelow(n)
                while selected.contains(j) { j = randbelow(n) }
                selected.insert(j)
                result.append(population[j])
            }
        }
        return result
    }

    private func pow4(_ e: Int) -> Int { (0..<max(0, e)).reduce(1) { acc, _ in acc * 4 } }
}
