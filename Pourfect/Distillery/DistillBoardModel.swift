import BottleSortCore
import DistilleryCore
import Foundation
import Observation
import SwiftUI

/// The distillery board on screen (R10): the game (`DistillGame`, the only truth) and the timing of
/// what the board shows: pieces turning, liquid running along newly connected pipes in the core's
/// `tick` order, flasks filling, and the win.
///
/// A tap is played on the game at once; the board then animates towards it. The turned piece spins
/// for `turnDuration` and its liquid is hidden meanwhile; channels that became wet fill one `step`
/// per tick after that; channels that ran dry drain at once. Input is never locked: a second tap
/// during an animation simply starts from where the board is.
@Observable
final class DistillBoardModel {
    /// A piece's quarter-turn in progress (displayed angle in quarter turns, not wrapped).
    struct Turn: Equatable {
        var from: Double
        var to: Double
        var start: Date
    }

    enum Outcome: Equatable {
        case won(stars: Int, taps: Int, newBest: Bool)
    }

    /// Seconds a quarter turn takes on screen.
    static let turnDuration: TimeInterval = 0.16
    /// Seconds liquid takes per channel (one core tick).
    static let step: TimeInterval = 0.07

    private(set) var game: DistillGame
    var level: DistillLevel { game.level }
    var board: DistillBoard { game.board }
    var flow: DistillFlow { game.flow }

    /// Displayed quarter turns per cell index (cumulative, so a turn always spins the way it was tapped).
    private(set) var angles: [Int: Double] = [:]
    private(set) var turns: [Int: Turn] = [:]
    /// When each wet channel started filling (it is full `step` later).
    private(set) var fillStart: [DistillNodeRef: Date] = [:]
    /// Until when the board needs frames (fills and turns; leaks and murk animate on their own).
    private(set) var busyUntil = Date.distantPast
    /// Bumped when `busyUntil` passes, so the board pauses its timeline.
    private(set) var idleTick = 0

    /// A hint was used: the third star is gone for this attempt (restart gives it back).
    private(set) var usedHint = false
    /// The piece the last hint turned (glows for a moment).
    private(set) var hintCell: DistillPos?
    private(set) var hintBusy = false
    /// Goes up at the win's celebration: every flask fills to the brim and is corked.
    private(set) var celebrations = 0
    private(set) var outcome: Outcome?
    /// Bumped on each tap that did nothing (riveted piece, cross, empty cell): the cell shakes.
    private(set) var refusedCell: DistillPos?
    private(set) var refusedAt = Date.distantPast

    var settings = GameSettings()
    var reduceMotion = false {
        didSet {
            // Turned on (also right after init, which laid out a running fill): every fill lands now.
            guard reduceMotion, !oldValue else { return }
            let now = Date()
            for (ref, start) in fillStart where start > now { fillStart[ref] = now }
        }
    }
    /// Saves a win; returns true when its tap count is a new best. Not called for a demo.
    var onWin: ((_ stars: Int, _ taps: Int, _ usedHint: Bool) -> Bool)?
    let isDemo: Bool

    @ObservationIgnored private var timers: [Task<Void, Never>] = []
    /// Said before the next tap's VoiceOver summary (the hint names the piece it turned).
    @ObservationIgnored private var announcePrefix: String?

    /// Seconds per channel on screen: none under Reduce Motion, where fills are instant (DECISIONS 280).
    private var fillStep: TimeInterval { reduceMotion ? 0 : Self.step }

    init(level: DistillLevel, isDemo: Bool = false) {
        game = DistillGame(level: level)
        self.isDemo = isDemo
        resetDisplay(animateFlow: true)
    }

    var taps: Int { game.taps }
    var isWon: Bool { game.isWon }
    var canUndo: Bool { game.canUndo }
    /// Stars of the current tap count; a hint caps them at two.
    var stars: Int { usedHint ? min(2, game.stars) : game.stars }

    // MARK: Display state

    /// Displayed quarter turns of a cell at `now` (eased while turning).
    func angle(_ cell: Int, at now: Date) -> Double {
        let rest = angles[cell] ?? Double(board.pieces[cell].rotation)
        guard let turn = turns[cell] else { return rest }
        let t = min(1, max(0, now.timeIntervalSince(turn.start) / Self.turnDuration))
        guard t < 1, !reduceMotion else { return turn.to }
        let eased = 1 - pow(1 - t, 3) * (1 - 0.9 * t)   // snappy, a hair of overshoot-free settle
        return turn.from + (turn.to - turn.from) * min(1, eased)
    }

    func isTurning(_ cell: Int, at now: Date) -> Bool {
        guard let turn = turns[cell], !reduceMotion else { return false }
        return now.timeIntervalSince(turn.start) < Self.turnDuration
    }

    /// 0…1: how full a wet channel is drawn at `now` (0 for dry ones).
    func fill(_ ref: DistillNodeRef, at now: Date) -> Double {
        guard let start = fillStart[ref] else { return 0 }
        if reduceMotion { return now >= start ? 1 : 0 }
        return min(1, max(0, now.timeIntervalSince(start) / Self.step))
    }

    /// Whether the liquid has reached a flask on screen.
    func flaskFilled(_ target: Int, at now: Date) -> Bool {
        let t = board.targets[target]
        guard let start = fillStart[DistillNodeRef(pos: t.pos, channel: 0)] else { return false }
        return now >= start.addingTimeInterval(reduceMotion ? 0 : Self.step)
    }

    func isBusy(at now: Date) -> Bool { now < busyUntil }

    // MARK: Input

    /// Turns the piece at `pos` (clockwise for a tap or click, counter-clockwise for a long-press or right-click).
    func tap(_ pos: DistillPos, clockwise: Bool = true) {
        guard outcome == nil, !isWon else { return }
        let valves = flow.valveOpenedAt.count
        guard let result = game.tap(pos, clockwise: clockwise) else {
            refusedCell = pos
            refusedAt = Date()
            markBusy(until: refusedAt.addingTimeInterval(0.3))
            DistillFeedback.play(.refused, settings: settings)
            return
        }
        hintCell = nil
        apply(result, clockwise: clockwise, valvesBefore: valves)
    }

    func undo() {
        let valves = flow.valveOpenedAt.count
        guard let result = game.undo() else { return }
        hintCell = nil
        apply(result, clockwise: result.tap.clockwise, valvesBefore: valves)
    }

    func restart() {
        cancelTimers()
        game.restart()
        usedHint = false
        hintCell = nil
        outcome = nil
        resetDisplay(animateFlow: true)
        DistillFeedback.play(.restart, settings: settings)
    }

    /// Turns one piece towards the cheapest solution from here. Costs the third star.
    func hint() {
        guard outcome == nil, !isWon, !hintBusy else { return }
        hintBusy = true
        let snapshot = game
        Task {
            let tap = await Task.detached(priority: .userInitiated) { snapshot.hint() }.value
            hintBusy = false
            guard let tap, game.board == snapshot.board else { return }
            usedHint = true
            announcePrefix = String(localized: "Hint turned the piece in row \(tap.pos.r + 1), column \(tap.pos.c + 1).",
                                    comment: "VoiceOver: a distillery hint turned a piece; arguments are its row and column")
            self.tap(tap.pos, clockwise: tap.clockwise)
            hintCell = tap.pos
        }
    }

    func stop() {
        cancelTimers()
        FeedbackPlayer.cancelPending()
    }

    #if DEBUG
    /// `-LPDistillDemo K`: plays K solver taps (fewest-taps path), one every 0.45 s; nothing is saved.
    func debugAutoplay(taps: Int) async {
        try? await Task.sleep(for: .seconds(1.2))
        for _ in 0..<taps {
            guard !isWon, let tap = game.hint() else { return }
            self.tap(tap.pos, clockwise: tap.clockwise)
            try? await Task.sleep(for: .seconds(0.45))
        }
    }
    #endif

    // MARK: Animation bookkeeping

    private func resetDisplay(animateFlow: Bool) {
        angles = [:]
        turns = [:]
        for i in 0..<board.cellCount where board.pieces[i].isRotatable { angles[i] = Double(board.pieces[i].rotation) }
        fillStart = [:]
        let now = Date()
        let base = animateFlow && !reduceMotion ? now.addingTimeInterval(0.35) : now
        var last = now
        for node in flow.nodes where node.liquid.isWet {
            let start = base.addingTimeInterval(Double(node.tick) * fillStep)
            fillStart[DistillNodeRef(pos: node.pos, channel: node.channel)] = start
            last = max(last, start)
        }
        markBusy(until: last.addingTimeInterval(Self.step))
    }

    private func apply(_ result: DistillTapResult, clockwise: Bool, valvesBefore: Int) {
        let cell = board.index(result.tap.pos)
        let now = Date()
        let from = angle(cell, at: now)
        let rest = angles[cell] ?? Double(result.oldRotation)
        let to = (turns[cell]?.to ?? rest) + (clockwise ? 1 : -1)
        angles[cell] = to
        turns[cell] = Turn(from: from, to: to, start: now)
        let landed = now.addingTimeInterval(reduceMotion ? 0 : Self.turnDuration)

        // Dry channels drain at once; the turned piece's channels refill once it lands.
        for ref in result.newlyDry { fillStart[ref] = nil }
        for node in result.flow.nodes where node.pos == result.tap.pos && node.liquid.isWet {
            let ref = DistillNodeRef(pos: node.pos, channel: node.channel)
            if !result.newlyWet.contains(ref) { fillStart[ref] = landed }
        }
        let wet = result.flow.nodes.filter { $0.liquid.isWet }
        let fresh = Set(result.newlyWet)
        let firstTick = wet.filter { fresh.contains(DistillNodeRef(pos: $0.pos, channel: $0.channel)) }.map(\.tick).min() ?? 0
        var lastFill = landed
        for node in wet {
            let ref = DistillNodeRef(pos: node.pos, channel: node.channel)
            guard fresh.contains(ref) else { continue }
            let start = landed.addingTimeInterval(Double(node.tick - firstTick) * fillStep)
            fillStart[ref] = start
            lastFill = max(lastFill, start)
        }
        let done = max(landed, lastFill.addingTimeInterval(fillStep))
        markBusy(until: done)

        // Sound and touch, timed with the board.
        DistillFeedback.play(.turn, settings: settings)
        if !fresh.isEmpty {
            DistillFeedback.play(.flow(count: fresh.count), settings: settings,
                                 after: landed.timeIntervalSince(now))
        }
        for target in result.newlySatisfied {
            let ref = DistillNodeRef(pos: board.targets[target].pos, channel: 0)
            let at = (fillStart[ref] ?? landed).addingTimeInterval(fillStep).timeIntervalSince(now)
            DistillFeedback.play(.flaskFilled, settings: settings, after: at)
        }
        if result.flow.valveOpenedAt.count > valvesBefore {
            DistillFeedback.play(.valveOpened, settings: settings, after: landed.timeIntervalSince(now))
        }
        if result.flow.murkyCount > 0, !fresh.isEmpty {
            DistillFeedback.play(.murky, settings: settings, after: done.timeIntervalSince(now))
        }
        if result.didWin {
            announcePrefix = nil
            scheduleWin(after: done.timeIntervalSince(now))
        } else {
            announceTurn(result)
        }
    }

    /// VoiceOver: the turned piece's new openings and the board's state (flasks filled, drips, murk).
    private func announceTurn(_ result: DistillTapResult) {
        var parts: [String] = []
        if let prefix = announcePrefix { parts.append(prefix) }
        announcePrefix = nil
        if !result.newlySatisfied.isEmpty {
            parts.append(String(localized: "Flask \(result.newlySatisfied.map { String($0 + 1) }.formatted(.list(type: .and))) filled.",
                                comment: "VoiceOver: distillery flasks just received their potion; the argument lists their numbers"))
        }
        parts.append(DistillSpeech.status(result.flow, targets: board.targets.count))
        announce(parts.joined(separator: " "))
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    private func scheduleWin(after delay: TimeInterval) {
        let stars = stars, taps = taps, hinted = usedHint
        let newBest = isDemo ? false : (onWin?(stars, taps, hinted) ?? false)
        later(delay + 0.1) { [weak self] in
            guard let self else { return }
            celebrations += 1
            DistillFeedback.play(.won, settings: settings)
            markBusy(until: Date().addingTimeInterval(1.2))
        }
        later(delay + (reduceMotion ? 0.5 : 1.3)) { [weak self] in
            self?.outcome = .won(stars: stars, taps: taps, newBest: newBest)
            self?.announce(String(localized: "Distilled! Every flask is filled. \(stars) stars, \(taps) taps.",
                                  comment: "VoiceOver: a distillery level is won; arguments are stars and taps"))
        }
    }

    private func markBusy(until date: Date) {
        busyUntil = max(date, Date() < busyUntil ? busyUntil : date)
        let wait = busyUntil.timeIntervalSinceNow
        later(max(0, wait) + 0.02) { [weak self] in
            guard let self, Date() >= busyUntil else { return }
            idleTick += 1
        }
    }

    private func later(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        timers.removeAll { $0.isCancelled }
        timers.append(Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        })
    }

    private func cancelTimers() {
        for timer in timers { timer.cancel() }
        timers.removeAll()
    }
}
