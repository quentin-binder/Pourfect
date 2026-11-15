import BottleSortCore
import Foundation
import Observation

/// One bundled recipe pack: a main-path chapter (`chapter_NN.json`) or a challenge pack
/// (`challenge_*.json`).
struct LevelPackInfo: Identifiable, Hashable {
    let id: String          // file name without extension, e.g. "chapter_02"
    let name: String
    let subtitle: String?
    let kind: PackKind
    /// 1-based chapter number (chapters only).
    let chapter: Int?
    let introduces: [Mechanic]
    let levels: [LevelDefinition]

    var isChapter: Bool { kind == .chapter }
    var maxStars: Int { ChapterGate.maxStars(recipeCount: levels.count) }
}

/// All recipe packs shipped in the app bundle: chapters by number, then challenges by file name.
@Observable
final class LevelCatalog {
    let chapters: [LevelPackInfo]
    let challenges: [LevelPackInfo]
    let loadErrors: [String]

    init(packs: [LevelPackInfo], loadErrors: [String] = []) {
        self.chapters = packs.filter(\.isChapter).sorted { ($0.chapter ?? 0, $0.id) < ($1.chapter ?? 0, $1.id) }
        self.challenges = packs.filter { !$0.isChapter }.sorted { $0.id < $1.id }
        self.loadErrors = loadErrors
    }

    /// Chapters, then challenges (the numbering `-LPOpenPack` uses).
    var packs: [LevelPackInfo] { chapters + challenges }

    func pack(id: String) -> LevelPackInfo? { packs.first { $0.id == id } }
    func chapter(_ number: Int) -> LevelPackInfo? { chapters.first { $0.chapter == number } }

    /// File-name prefixes the catalog loads. `pack_` keeps older files working.
    static let filePrefixes = ["chapter_", "challenge_", "pack_"]

    /// Loads every recipe file in the main bundle. A broken file is skipped and reported.
    static func loadBundled(bundle: Bundle = .main) -> LevelCatalog {
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { url in filePrefixes.contains { url.lastPathComponent.hasPrefix($0) } }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var packs: [LevelPackInfo] = []
        var errors: [String] = []
        for url in urls {
            let id = url.deletingPathExtension().lastPathComponent
            do {
                packs.append(info(id: id, pack: try LevelLoader.load(contentsOf: url)))
            } catch {
                errors.append("\(id): \(error)")
            }
        }
        // Two files claiming the same chapter: keep the first, report the rest.
        var seen = Set<Int>()
        packs = packs.filter { pack in
            guard let n = pack.chapter else { return true }
            if seen.insert(n).inserted { return true }
            errors.append("\(pack.id): chapter \(n) appears twice")
            return false
        }
        if urls.isEmpty { errors.append(String(localized: "No recipe chapters found in the app bundle")) }
        return LevelCatalog(packs: packs, loadErrors: errors)
    }

    /// Builds the app's view of a pack. Files without metadata still work: the kind and chapter
    /// number fall back to the file name (`chapter_NN` is chapter NN; anything else is a challenge).
    static func info(id: String, pack: LevelPack) -> LevelPackInfo {
        let numberFromName = id.hasPrefix("chapter_") ? Int(id.dropFirst("chapter_".count)) : nil
        let kind = pack.kind ?? (numberFromName != nil ? .chapter : .challenge)
        let chapter = kind == .chapter ? (pack.chapter ?? numberFromName) : nil
        return LevelPackInfo(id: id,
                             name: pack.name ?? pack.location ?? id,
                             subtitle: pack.subtitle,
                             kind: chapter == nil ? .challenge : kind,
                             chapter: chapter,
                             introduces: pack.introduces ?? [],
                             levels: pack.levels)
    }
}
