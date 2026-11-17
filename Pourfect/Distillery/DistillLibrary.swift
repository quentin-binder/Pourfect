import DistilleryCore
import Foundation

/// The bundled distillery packs (`distillery_*.json`, R10): the three workshop stages and the
/// Expert and Master challenge packs, loaded once. A broken file is skipped and reported in `loadErrors`.
enum DistillLibrary {
    static let shared: Library = load()

    struct Library {
        /// The packs in `DistillPack` order (stages 1–3, then Expert and Master).
        let packs: [(pack: DistillPack, file: DistillPackFile)]
        let loadErrors: [String]

        func file(_ pack: DistillPack) -> DistillPackFile? { packs.first { $0.pack == pack }?.file }

        func level(id: String) -> DistillLevel? {
            for entry in packs { if let level = entry.file.levels.first(where: { $0.id == id }) { return level } }
            return nil
        }

        /// The pack holding `levelID`, if any.
        func pack(of levelID: String) -> DistillPack? {
            packs.first { $0.file.levels.contains { $0.id == levelID } }?.pack
        }

        /// The level after `levelID` in its pack, if any.
        func next(after levelID: String) -> DistillLevel? {
            guard let file = packs.first(where: { $0.file.levels.contains { $0.id == levelID } })?.file,
                  let i = file.levels.firstIndex(where: { $0.id == levelID }), i + 1 < file.levels.count else { return nil }
            return file.levels[i + 1]
        }

        /// 1-based position of a level in its pack ("Still 7").
        func number(of levelID: String) -> Int? {
            for entry in packs {
                if let i = entry.file.levels.firstIndex(where: { $0.id == levelID }) { return i + 1 }
            }
            return nil
        }
    }

    static func load(bundle: Bundle = .main) -> Library {
        var packs: [(DistillPack, DistillPackFile)] = []
        var errors: [String] = []
        for pack in DistillPack.allCases {
            guard let url = bundle.url(forResource: pack.fileName, withExtension: nil)
                    ?? bundle.url(forResource: (pack.fileName as NSString).deletingPathExtension, withExtension: "json") else {
                errors.append("\(pack.fileName): missing")
                continue
            }
            do {
                packs.append((pack, try DistillPackFile.decode(Data(contentsOf: url))))
            } catch {
                errors.append("\(url.lastPathComponent): \(error)")
            }
        }
        return Library(packs: packs, loadErrors: errors)
    }
}
