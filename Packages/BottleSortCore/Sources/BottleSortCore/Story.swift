import Foundation

/// A short story scene between the apprentice and the old alchemist (R7). The lines themselves
/// live in the app (String catalog); the core decides when a scene plays. DECISIONS 400.
public enum StoryScene: Hashable, Sendable {
    /// Plays the first time chapter N's recipe list is opened.
    case chapter(Int)
    /// Plays once after the last recipe of the final chapter is solved for the first time.
    case ending

    /// Stable id saved in the "seen" set: `chapter.3`, `ending`.
    public var id: String {
        switch self {
        case .chapter(let n): "chapter.\(n)"
        case .ending: "ending"
        }
    }

    public init?(id: String) {
        if id == "ending" { self = .ending; return }
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

    /// Scenes chapter `number`'s screen can replay ("Story"): its opening, and for the final
    /// chapter also the ending once it has been seen.
    public static func replayable(chapter number: Int, seen: Set<String>) -> [StoryScene] {
        guard chapters.contains(number) else { return [] }
        var scenes: [StoryScene] = [.chapter(number)]
        if number == finalChapter, seen.contains(StoryScene.ending.id) { scenes.append(.ending) }
        return scenes
    }
}
