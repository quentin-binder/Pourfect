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
}
