import Foundation

/// A short story scene between the apprentice and the old alchemist (R7). The lines themselves
/// live in the app (String catalog); the core decides when a scene plays. DECISIONS 236.
public enum StoryScene: Hashable, Sendable {
    /// Plays the first time chapter N's recipe list is opened.
    case chapter(Int)
    /// Plays once after the last recipe of the final chapter is solved for the first time.
    case ending
    /// Plays the first time ingredient-gathering episode N (R9, match-3) is opened.
    case gathering(Int)
    /// Plays the first time distillery workshop stage N (R10, pipe rotation) is opened.
    case distillery(Int)
    /// Plays the first time hidden-object room N (R11: 1 attic, 2 market, 3 hoard) is opened.
    case hidden(Int)

    /// Stable id saved in the "seen" set: `chapter.3`, `ending`, `gathering.3`, `distillery.2`, `hidden.attic`.
    public var id: String {
        switch self {
        case .chapter(let n): "chapter.\(n)"
        case .ending: "ending"
        case .gathering(let n): "gathering.\(n)"
        case .distillery(let n): "distillery.\(n)"
        case .hidden(let n): "hidden.\(Story.hiddenRoomName(n) ?? "\(n)")"
        }
    }

    public init?(id: String) {
        if id == "ending" { self = .ending; return }
        if id.hasPrefix("gathering."), let n = Int(id.dropFirst("gathering.".count)), Story.gatherings.contains(n) {
            self = .gathering(n)
            return
        }
        if id.hasPrefix("distillery."), let n = Int(id.dropFirst("distillery.".count)), Story.distilleries.contains(n) {
            self = .distillery(n)
            return
        }
        if id.hasPrefix("hidden."), let n = Story.hiddenRoomNames.firstIndex(of: String(id.dropFirst("hidden.".count))) {
            self = .hidden(n + 1)
            return
        }
        guard id.hasPrefix("chapter."), let n = Int(id.dropFirst("chapter.".count)),
              Story.chapters.contains(n) else { return nil }
        self = .chapter(n)
    }
}

public enum Story {
    /// Chapters with an opening scene.
    public static let chapters = 1...10
    /// The chapter whose last recipe leads to the ending.
    public static let finalChapter = 10
    /// Ingredient-gathering episodes with an opening scene (R9; the same numbers as
    /// `M3Progression.episodes`, whose `sceneID` is this scene's id).
    public static let gatherings = 1...10
    /// Distillery workshop stages with an opening scene (R10; `DistillProgression.sceneID` gives the same ids).
    public static let distilleries = 1...3
    /// Hidden-object rooms with an opening scene (R11), by number; their ids use the room names
    /// (`hidden.attic`, the same as `HiddenProgression.sceneID`).
    public static let hiddenRooms = 1...3
    public static let hiddenRoomNames = ["attic", "market", "hoard"]

    public static func hiddenRoomName(_ number: Int) -> String? {
        hiddenRooms.contains(number) ? hiddenRoomNames[number - 1] : nil
    }

    /// The scene to play when hidden-object room `number` is opened, if it hasn't been seen.
    public static func sceneOnOpening(hiddenRoom number: Int, seen: Set<String>) -> StoryScene? {
        guard hiddenRooms.contains(number) else { return nil }
        let scene = StoryScene.hidden(number)
        return seen.contains(scene.id) ? nil : scene
    }

    /// The scene to play when distillery stage `number` is opened, if it hasn't been seen.
    public static func sceneOnOpening(distillery number: Int, seen: Set<String>) -> StoryScene? {
        guard distilleries.contains(number) else { return nil }
        let scene = StoryScene.distillery(number)
        return seen.contains(scene.id) ? nil : scene
    }

    /// The scene to play when gathering episode `number` is opened, if it hasn't been seen.
    public static func sceneOnOpening(gathering number: Int, seen: Set<String>) -> StoryScene? {
        guard gatherings.contains(number) else { return nil }
        let scene = StoryScene.gathering(number)
        return seen.contains(scene.id) ? nil : scene
    }

    /// The scene to play when chapter `number` is opened, if it has one and it hasn't been seen.
    public static func sceneOnOpening(chapter number: Int, seen: Set<String>) -> StoryScene? {
        guard chapters.contains(number) else { return nil }
        let scene = StoryScene.chapter(number)
        return seen.contains(scene.id) ? nil : scene
    }

    /// The scene to play after `recipeID` is solved: the ending when it is the final chapter's
    /// last recipe (`finalRecipeID`) and the ending hasn't been seen.
    public static func sceneAfterWin(recipeID: String, finalRecipeID: String?, seen: Set<String>) -> StoryScene? {
        guard let finalRecipeID, recipeID == finalRecipeID, !seen.contains(StoryScene.ending.id) else { return nil }
        return .ending
    }

    /// The recipe after which the ending plays: the final chapter's last own recipe. Customer
    /// orders (R7) are appended after it as bonus recipes, so they never hold the ending back.
    public static func finalRecipeID(of levels: [LevelDefinition]) -> String? {
        levels.last { !$0.isCustomerOrder }?.id
    }

    /// Scenes chapter `number`'s screen can replay ("Story"): its opening, and for the final
    /// chapter also the ending once it has been seen.
    public static func replayable(chapter number: Int, seen: Set<String>) -> [StoryScene] {
        guard chapters.contains(number) else { return [] }
        var scenes: [StoryScene] = [.chapter(number)]
        if number == finalChapter, seen.contains(StoryScene.ending.id) { scenes.append(.ending) }
        return scenes
    }
}
