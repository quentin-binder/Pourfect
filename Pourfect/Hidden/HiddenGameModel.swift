import BottleSortCore
import CoreGraphics
import Foundation
import HiddenCore
import Observation
import SwiftUI

/// A short effect drawn over the scene at a background point: the sparkle of a find or the puff of a wrong tap.
struct HiddenEffect: Identifiable, Equatable {
    enum Kind: Equatable { case sparkle, puff }
    let id = UUID()
    let kind: Kind
    /// Background pixels.
    let point: CGPoint
    /// Radius of the sparkle in background pixels (the found object's size).
    let size: CGFloat
    let start: Date

    static let duration: TimeInterval = 0.9
}

/// One round of a hidden-object room in play (R11): generates and renders the layout off the main actor, turns taps
/// into finds and wrong taps through the core's hit tester and round state, runs the lantern hint and reports the
/// finished round.
@Observable
final class HiddenGameModel {
    enum Phase: Equatable {
        case loading
        case playing
        /// Stars, and whether they are a new best for the round.
        case complete(stars: Int, newBest: Bool)
        case failed(String)
    }

    let room: HiddenSceneID
    private(set) var round: Int
    private(set) var phase: Phase = .loading
    private(set) var assets: HiddenRoomAssets?
    private(set) var layout: HiddenRoundLayout?
    /// Drawn back to front.
    private(set) var layers: [HiddenLayerSet] = []
    private(set) var state: HiddenRoundState?
    private(set) var effects: [HiddenEffect] = []
    /// The lit lantern and when it was lit.
    private(set) var hint: (glow: HiddenHintGlow, lit: Date)?
    /// The object just found (the find list's flourish).
    private(set) var lastFound: String?
    /// Bumped on each wrong tap (the count's little shake).
    private(set) var wrongPulse = 0
    /// Asks the viewer to bring a background point into view (hint, reveal).
    private(set) var focusRequest: (point: CGPoint, id: Int)?

    @ObservationIgnored var settings = GameSettings()
    @ObservationIgnored var reduceMotion = false
    /// Saves a finished round; returns true for a new best.
    @ObservationIgnored var onComplete: ((_ round: Int, _ stars: Int) -> Bool)?
    @ObservationIgnored private var hitTester: HiddenHitTester?
    @ObservationIgnored private var loadID = 0
    @ObservationIgnored private var focusCounter = 0
    /// The state before the last wrong tap, for a double tap / double click that was meant as a zoom.
    @ObservationIgnored private var beforeWrong: (state: HiddenRoundState, at: Date, point: CGPoint, effect: UUID)?
    @ObservationIgnored private var lastTap: (at: Date, point: CGPoint)?

    init(room: HiddenSceneID, round: Int) {
        self.room = room
        self.round = round
    }

    var scene: HiddenScene? { assets?.scene }
    var sceneSize: CGSize { CGSize(width: scene?.width ?? 2752, height: scene?.height ?? 1536) }
    var found: Set<String> { state?.foundSet ?? [] }
    var isComplete: Bool { state?.isComplete ?? false }

    /// The find list: object ids in list order.
    var targets: [String] { state?.targets ?? [] }

    func name(_ id: String) -> String {
        HiddenNames.object(id, in: room, fallback: scene?.object(id)?.name ?? id)
    }

    // MARK: Loading

    /// Builds round `round` (its fixed layout, or the generator's for a DEBUG seed) and renders its layers.
    func load(round: Int, seed: UInt64? = nil) async {
        loadID += 1
        let ticket = loadID
        self.round = round
        phase = .loading
        effects = []
        hint = nil
        lastFound = nil
        beforeWrong = nil
        let room = room
        do {
            let result = try await Task.detached(priority: .userInitiated) { () throws -> (HiddenRoomAssets, HiddenRoundLayout, [HiddenLayerSet]) in
                let assets = try HiddenRoomAssets.load(room)
                // Every player gets the room's fixed rounds; a seed (DEBUG) asks the generator instead.
                let layout: HiddenRoundLayout
                if let seed {
                    layout = HiddenGenerator.layout(assets.scene, spec: HiddenCurve.spec(room, round: round), seed: seed)
                } else {
                    layout = assets.rounds[min(max(round, 1), assets.rounds.count) - 1]
                }
                return (assets, layout, HiddenRenderer.layers(layout, assets: assets))
            }.value
            guard ticket == loadID else { return }
            assets = result.0
            layout = result.1
            layers = result.2
            state = HiddenRoundState(layout: result.1)
            hitTester = HiddenHitTester(layout: result.1, masks: result.0.masks(for: result.1))
            phase = .playing
        } catch {
            guard ticket == loadID else { return }
            phase = .failed(String(describing: error))
        }
    }

    // MARK: Play

    /// A tap at a background point; `pointsPerPixel` is the current zoom (screen points per background pixel).
    func tap(at p: CGPoint, pointsPerPixel: CGFloat) {
        guard phase == .playing, var s = state, let hitTester else { return }
        let now = Date()
        // The second tap of a double tap (a zoom) is not a tap.
        if let last = lastTap, now.timeIntervalSince(last.at) < 0.35,
           hypot(last.point.x - p.x, last.point.y - p.y) * pointsPerPixel < 30 {
            return
        }
        lastTap = (now, p)
        let slop = HiddenTouch.slop(pointsPerBackgroundPixel: Double(pointsPerPixel))
        let hit = hitTester.hit(at: HiddenPoint(x: Double(p.x), y: Double(p.y)), slop: slop, found: s.foundSet)
        let before = s
        switch s.tap(hit) {
        case .found(let id, _):
            state = s
            found(id)
        case .wrong:
            state = s
            let effect = HiddenEffect(kind: .puff, point: p, size: 24 / max(pointsPerPixel, 0.05), start: now)
            effects.append(effect)
            beforeWrong = (before, now, p, effect.id)
            wrongPulse += 1
            HiddenFeedback.play(.wrong, settings: settings)
            prune()
        }
    }

    /// A double tap / double click zooms; a wrong tap it began with is taken back.
    func doubleTapped(at p: CGPoint, pointsPerPixel: CGFloat) {
        guard let b = beforeWrong, Date().timeIntervalSince(b.at) < 0.6,
              hypot(b.point.x - p.x, b.point.y - p.y) * pointsPerPixel < 30 else { return }
        state = b.state
        effects.removeAll { $0.id == b.effect }
        beforeWrong = nil
    }

    private func found(_ id: String) {
        beforeWrong = nil
        lastFound = id
        if hint?.glow.objectID == id { hint = nil }
        if let p = layout?.placement(id) {
            effects.append(HiddenEffect(kind: .sparkle, point: CGPoint(x: p.center.x, y: p.center.y),
                                        size: CGFloat(max(p.width, p.height)), start: Date()))
        }
        prune()
        if state?.isComplete == true {
            finish()
        } else {
            HiddenFeedback.play(.found, settings: settings)
        }
    }

    private func finish() {
        guard let s = state else { return }
        hint = nil
        let newBest = onComplete?(s.round, s.stars) ?? false
        HiddenFeedback.play(.complete, settings: settings)
        let stars = s.stars
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 1100))
            if self.state == s { withAnimation(self.reduceMotion ? nil : .spring(duration: 0.45)) {
                self.phase = .complete(stars: stars, newBest: newBest)
            } }
        }
    }

    /// Seconds until the lantern is ready again.
    func hintCooldown(now: Date) -> Double {
        state?.hintCooldownRemaining(now: now.timeIntervalSinceReferenceDate) ?? 0
    }

    /// Lights the lantern over a remaining object (counts as a hint).
    func useHint() {
        guard phase == .playing, var s = state, let layout else { return }
        let now = Date()
        guard let glow = s.useHint(now: now.timeIntervalSinceReferenceDate, layout: layout) else { return }
        state = s
        hint = (glow, now)
        prune()
        focus(CGPoint(x: glow.center.x, y: glow.center.y))
        HiddenFeedback.play(.hint, settings: settings)
    }

    /// The lantern stays lit this long (or until its object is found).
    static let hintDuration: TimeInterval = 9

    /// Accessibility "reveal next": finds the next object on the list at once (counts as a hint). Returns its name.
    @discardableResult
    func revealNext() -> String? {
        guard phase == .playing, var s = state, let id = s.revealNext() else { return nil }
        state = s
        if let p = layout?.placement(id) { focus(CGPoint(x: p.center.x, y: p.center.y)) }
        found(id)
        return name(id)
    }

    private func focus(_ p: CGPoint) {
        focusCounter += 1
        focusRequest = (p, focusCounter)
    }

    /// Drops finished effects and an expired lantern now, and again once the newest ones are over.
    func prune(now: Date = Date()) {
        effects.removeAll { now.timeIntervalSince($0.start) > HiddenEffect.duration }
        if let h = hint, now.timeIntervalSince(h.lit) > Self.hintDuration { hint = nil }
        let wait = max(effects.isEmpty ? 0 : HiddenEffect.duration + 0.05,
                       hint.map { Self.hintDuration + 0.05 - now.timeIntervalSince($0.lit) } ?? 0)
        guard wait > 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(wait))
            self.prune()
        }
    }

    #if DEBUG
    /// Dev aid for screenshots: finds `count` objects (as if tapped), then optionally makes a wrong tap / lights
    /// the lantern.
    func debugDemo(finds count: Int, wrong: Bool, hint lantern: Bool) {
        guard phase == .playing, let layout else { return }
        for p in layout.targets.prefix(count) where state?.isComplete == false {
            var s = state!
            _ = s.tap(.target(p.objectID))
            state = s
            found(p.objectID)
        }
        let middle = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        if wrong, let d = layout.decoys.min(by: { hypot($0.center.x - middle.x, $0.center.y - middle.y)
                                                    < hypot($1.center.x - middle.x, $1.center.y - middle.y) }) {
            lastTap = nil
            tap(at: CGPoint(x: d.center.x, y: d.center.y), pointsPerPixel: 1)
        }
        if lantern { useHint() }
    }
    #endif
}

/// Sound and haptics of the hidden-object rooms, honoring the player's settings.
enum HiddenFeedback {
    enum Event { case found, wrong, hint, complete }

    static func play(_ event: Event, settings: GameSettings) {
        let engine = SoundEngine.shared
        switch event {
        case .found:
            if settings.soundEnabled { engine.play(.hiddenFind) }
            if settings.hapticsEnabled { Haptics.select() }
        case .wrong:
            if settings.soundEnabled { engine.play(.hiddenPuff) }
            if settings.hapticsEnabled { Haptics.illegal() }
        case .hint:
            if settings.soundEnabled { engine.play(.hiddenShimmer) }
            if settings.hapticsEnabled { Haptics.pour() }
        case .complete:
            if settings.soundEnabled {
                engine.play(.hiddenFind)
                engine.play(.success, after: 0.35)
            }
            if settings.hapticsEnabled { Haptics.levelWon() }
        }
    }
}
