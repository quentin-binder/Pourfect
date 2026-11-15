import BottleSortCore
import SwiftUI

/// The fixed liquid palette — the only place colors are defined.
/// Index = `ColorID.rawValue`. Chosen to stay distinct from each other.
enum Palette {
    static let colors: [Color] = [
        Color(red: 0.90, green: 0.20, blue: 0.22),  //  0 red
        Color(red: 0.16, green: 0.45, blue: 0.95),  //  1 blue
        Color(red: 0.98, green: 0.80, blue: 0.15),  //  2 yellow
        Color(red: 0.20, green: 0.72, blue: 0.33),  //  3 green
        Color(red: 0.62, green: 0.32, blue: 0.86),  //  4 purple
        Color(red: 1.00, green: 0.55, blue: 0.10),  //  5 orange
        Color(red: 0.35, green: 0.85, blue: 0.95),  //  6 cyan
        Color(red: 0.98, green: 0.45, blue: 0.70),  //  7 pink
        Color(red: 0.50, green: 0.30, blue: 0.16),  //  8 brown
        Color(red: 0.60, green: 0.85, blue: 0.20),  //  9 lime
        Color(red: 0.08, green: 0.20, blue: 0.50),  // 10 navy
        Color(red: 0.62, green: 0.64, blue: 0.68),  // 11 grey
    ]

    static func color(_ id: Int) -> Color {
        colors.indices.contains(id) ? colors[id] : .black
    }

    /// Potion names of the palette colors (same index as `colors`), spoken by VoiceOver and
    /// usable in tutorials or legends. Distinct from the rune names on purpose: these name the brew.
    static let potionNames: [String] = [
        String(localized: "Dragon's Blood", comment: "Potion name of the red liquid"),
        String(localized: "Sapphire Draught", comment: "Potion name of the blue liquid"),
        String(localized: "Liquid Sunlight", comment: "Potion name of the yellow liquid"),
        String(localized: "Forest Elixir", comment: "Potion name of the green liquid"),
        String(localized: "Moonshade", comment: "Potion name of the purple liquid"),
        String(localized: "Phoenix Ember", comment: "Potion name of the orange liquid"),
        String(localized: "Mermaid Teal", comment: "Potion name of the cyan liquid"),
        String(localized: "Fairy Blush", comment: "Potion name of the pink liquid"),
        String(localized: "Mandrake Root", comment: "Potion name of the brown liquid"),
        String(localized: "Goblin Lime", comment: "Potion name of the lime liquid"),
        String(localized: "Midnight Ink", comment: "Potion name of the navy liquid"),
        String(localized: "Ghost Mist", comment: "Potion name of the grey liquid"),
    ]

    static func potionName(_ id: Int) -> String {
        potionNames.indices.contains(id) ? potionNames[id] : String(localized: "Unknown potion")
    }

    /// Key / lock colors, by `KeyID.rawValue` (a key and the bottle it opens share one).
    /// Metallic tones so they don't read as liquids.
    static let keyColors: [Color] = [
        Color(red: 0.85, green: 0.50, blue: 0.30),  //  0 copper
        Color(red: 0.95, green: 0.76, blue: 0.20),  //  1 gold (generated levels number keys from 1)
        Color(red: 0.55, green: 0.80, blue: 1.00),  //  2 steel blue
        Color(red: 0.95, green: 0.45, blue: 0.85),  //  3 magenta
        Color(red: 0.45, green: 0.95, blue: 0.70),  //  4 mint
    ]

    static func keyColor(_ id: Int) -> Color {
        keyColors.indices.contains(id) ? keyColors[id] : .white
    }

    /// Names of the rune-key metals (same index as `keyColors`), for VoiceOver.
    static let keyNames: [String] = [
        String(localized: "Copper", comment: "Metal of a rune key and its seal"),
        String(localized: "Gold", comment: "Metal of a rune key and its seal"),
        String(localized: "Steel", comment: "Metal of a rune key and its seal"),
        String(localized: "Rose Gold", comment: "Metal of a rune key and its seal"),
        String(localized: "Verdigris", comment: "Metal of a rune key and its seal"),
    ]

    static func keyName(_ id: Int) -> String {
        keyNames.indices.contains(id) ? keyNames[id] : String(localized: "Silver", comment: "Metal of a rune key and its seal")
    }

    /// Background of a key layer (dark, so the key icon stands out from the liquids).
    static let keyLayer = Color(white: 0.20)
    /// A layer shown as "?" in hidden-layers mode.
    static let hiddenLayer = Color(white: 0.55)
}

extension Layer {
    /// Fill color of a layer when drawn as liquid (the key-layer backing for keys).
    var liquidColor: Color {
        switch self {
        case .color(let id): return Palette.color(id.rawValue)
        case .key: return Palette.keyLayer
        }
    }

    /// What VoiceOver says for this layer, e.g. "Dragon's Blood" or "Gold rune key".
    var spokenName: String {
        switch self {
        case .color(let id): return Palette.potionName(id.rawValue)
        case .key(let key): return String(localized: "\(Palette.keyName(key.rawValue)) rune key")
        }
    }
}

extension Bottle {
    /// VoiceOver description of a flask's contents, bottom to top, with runs of the same potion
    /// grouped. The bottom `hiddenLayers` are murky and not named.
    func spokenContents(hiddenLayers: Int) -> String {
        var parts: [String] = []
        if hiddenLayers > 0 {
            parts.append(String(localized: "\(hiddenLayers) murky", comment: "Count of hidden layers in a flask"))
        }
        for run in BottleView.runs(layers, hiddenLayers: hiddenLayers) where !run.hidden {
            parts.append(run.count == 1 ? run.layer.spokenName
                                        : String(localized: "\(run.count) \(run.layer.spokenName)",
                                                 comment: "Layer count and potion name, e.g. 2 Moonshade"))
        }
        var text = parts.isEmpty ? String(localized: "Empty") : parts.joined(separator: ", ")
        if Rules.isCompleted(self) { text += ", " + String(localized: "corked") }
        if let key = lockedBy {
            text += ", " + String(localized: "sealed with a \(Palette.keyName(key.rawValue)) rune",
                                  comment: "A sealed flask; the argument is the key metal")
        }
        return text
    }
}
