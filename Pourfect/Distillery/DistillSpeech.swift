import BottleSortCore
import DistilleryCore
import SwiftUI

/// What VoiceOver says for a distillery cell (R10): piece type, the sides it opens to, and what it carries.
enum DistillSpeech {
    static func direction(_ d: DistillDir) -> String {
        switch d {
        case .north: String(localized: "north", comment: "Distillery direction, spoken by VoiceOver")
        case .east: String(localized: "east", comment: "Distillery direction, spoken by VoiceOver")
        case .south: String(localized: "south", comment: "Distillery direction, spoken by VoiceOver")
        case .west: String(localized: "west", comment: "Distillery direction, spoken by VoiceOver")
        }
    }

    static func shapeName(_ shape: DistillShape) -> String {
        switch shape {
        case .empty: String(localized: "Empty", comment: "Distillery: an empty cell")
        case .cap: String(localized: "End cap", comment: "Distillery piece: a pipe closed at one end")
        case .straight: String(localized: "Straight pipe", comment: "Distillery piece")
        case .elbow: String(localized: "Elbow", comment: "Distillery piece: a bent pipe")
        case .tee: String(localized: "Splitter", comment: "Distillery piece: a T-shaped junction")
        case .cross: String(localized: "Crossing", comment: "Distillery piece: two pipes crossing without mixing")
        }
    }

    static func liquidName(_ liquid: DistillLiquid) -> String? {
        switch liquid {
        case .dry: nil
        case .murky: String(localized: "murky", comment: "Distillery: two colors met in this pipe")
        case .liquid(let c): Palette.potionName(c.rawValue)
        }
    }

    static func cell(_ pos: DistillPos, board: DistillBoard, flow: DistillFlow) -> Text {
        var parts: [String] = []
        switch board.kind(at: pos) {
        case .source(let i):
            let source = board.sources[i]
            parts.append(String(localized: "Cauldron of \(Palette.potionName(source.color.rawValue)), pours \(direction(source.outlet))",
                                comment: "VoiceOver: a distillery source; arguments are the potion and the outlet side"))
        case .target(let i):
            let target = board.targets[i]
            parts.append(String(localized: "Flask \(i + 1), wants \(Palette.potionName(target.color.rawValue)), fills from \(direction(target.inlet))",
                                comment: "VoiceOver: a distillery target flask; arguments are its number, wanted potion and inlet side"))
            switch flow.received[i] {
            case .dry: parts.append(String(localized: "empty", comment: "VoiceOver: a distillery flask holds nothing yet"))
            case .murky: parts.append(String(localized: "holds murky liquid", comment: "VoiceOver: a distillery flask"))
            case .liquid(let c):
                parts.append(c == target.color
                             ? String(localized: "filled", comment: "VoiceOver: a distillery flask holds its own color")
                             : String(localized: "holds \(Palette.potionName(c.rawValue)), wrong potion",
                                      comment: "VoiceOver: a distillery flask holds another color"))
            }
        case .piece(let piece):
            parts.append(shapeName(piece.shape))
            if piece.shape == .cross {
                parts.append(String(localized: "north to south and east to west, never mixing",
                                    comment: "VoiceOver: a distillery crossing's two pipes"))
            } else if piece.shape != .empty {
                let sides = DistillMask.dirs(piece.mask).map { direction($0) }
                parts.append(String(localized: "opens \(sides.formatted(.list(type: .and)))",
                                    comment: "VoiceOver: the sides a distillery pipe opens to"))
            }
            if piece.fixed {
                parts.append(String(localized: "riveted, can't turn", comment: "VoiceOver: a fixed distillery piece"))
            }
            if let coil = piece.coil {
                parts.append(String(localized: "heat coil, turns \(Palette.potionName(coil.from.rawValue)) into \(Palette.potionName(coil.to.rawValue))",
                                    comment: "VoiceOver: a distillery heat coil; arguments are the potions in and out"))
            }
            if let valve = piece.valve {
                parts.append(flow.isValveOpen(at: pos)
                             ? String(localized: "valve, open", comment: "VoiceOver: a distillery valve")
                             : String(localized: "valve, shut until flask \(valve + 1) is filled",
                                      comment: "VoiceOver: a distillery valve; the argument is the linked flask's number"))
            }
            let carried = flow.nodes(at: pos).compactMap { liquidName($0.liquid) }
            if !carried.isEmpty {
                parts.append(String(localized: "carries \(carried.formatted(.list(type: .and)))",
                                    comment: "VoiceOver: what flows through a distillery pipe"))
            }
        }
        if flow.leaks.contains(where: { $0.pos == pos }) {
            parts.append(String(localized: "leaking", comment: "VoiceOver: liquid drips out of this distillery pipe"))
        }
        let place = String(localized: "Row \(pos.r + 1), column \(pos.c + 1)", comment: "VoiceOver: a distillery cell's place")
        return Text(verbatim: parts.joined(separator: ", ") + ". " + place)
    }

    /// A one-line summary for the board's status ("2 of 3 flasks filled, 1 leak").
    static func status(_ flow: DistillFlow, targets: Int) -> String {
        var parts = [String(localized: "\(flow.satisfiedTargets) of \(targets) flasks filled",
                            comment: "VoiceOver: distillery progress")]
        if !flow.leaks.isEmpty {
            parts.append(String(localized: "dripping", comment: "VoiceOver: an open pipe end in the distillery drips"))
        }
        if flow.murkyCount > 0 {
            parts.append(String(localized: "colors mixing", comment: "VoiceOver: two colors met in the distillery"))
        }
        return parts.joined(separator: ", ")
    }
}
