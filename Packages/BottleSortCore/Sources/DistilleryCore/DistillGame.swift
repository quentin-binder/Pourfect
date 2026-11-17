import BottleSortCore

/// One tap on the board.
public struct DistillTap: Hashable, Sendable, Codable {
    public var pos: DistillPos
    /// Clockwise (tap / click); false is counter-clockwise (long-press / right-click).
    public var clockwise: Bool
    public init(_ pos: DistillPos, clockwise: Bool = true) {
        self.pos = pos
        self.clockwise = clockwise
    }
}

/// What a tap changed, for the app's animations.
public struct DistillTapResult: Hashable, Sendable {
    public var tap: DistillTap
    public var oldRotation: Int
    public var newRotation: Int
    public var flow: DistillFlow
    /// Channels wet after the tap that were dry before (animate their fill in `tick` order).
    public var newlyWet: [DistillNodeRef]
    /// Channels that ran dry (drain them).
    public var newlyDry: [DistillNodeRef]
    /// Target flasks (indices) that now hold their own color and didn't before.
    public var newlySatisfied: [Int]
    public var didWin: Bool
}

/// Stars by taps: 3 at the minimum, 2 within `margin(minTaps:)` more, else 1 (DECISIONS 272).
public enum DistillStars {
    /// Two-star margin: 2 + minTaps / 5 extra taps (a wrong turn costs two taps: there and back).
    public static func margin(minTaps: Int) -> Int { 2 + max(0, minTaps) / 5 }

    public static func stars(taps: Int, minTaps: Int) -> Int {
        if taps <= minTaps { return 3 }
        if taps <= minTaps + margin(minTaps: minTaps) { return 2 }
        return 1
    }
}

/// A distillery level in play: taps, undo, restart, live flow. No tap limit; the level is always finishable.
public struct DistillGame: Sendable {
    public let level: DistillLevel
    public private(set) var board: DistillBoard
    public private(set) var history: [DistillTap] = []
    public private(set) var flow: DistillFlow

    public init(level: DistillLevel) {
        self.level = level
        board = level.board
        flow = level.board.flow
    }

    /// Taps that count: undone taps don't.
    public var taps: Int { history.count }
    public var canUndo: Bool { !history.isEmpty && !isWon }
    public var isWon: Bool { flow.isWon }
    public var stars: Int { DistillStars.stars(taps: taps, minTaps: level.minTaps) }

    /// Whether tapping this cell turns something.
    public func canTap(_ pos: DistillPos) -> Bool {
        guard board.contains(pos), !isWon else { return false }
        if case .piece(let piece) = board.kind(at: pos) { return piece.isRotatable }
        return false
    }

    /// Turns the piece a quarter; nil (nothing counted) on a riveted piece, a cross, an empty cell, a source
    /// or target, or after the win.
    @discardableResult
    public mutating func tap(_ pos: DistillPos, clockwise: Bool = true) -> DistillTapResult? {
        guard canTap(pos) else { return nil }
        let tap = DistillTap(pos, clockwise: clockwise)
        let old = board[pos].rotation
        board[pos].rotation = (old + (clockwise ? 1 : 3)) % 4
        history.append(tap)
        return refresh(tap: tap, oldRotation: old)
    }

    /// Takes the last tap back (not after the win).
    @discardableResult
    public mutating func undo() -> DistillTapResult? {
        guard canUndo, let last = history.popLast() else { return nil }
        let old = board[last.pos].rotation
        board[last.pos].rotation = (old + (last.clockwise ? 3 : 1)) % 4
        return refresh(tap: DistillTap(last.pos, clockwise: !last.clockwise), oldRotation: old)
    }

    /// Back to the level's start, taps at 0.
    public mutating func restart() {
        board = level.board
        history = []
        flow = board.flow
    }

    private mutating func refresh(tap: DistillTap, oldRotation: Int) -> DistillTapResult {
        let before = flow
        flow = board.flow
        let wasWet = before.wetNodes, isWet = flow.wetNodes
        let newlyWet = flow.nodes.filter { $0.liquid.isWet && !wasWet.contains(DistillNodeRef(pos: $0.pos, channel: $0.channel)) }
            .sorted { ($0.tick, $0.pos, $0.channel) < ($1.tick, $1.pos, $1.channel) }
            .map { DistillNodeRef(pos: $0.pos, channel: $0.channel) }
        let newlyDry = wasWet.subtracting(isWet).sorted()
        let wanted = board.targets.map(\.color)
        let satisfied = flow.received.indices.filter {
            flow.received[$0].color == wanted[$0] && before.received[$0].color != wanted[$0]
        }
        return DistillTapResult(tap: tap, oldRotation: oldRotation, newRotation: board[tap.pos].rotation, flow: flow,
                                newlyWet: newlyWet, newlyDry: newlyDry, newlySatisfied: satisfied, didWin: flow.isWon)
    }

    /// A tap on the way to the cheapest win from here (nil when won or unsolvable within the limits).
    public func hint(limits: DistillSolverLimits = .init()) -> DistillTap? {
        guard !isWon else { return nil }
        return DistillSolver.hint(board, limits: limits)
    }
}
