import BottleSortCore
import Foundation
import Match3Core

/// The bundled ingredient-gathering episodes (`gathering_NN.json`, R9), loaded once.
/// A broken file is skipped and reported in `loadErrors`.
enum Match3Library {
    static let shared: Library = load()

    struct Library {
        let episodes: [M3EpisodeFile]
        let loadErrors: [String]

        func level(id: String) -> M3Level? {
            for file in episodes { if let level = file.levels.first(where: { $0.id == id }) { return level } }
            return nil
        }

        func episode(of levelID: String) -> M3EpisodeFile? {
            episodes.first { $0.levels.contains { $0.id == levelID } }
        }

        /// The level after `levelID` in its episode, if any.
        func next(after levelID: String) -> M3Level? {
            guard let file = episode(of: levelID), let i = file.levels.firstIndex(where: { $0.id == levelID }),
                  i + 1 < file.levels.count else { return nil }
            return file.levels[i + 1]
        }
    }

    static func load(bundle: Bundle = .main) -> Library {
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("gathering_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var files: [M3EpisodeFile] = []
        var errors: [String] = []
        for url in urls {
            do {
                let file = try M3EpisodeFile.decode(Data(contentsOf: url))
                files.append(file)
            } catch {
                errors.append("\(url.lastPathComponent): \(error)")
            }
        }
        return Library(episodes: files.sorted { $0.episode.number < $1.episode.number }, loadErrors: errors)
    }
}
