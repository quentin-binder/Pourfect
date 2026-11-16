import AVFoundation
import Foundation

/// Plays the game's sounds. Every sound is synthesized into an `AVAudioPCMBuffer` once (no audio
/// files) and played through a small pool of `AVAudioPlayerNode`s on one `AVAudioEngine`.
///
/// The engine starts lazily on the first sound (or `warmUp()`), restarts itself after an
/// interruption or route/configuration change, and quietly does nothing when audio is
/// unavailable. On iOS the session is `.ambient`: it respects the silent switch and mixes with
/// music. Whether sounds are wanted at all is the caller's decision (see `FeedbackPlayer`).
final class SoundEngine {
    static let shared = SoundEngine()

    nonisolated enum Sound: CaseIterable, Sendable {
        /// Bright glass clink (bottle picked up).
        case clink
        /// Lower, softer clink (bottle lip touches as a pour starts).
        case clinkLow
        /// Cork pop followed by a sparkle chime (flask completed).
        case corkPop
        /// Soft rising arpeggio (level solved).
        case success
        /// Dull muted tap (illegal move).
        case tap
        /// A key dropping into its lock.
        case keyClick
        /// Low glassy hum with a slight wobble: an essence flask's rune refuses a pour.
        case runeHum
        /// A brass valve turning: a short metallic squeak and a click (a tap flask opens).
        case valve
        /// A dull knock on brass: a funnel or a tap flask refuses a pour.
        case brassKnock
        /// A cold, high tink on ice: a frozen layer refuses a pour.
        case frostTink
        /// Ice thawing: a soft crackle, then a few gentle drips (a frozen layer melts).
        case thaw
        /// A bubbling flask bubbling up: small bubbles quickening and rising in pitch, then a
        /// round "bloop" as the bottom layer reaches the top.
        case bubbleUp
        /// Silver chain links jingling: a twin chain refuses a pour (softly: a pour splits
        /// between twins).
        case chainRattle
        /// A pressure pipe pushes (F2): a low pneumatic thump and hiss, then hollow glugs as the
        /// bottom layers run through the tube into the far flask.
        case pipePush
        /// Brewing in a cauldron: a stirring swish with bubbles, then a soft sparkling chime as
        /// the new potion blooms (two ingredients mixed).
        case brew
    }

    /// Synthesis rate; the mixer converts to the hardware rate.
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynthesis.sampleRate, channels: 1)!

    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    /// Gurgle variants per poured amount (1…4 layers), alternated so repeats don't sound identical.
    private var gurgles: [[AVAudioPCMBuffer]] = []
    private var gurgleTurn = 0

    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    /// After a failed start, don't retry before this time (avoids hammering a dead device).
    private var retryAfter = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    /// Delayed sounds not yet started, by id (see `cancelPending()`).
    private var pending: [Int: Task<Void, Never>] = [:]
    private var pendingCount = 0

    private init() {
        // Synthesis is pure math; do it off the main actor so opening a level never waits on it.
        // Sounds requested before it finishes are skipped.
        Task.detached(priority: .userInitiated) { [weak self] in
            let output = SoundSynthesis.makeAll()
            await self?.install(output)
        }
    }

    // MARK: API

    /// Starts the engine ahead of the first sound so it plays without delay.
    func warmUp() {
        _ = ensureRunning()
    }

    /// Plays `sound` now, or after `delay` seconds.
    func play(_ sound: Sound, after delay: TimeInterval = 0, volume: Float = 1) {
        guard let buffer = buffers[sound] else { return }   // still synthesizing
        schedule(buffer, after: delay, volume: volume)
    }

    /// Bubbly pour sound for `amount` layers (1…4+). Lasts `gurgleDuration(amount:)` seconds;
    /// more layers sound longer and busier.
    func playGurgle(amount: Int, after delay: TimeInterval = 0) {
        guard !gurgles.isEmpty else { return }
        let variants = gurgles[min(max(amount, 1), gurgles.count) - 1]
        gurgleTurn += 1
        schedule(variants[gurgleTurn % variants.count], after: delay, volume: 1)
    }

    /// Length of the gurgle for `amount` layers: 0.35 s (1 layer) to 0.5 s (4+), around the
    /// pour animation's 0.4 s flow; the last third is a fade-out.
    nonisolated static func gurgleDuration(amount: Int) -> TimeInterval {
        0.30 + 0.05 * Double(min(max(amount, 1), 4))
    }

    /// Drops sounds scheduled with a delay that haven't started yet (a pour was cancelled).
    func cancelPending() {
        for task in pending.values { task.cancel() }
        pending.removeAll()
    }

    /// Silences everything that is playing or scheduled.
    func stopAll() {
        cancelPending()
        for player in players where player.isPlaying { player.stop() }
        if engine?.isRunning == true { for player in players { player.play() } }
    }

    #if DEBUG
    /// Dev aid (`-LPExportSounds <dir>`): writes every synthesized sound as a WAV file.
    func debugExport(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if buffers.isEmpty { install(SoundSynthesis.makeAll()) }   // launch-time export: don't wait
        var all: [(String, AVAudioPCMBuffer)] = buffers.map { ("\($0.key)", $0.value) }
        for (k, variants) in gurgles.enumerated() {
            for (v, buffer) in variants.enumerated() { all.append(("gurgle\(k + 1)-\(v + 1)", buffer)) }
        }
        for (name, buffer) in all {
            let url = directory.appendingPathComponent("\(name).wav")
            if let file = try? AVAudioFile(forWriting: url, settings: format.settings) {
                try? file.write(from: buffer)
            }
        }
    }
    #endif

    // MARK: Playback

    private func schedule(_ buffer: AVAudioPCMBuffer, after delay: TimeInterval, volume: Float) {
        if delay > 0 {
            pendingCount += 1
            let id = pendingCount
            pending[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                self.pending[id] = nil
                self.schedule(buffer, after: 0, volume: volume)
            }
            return
        }
        guard ensureRunning(), !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// True when the engine runs and the players are ready. Builds the engine on first use and
    /// restarts it after it was stopped by the system.
    private func ensureRunning() -> Bool {
        if let engine, engine.isRunning { return true }
        guard Date() >= retryAfter else { return false }
        #if os(iOS)
        guard activateSession() else { return fail() }
        #endif
        let engine = self.engine ?? makeEngine()
        // No output device (sample rate 0): starting would fail or raise.
        guard engine.outputNode.outputFormat(forBus: 0).sampleRate > 0 else { return fail() }
        for player in players {
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = 0.9
        engine.prepare()
        do {
            try engine.start()
        } catch {
            return fail()
        }
        for player in players { player.play() }
        return true
    }

    private func fail() -> Bool {
        retryAfter = Date().addingTimeInterval(2)
        return false
    }

    private func makeEngine() -> AVAudioEngine {
        let engine = AVAudioEngine()
        players = (0..<8).map { _ in AVAudioPlayerNode() }
        for player in players { engine.attach(player) }
        self.engine = engine
        // A route or format change stops the engine; the next sound restarts it.
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.retryAfter = .distantPast }
            })
        #if os(iOS)
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
                // Began: the system stopped the engine. Ended: the next sound restarts it.
                MainActor.assumeIsolated { self?.retryAfter = .distantPast }
            })
        #endif
        return engine
    }

    #if os(iOS)
    private var sessionConfigured = false

    private func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            if !sessionConfigured {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                sessionConfigured = true
            }
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }
    #endif

    /// Installs the synthesized samples as playable buffers.
    private func install(_ output: SoundSynthesis.Output) {
        buffers = output.sounds.compactMapValues { buffer(from: $0) }
        gurgles = output.gurgles.map { $0.compactMap { buffer(from: $0) } }.filter { !$0.isEmpty }
    }

    /// Copies samples into a mono float buffer.
    private func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }   // memcpy
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}

/// The game's sounds as samples (mono, `sampleRate`), synthesized from scratch. Pure math, kept
/// off the main actor: about 30 ms optimized, but most of a second in an unoptimized Debug build.
nonisolated enum SoundSynthesis {
    struct Output: Sendable {
        var sounds: [SoundEngine.Sound: [Float]] = [:]
        /// Variants per poured amount (1…4 layers).
        var gurgles: [[[Float]]] = []
    }

    static let sampleRate = 44_100.0

    static func makeAll() -> Output {
        var out = Output()
        var rng = NoiseGenerator(seed: 0x5EED)
        out.sounds[.clink] = render(0.55, peak: 0.20) { Self.clink(t: $0, f0: 1880) }
        out.sounds[.clinkLow] = render(0.5, peak: 0.13) { Self.clink(t: $0, f0: 1320) }
        let lowNoise = Self.lowpassedNoise(count: Int(0.16 * sampleRate), cutoff: 600, rng: &rng)
        out.sounds[.tap] = render(0.16, peak: 0.16) { t in
            let i = min(Int(t * sampleRate), lowNoise.count - 1)
            return (sin(2 * .pi * 150 * t) * 0.8 + lowNoise[i] * 0.6) * exp(-t * 32)
        }
        out.sounds[.keyClick] = render(0.3, peak: 0.16) { t in
            (sin(2 * .pi * 2600 * t) * 0.5 + sin(2 * .pi * 3900 * t) * 0.3) * exp(-t * 40)
                + Self.clink(t: max(0, t - 0.07), f0: 2300) * (t > 0.07 ? 0.6 : 0)
        }
        out.sounds[.runeHum] = render(0.42, peak: 0.13) { t in
            // Two detuned glass tones beating against each other, a muted strike, quick fade.
            let attack = min(1, t / 0.012)
            let wobble = 1 + 0.5 * sin(2 * .pi * 14 * t)
            let tone = sin(2 * .pi * 392 * t) + 0.8 * sin(2 * .pi * 370 * t) + 0.25 * sin(2 * .pi * 1176 * t)
            return attack * tone * wobble * exp(-t * 9) + Self.clink(t: t, f0: 1100) * 0.18
        }
        out.sounds[.valve] = render(0.32, peak: 0.12) { t in
            // A short squeak gliding up (metal on metal), then the valve seating with a click.
            let squeak = t < 0.14 ? sin(2 * .pi * (620 * t + 1400 * t * t)) * sin(.pi * t / 0.14) * 0.5 : 0
            let click = t > 0.15 ? Self.clink(t: t - 0.15, f0: 2900) * exp(-(t - 0.15) * 30) * 0.7 : 0
            return squeak + click
        }
        out.sounds[.brassKnock] = render(0.35, peak: 0.14) { t in
            // Two low inharmonic metal partials with a fast strike: a muted bell knock.
            let attack = min(1, t / 0.004)
            let tone = sin(2 * .pi * 310 * t) + 0.6 * sin(2 * .pi * 755 * t) * exp(-t * 18)
                + 0.3 * sin(2 * .pi * 1480 * t) * exp(-t * 30)
            return attack * tone * exp(-t * 11)
        }
        out.sounds[.frostTink] = render(0.4, peak: 0.11) { t in
            // A thin, high glass strike with a shimmering second tone: colder than the clink.
            let shimmer = 1 + 0.3 * sin(2 * .pi * 23 * t)
            return Self.clink(t: t, f0: 2650) * 0.8 + sin(2 * .pi * 3720 * t) * exp(-t * 14) * 0.35 * shimmer
        }
        out.sounds[.thaw] = renderThaw(rng: &rng)
        out.sounds[.bubbleUp] = renderBubbleUp(rng: &rng)
        out.sounds[.chainRattle] = renderChainRattle(rng: &rng)
        out.sounds[.pipePush] = renderPipePush(rng: &rng)
        out.sounds[.brew] = renderBrew(rng: &rng)
        out.sounds[.corkPop] = renderCorkPop(rng: &rng)
        out.sounds[.success] = render(1.7, peak: 0.20) { t in
            let notes = [523.25, 659.25, 783.99, 1046.50]
            var sum = 0.0
            for (k, f) in notes.enumerated() {
                let start = Double(k) * 0.11
                guard t >= start else { continue }
                let local = t - start
                let decay = k == notes.count - 1 ? 2.2 : 3.5
                sum += Self.softNote(t: local, f: f) * exp(-local * decay)
            }
            return sum
        }
        for amount in 1...4 {
            var variants: [[Float]] = []
            for variant in 0..<3 {
                let seed = UInt64(amount * 31 + variant * 7 + 1)
                let density = 16.0 + 5.0 * Double(amount)
                variants.append(renderGurgle(duration: SoundEngine.gurgleDuration(amount: amount),
                                             bubblesPerSecond: density, seed: seed))
            }
            out.gurgles.append(variants)
        }
        return out
    }

    /// Glass: a few inharmonic partials, each fading at its own rate, plus a tiny strike.
    private static func clink(t: Double, f0: Double) -> Double {
        let ratios = [1.0, 2.32, 4.25, 6.63]
        let amps = [1.0, 0.45, 0.25, 0.12]
        let decays = [7.0, 10.0, 15.0, 22.0]
        var sum = 0.0
        for k in 0..<ratios.count {
            sum += amps[k] * sin(2 * .pi * f0 * ratios[k] * t) * exp(-t * decays[k])
        }
        return sum
    }

    /// Mellow tone: fundamental with a little 2nd and 3rd harmonic and a soft attack.
    private static func softNote(t: Double, f: Double) -> Double {
        let attack = min(1, t / 0.008)
        return attack * (sin(2 * .pi * f * t) + 0.22 * sin(4 * .pi * f * t) + 0.08 * sin(6 * .pi * f * t))
    }

    private static func renderCorkPop(rng: inout NoiseGenerator) -> [Float] {
        let noise = Self.lowpassedNoise(count: Int(0.02 * sampleRate), cutoff: 3000, rng: &rng)
        let chime = [2093.0, 2637.0, 3136.0, 4186.0]
        return render(1.2, peak: 0.22) { t in
            var sum = 0.0
            // Pop: a pitch drop from 1100 to ~350 Hz over a few tens of ms, plus a puff of air.
            if t < 0.08 {
                let phase = 2 * .pi * (350 * t + (1100 - 350) / 60 * (1 - exp(-t * 60)))
                sum += sin(phase) * exp(-t * 55) * 0.9
                let i = Int(t * sampleRate)
                if i < noise.count { sum += noise[i] * exp(-t * 200) * 0.7 }
            }
            // Sparkle: a quick rising C-major bell run.
            for (k, f) in chime.enumerated() {
                let start = 0.09 + Double(k) * 0.055
                guard t >= start else { continue }
                let local = t - start
                let bell = sin(2 * .pi * f * local) + 0.25 * sin(2 * .pi * f * 2.76 * local) * exp(-local * 8)
                sum += 0.32 * min(1, local / 0.003) * bell * exp(-local * 4.5)
            }
            return sum
        }
    }

    /// Ice thawing: a quiet crackle (short bright noise ticks over 0.3 s) and then three soft
    /// drips, each a short sine gliding down, fading out.
    private static func renderThaw(rng: inout NoiseGenerator) -> [Float] {
        let duration = 1.0
        let count = Int(duration * sampleRate)
        var samples = [Double](repeating: 0, count: count)
        let noise = Self.lowpassedNoise(count: count, cutoff: 5200, rng: &rng)
        // Crackle: 14 ticks, denser at the start, each a few ms of filtered noise.
        for k in 0..<14 {
            let start = 0.3 * pow(Double(k) / 14, 1.4) + rng.unit() * 0.02
            let length = 0.004 + rng.unit() * 0.006
            let amp = (0.5 + rng.unit() * 0.5) * (1 - Double(k) / 20)
            let first = Int(start * sampleRate)
            for j in 0..<Int(length * sampleRate) where first + j < count {
                let local = Double(j) / sampleRate
                samples[first + j] += noise[first + j] * amp * exp(-local / (length / 3))
            }
        }
        // Drips: soft "plink" glides (water drops) after the crack.
        for (k, f) in [1250.0, 980.0, 1120.0].enumerated() {
            let start = 0.36 + Double(k) * 0.17
            let first = Int(start * sampleRate)
            var phase = 0.0
            for j in 0..<Int(0.16 * sampleRate) where first + j < count {
                let local = Double(j) / sampleRate
                phase += 2 * .pi * f * (1 - 0.35 * min(1, local / 0.05)) / sampleRate
                samples[first + j] += 0.55 * sin(phase) * min(1, local / 0.003) * exp(-local * 28) * (1 - Double(k) * 0.2)
            }
        }
        for k in 0..<Int(0.02 * sampleRate) { samples[count - 1 - k] *= Double(k) / (0.02 * sampleRate) }
        return normalized(samples, peak: 0.12)
    }

    /// Bubbling up (D2), timed on `RisePose`: seven small bubbles, closer together and higher as
    /// the big one climbs (each a short sine gliding up, like the pour's gurgle), over a soft low
    /// simmer; then a round, deeper "bloop" (a sine gliding up, slower decay) when it arrives on top.
    private static func renderBubbleUp(rng: inout NoiseGenerator) -> [Float] {
        let duration = 1.05
        let count = Int(duration * sampleRate)
        var samples = Self.lowpassedNoise(count: count, cutoff: 220, rng: &rng).enumerated().map { i, v in
            let t = Double(i) / sampleRate
            return v * 0.12 * min(1, t / 0.08) * max(0, 1 - t / 0.85)
        }
        let blip = { (start: Double, f0: Double, tau: Double, rise: Double, amp: Double, samples: inout [Double]) in
            let first = Int(start * sampleRate)
            var phase = 0.0
            for j in 0..<Int(tau * 6 * sampleRate) where first + j < count {
                let local = Double(j) / sampleRate
                phase += 2 * .pi * f0 * (1 + rise * local) / sampleRate
                samples[first + j] += amp * sin(phase) * exp(-local / tau) * min(1, local / 0.002)
            }
        }
        var time = 0.04
        for k in 0..<7 {
            let f0 = 420 + Double(k) * 70 + rng.unit() * 90
            blip(time, f0, 0.022 + rng.unit() * 0.012, 5 + rng.unit() * 3, 0.45 + 0.05 * Double(k), &samples)
            time += 0.12 - Double(k) * 0.011
        }
        blip(RisePose.arrival - 0.04, 210, 0.07, 3.2, 1.0, &samples)
        blip(RisePose.arrival + 0.06, 520, 0.03, 6, 0.4, &samples)
        for k in 0..<Int(0.02 * sampleRate) { samples[count - 1 - k] *= Double(k) / (0.02 * sampleRate) }
        return normalized(samples, peak: 0.16)
    }

    /// Twin chain (F1): six small metal links knocking together, quick and uneven, each a short
    /// high inharmonic ping with a tick of noise, softening as the chain settles.
    private static func renderChainRattle(rng: inout NoiseGenerator) -> [Float] {
        let duration = 0.45
        let count = Int(duration * sampleRate)
        var samples = [Double](repeating: 0, count: count)
        var time = 0.005
        for k in 0..<6 {
            let f0 = 2900 + rng.unit() * 1300
            let amp = 1.0 - Double(k) * 0.13
            let first = Int(time * sampleRate)
            for j in 0..<Int(0.12 * sampleRate) where first + j < count {
                let t = Double(j) / sampleRate
                let ping = sin(2 * .pi * f0 * t) + 0.55 * sin(2 * .pi * f0 * 1.47 * t) * exp(-t * 30)
                    + 0.3 * sin(2 * .pi * f0 * 2.09 * t) * exp(-t * 45)
                let tick = t < 0.002 ? (rng.unit() * 2 - 1) * 0.8 : 0
                samples[first + j] += amp * (ping * exp(-t * 38) + tick)
            }
            time += 0.035 + rng.unit() * 0.03
        }
        for k in 0..<Int(0.02 * sampleRate) { samples[count - 1 - k] *= Double(k) / (0.02 * sampleRate) }
        return normalized(samples, peak: 0.11)
    }

    /// Pressure pipe (F2), timed on the push: a low thump (a sine dropping from 95 to 55 Hz,
    /// fast decay) with a short pneumatic hiss (noise, quick fade) as the flask's bottom gives
    /// way, a soft rush of liquid in a tube (low-passed noise swelling and fading) and three
    /// hollow glugs (low sines gliding up) as the layers run through and rise into the far flask.
    private static func renderPipePush(rng: inout NoiseGenerator) -> [Float] {
        let duration = 0.62
        let count = Int(duration * sampleRate)
        var samples = Self.lowpassedNoise(count: count, cutoff: 380, rng: &rng).enumerated().map { i, v in
            let t = Double(i) / sampleRate
            return v * 0.3 * sin(.pi * min(1, t / duration))
        }
        var thump = 0.0
        for j in 0..<Int(0.16 * sampleRate) {
            let t = Double(j) / sampleRate
            thump += 2 * .pi * (55 + 40 * exp(-t * 30)) / sampleRate
            let hiss = (rng.unit() * 2 - 1) * 0.25 * exp(-t * 28)
            samples[j] += (1.1 * sin(thump) * exp(-t * 22) + hiss) * min(1, t / 0.003)
        }
        for (k, start) in [0.1, 0.25, 0.4].enumerated() {
            let f0 = 170 + Double(k) * 45 + rng.unit() * 20
            let first = Int(start * sampleRate)
            var phase = 0.0
            for j in 0..<Int(0.2 * sampleRate) where first + j < count {
                let t = Double(j) / sampleRate
                phase += 2 * .pi * f0 * (1 + 2.2 * t) / sampleRate
                let tone = sin(phase) + 0.35 * sin(2 * phase) * exp(-t * 25)
                samples[first + j] += (0.9 - 0.15 * Double(k)) * tone * exp(-t * 16) * min(1, t / 0.004)
            }
        }
        for k in 0..<Int(0.02 * sampleRate) { samples[count - 1 - k] *= Double(k) / (0.02 * sampleRate) }
        return normalized(samples, peak: 0.15)
    }

    /// Brewing (E1), timed on `MixPose`: a low stirring swish (low-passed noise swelling and
    /// ebbing three times a second, like a ladle going round), small bubbles blipping up through
    /// it, and at the bloom a soft three-note sparkle (a rising major triad an octave up, slow
    /// decay) as the new potion appears.
    private static func renderBrew(rng: inout NoiseGenerator) -> [Float] {
        let duration = 1.4
        let count = Int(duration * sampleRate)
        let noise = Self.lowpassedNoise(count: count, cutoff: 380, rng: &rng)
        var samples = noise.enumerated().map { i, v -> Double in
            let t = Double(i) / sampleRate
            let swell = min(1, t / 0.1) * max(0, 1 - t / 1.0)
            let stir = 0.55 + 0.45 * sin(2 * .pi * 3 * t - .pi / 2)
            return v * 0.3 * swell * stir
        }
        let blip = { (start: Double, f0: Double, tau: Double, amp: Double, samples: inout [Double]) in
            let first = Int(start * sampleRate)
            var phase = 0.0
            for j in 0..<Int(tau * 6 * sampleRate) where first + j < count {
                let local = Double(j) / sampleRate
                phase += 2 * .pi * f0 * (1 + 6 * local) / sampleRate
                samples[first + j] += amp * sin(phase) * exp(-local / tau) * min(1, local / 0.002)
            }
        }
        var time = 0.08
        for k in 0..<9 {
            blip(time, 360 + rng.unit() * 380, 0.018 + rng.unit() * 0.012, 0.35 + 0.04 * Double(k), &samples)
            time += 0.07 + rng.unit() * 0.05
        }
        for (k, f) in [1046.50, 1318.51, 1567.98].enumerated() {
            let start = MixPose.bloom - 0.05 + Double(k) * 0.07
            let first = Int(start * sampleRate)
            for j in 0..<(count - first) {
                let local = Double(j) / sampleRate
                let shimmer = 1 + 0.15 * sin(2 * .pi * 9 * local)
                samples[first + j] += 0.32 * Self.softNote(t: local, f: f) * exp(-local * 4.5) * shimmer
            }
        }
        for k in 0..<Int(0.03 * sampleRate) { samples[count - 1 - k] *= Double(k) / (0.03 * sampleRate) }
        return normalized(samples, peak: 0.15)
    }

    /// Bubbles: short decaying sines with a rising pitch (like air entering a bottle), at random
    /// times, over a bed of low rumbling noise. Fades in fast and out over the last third.
    private static func renderGurgle(duration: Double, bubblesPerSecond: Double, seed: UInt64) -> [Float] {
        var rng = NoiseGenerator(seed: seed)
        let count = Int(duration * sampleRate)
        var samples = Self.lowpassedNoise(count: count, cutoff: 260, rng: &rng).map { $0 * 0.35 }
        var time = 0.01
        while time < duration - 0.05 {
            let f0 = 260 + rng.unit() * 520
            let tau = 0.018 + rng.unit() * 0.03
            let rise = 4 + rng.unit() * 5
            let amp = 0.45 + rng.unit() * 0.55
            let start = Int(time * sampleRate)
            let length = Int(tau * 5 * sampleRate)
            var phase = 0.0
            for j in 0..<length where start + j < count {
                let local = Double(j) / sampleRate
                phase += 2 * .pi * f0 * (1 + rise * local) / sampleRate
                samples[start + j] += amp * sin(phase) * exp(-local / tau) * min(1, local / 0.002)
            }
            time += (0.5 + rng.unit()) / bubblesPerSecond
        }
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let fadeIn = min(1, t / 0.03)
            let fadeOut = min(1, (duration - t) / (duration / 3))
            samples[i] *= fadeIn * fadeOut
        }
        return normalized(samples, peak: 0.24)
    }

    private static func lowpassedNoise(count: Int, cutoff: Double, rng: inout NoiseGenerator) -> [Double] {
        let a = exp(-2 * .pi * cutoff / sampleRate)
        var y = 0.0
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            y = (1 - a) * (rng.unit() * 2 - 1) + a * y
            out[i] = y
        }
        let peak = out.map(abs).max() ?? 1
        return peak > 0 ? out.map { $0 / peak } : out
    }

    private static func render(_ duration: Double, peak: Double, _ sample: (Double) -> Double) -> [Float] {
        let count = Int(duration * sampleRate)
        var samples = [Double](repeating: 0, count: count)
        for i in 0..<count { samples[i] = sample(Double(i) / sampleRate) }
        // Short fades so no buffer starts or ends on a click.
        let fadeIn = min(count, Int(0.001 * sampleRate))
        for k in 0..<fadeIn { samples[k] *= Double(k) / Double(fadeIn) }
        let fadeOut = min(count, Int(0.02 * sampleRate))
        for k in 0..<fadeOut { samples[count - 1 - k] *= Double(k) / Double(fadeOut) }
        return normalized(samples, peak: peak)
    }

    /// Scales `samples` so the loudest one is `peak`.
    private static func normalized(_ samples: [Double], peak: Double) -> [Float] {
        let maxValue = samples.map(abs).max() ?? 0
        let gain = maxValue > 0 ? peak / maxValue : 0
        return samples.map { Float($0 * gain) }
    }
}

/// Small deterministic RNG (SplitMix64) so every launch synthesizes the same sounds.
nonisolated private struct NoiseGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
