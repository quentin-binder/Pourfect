import BottleSortCore
import Foundation
import Observation

/// One bundled level pack (`pack_NN.json`).
struct LevelPackInfo: Identifiable, Hashable {
    let id: String          // file name without extension, e.g. "pack_02"
    let name: String
    let subtitle: String?
    let levels: [LevelDefinition]
}

/// All level packs shipped in the app bundle, in file-name order.
@Observable
final class LevelCatalog {
    let packs: [LevelPackInfo]
    let loadErrors: [String]

    init(packs: [LevelPackInfo], loadErrors: [String] = []) {
        self.packs = packs
        self.loadErrors = loadErrors
    }

    func pack(id: String) -> LevelPackInfo? { packs.first { $0.id == id } }

    /// Loads every `pack_*.json` in the main bundle. A broken pack is skipped and reported.
    static func loadBundled(bundle: Bundle = .main) -> LevelCatalog {
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("pack_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var packs: [LevelPackInfo] = []
        var errors: [String] = []
        for url in urls {
            let id = url.deletingPathExtension().lastPathComponent
            do {
                let pack = try LevelLoader.load(contentsOf: url)
                packs.append(LevelPackInfo(id: id, name: pack.name ?? id, subtitle: pack.subtitle, levels: pack.levels))
            } catch {
                errors.append("\(id): \(error)")
            }
        }
        if urls.isEmpty { errors.append("No level packs found in the app bundle") }
        return LevelCatalog(packs: packs, loadErrors: errors)
    }
}
