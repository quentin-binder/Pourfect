import BottleSortCore
import Match3Core
import Observation
import SwiftUI

/// The ingredient-gathering board on screen (R9): the game (`M3Game`, the only truth) and what the
/// board shows while a swap's result plays out.
///
/// A swap is played on the game at once; its `M3StepResult` is then animated phase by phase, in
/// the core's order (swap → waves, settles and flask collections through every cascade →
/// reshuffle). Pieces are tokens with stable ids that move between cells, so SwiftUI animates
/// them. Input is locked while anything animates, and when a step has played out the tokens are
/// checked against the game's board (and rebuilt from it if they ever differ), so the screen can
/// never drift from the state.
@Observable
final class MatchBoardModel {
    /// One piece or flask on screen.
    struct Token: Identifiable, Equatable {
        let id: Int
        var item: M3Item
        var pos: M3Pos
        /// Offset from `pos` in cells (a new piece starts above the board; a nudge, a collected flask).
        var dx: Double = 0
        var dy: Double = 0
        var scale: Double = 1
        /// 0…1: matched, squashed before it pops.
        var squash: Double = 0
        /// 0…1: a new or changed special glows.
        var glow: Double = 0
        var spin: Double = 0
        var opacity: Double = 1
    }

    /// The counters the HUD shows; they follow the animation and match the game when it ends.
    struct HUD: Equatable {
        var moves: Int
        var score: Int
        var collected: [Int]
        var flasks: Int
        var frostCleared: Int
        var crateHits: Int
    }

    enum Outcome: Equatable {
        /// `movesLeft`: moves left at the win, before the finale turned them into specials.
        case won(stars: Int, score: Int, newBest: Bool, movesLeft: Int)
        case lost
    }

    enum Banner: Equatable {
        case finale
        case shuffle
        case cascade(Int)
    }

    let level: M3Level
    /// A demo (`-LPM3Demo`) saves nothing.
    let isDemo: Bool
    private(set) var game: M3Game
    private(set) var tokens: [Token] = []
    /// Hits left per cell (row-major), as shown.
    private(set) var crates: [Int]
    private(set) var hud: HUD
    private(set) var effects: [BoardFX] = []
    private(set) var selected: M3Pos?
    private(set) var hint: M3Swap?
    /// True while a step, the intro or the finale animates: input is ignored.
    private(set) var busy = false
    private(set) var banner: Banner?
    private(set) var outcome: Outcome?
    /// Changes on every interaction and at the end of every step: restarts the idle-hint timer.
    private(set) var idleTick = 0

    /// Set by the view from the environment.
    var reduceMotion = false
    /// Saves a win (stars, score, moves left at the win); returns true for a new best score.
    /// Not called for demo games.
    @ObservationIgnored var onWin: ((_ stars: Int, _ score: Int, _ movesLeft: Int) -> Bool)?
    var settings = GameSettings()

    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var driver: Task<Void, Never>?
    @ObservationIgnored private var finaleRunning = false

    init?(level: M3Level, isDemo: Bool = false) {
        guard let game = M3Game(level: level) else { return nil }
        self.level = level
        self.isDemo = isDemo
        self.game = game
        self.crates = game.board.cells.map(\.crate)
        self.hud = Self.hud(of: game)
        self.tokens = []
    }

    var width: Int { game.board.width }
    var height: Int { game.board.height }
    var isPlaying: Bool { game.status == .playing && outcome == nil }

    // MARK: Lifecycle

    /// Fills the board with the start pieces dropping in (or fading in with Reduce Motion).
    func start() {
        guard tokens.isEmpty else { return }
        run { [self] in try await intro() }
    }

    /// Starts the level over with the same seed: the same board comes back (free, always).
    func restart() {
        driver?.cancel()
        guard let fresh = M3Game(level: level) else { return }
        game = fresh
        withAnimation(nil) {
            tokens = []
            effects = []
        }
        crates = fresh.board.cells.map(\.crate)
        hud = Self.hud(of: fresh)
        outcome = nil
        banner = nil
        selected = nil
        hint = nil
        busy = false
        finaleRunning = false
        start()
    }

    /// Stops any running animation (the screen went away).
    func stop() {
        driver?.cancel()
        driver = nil
    }

    // MARK: Input

    /// A tap (click) on a cell: selects a piece, or swaps it with the selected neighbour.
    func tap(_ pos: M3Pos) {
        guard !busy, isPlaying else { return }
        bumpIdle()
        if let from = selected {
            if from == pos {
                selected = nil
                return
            }
            if from.isAdjacent(to: pos) {
                requestSwap(M3Swap(from, pos))
                return
            }
        }
        if game.board.isSwappable(pos) {
            selected = pos
            feedback(.select)
        } else {
            selected = nil
            if game.board.contains(pos), game.board[pos].item != nil || game.board[pos].crate > 0 {
                nudge(pos, toward: nil)
                feedback(.refused)
                announce(String(localized: "This one can't be moved", comment: "VoiceOver: a frozen piece, crate or flask was picked"))
            }
        }
    }

    /// A swipe (drag) from one cell towards a neighbour, or a VoiceOver swap action.
    func requestSwap(_ swap: M3Swap) {
        guard !busy, isPlaying else { return }
        bumpIdle()
        selected = nil
        hint = nil
        let board = game.board
        guard board.contains(swap.from), swap.from.isAdjacent(to: swap.to) else { return }
        guard board.isSwappable(swap.from), board.contains(swap.to), board.isSwappable(swap.to) else {
            // Frost, a crate, a flask, a hole or the edge: the piece leans over and comes back.
            if board[swap.from].item != nil { nudge(swap.from, toward: swap.to) }
            feedback(.refused)
            announce(String(localized: "Can't swap there", comment: "VoiceOver: a match-3 swap with a frozen piece, crate, flask, hole or the edge"))
            return
        }
        guard game.isValidSwap(swap) else {
            run { [self] in try await bounce(swap) }
            return
        }
        run { [self] in
            let result = game.play(swap)
            try await animate(result)
            try await finish()
        }
    }

    /// The idle hint: a gentle glow on one valid swap (free; never affects stars).
    func showHint() {
        guard !busy, isPlaying, hint == nil else { return }
        hint = game.hint()
    }

    private func bumpIdle() {
        idleTick &+= 1
        hint = nil
    }

    // MARK: Driver

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        busy = true
        driver = Task { @MainActor [weak self] in
            do {
                try await body()
            } catch {
                return   // cancelled: `restart()` / `stop()` took over
            }
            guard let self else { return }
            self.busy = false
            self.idleTick &+= 1
        }
    }

    private var pace: Double { DebugTiming.slow * (finaleRunning ? 0.7 : 1) }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds * pace))
        pruneEffects()
    }

    /// One frame, so tokens just inserted at their start are drawn there before they move.
    private func frame() async throws {
        try await Task.sleep(for: .milliseconds(24))
    }

    private func animate(_ animation: Animation, _ changes: () -> Void) {
        withAnimation(animation.speed(1 / pace), changes)
    }

    private func instantly(_ changes: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
    }

    private func feedback(_ event: Match3Feedback.Event) {
        Match3Feedback.play(event, settings: settings)
    }

    // MARK: Tokens

    private func makeToken(_ item: M3Item, at pos: M3Pos) -> Token {
        nextID += 1
        return Token(id: nextID, item: item, pos: pos)
    }

    private func tokenIndex(at pos: M3Pos) -> Int? {
        tokens.firstIndex { $0.pos == pos }
    }

    private func center(_ cells: [M3Pos]) -> CGPoint {
        guard !cells.isEmpty else { return .zero }
        let r = cells.map { Double($0.row) }.reduce(0, +) / Double(cells.count)
        let c = cells.map { Double($0.col) }.reduce(0, +) / Double(cells.count)
        return CGPoint(x: c, y: r)
    }

    /// The top open cell's row of a column, as shown (crates may have broken since).
    private func topOpenRow(_ col: Int) -> Int {
        for r in 0..<height where game.board[r, col].exists && crates[r * width + col] == 0 { return r }
        return 0
    }

    // MARK: Intro, bounce, nudge

    private func intro() async throws {
        let board = game.board
        var fresh: [Token] = []
        for p in board.positions {
            guard let item = board[p].item else { continue }
            var token = makeToken(item, at: p)
            if reduceMotion { token.opacity = 0 } else { token.dy = -Double(height) - 0.5 }
            fresh.append(token)
        }
        instantly { tokens = fresh }
        try await frame()
        if reduceMotion {
            animate(.easeOut(duration: 0.3)) { for i in tokens.indices { tokens[i].opacity = 1 } }
            try await pause(0.3)
            return
        }
        for col in 0..<width {
            animate(.spring(duration: 0.5, bounce: 0.3).delay(Double(col) * 0.035)) {
                for i in tokens.indices where tokens[i].pos.col == col { tokens[i].dy = 0 }
            }
        }
        feedback(.swap)
        try await pause(0.5 + Double(width) * 0.035)
    }

    /// A swap that makes no match: the pieces trade places and slide back.
    private func bounce(_ swap: M3Swap) async throws {
        guard let a = tokenIndex(at: swap.from), let b = tokenIndex(at: swap.to) else { return }
        feedback(.refused)
        announce(String(localized: "No match, the pieces slide back", comment: "VoiceOver: a match-3 swap that makes no line of three"))
        if reduceMotion {
            nudge(swap.from, toward: swap.to)
            try await pause(0.2)
            return
        }
        let dr = Double(swap.to.row - swap.from.row), dc = Double(swap.to.col - swap.from.col)
        animate(.easeInOut(duration: 0.13)) {
            tokens[a].dx = dc * 0.55; tokens[a].dy = dr * 0.55
            tokens[b].dx = -dc * 0.55; tokens[b].dy = -dr * 0.55
        }
        try await pause(0.13)
        animate(.spring(duration: 0.3, bounce: 0.45)) {
            for i in [a, b] { tokens[i].dx = 0; tokens[i].dy = 0 }
        }
        try await pause(0.2)
    }

    /// A piece that can't go leans towards `target` (or wiggles) and comes back.
    private func nudge(_ pos: M3Pos, toward target: M3Pos?) {
        guard let i = tokenIndex(at: pos), !reduceMotion else { return }
        let dr = target.map { Double($0.row - pos.row) } ?? 0, dc = target.map { Double($0.col - pos.col) } ?? 0.4
        withAnimation(.easeOut(duration: 0.08)) { tokens[i].dx = dc * 0.18; tokens[i].dy = dr * 0.18 }
        withAnimation(.spring(duration: 0.3, bounce: 0.6).delay(0.08)) { tokens[i].dx = 0; tokens[i].dy = 0 }
    }

    // MARK: Step animation

    private func animate(_ result: M3StepResult) async throws {
        for phase in result.phases { try await animate(phase) }
    }

    private func animate(_ phase: M3Phase) async throws {
        switch phase {
        case .swap(let swap): try await animateSwap(swap)
        case .wave(let wave): try await animateWave(wave)
        case .settle(let settle): try await animateSettle(settle)
        case .collect(let cells): try await animateCollect(cells)
        case .reshuffle(let reshuffle): try await animateReshuffle(reshuffle)
        }
    }

    private func animateSwap(_ swap: M3Swap) async throws {
        guard let a = tokenIndex(at: swap.from), let b = tokenIndex(at: swap.to) else { return }
        feedback(.swap)
        if reduceMotion {
            instantly { tokens[a].pos = swap.to; tokens[b].pos = swap.from }
            try await pause(0.08)
        } else {
            animate(.easeInOut(duration: 0.17)) { tokens[a].pos = swap.to; tokens[b].pos = swap.from }
            try await pause(0.18)
        }
    }

    private func animateWave(_ wave: M3Wave) async throws {
        if wave.cascade >= 3 && !finaleRunning { banner = .cascade(wave.cascade) }
        // Colors of the specials that fire, read before their tokens pop.
        var colors: [M3Pos: Color] = [:]
        for t in tokens { if let kind = t.item.piece?.kind { colors[t.pos] = kind.color } }
        // 1. Matched pieces squash.
        let matched = Set(wave.groups.flatMap(\.cells))
        if !matched.isEmpty {
            animate(.easeOut(duration: 0.1)) {
                for i in tokens.indices where matched.contains(tokens[i].pos) { tokens[i].squash = 1 }
            }
            feedback(.pop(cascade: wave.cascade))
            try await pause(0.11)
        }
        // 2. A prism turned pieces into specials before they fire.
        if !wave.conversions.isEmpty {
            animate(.easeOut(duration: 0.2)) {
                for c in wave.conversions {
                    if let i = tokenIndex(at: c.at) { tokens[i].item = .piece(c.piece); tokens[i].glow = 1 }
                }
            }
            for c in wave.conversions { addEffect(.ring(c.at, (c.piece.kind?.color ?? .white)), duration: 0.5) }
            feedback(.created)
            try await pause(0.32)
        }
        // 3. Matched pieces (and the specials a combo used up) pop.
        removeTokens(wave.cleared.filter { $0.cause != .blast })
        // 4. Specials fire in order; what each blast reaches pops right after it.
        for (k, activation) in wave.activations.enumerated() {
            addActivationEffect(activation, color: colors[activation.at] ?? .white)
            feedback(.special)
            try await pause(reduceMotion ? 0.05 : 0.09)
            removeTokens(wave.cleared.filter { $0.cause == .blast && $0.activation == k })
            try await pause(reduceMotion ? 0.04 : 0.08)
        }
        removeTokens(wave.cleared.filter { $0.cause == .blast && $0.activation == nil })
        try await pause(wave.activations.isEmpty ? 0.1 : 0.12)
        // 5. Frost cracks: one layer per hit.
        if !wave.frostHits.isEmpty {
            animate(.easeOut(duration: 0.2)) {
                for hit in wave.frostHits {
                    guard let i = tokenIndex(at: hit.at), var piece = tokens[i].item.piece else { continue }
                    piece.frost = hit.remaining
                    tokens[i].item = .piece(piece)
                }
            }
            for hit in wave.frostHits { addEffect(.crack(hit.at), duration: 0.6) }
            feedback(.frost)
            hud.frostCleared += wave.frostHits.count
        }
        // 6. Crates take hits; a crate at 0 breaks apart.
        if !wave.crateHits.isEmpty {
            animate(.easeOut(duration: 0.2)) {
                for hit in wave.crateHits { crates[hit.at.row * width + hit.at.col] = hit.remaining }
            }
            for hit in wave.crateHits { addEffect(.splinters(hit.at, broken: hit.remaining == 0), duration: 0.7) }
            feedback(.crate)
            hud.crateHits += wave.crateHits.count
        }
        if !wave.frostHits.isEmpty || !wave.crateHits.isEmpty { try await pause(0.14) }
        // 7. New specials appear where their match was.
        if !wave.created.isEmpty {
            var grown: [Int] = []
            instantly {
                for c in wave.created {
                    if let i = tokenIndex(at: c.at) {
                        tokens[i].item = .piece(c.piece)
                    } else {
                        var token = makeToken(.piece(c.piece), at: c.at)
                        token.scale = reduceMotion ? 1 : 0.1
                        token.opacity = reduceMotion ? 0 : 1
                        tokens.append(token)
                        grown.append(token.id)
                    }
                }
            }
            try await frame()
            animate(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.5)) {
                for i in tokens.indices where wave.created.contains(where: { $0.at == tokens[i].pos }) {
                    tokens[i].scale = 1; tokens[i].opacity = 1; tokens[i].glow = 1
                }
            }
            for c in wave.created { addEffect(.ring(c.at, c.piece.kind?.color ?? .white), duration: 0.6) }
            feedback(.created)
            try await pause(0.3)
        }
        // Score for the wave, floating up from where it happened.
        for cleared in wave.cleared { if let kind = cleared.piece.kind { hud.collected[kind.index] += 1 } }
        if wave.score > 0 {
            let cells = wave.groups.isEmpty ? (wave.activations.first.map { [$0.at] } ?? wave.cleared.map(\.at)) : wave.groups.flatMap(\.cells)
            addEffect(.score(center(cells), wave.score, wave.cascade), duration: 0.9)
            hud.score += wave.score
        }
        animate(.easeOut(duration: 0.4)) {
            for i in tokens.indices where tokens[i].glow > 0 { tokens[i].glow = 0 }
        }
    }

    /// Pops the tokens at the cleared cells with sparkles in their colors.
    private func removeTokens(_ cleared: [M3Cleared]) {
        guard !cleared.isEmpty else { return }
        let cells = Set(cleared.map(\.at))
        for c in cleared {
            addEffect(.sparkle(c.at, c.piece.kind?.color ?? .white, c.cause == .blast), duration: 0.55)
        }
        animate(.easeIn(duration: 0.16)) {
            tokens.removeAll { cells.contains($0.pos) && $0.item.piece.map { !$0.isFrozen } ?? false }
        }
    }

    private func addActivationEffect(_ a: M3Activation, color: Color) {
        switch a.effect {
        case .row: addEffect(.beam(a.at, horizontal: true, span: 1, color), duration: 0.5)
        case .column: addEffect(.beam(a.at, horizontal: false, span: 1, color), duration: 0.5)
        case .cross(let w):
            addEffect(.beam(a.at, horizontal: true, span: w, color), duration: 0.55)
            addEffect(.beam(a.at, horizontal: false, span: w, color), duration: 0.55)
        case .square(let r): addEffect(.burst(a.at, radius: r), duration: 0.6)
        case .kind(let kind): addEffect(.rays(a.at, a.cells, kind.color), duration: 0.7)
        case .board:
            addEffect(.flash, duration: 0.8)
            addEffect(.rays(a.at, a.cells, .white), duration: 0.8)
        }
    }

    private func animateSettle(_ settle: M3Settle) async throws {
        // Every token that falls, found before anything moves.
        let falls: [(Int, M3Pos)] = settle.falls.compactMap { fall in tokenIndex(at: fall.from).map { ($0, fall.to) } }
        var maxDistance = settle.falls.map { $0.to.row - $0.from.row }.max() ?? 0
        var spawned: [Int] = []
        instantly {
            for spawn in settle.spawns {
                var token = makeToken(spawn.item, at: spawn.at)
                let startRow = topOpenRow(spawn.at.col) - (spawn.columnCount - spawn.rank)
                let distance = spawn.at.row - startRow
                maxDistance = max(maxDistance, distance)
                if reduceMotion { token.opacity = 0 } else { token.dy = -Double(distance) }
                tokens.append(token)
                spawned.append(token.id)
            }
        }
        if reduceMotion {
            instantly { for (i, to) in falls { tokens[i].pos = to } }
            animate(.easeOut(duration: 0.18)) {
                for i in tokens.indices where spawned.contains(tokens[i].id) { tokens[i].opacity = 1 }
            }
            try await pause(0.18)
            return
        }
        try await frame()
        let duration = min(0.6, 0.24 + 0.045 * Double(maxDistance))
        animate(.spring(duration: duration, bounce: 0.28)) {
            for (i, to) in falls { tokens[i].pos = to }
            for i in tokens.indices where spawned.contains(tokens[i].id) { tokens[i].dy = 0 }
        }
        try await pause(duration * 0.8)
    }

    private func animateCollect(_ cells: [M3Pos]) async throws {
        let set = Set(cells)
        for p in cells { addEffect(.glitter(p), duration: 0.8) }
        feedback(.flask)
        hud.score += M3Rules.Points.flask * cells.count
        animate(.easeIn(duration: reduceMotion ? 0.25 : 0.4)) {
            for i in tokens.indices where set.contains(tokens[i].pos) && tokens[i].item.isFlask {
                if !reduceMotion { tokens[i].dy = -0.8; tokens[i].scale = 1.3 }
                tokens[i].opacity = 0
            }
        }
        try await pause(0.42)
        instantly { tokens.removeAll { set.contains($0.pos) && $0.item.isFlask } }
        hud.flasks += cells.count
    }

    private func animateReshuffle(_ reshuffle: M3Reshuffle) async throws {
        banner = .shuffle
        feedback(.reshuffle)
        announce(String(localized: "No swaps left: stirring the tray", comment: "Match-3: the board is reshuffled"))
        addEffect(.swirl, duration: 1.0)
        try await pause(0.35)
        let moves: [(Int, M3Pos)] = reshuffle.moves.compactMap { m in tokenIndex(at: m.from).map { ($0, m.to) } }
        if reduceMotion {
            animate(.easeOut(duration: 0.15)) { for (i, _) in moves { tokens[i].opacity = 0 } }
            try await pause(0.15)
            instantly { for (i, to) in moves { tokens[i].pos = to } }
            animate(.easeOut(duration: 0.2)) { for (i, _) in moves { tokens[i].opacity = 1 } }
        } else {
            animate(.easeInOut(duration: 0.75)) {
                for (i, to) in moves { tokens[i].pos = to; tokens[i].spin += 360 }
            }
        }
        if !reshuffle.rerolled.isEmpty {
            animate(.easeInOut(duration: 0.3)) {
                for r in reshuffle.rerolled {
                    if let i = tokenIndex(at: r.at) { tokens[i].item = .piece(r.piece); tokens[i].glow = 1 }
                }
            }
        }
        try await pause(0.8)
        banner = nil
        animate(.easeOut(duration: 0.3)) { for i in tokens.indices { tokens[i].glow = 0 } }
    }

    // MARK: End of a step

    private func finish() async throws {
        if case .cascade = banner { banner = nil }
        sync()
        switch game.status {
        case .playing:
            announce(spokenProgress)
            return
        case .lost:
            try await pause(0.3)
            feedback(.outOfMoves)
            announce(String(localized: "Out of moves. Retrying is free, and the board starts the same way.",
                            comment: "VoiceOver: a match-3 level was lost"))
            withAnimation(.spring(duration: 0.4)) { outcome = .lost }
        case .won:
            // The finale is played in the core first and the win saved at once, so leaving the
            // screen (or Retry) while the finale is still animating can't lose it.
            let movesLeft = game.movesLeft
            let result: M3Finale? = movesLeft > 0 ? game.playFinale() : nil
            let stars = game.stars, score = game.score
            let newBest = isDemo ? false : (onWin?(stars, score, movesLeft) ?? false)
            try await pause(0.35)
            if let result { try await finale(result) }
            feedback(.won)
            announce(String(localized: "Gathered! Stars: \(stars) of 3. Score \(score)",
                            comment: "VoiceOver: a match-3 level was won; stars and the final score"))
            withAnimation(.spring(duration: 0.45)) {
                outcome = .won(stars: stars, score: score, newBest: newBest, movesLeft: movesLeft)
            }
        }
    }

    /// "Bubbling Over": every move left becomes a special that fires at once, for bonus points
    /// (`result` is the core's finale, already played; this shows it).
    private func finale(_ result: M3Finale) async throws {
        guard !result.bursts.isEmpty else { return }
        finaleRunning = true
        defer { finaleRunning = false }
        withAnimation(.spring(duration: 0.4)) { banner = .finale }
        announce(String(localized: "Bubbling Over: the moves left fire as specials",
                        comment: "VoiceOver: the match-3 finale starts"))
        try await pause(0.9)
        for burst in result.bursts {
            if let i = tokenIndex(at: burst.at), var piece = tokens[i].item.piece {
                piece.special = burst.special
                animate(.spring(duration: 0.3, bounce: 0.5)) { tokens[i].item = .piece(piece); tokens[i].glow = 1 }
                addEffect(.ring(burst.at, piece.kind?.color ?? .white), duration: 0.5)
            }
            hud.moves = max(0, hud.moves - 1)
            try await pause(0.2)
            for phase in burst.phases { try await animate(phase) }
            hud.score += M3Rules.Points.finaleBurst
        }
        withAnimation(.easeOut(duration: 0.3)) { banner = nil }
        sync()
        try await pause(0.3)
    }

    /// The HUD and board as the game has them; rebuilds the tokens if they ever differ.
    private func sync() {
        hud = Self.hud(of: game)
        let board = game.board
        crates = board.cells.map(\.crate)
        var shown: [M3Pos: M3Item] = [:]
        var duplicate = false
        for t in tokens { if shown.updateValue(t.item, forKey: t.pos) != nil { duplicate = true } }
        var expected: [M3Pos: M3Item] = [:]
        for p in board.positions { if let item = board[p].item { expected[p] = item } }
        guard duplicate || shown != expected else { return }
        #if DEBUG
        print("MatchBoardModel: tokens drifted from the board; rebuilt")
        #endif
        instantly {
            tokens = board.positions.compactMap { p in board[p].item.map { makeToken($0, at: p) } }
        }
    }

    private static func hud(of game: M3Game) -> HUD {
        HUD(moves: game.movesLeft, score: game.score, collected: game.collected, flasks: game.flasksCollected,
            frostCleared: game.startFrost - game.board.frostLayers, crateHits: game.startCrates - game.board.crateHits)
    }

    // MARK: Goals

    /// (current, target) of a goal as the HUD shows it.
    func progress(_ goal: M3Goal) -> (current: Int, target: Int) {
        let truth = game.progress(goal)
        switch goal.type {
        case .collect: return (min(goal.kind.map { hud.collected[$0.index] } ?? 0, truth.target), truth.target)
        case .frost: return (min(hud.frostCleared, truth.target), truth.target)
        case .crates: return (min(hud.crateHits, truth.target), truth.target)
        case .drops: return (min(hud.flasks, truth.target), truth.target)
        case .score: return (min(hud.score, truth.target), truth.target)
        }
    }

    // MARK: Effects

    private func addEffect(_ kind: BoardFX.Kind, duration: Double) {
        nextID += 1
        effects.append(BoardFX(id: nextID, kind: kind, start: .now, duration: duration * pace, reduceMotion: reduceMotion))
    }

    private func pruneEffects() {
        let now = Date.now
        if effects.contains(where: { $0.isOver(at: now) }) { effects.removeAll { $0.isOver(at: now) } }
    }

    // MARK: Accessibility

    /// "Moonflower, frozen (2 layers)", "Sealed crate, 2 hits left", "Potion flask".
    func spokenCell(_ p: M3Pos) -> String {
        let cell = game.board[p]
        if cell.crate > 0 {
            return String(localized: "Sealed crate, \(cell.crate) hits left", comment: "VoiceOver: a match-3 crate cell")
        }
        switch cell.item {
        case nil: return String(localized: "Empty", comment: "VoiceOver: an empty match-3 cell")
        case .flask: return String(localized: "Potion flask, bring it to the bottom", comment: "VoiceOver: the drop-down goal item")
        case .piece(let piece):
            var text: String
            if piece.isPrism {
                text = String(localized: "Prism, clears every piece of the kind it is swapped with", comment: "VoiceOver: a prism piece")
            } else {
                let name = piece.kind?.displayName ?? ""
                if let special = piece.special {
                    text = String(localized: "\(name) \(special.displayName)", comment: "VoiceOver: an ingredient that is a special, e.g. Ember row comet")
                } else {
                    text = name
                }
            }
            if piece.frost > 0 {
                text += ", " + String(localized: "frozen, \(piece.frost) ice layers", comment: "VoiceOver: a frozen match-3 piece")
            }
            return text
        }
    }

    /// Read out after each swap has played out: moves left and the goals.
    private var spokenProgress: String {
        String(localized: "Moves left: \(hud.moves). \(spokenGoals)", comment: "VoiceOver: after a match-3 swap; moves left, then the goals")
    }

    private var spokenGoals: String {
        level.goals.map { goal -> String in
            let p = progress(goal)
            return "\(Match3Goals.name(goal)) \(p.current)/\(p.target)"
        }
        .formatted(.list(type: .and))
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    /// The board summary for VoiceOver.
    var spokenSummary: String {
        String(localized: "\(width) by \(height) board, \(hud.moves) moves left, \(spokenGoals)",
                      comment: "VoiceOver: match-3 board summary")
    }

    #if DEBUG
    /// `-LPM3Demo K`: plays K bot moves through the normal swap path, waiting for each to play out.
    func debugAutoplay(moves: Int) async {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<moves {
            while busy { try? await Task.sleep(for: .milliseconds(50)) }
            guard isPlaying, let swap = M3Bot.choose(game, policy: .greedy, rng: &rng) else { return }
            try? await Task.sleep(for: .milliseconds(450))
            requestSwap(swap)
        }
    }
    #endif
}

/// Names of goals for the HUD and VoiceOver.
enum Match3Goals {
    static func name(_ goal: M3Goal) -> String {
        switch goal.type {
        case .collect: goal.kind?.displayName ?? ""
        case .frost: String(localized: "Frost", comment: "Match-3 goal: clear every frost layer")
        case .crates: String(localized: "Crates", comment: "Match-3 goal: break every sealed crate")
        case .drops: String(localized: "Flasks", comment: "Match-3 goal: bring the potion flasks down")
        case .score: String(localized: "Score", comment: "Match-3 goal: reach a score")
        }
    }
}
