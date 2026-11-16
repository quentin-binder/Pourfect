import BottleSortCore
import Observation
import SwiftUI

/// Who speaks a story line (R7): the player's apprentice or the old alchemist.
enum StorySpeaker: Hashable {
    case apprentice, alchemist

    var name: String {
        switch self {
        case .apprentice: String(localized: "Apprentice", comment: "Story speaker name")
        case .alchemist: String(localized: "Alchemist", comment: "Story speaker name")
        }
    }

    func portrait(_ mood: StoryMood) -> ImageResource {
        switch (self, mood) {
        case (.apprentice, .neutral): .portraitApprenticeNeutral
        case (.apprentice, .happy): .portraitApprenticeHappy
        case (.apprentice, .worried): .portraitApprenticeWorried
        case (.alchemist, .neutral): .portraitAlchemistNeutral
        case (.alchemist, .happy): .portraitAlchemistHappy
        case (.alchemist, .worried): .portraitAlchemistWorried
        }
    }
}

/// The expression of the speaker's portrait for a line.
enum StoryMood: Hashable { case neutral, happy, worried }

struct StoryLine: Hashable {
    let speaker: StorySpeaker
    let mood: StoryMood
    let text: String
}

/// The story's lines: a short scene for each chapter's first opening and one ending (DECISIONS
/// 236). Each scene fits its chapter's place and the mechanic it brings. When a scene plays is
/// decided in the core (`Story`).
enum StoryScript {
    static func lines(_ scene: StoryScene) -> [StoryLine] {
        typealias L = StoryLine
        switch scene {
        case .chapter(1):
            return [
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Welcome to my cellar, young one. Every great alchemist starts down here, among the dusty flasks.", comment: "Story, chapter 1 (Apprentice Cellar)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "It's all mixed up! Is that three different potions in one flask?", comment: "Story, chapter 1 (Apprentice Cellar)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Pour onto a matching potion or into an empty flask. One potion per flask, and we'll have order by supper.", comment: "Story, chapter 1 (Apprentice Cellar)")),
                L(speaker: .apprentice, mood: .happy, text: String(localized: "Sorting potions. I can do that!", comment: "Story, chapter 1 (Apprentice Cellar)")),
            ]
        case .chapter(2):
            return [
                L(speaker: .apprentice, mood: .worried, text: String(localized: "This vault hasn't been opened in a hundred years. And these flasks are sealed shut!", comment: "Story, chapter 2 (Rune Vault)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Rune seals. Somewhere in the other flasks lies a rune-stone key of the same metal. Pour it onto its seal and the lock gives way.", comment: "Story, chapter 2 (Rune Vault)")),
                L(speaker: .apprentice, mood: .happy, text: String(localized: "A treasure hunt inside a puzzle. Best day ever.", comment: "Story, chapter 2 (Rune Vault)")),
            ]
        case .chapter(3):
            return [
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Mind your step. The marsh mist creeps into the flasks and clouds whatever lies beneath.", comment: "Story, chapter 3 (Misty Marsh)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "So I can't see what's at the bottom?", comment: "Story, chapter 3 (Misty Marsh)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Not until you pour off what's on top. A good alchemist is patient, and a little curious.", comment: "Story, chapter 3 (Misty Marsh)")),
            ]
        case .chapter(4):
            return [
                L(speaker: .apprentice, mood: .happy, text: String(localized: "So many books! Wait, that flask has a glowing rune on it.", comment: "Story, chapter 4 (Glyph Library)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "An essence flask. It takes only the potion its rune names, and politely refuses everything else.", comment: "Story, chapter 4 (Glyph Library)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Politely?", comment: "Story, chapter 4 (Glyph Library)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "It glares a little. Plan ahead and it will be your best helper.", comment: "Story, chapter 4 (Glyph Library)")),
            ]
        case .chapter(5):
            return [
                L(speaker: .alchemist, mood: .happy, text: String(localized: "The Glass Works! My old friend the glassblower makes the finest flasks in the land.", comment: "Story, chapter 5 (Glass Works)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Some of them look funny. That one has a skinny neck, and that one has a tap on its side!", comment: "Story, chapter 5 (Glass Works)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "A narrow neck lets one layer through at a time, a funnel only takes potions in, and a tap pours from the bottom. Each one changes how the potions flow.", comment: "Story, chapter 5 (Glass Works)")),
            ]
        case .chapter(6):
            return [
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Brr! My potions froze solid on the way up the mountain.", comment: "Story, chapter 6 (Frost Peak)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Frozen layers can't be poured. But watch the little numbers on the ice: every pour you make brings the thaw closer.", comment: "Story, chapter 6 (Frost Peak)")),
                L(speaker: .apprentice, mood: .happy, text: String(localized: "So I keep brewing and they melt on their own. Cold hands, warm heart!", comment: "Story, chapter 6 (Frost Peak)")),
            ]
        case .chapter(7):
            return [
                L(speaker: .alchemist, mood: .worried, text: String(localized: "Careful now. The bog air makes some of the flasks bubble.", comment: "Story, chapter 7 (Bubbling Bog)")),
                L(speaker: .apprentice, mood: .neutral, text: String(localized: "What happens when they bubble?", comment: "Story, chapter 7 (Bubbling Bog)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Every few pours the bottom potion rises to the top. The little dial counts down to it.", comment: "Story, chapter 7 (Bubbling Bog)")),
                L(speaker: .apprentice, mood: .happy, text: String(localized: "A flask that stirs itself? I like this bog.", comment: "Story, chapter 7 (Bubbling Bog)")),
            ]
        case .chapter(8):
            return [
                L(speaker: .apprentice, mood: .neutral, text: String(localized: "Why are these two flasks chained together?", comment: "Story, chapter 8 (Twin Towers)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Twins. Pour into one and the potion is shared evenly between both. And pour into a full flask with a brass pipe, and it pushes its bottom layer across.", comment: "Story, chapter 8 (Twin Towers)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Chains, pipes… everything in these towers is connected!", comment: "Story, chapter 8 (Twin Towers)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Then think in pairs, and the towers will dance for you.", comment: "Story, chapter 8 (Twin Towers)")),
            ]
        case .chapter(9):
            return [
                L(speaker: .alchemist, mood: .happy, text: String(localized: "My old hall, and my favorite cauldron. Here we don't just sort potions, we brew them.", comment: "Story, chapter 9 (Alchemist's Hall)")),
                L(speaker: .apprentice, mood: .neutral, text: String(localized: "The card under the cauldron shows two potions… and a new one?", comment: "Story, chapter 9 (Alchemist's Hall)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Pour one ingredient onto the other inside the cauldron and they become the potion on the card.", comment: "Story, chapter 9 (Alchemist's Hall)")),
                L(speaker: .apprentice, mood: .happy, text: String(localized: "Real brewing at last!", comment: "Story, chapter 9 (Alchemist's Hall)")),
            ]
        case .chapter(10):
            return [
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Is that… a dragon? Asleep on a mountain of gold?", comment: "Story, chapter 10 (Dragon's Hoard)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Shh. Its hoard is kept behind gates. Fill a switch flask to the top with one potion and its gate lifts.", comment: "Story, chapter 10 (Dragon's Hoard)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "And the dragon?", comment: "Story, chapter 10 (Dragon's Hoard)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Dragons love a tidy shelf. Let's not keep it waiting.", comment: "Story, chapter 10 (Dragon's Hoard)")),
            ]
        case .chapter:
            return []
        case .ending:
            return [
                L(speaker: .apprentice, mood: .happy, text: String(localized: "Every flask sorted, every gate open… and listen, the dragon is purring!", comment: "Story, ending")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "From a dusty cellar to a dragon's hoard. You're no apprentice any more, my friend.", comment: "Story, ending")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "But… what happens now?", comment: "Story, ending")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Now we put the kettle on. And tomorrow, there's always a new brew.", comment: "Story, ending")),
            ]
        }
    }

    /// Small heading above a scene: "Chapter 3 · Misty Marsh", or "Epilogue".
    static func heading(_ scene: StoryScene, catalog: LevelCatalog) -> String {
        switch scene {
        case .chapter(let n):
            let name = ChapterArt.name(of: n, in: catalog) ?? ""
            return String(localized: "Chapter \(n) · \(name)", comment: "Story scene heading")
        case .ending:
            return String(localized: "Epilogue", comment: "Story scene heading for the ending")
        }
    }

    /// The painting behind a scene.
    static func backdrop(_ scene: StoryScene) -> ImageResource {
        switch scene {
        case .chapter(let n): ChapterArt.vignette(n) ?? .bgWorkbenchLandscape
        case .ending: .chapter10
        }
    }
}

/// The story scene on screen, if any. Injected at the app root; `RootView` draws it over
/// everything, chapter screens and the game ask it to play a scene.
@Observable
final class StoryPresenter {
    private(set) var scene: StoryScene?
    /// Line to open on (DEBUG `-LPStoryLine`).
    private(set) var startLine = 0

    func show(_ scene: StoryScene, line: Int = 0) {
        guard self.scene == nil, !StoryScript.lines(scene).isEmpty else { return }
        startLine = line
        self.scene = scene
    }

    func finish() { scene = nil }

    /// Whether scenes may start on their own (DEBUG `-LPSkipTutorials 1` keeps screenshots clean).
    static var autoPlays: Bool {
        #if DEBUG
        return !UserDefaults.standard.bool(forKey: "LPSkipTutorials")
        #else
        return true
        #endif
    }
}
