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
}
