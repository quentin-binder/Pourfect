import BottleSortCore
import Foundation

/// How the board splits its flasks into rows, and where linked flasks go after the shuffle.
enum BoardLayout {
    /// At most this many flasks share a row.
    static let maxPerRow = 7

    /// Flasks per row (the last row may hold fewer).
    static func perRow(count: Int) -> Int {
        let rows = max(1, Int((Double(count) / Double(maxPerRow)).rounded(.up)))
        return max(1, Int((Double(count) / Double(rows)).rounded(.up)))
    }

    /// The bottle indices of each row, top row first.
    static func rows(count: Int) -> [[Int]] {
        let perRow = perRow(count: count)
        return stride(from: 0, to: count, by: perRow).map { Array($0..<min($0 + perRow, count)) }
    }

    /// `state` (already shuffled) with the two flasks of every link side by side in one row, so
    /// a chain or a pipe is short and never crosses the board (DECISIONS 187). The flasks keep
    /// their shuffled order otherwise: the first flask of a pair stays where the shuffle put it
    /// (within its row) and its partner joins it; a pair that would straddle two rows waits
    /// for the next row while single flasks fill the gap. Changes nothing without links.
    static func keepingLinksTogether(_ state: GameState) -> GameState {
        guard !state.links.isEmpty else { return state }
        let count = state.bottles.count
        // Units in shuffled order: a linked pair, or one flask.
        var units: [[Int]] = []
        var placed = Set<Int>()
        for i in 0..<count where !placed.contains(i) {
            let partner = state.link(at: i).map { $0.endpoints.0 == i ? $0.endpoints.1 : $0.endpoints.0 }
            if let partner, partner != i, !placed.contains(partner) {
                units.append([i, partner])
                placed.formUnion([i, partner])
            } else {
                units.append([i])
                placed.insert(i)
            }
        }
        var order: [Int] = []
        for row in rows(count: count) {
            var room = row.count
            while room > 0, !units.isEmpty {
                // The next unit that fits this row; a pair only when no single flask is left.
                let index = units.firstIndex { $0.count <= room } ?? 0
                let unit = units.remove(at: index)
                order += unit
                room -= unit.count
            }
        }
        return state.permuted(by: order)
    }
}
