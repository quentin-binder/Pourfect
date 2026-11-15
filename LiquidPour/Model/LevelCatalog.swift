import BottleSortCore
import Foundation
import Observation

/// The levels shipped in the app bundle.
@Observable
final class LevelCatalog {
    let levels: [LevelDefinition]
    let loadError: String?

    init(levels: [LevelDefinition], loadError: String? = nil) {
        self.levels = levels
        self.loadError = loadError
    }

    static func loadBundled(named name: String = "pack_01") -> LevelCatalog {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            return LevelCatalog(levels: [], loadError: "\(name).json is missing from the app bundle")
        }
        do {
            return LevelCatalog(levels: try LevelLoader.load(contentsOf: url).levels)
        } catch {
            return LevelCatalog(levels: [], loadError: "\(error)")
        }
    }
}
