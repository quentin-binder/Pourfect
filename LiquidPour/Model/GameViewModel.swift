import BottleSortCore
import Foundation
import Observation
import Accessibility
import SwiftUI

/// Drives one game screen. Wraps `GameSession`; all rule decisions come from BottleSortCore.
@MainActor
@Observable
final class GameViewModel {
    enum Status: Equatable {
        case playing
        case won(stars: Int)
        case stuck
    }

    /// One legal pour that was just applied to the session. The view animates it, then calls
    /// `finishPour(_:)`. Holds the two bottles as they were *before* the move, so the
    /// animation can draw the transfer without re-deriving any rule.
    struct PourEvent: Identifiable, Equatable {
        let id: Int
        let from: Int
        let to: Int
        /// The layer kind that moved (all moved layers are identical).
        let layer: Layer
        /// Number of layers that left the source (`targetAmount` landed in `to`, the rest in
        /// `shares`).
        let amount: Int
        /// Layers that landed in `to`: all of them, unless the pour was split between twins (F1)
        /// or ran on through an overflow pipe (F2). 0 when a full flask passed it all on.
        let targetAmount: Int
        /// The other flasks the pour filled (the target's twin, or the far end of its pipe),
        /// as they were before the move.
        let shares: [Landing]
        /// Every twin flask of the level (they wear a silver band, also in flight).
        let twins: Set<Int>
        /// The layers left from the source's bottom, through its tap (C4): the stack above
        /// slides down. Otherwise they left from the top.
        let fromBottom: Bool
        let sourceBefore: Bottle
        let targetBefore: Bottle
        /// Per layer (0 = bottom) of each bottle: shown as "?" before the move (murky potions).
        let sourceHiddenBefore: [Bool]
        let targetHiddenBefore: [Bool]

        /// Bottles that became complete (full, one color) through this move. Reported as
        /// `.flaskCompleted` when the animation lands.
        let completed: [Int]
        /// What happened on its own after the pour (`Turn.events`, e.g. a layer thawing): played
        /// when the pour lands.
        let events: [TurnEvent]
        /// Every bottle's frozen layers before the move: the board keeps showing them while the
        /// pour is in the air, so the counters tick (and ice thaws) when it lands.
        let iceBefore: [[FrozenLayer]]
        /// Every bottle's bubbling phase before the move (D2): the dials tick when it lands.
        let bubblingBefore: [Bubbling?]
        /// Bubbling flasks whose bottom layer rose after this move (`TurnEvent.bubbled`), as they
        /// were before the rise: the board shows them so while the pour is in the air, and their
        /// rise plays when it lands (`BubbleRise`).
        let rises: [RiseMark]
        /// The mix this pour made in its target cauldron (`TurnEvent.mixed`, E1), with the
        /// cauldron as the pour left it and as it ends: the swirl plays when the pour lands
        /// (`MixSwirl`).
        let mix: MixMark?

        /// A key pour: the key drops into the target's lock instead of liquid flowing.
        var isKey: Bool { layer.isKey }
        /// The pour was split evenly between twins.
        var isSplit: Bool { shares.contains { $0.route == .twin } }
        /// What ran on through the target's overflow pipe, if anything.
        var overflow: Landing? { shares.first { $0.route == .overflow } }
        /// Every flask the pour animation draws: the source, the target and the shares.
        var bottles: [Int] { [from, to] + shares.map(\.bottle) }
    }

    /// Part of a pour that landed in another flask than the one poured into (`PourShare`).
    struct Landing: Equatable {
        let bottle: Int
        let amount: Int
        let route: PourShare.Route
        let before: Bottle
        let hiddenBefore: [Bool]
    }

    /// Something the player should hear or feel. Published in order through `feedback`.
    enum FeedbackEvent: Equatable {
        /// A bottle was picked up as the pour source.
        case select(bottle: Int)
        /// A tap that can't do anything (empty bottle selected, or an illegal pour).
        case illegal(bottle: Int)
        /// A flask modifier refused the pour (`Rules.refusal`): an essence flask's rune flares
        /// (`runeHum`), a funnel or a tap flask knocks its brass (`brassKnock`).
        case refused(bottle: Int, modifier: BottleModifier)
        /// A twin chain refused the pour (`Rules.linkRefusal`): the chain rattles.
        case refusedLink(bottles: [Int])
        /// A legal pour started animating (same moment as `pour` is set). `amount` = layers moved;
        /// `fromBottom`: poured through a tap (the valve opens instead of the lip clinking).
        case pour(from: Int, to: Int, amount: Int, isKey: Bool, fromBottom: Bool)
        /// The pour that just started is split between twins (F1): the chain chimes as the
        /// stream forks.
        case split(bottles: [Int])
        /// Part of the pour that just started runs on through an overflow pipe (F2), once
        /// `start` (0…1) of the flow has gone into the full flask: the pipe glugs.
        case overflow(into: Int, start: Double)
        /// Frozen layers of these bottles thawed (D1); fires when the pour animation lands, as
        /// the ice cracks and melts.
        case thawed(bottles: [Int])
        /// The bottom layer of these bubbling flasks rose to the top (D2); fires when the pour
        /// animation lands, as the bubble starts to climb.
        case bubbled(bottles: [Int])
        /// The pour into this cauldron mixed (E1); fires when the pour animation lands, as the
        /// ingredients start to swirl.
        case mixed(bottle: Int)
        /// Bottles that became complete; fires when the pour animation lands (`finishPour`).
        case flaskCompleted(bottles: [Int])
        /// The level was solved; fires when the winning pour lands, right after any `flaskCompleted`.
        case levelWon(stars: Int)
    }

    struct Feedback: Identifiable, Equatable {
        /// Increments by one per event, never reused within a model.
        let id: Int
        let event: FeedbackEvent
    }

    private(set) var levels: [LevelDefinition]
    /// Pack progress; nil for random levels, which never affect saved progress.
    private let progress: ProgressModel?
    /// Set by the dev aid `-LPDemoMoves` (DEBUG): a demo win records no stars and no daily
    /// result, so automated runs leave the saved progress alone.
    @ObservationIgnored private var isDemo = false
    /// Set when playing a random level: the options used to make the next one.
    let randomOptions: RandomLevelOptions?
    /// Generates the next random level ("New Random Brew" on the win card).
    let randomMaker = RandomLevelMaker()
    /// Set when playing the daily puzzle: its UTC date and where the result is recorded.
    let dailyDate: DailyDate?
    private let daily: DailyModel?
    /// The daily's result after a win (first solve, replay, or too late to count).
    private(set) var dailyOutcome: DailyModel.RecordOutcome?
    /// A hint was shown on this daily (kept across Restart, and saved per date in `DailyModel`, so
    /// reopening the puzzle keeps it): it forfeits "perfect" (DECISIONS 109, 115).
    private(set) var usedHint = false

    private(set) var levelIndex: Int
    private(set) var session: GameSession
    private(set) var status: Status = .playing
    /// Optimal move count (from level meta, or computed in the background).
    private(set) var minMoves: Int?
    /// Currently selected source bottle.
    private(set) var selected: Int?
    /// Move highlighted by the Hint button.
    private(set) var hint: Move?
    private(set) var hintMessage: String?
    private(set) var isThinking = false
    /// Incremented per bottle on an illegal move (drives the shake animation).
    private(set) var shakes: [Int] = []
    /// Incremented per bottle each time its rune refuses a pour (drives the rune flare).
    private(set) var refusals: [Int] = []
    /// Incremented per link (index in `state.links`) each time a twin chain refuses a pour
    /// (drives the chain's glint and rattle).
    private(set) var linkRefusals: [Int] = []
    /// Recent feedback events, oldest first (only the last few are kept). Observe
    /// `feedback.last?.id` and read `feedback(after:)` so events published in one update
    /// (e.g. a completion followed by a queued tap) are never lost.
    /// Goes up each time a pour is cancelled mid-animation (undo, restart, level load), so the
    /// view can drop that pour's delayed sounds and haptics.
    private(set) var cancelledPours = 0
    private(set) var feedback: [Feedback] = []
    /// Incremented per bottle each time it becomes complete (drives the cork / burst visuals).
    private(set) var completions: [Int] = []
    /// The pour being animated, if any. While set, taps are queued (not applied) so the
    /// board the view shows and the session can't drift apart.
    private(set) var pour: PourEvent?
    /// Frozen layers that thawed when the last pour landed; each cracks and melts once, then is
    /// removed (`ThawingIce`).
    private(set) var thaws: [ThawMark] = []
    private var thawCount = 0
    private var thawClearTask: Task<Void, Never>?
    /// Bubbling flasks whose bottom layer rose when the last pour landed; each plays its rise
    /// once, then is removed (`BubbleRise`).
    private(set) var rises: [RiseMark] = []
    private var riseCount = 0
    private var riseClearTask: Task<Void, Never>?
    /// Cauldrons that mixed when the last pour landed; each swirls once, then is removed
    /// (`MixSwirl`). A cauldron the mix completes is counted complete (cork, sound) and a win
    /// is announced only then.
    private(set) var mixes: [MixMark] = []
    private var mixCount = 0
    private var mixClearTask: Task<Void, Never>?

    /// Latest optimal solution, valid for `solutionState`. Lets Hint answer instantly.
    private var solution: (state: GameState, moves: [Move])?
    private var analysisTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var hintClearTask: Task<Void, Never>?
    private var pourCount = 0
    private var feedbackCount = 0
    /// Taps received while a pour animates, or a pour that would pick up a flask whose bottom
    /// layer is still rising (`rises`); replayed in order when that ends.
    private var queuedTaps: [Int] = []
    /// Safety net: ends a pour even if the view never reports back (e.g. it went off screen).
    private var pourTimeout: Task<Void, Never>?

    nonisolated static let solverLimits = SolverLimits(maxStates: 1_000_000, timeout: .seconds(4))

    /// Mechanics the pack introduces (its first recipe teaches them).
    let introduces: [Mechanic]

    init(levels: [LevelDefinition], index: Int, progress: ProgressModel, introduces: [Mechanic] = []) {
        self.levels = levels
        self.introduces = introduces
        self.progress = progress
        self.randomOptions = nil
        self.dailyDate = nil
        self.daily = nil
        self.levelIndex = index
        self.session = GameSession(levels[index].gameState, hidden: levels[index].isHidden)
        startLevel(index)
    }

    /// Plays one generated level; the win card then offers a new one with the same options.
    init(randomLevel: LevelDefinition, options: RandomLevelOptions) {
        self.levels = [randomLevel]
        self.introduces = []
        self.progress = nil
        self.randomOptions = options
        self.dailyDate = nil
        self.daily = nil
        self.levelIndex = 0
        self.session = GameSession(randomLevel.gameState, hidden: randomLevel.isHidden)
        startLevel(0)
    }

    /// Plays the daily puzzle of `date`. A win is recorded in `daily`, never in chapter stars.
    init(dailyLevel: LevelDefinition, date: DailyDate, daily: DailyModel) {
        self.levels = [dailyLevel]
        self.introduces = []
        self.progress = nil
        self.randomOptions = nil
        self.dailyDate = date
        self.daily = daily
        self.usedHint = daily.hintUsed(on: date)
        self.levelIndex = 0
        self.session = GameSession(dailyLevel.gameState, hidden: dailyLevel.isHidden)
        startLevel(0)
    }

    var isRandom: Bool { randomOptions != nil }
    var isDaily: Bool { dailyDate != nil }
    var title: String {
        if let dailyDate {
            return String(localized: "Daily Brew · \(dailyDate.weekday.localizedName)")
        }
        if let randomOptions { return String(localized: "Random Brew · \(randomOptions.mode.title)") }
        return String(localized: "Recipe \(levelIndex + 1)")
    }

    var level: LevelDefinition { levels[levelIndex] }
    /// Mechanics the current recipe uses, for the first-time tips and the "?" button.
    var tutorialTopics: [TutorialTopic] {
        TutorialTopic.topics(in: level, introduces: levelIndex == 0 ? introduces : [])
    }
    var state: GameState { session.state }
    var moveCount: Int { session.moveCount }
    var canUndo: Bool { session.canUndo }
    var hasNextLevel: Bool { levelIndex + 1 < levels.count }

    /// The frozen layers to draw on bottle `index`. While a pour is in the air, the ones from
    /// before the move: the counters tick down (and thawed ice melts) when the pour lands.
    func ice(_ index: Int) -> [FrozenLayer] {
        if let pour, pour.iceBefore.indices.contains(index) { return pour.iceBefore[index] }
        return state.bottles.indices.contains(index) ? state.bottles[index].frozenLayers : []
    }

    /// The bottle to draw at `index`. A bubbling flask whose bottom layer rises after the pour
    /// in the air keeps its order from before the rise until the pour lands.
    func bottle(_ index: Int) -> Bottle {
        var bottle = state.bottles[index]
        if let mark = pour?.rises.first(where: { $0.bottle == index }) { bottle.layers = mark.layers }
        if let mix = pour?.mix, mix.bottle == index { bottle.layers = mix.before }
        return bottle
    }

    /// The mix swirling in cauldron `index`, if any.
    func mix(_ index: Int) -> MixMark? {
        mixes.last { $0.bottle == index }
    }

    /// Whether a mix is still swirling: the win card waits for it.
    var isMixing: Bool { !mixes.isEmpty }

    /// The bubbling phase to show on bottle `index`'s dial: from before the move while a pour is
    /// in the air, so the dial ticks when it lands.
    func bubbling(_ index: Int) -> Bubbling? {
        if let pour, pour.bubblingBefore.indices.contains(index) { return pour.bubblingBefore[index] }
        return state.bottles.indices.contains(index) ? state.bottles[index].bubbling : nil
    }

    /// The rise playing on bottle `index`, if any.
    func rise(_ index: Int) -> RiseMark? {
        rises.last { $0.bottle == index }
    }

    /// Layers of bottle `index` that are thawing right now.
    func thaws(_ index: Int) -> [ThawMark] {
        thaws.filter { $0.bottle == index }
    }

    /// Per layer (0 = bottom) of bottle `index`: whether it shows as "?". The flags move with
    /// their layers (a tap drains from the bottom, `GameSession.hiddenMasks`). While a pour
    /// animates, the source keeps its pre-move flags so the reveal plays when the board bottle
    /// comes back.
    func hiddenMask(_ index: Int) -> [Bool] {
        if let pour, pour.from == index { return pour.sourceHiddenBefore }
        if let mark = pour?.rises.first(where: { $0.bottle == index }) { return mark.hidden }
        return session.hiddenMasks.indices.contains(index) ? session.hiddenMasks[index] : []
    }

    // MARK: Intents

    func tap(bottle index: Int) {
        guard !isWon else { return }
        if pour != nil || !queuedTaps.isEmpty || waitsForRise(index) {
            if queuedTaps.count < 2 { queuedTaps.append(index) }
            return
        }
        perform(tap: index)
    }

    /// Whether tapping `index` now would start a pour with a flask whose rise (or mix) is still
    /// playing: the pour waits for it, so the flask never jumps to its new order (DECISIONS 177).
    private func waitsForRise(_ index: Int) -> Bool {
        guard let from = selected, from != index else { return false }
        // A pour into a linked flask may also fill its twin or the far end of its pipe.
        let touched = [from, index, state.twin(of: index), state.overflowTarget(of: index)].compactMap { $0 }
        return rises.contains { touched.contains($0.bottle) } || mixes.contains { touched.contains($0.bottle) }
    }

    /// Replays queued taps in order, until one starts a pour or has to wait for a rise.
    private func replayQueuedTaps() {
        while pour == nil, let next = queuedTaps.first, !waitsForRise(next), !isWon {
            queuedTaps.removeFirst()
            perform(tap: next)
        }
        if isWon { queuedTaps.removeAll() }
    }

    private func perform(tap index: Int) {
        clearHint()
        guard let from = selected else {
            let bottle = state.bottles[index]
            if bottle.isEmpty {
                reject(index)
            } else if Rules.outlet(of: bottle) == nil {
                // Nothing can leave it right now (a seal, a funnel, ice on top or in a tap
                // flask): it isn't picked up. `Rules.outletBlocker` names the reason.
                if let blocker = Rules.outletBlocker(of: bottle), Self.explains(blocker) {
                    refuse(index, modifier: blocker)
                } else {
                    reject(index)
                }
            } else {
                selected = index
                emit(.select(bottle: index))
            }
            return
        }
        selected = nil
        if from == index { return }   // tapping the same bottle deselects
        let move = Move(from: from, to: index)
        let before = state
        let hiddenBefore = session.hiddenMasks
        if let turn = session.play(move) {
            if let event = turn.pour { startPour(event, before: before, hiddenBefore: hiddenBefore) }
            afterStateChange()
        } else if let refusal = Rules.refusal(of: move, in: before), Self.explains(refusal.modifier) {
            refuse(refusal.bottle, modifier: refusal.modifier)
        } else if let link = Rules.linkRefusal(of: move, in: before) {
            refuse(move, link: link)
        } else {
            reject(from)
        }
    }

    /// Called by the view when the pour animation `id` has finished. Replays queued taps.
    /// `reduceMotion`: the thaw plays as a short fade, so its marks clear sooner.
    func finishPour(_ id: Int, reduceMotion: Bool = false) {
        guard let landed = pour, landed.id == id else { return }
        pour = nil
        pourTimeout?.cancel()
        announceLanding(landed)
        startThaws(landed.events, reduceMotion: reduceMotion)
        startRises(landed.rises, reduceMotion: reduceMotion)
        // A cauldron the mix completes is corked when the swirl has settled (`startMix`).
        let completed = landed.completed.filter { $0 != landed.mix?.bottle }
        if !completed.isEmpty {
            for index in completed where completions.indices.contains(index) { completions[index] += 1 }
            emit(.flaskCompleted(bottles: completed))
        }
        if let mix = landed.mix {
            startMix(mix, completes: landed.completed.contains(mix.bottle), reduceMotion: reduceMotion)
        } else if case .won(let stars) = status, mixes.isEmpty {
            // (While a mix still swirls, its end announces the win.)
            emit(.levelWon(stars: stars))
        }
        replayQueuedTaps()
    }

    func undo() {
        guard session.undo() else { return }
        randomMaker.cancel()   // the player went back to the board: drop a pending new level
        cancelPour()
        selected = nil
        clearHint()
        afterStateChange()
    }

    func restart() {
        session.restart()
        randomMaker.cancel()   // Replay while "New Random Brew" runs: keep the replayed board
        dailyOutcome = nil     // a replayed daily is checked again on its win (it won't replace the first)
        cancelPour()
        selected = nil
        clearHint()
        afterStateChange()
    }

    func requestHint() {
        guard !isWon else { return }
        selected = nil
        if let solution, solution.state == state, let first = solution.moves.first {
            showHint(first)
            return
        }
        isThinking = true
        let current = state
        hintTask?.cancel()
        hintTask = Task {
            let result = await Self.solve(current)
            guard !Task.isCancelled, current == self.state else { return }   // board changed meanwhile
            self.isThinking = false
            self.handle(result, for: current)
            switch result {
            case .solved(let moves, _):
                if let first = moves.first { self.showHint(first) }
            case .unsolvable:
                self.flash(String(localized: "No solution from here — undo?"))
            case .unknown:
                self.flash(String(localized: "Couldn't find a hint in time"))
            }
        }
    }

    func startLevel(_ index: Int) {
        analysisTask?.cancel()
        levelIndex = index
        // Present the bottles in a fresh random order on every load (Restart/Replay keep it),
        // so empty bottles aren't always at the end. Order doesn't change the puzzle.
        var rng = SystemRandomNumberGenerator()
        // Linked flasks stay side by side, so their chain or pipe stays short (DECISIONS 187).
        let shuffled = BoardLayout.keepingLinksTogether(levels[index].gameState.shufflingBottles(using: &rng))
        session = GameSession(shuffled, hidden: levels[index].isHidden)
        cancelPour()
        minMoves = levels[index].meta?.minMoves
        shakes = Array(repeating: 0, count: session.state.bottles.count)
        refusals = Array(repeating: 0, count: session.state.bottles.count)
        linkRefusals = Array(repeating: 0, count: session.state.links.count)
        completions = Array(repeating: 0, count: session.state.bottles.count)
        selected = nil
        solution = nil
        clearHint()
        afterStateChange()
    }

    func nextLevel() {
        guard hasNextLevel else { return }
        startLevel(levelIndex + 1)
    }

    /// Random levels: generates a new level with the same options (off the main thread)
    /// and starts it. Progress and failure are published by `randomMaker`.
    func newRandomLevel() {
        guard let randomOptions else { return }
        randomMaker.generate(randomOptions) { [weak self] level in
            guard let self else { return }
            self.levels = [level]
            self.startLevel(0)
        }
    }

    // MARK: Helpers

    private var isWon: Bool { if case .won = status { return true } else { return false } }

    /// Starts animating the pour the core reported (`Turn.pour`): what moved, how much and
    /// from which end of the source. Nothing is re-derived from the states.
    private func startPour(_ event: BottleSortCore.PourEvent, before: GameState, hiddenBefore: [[Bool]]) {
        let move = event.move
        guard event.amount > 0 else { return }
        pourCount += 1
        let id = pourCount
        let mask = { (i: Int) in hiddenBefore.indices.contains(i) ? hiddenBefore[i] : [] }
        // A flask in this pour is drawn by the pour animation: an older rise on it stops. (Taps
        // wait for a running rise, `waitsForRise`; this only catches the dev aids.)
        let shares = event.shares.map {
            Landing(bottle: $0.bottle, amount: $0.amount, route: $0.route,
                    before: before.bottles[$0.bottle], hiddenBefore: mask($0.bottle))
        }
        rises.removeAll { $0.bottle == move.from || $0.bottle == move.to || event.shares.map(\.bottle).contains($0.bottle) }
        mixes.removeAll { $0.bottle == move.from || $0.bottle == move.to }
        let twins = Set(state.links.flatMap { link -> [Int] in
            guard case let .twins(a, b) = link else { return [] }
            return [a, b]
        })
        pour = PourEvent(id: id, from: move.from, to: move.to, layer: event.layer, amount: event.amount,
                         targetAmount: event.targetAmount, shares: shares, twins: twins,
                         fromBottom: event.fromBottom,
                         sourceBefore: before.bottles[move.from], targetBefore: before.bottles[move.to],
                         sourceHiddenBefore: mask(move.from), targetHiddenBefore: mask(move.to),
                         completed: Rules.completedBottles(before: before, after: state),
                         events: session.lastEvents, iceBefore: before.bottles.map(\.frozenLayers),
                         bubblingBefore: before.bottles.map(\.bubbling),
                         rises: pendingRises(session.lastEvents, hiddenBefore: hiddenBefore),
                         mix: pendingMix(event))
        emit(.pour(from: move.from, to: move.to, amount: event.amount, isKey: event.layer.isKey,
                   fromBottom: event.fromBottom))
        if let pour, pour.isSplit { emit(.split(bottles: [move.to] + shares.map(\.bottle))) }
        if let overflow = pour?.overflow {
            emit(.overflow(into: overflow.bottle, start: Double(event.targetAmount) / Double(event.amount)))
        }
        pourTimeout?.cancel()
        pourTimeout = Task {
            try? await Task.sleep(for: .seconds(3 * DebugTiming.slow))
            guard !Task.isCancelled else { return }
            self.finishPour(id)
        }
    }

    private func cancelPour() {
        if pour != nil { cancelledPours += 1 }
        pour = nil
        thawClearTask?.cancel()
        thaws.removeAll()
        riseClearTask?.cancel()
        rises.removeAll()
        mixClearTask?.cancel()
        mixes.removeAll()
        queuedTaps.removeAll()
        pourTimeout?.cancel()
    }

    private func reject(_ bottle: Int) {
        shakes[bottle] += 1
        emit(.illegal(bottle: bottle))
    }

    /// Modifiers whose refusal gets its own feedback (a message naming the rule); any other
    /// refusal is the plain shake of the source.
    private static func explains(_ modifier: BottleModifier) -> Bool {
        switch modifier {
        case .essence, .funnel, .tap, .frozen: return true
        default: return false
        }
    }

    /// A flask's modifier said no: that flask shakes, its mark flares (the rune, the funnel or
    /// the spigot), and a short line says why (the rule comes from `Rules.refusal` /
    /// `Rules.outlet`, not from the app).
    private func refuse(_ bottle: Int, modifier: BottleModifier) {
        shakes[bottle] += 1
        refusals[bottle] += 1
        switch modifier {
        case .essence(let color):
            flash(String(localized: "This essence flask only takes \(Palette.potionName(color.rawValue))",
                         comment: "Shown when an essence flask refuses a pour; the argument is a potion name"))
        case .funnel:
            flash(String(localized: "A funnel flask only fills. Nothing pours out of it.",
                         comment: "Shown when the player tries to pour from a funnel flask"))
        case .tap:
            flash(String(localized: "A tap flask only pours from its tap. Nothing goes in.",
                         comment: "Shown when the player tries to pour into a tap flask"))
        case .frozen:
            let flask = state.bottles[bottle]
            if flask.hasTap, !flask.isIcedOver {
                // A tap pours from under the ice: it waits until every frozen layer has thawed.
                let turns = flask.frozenLayers.map(\.turns).max() ?? 1
                flash(String(localized: "A tap can't pour while its flask holds ice. It thaws in \(turns) moves.",
                             comment: "Shown when the player picks up a tap flask that holds a frozen layer; the argument is the moves until the last ice thaws"))
            } else {
                let turns = flask.frozenLayers.last?.turns ?? 1
                flash(String(localized: "Ice seals this flask. It thaws in \(turns) moves.",
                             comment: "Shown when the player pours into or out of a flask whose top layer is frozen; the argument is the moves until it thaws"))
            }
        default:
            break
        }
        emit(.refused(bottle: bottle, modifier: modifier))
    }

    /// A twin chain said no (`Rules.linkRefusal`): both twins shake, the chain glints and
    /// rattles, and a short line says why.
    private func refuse(_ move: Move, link: BottleSortCore.Link) {
        let twins: [Int]
        if case let .twins(a, b) = link { twins = [a, b] } else { twins = [move.to] }
        for bottle in twins where shakes.indices.contains(bottle) { shakes[bottle] += 1 }
        if let index = state.links.firstIndex(of: link), linkRefusals.indices.contains(index) {
            linkRefusals[index] += 1
        }
        let source = state.bottles[move.from]
        if twins.contains(move.from) {
            flash(String(localized: "Twins can't pour into each other.",
                         comment: "Shown when the player pours from one twin flask into the other"))
        } else if Rules.movableRunCount(source) < 2 || source.hasNarrowNeck || source.layers.last?.isKey == true {
            flash(String(localized: "Twins share every pour evenly. A single layer can't be split between them.",
                         comment: "Shown when the player pours one layer (or a key) into a twin flask"))
        } else {
            flash(String(localized: "Twins share every pour. Both need room for this potion.",
                         comment: "Shown when a pour into a twin flask is refused because its twin is full or has another potion on top"))
        }
        emit(.refusedLink(bottles: twins))
    }

    /// VoiceOver: where a pour that used a link landed (split between twins, or run through a
    /// pipe), said when it lands.
    private func announceLanding(_ pour: PourEvent) {
        if pour.isSplit, let twin = pour.shares.first(where: { $0.route == .twin }) {
            AccessibilityNotification.Announcement(
                String(localized: "Split between flask \(pour.to + 1) and flask \(twin.bottle + 1)",
                       comment: "VoiceOver: a pour into a twin flask was shared evenly with its twin; the arguments are flask numbers")).post()
        }
        if let overflow = pour.overflow {
            AccessibilityNotification.Announcement(
                String(localized: "The rest ran through the pipe into flask \(overflow.bottle + 1)",
                       comment: "VoiceOver: what didn't fit into a full flask ran on through its overflow pipe; the argument is the flask number")).post()
        }
    }

    /// The pour landed: the layers that thawed after it crack and melt now (`ThawingIce`), with
    /// a sound and, for VoiceOver, a line naming the flasks.
    private func startThaws(_ events: [TurnEvent], reduceMotion: Bool) {
        var bottles: [Int] = []
        for event in events {
            guard case let .thawed(bottle, layer) = event else { continue }
            thawCount += 1
            thaws.append(ThawMark(id: thawCount, bottle: bottle, layer: layer))
            if !bottles.contains(bottle) { bottles.append(bottle) }
        }
        guard !bottles.isEmpty else { return }
        emit(.thawed(bottles: bottles))
        let names = bottles.map { String($0 + 1) }.formatted(.list(type: .and))
        AccessibilityNotification.Announcement(
            String(localized: "Ice melted in flask \(names)",
                   comment: "VoiceOver: frozen layers thawed after a move; the argument lists flask numbers")).post()
        let lastID = thawCount
        thawClearTask?.cancel()
        thawClearTask = Task {
            // As long as `ThawingIce` plays (the frost rim stays while a mark is left).
            let duration = reduceMotion ? ThawPose.reducedDuration : ThawPose.duration
            try? await Task.sleep(for: .seconds((duration + 0.15) * DebugTiming.slow))
            guard !Task.isCancelled else { return }
            self.thaws.removeAll { $0.id <= lastID }
        }
    }

    /// The bubbling flasks whose bottom layer rose in this move (`TurnEvent.bubbled`), as they
    /// were before the rise: the layers come back from `Rules.sunk`, the murky flags likewise,
    /// except the bottom one, which is the flag that layer had before the move (a pour never
    /// touches a bottom layer that then rises; the session revealed it on top).
    private func pendingRises(_ events: [TurnEvent], hiddenBefore: [[Bool]]) -> [RiseMark] {
        events.compactMap { event in
            guard case .bubbled(let b) = event, state.bottles.indices.contains(b) else { return nil }
            var mask = session.hiddenMasks.indices.contains(b) ? Rules.sunk(session.hiddenMasks[b]) : []
            if !mask.isEmpty, hiddenBefore.indices.contains(b), let bottom = hiddenBefore[b].first {
                mask[0] = bottom
            }
            riseCount += 1
            return RiseMark(id: riseCount, bottle: b, layers: Rules.sunk(state.bottles[b].layers), hidden: mask)
        }
    }

    /// The pour landed: the bottom layers that rose climb through their flasks now
    /// (`BubbleRise`), with a bubbly sound and, for VoiceOver, a line naming what rose.
    private func startRises(_ marks: [RiseMark], reduceMotion: Bool) {
        guard !marks.isEmpty else { return }
        rises.append(contentsOf: marks)
        let bottles = marks.map(\.bottle)
        emit(.bubbled(bottles: bottles))
        for mark in marks {
            let risen = mark.layers.first
            let murky = mark.hidden.first == true
            let line: String
            if let risen, !murky {
                line = String(localized: "Flask \(mark.bottle + 1) bubbled up: \(risen.spokenName) rose to the top",
                              comment: "VoiceOver: a bubbling flask's bottom layer rose to the top; the arguments are the flask number and the potion")
            } else {
                line = String(localized: "Flask \(mark.bottle + 1) bubbled up: its bottom layer rose to the top",
                              comment: "VoiceOver: a bubbling flask's bottom layer rose to the top (a murky layer, revealed on top)")
            }
            AccessibilityNotification.Announcement(line).post()
        }
        let lastID = riseCount
        riseClearTask?.cancel()
        riseClearTask = Task {
            let duration = reduceMotion ? RisePose.reducedDuration : RisePose.duration
            try? await Task.sleep(for: .seconds((duration + 0.1) * DebugTiming.slow))
            guard !Task.isCancelled else { return }
            self.rises.removeAll { $0.id <= lastID }
            // A pour that waited for this rise starts now.
            withAnimation(.easeInOut(duration: 0.3)) { self.replayQueuedTaps() }
        }
    }

    /// The mix this pour made (`TurnEvent.mixed`, E1): the cauldron's layers after the turn,
    /// and as the pour left them before mixing (`Rules.beforeMixing`, from the pour's layer and
    /// the amount that landed there).
    private func pendingMix(_ event: BottleSortCore.PourEvent) -> MixMark? {
        for case let .mixed(b, recipe, pairs) in session.lastEvents where state.bottles.indices.contains(b) {
            guard let poured = event.layer.colorID else { continue }
            let amount = b == event.move.to ? event.targetAmount : event.shares.first { $0.bottle == b }?.amount ?? 0
            let after = state.bottles[b].layers
            let before = Rules.beforeMixing(after, poured: event.layer, amount: amount, recipe: recipe, pairs: pairs)
            mixCount += 1
            return MixMark(id: mixCount, bottle: b, recipe: recipe, pairs: pairs, poured: poured, amount: amount,
                           before: before, after: after)
        }
        return nil
    }

    /// The pour landed in a cauldron and mixed: the ingredients swirl into the new potion now
    /// (`MixSwirl`), with a brewing sound and, for VoiceOver, a line naming what was brewed.
    /// When the swirl has settled, a cauldron the mix `completes` is corked, a win is announced
    /// and a pour that waited for the cauldron starts.
    private func startMix(_ mark: MixMark, completes: Bool, reduceMotion: Bool) {
        mixes.append(mark)
        emit(.mixed(bottle: mark.bottle))
        let recipe = mark.recipe
        AccessibilityNotification.Announcement(
            String(localized: "Flask \(mark.bottle + 1) brewed \(2 * mark.pairs) \(Palette.potionName(recipe.result.rawValue)) from \(Palette.potionName(mark.poured.rawValue)) and \(Palette.potionName(mark.partner.rawValue))",
                   comment: "VoiceOver: a pour mixed in a cauldron; the arguments are the flask number, how many layers were brewed, the new potion and the two ingredients")).post()
        let lastID = mark.id
        mixClearTask?.cancel()
        mixClearTask = Task {
            let duration = reduceMotion ? MixPose.reducedDuration : MixPose.duration
            try? await Task.sleep(for: .seconds((duration + 0.05) * DebugTiming.slow))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                self.mixes.removeAll { $0.id <= lastID }
                if completes, self.completions.indices.contains(mark.bottle) {
                    self.completions[mark.bottle] += 1
                    self.emit(.flaskCompleted(bottles: [mark.bottle]))
                }
                if case .won(let stars) = self.status { self.emit(.levelWon(stars: stars)) }
                // A pour that waited for this cauldron starts now.
                self.replayQueuedTaps()
            }
        }
    }

    /// Events newer than `id` (all kept events for nil), oldest first.
    func feedback(after id: Int?) -> [Feedback] {
        guard let id else { return feedback }
        return feedback.filter { $0.id > id }
    }

    private func emit(_ event: FeedbackEvent) {
        feedbackCount += 1
        feedback.append(Feedback(id: feedbackCount, event: event))
        if feedback.count > 16 { feedback.removeFirst(feedback.count - 16) }
    }

    private func afterStateChange() {
        analysisTask?.cancel()
        hintTask?.cancel()
        isThinking = false
        if state.isSolved {
            let best = minMoves ?? moveCount
            let earned = StarRating.stars(moves: moveCount, minMoves: best)
            status = .won(stars: earned)
            if !isDemo { progress?.record(stars: earned, for: level.id) }
            if let daily, let dailyDate, dailyOutcome == nil, !isDemo {
                dailyOutcome = daily.record(date: dailyDate, moves: moveCount, minMoves: best, usedHint: usedHint)
            }
            return
        }
        if state.legalMoves().isEmpty {
            status = .stuck
            return
        }
        status = .playing
        // Check solvability (and cache the solution for Hint) off the main thread.
        let current = state
        analysisTask = Task {
            let result = await Self.solve(current)
            guard !Task.isCancelled, current == self.state else { return }
            self.handle(result, for: current)
        }
    }

    private func handle(_ result: SolverResult, for analyzed: GameState) {
        switch result {
        case .solved(let moves, _):
            solution = (analyzed, moves)
            if minMoves == nil && moveCount == 0 { minMoves = moves.count }
        case .unsolvable:
            if !isWon { status = .stuck }
        case .unknown:
            break
        }
    }

    /// Solves off the main actor. Cancelling the calling task stops the solver too
    /// (a detached task doesn't inherit cancellation, so it is forwarded).
    nonisolated private static func solve(_ state: GameState) async -> SolverResult {
        let work = Task.detached(priority: .userInitiated) {
            Solver().solve(state, limits: solverLimits)
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    private func showHint(_ move: Move) {
        if let dailyDate {
            usedHint = true
            daily?.markHintUsed(on: dailyDate)
        }
        hint = move
        hintMessage = nil
        scheduleHintClear()
    }

    private func flash(_ message: String) {
        hintMessage = message
        scheduleHintClear(after: .seconds(2.5))
        // VoiceOver hears the line too (e.g. why an essence flask refused a pour).
        AccessibilityNotification.Announcement(message).post()
    }

    private func scheduleHintClear(after delay: Duration = .seconds(1.6)) {
        hintClearTask?.cancel()
        hintClearTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.hint = nil
            self.hintMessage = nil
        }
    }

    private func clearHint() {
        hintClearTask?.cancel()
        hint = nil
        hintMessage = nil
    }

    #if DEBUG
    /// Dev aid: plays the first `moves` optimal moves through `tap(bottle:)`, like a player would.
    func debugPlayOptimal(moves: Int) async {
        isDemo = true
        guard case .solved(let solution, _) = await Self.solve(state) else { return }
        for move in solution.prefix(moves) {
            while pour != nil || !queuedTaps.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(450))
            tap(bottle: move.from)
            try? await Task.sleep(for: .milliseconds(250))
            tap(bottle: move.to)
        }
    }

    /// Dev aid: plays one legal pour out of a flask that holds ice (the potion above the ice
    /// pours; the ice and what's under it stay), to see the pinned layers in flight. Prefers a
    /// pour onto a matching potion over one into an empty flask.
    func debugIcePour() {
        let n = state.bottles.count
        let moves = (0..<n).flatMap { from in (0..<n).map { Move(from: from, to: $0) } }
            .filter { $0.from != $0.to && state.bottles[$0.from].holdsIce && Rules.isLegal($0, in: state) }
        guard let move = moves.first(where: { !state.bottles[$0.to].isEmpty }) ?? moves.first else { return }
        tap(bottle: move.from)
        tap(bottle: move.to)
    }

    /// Dev aid: tries one pour a flask modifier refuses (an essence flask, a tap flask; else
    /// picks up a funnel flask), to see the flare and message.
    func debugRefusedPour() {
        let n = state.bottles.count
        for from in 0..<n {
            for to in 0..<n where from != to {
                guard let refusal = Rules.refusal(of: Move(from: from, to: to), in: state),
                      Self.explains(refusal.modifier), refusal.modifier != .funnel else { continue }
                tap(bottle: from)
                // A flask that can't be picked up (ice on top) already refused.
                if selected == from { tap(bottle: to) }
                return
            }
        }
        if let funnel = state.bottles.indices.first(where: { !state.bottles[$0].isEmpty && state.bottles[$0].isFunnel }) {
            tap(bottle: funnel)
            return
        }
        // A pour a twin chain refuses (into a twin from a third flask first, else twin to twin).
        let refused = (0..<n).flatMap { from in (0..<n).map { Move(from: from, to: $0) } }
            .filter { $0.from != $0.to && Rules.linkRefusal(of: $0, in: state) != nil }
        if let move = refused.first(where: { state.twin(of: $0.from) == nil }) ?? refused.first {
            tap(bottle: move.from)
            if selected == move.from { tap(bottle: move.to) }
        }
    }

    /// Dev aid: plays one legal pour that uses a link (part of it runs through an overflow pipe,
    /// else one split between twins), to see it in flight.
    func debugLinkPour() {
        let n = state.bottles.count
        let pours = (0..<n).flatMap { from in (0..<n).map { Move(from: from, to: $0) } }
            .filter { $0.from != $0.to }
            .compactMap { Rules.resolve(state, afterAction: .pour($0))?.pour }
            .filter { !$0.shares.isEmpty }
        let overflow = pours.filter { $0.shares.contains { $0.route == .overflow } }
        // A pour that fills the first flask partly and then runs on reads best.
        guard let pour = overflow.first(where: { $0.targetAmount > 0 }) ?? overflow.first ?? pours.first else { return }
        tap(bottle: pour.move.from)
        tap(bottle: pour.move.to)
    }
    #endif
}
