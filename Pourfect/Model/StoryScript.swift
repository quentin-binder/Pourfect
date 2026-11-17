import BottleSortCore
import HiddenCore
import Match3Core
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
/// 236), and one for each ingredient-gathering episode (R9): what the two gather and for which
/// place on the path. Each scene fits its chapter's place and the mechanic it brings. When a scene plays is
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
        case .gathering(1):
            return [
                L(speaker: .apprentice, mood: .happy, text: String(localized: "Look at all these glowing caps! Why are we picking mushrooms instead of sorting?", comment: "Story, gathering episode 1 (Mushroom Hollow)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "The Rune Vault is pitch dark. Hollow-caps glow for hours once they're gathered: our lanterns for tomorrow.", comment: "Story, gathering episode 1 (Mushroom Hollow)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Swap two neighbors to line up three of a kind, and the basket fills itself.", comment: "Story, gathering episode 1 (Mushroom Hollow)")),
            ]
        case .gathering(2):
            return [
                L(speaker: .apprentice, mood: .worried, text: String(localized: "The marsh ahead is all mist. How will we see a thing?", comment: "Story, gathering episode 2 (Crystal Grotto)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "With grotto crystals. Hold one up and the fog thins around it.", comment: "Story, gathering episode 2 (Crystal Grotto)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Line up four or five and they leave a glowing special behind. Set it off and a whole row comes loose.", comment: "Story, gathering episode 2 (Crystal Grotto)")),
            ]
        case .gathering(3):
            return [
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "The Glyph Library's oldest runes have faded. Moonflowers glow just bright enough to read them.", comment: "Story, gathering episode 3 (Moonlit Meadow)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Some of them are frozen in the night frost!", comment: "Story, gathering episode 3 (Moonlit Meadow)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Match right beside them and the ice cracks. Patience, and a little warmth.", comment: "Story, gathering episode 3 (Moonlit Meadow)")),
            ]
        case .gathering(4):
            return [
                L(speaker: .apprentice, mood: .happy, text: String(localized: "Embers! Are these for the Glass Works?", comment: "Story, gathering episode 4 (Ember Hearth)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "My friend's furnace needs the hottest coals in the land. Mind the double frost here: it takes two thaws.", comment: "Story, gathering episode 4 (Ember Hearth)")),
                L(speaker: .apprentice, mood: .happy, text: String(localized: "Twice the cracking. I'll bring a bloom or two.", comment: "Story, gathering episode 4 (Ember Hearth)")),
            ]
        case .gathering(5):
            return [
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Before the climb to Frost Peak we need warm supplies, and they're locked in my old storeroom.", comment: "Story, gathering episode 5 (Sealed Storeroom)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Every crate has a rune seal on it.", comment: "Story, gathering episode 5 (Sealed Storeroom)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Seals give way when you match beside them. The stronger ones need a few knocks.", comment: "Story, gathering episode 5 (Sealed Storeroom)")),
            ]
        case .gathering(6):
            return [
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Ice and crates, all over the ridge. What are we after up here?", comment: "Story, gathering episode 6 (Icefall Ridge)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Icefall crystals. The Bubbling Bog boils over without something cold to calm it.", comment: "Story, gathering episode 6 (Icefall Ridge)")),
                L(speaker: .apprentice, mood: .happy, text: String(localized: "Frost, seals and six ingredients. I'm ready!", comment: "Story, gathering episode 6 (Icefall Ridge)")),
            ]
        case .gathering(7):
            return [
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Spring water from the bog, for the Twin Towers. Their chained flasks need it pure.", comment: "Story, gathering episode 7 (Bogwater Springs)")),
                L(speaker: .apprentice, mood: .neutral, text: String(localized: "Those little potion flasks are floating in the tray.", comment: "Story, gathering episode 7 (Bogwater Springs)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Clear the cells below them and they sink. Bring each one down to the bottom and it's ours.", comment: "Story, gathering episode 7 (Bogwater Springs)")),
            ]
        case .gathering(8):
            return [
                L(speaker: .apprentice, mood: .happy, text: String(localized: "So many feathers up here! The wind has carried them all over the towers.", comment: "Story, gathering episode 8 (Windy Rookery)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "My hall needs fresh quills. Every recipe on the cauldron cards is written with one.", comment: "Story, gathering episode 8 (Windy Rookery)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Gather them quickly, before the wind changes its mind.", comment: "Story, gathering episode 8 (Windy Rookery)")),
            ]
        case .gathering(9):
            return [
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "For the dragon we'll need a sleeping draught: every herb in my garden, at once.", comment: "Story, gathering episode 9 (Alchemist's Garden)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Frost, crates, flasks… the whole garden is a puzzle!", comment: "Story, gathering episode 9 (Alchemist's Garden)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Then use all you've learned. A prism and a comet together make quite a harvest.", comment: "Story, gathering episode 9 (Alchemist's Garden)")),
            ]
        case .gathering(10):
            return [
                L(speaker: .apprentice, mood: .happy, text: String(localized: "The dragon is purring, and it showed us its larder!", comment: "Story, gathering episode 10 (Dragon's Larder)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Rare ingredients, kept for a thousand years. Enough for the grandest brew of all.", comment: "Story, gathering episode 10 (Dragon's Larder)")),
                L(speaker: .apprentice, mood: .neutral, text: String(localized: "Then let's gather every last one.", comment: "Story, gathering episode 10 (Dragon's Larder)")),
            ]
        case .gathering:
            return []
        case .distillery(1):
            return [
                L(speaker: .apprentice, mood: .worried, text: String(localized: "What's behind this door? It's all brass pipes and cobwebs, and everything is stone cold.", comment: "Story, distillery stage 1 (The Cold Still)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "My old distillery! It hasn't run since I was your age. Someone knocked every pipe out of line.", comment: "Story, distillery stage 1 (The Cold Still)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Turn the pieces until the cauldron's outlet runs all the way to the flask. No open ends, or it drips on my floor.", comment: "Story, distillery stage 1 (The Cold Still)")),
                L(speaker: .apprentice, mood: .happy, text: String(localized: "Fewest turns gets three stars? Then I'll think before I twist.", comment: "Story, distillery stage 1 (The Cold Still)")),
            ]
        case .distillery(2):
            return [
                L(speaker: .apprentice, mood: .happy, text: String(localized: "The still is warm again! But this room has two cauldrons and pipes that split three ways.", comment: "Story, distillery stage 2 (Copper and Steam)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Splitters feed two flasks at once. The riveted pieces are bolted down, so plan around them.", comment: "Story, distillery stage 2 (Copper and Steam)")),
                L(speaker: .alchemist, mood: .worried, text: String(localized: "And never let two potions meet in one pipe. They turn to murk and block the line.", comment: "Story, distillery stage 2 (Copper and Steam)")),
                L(speaker: .apprentice, mood: .neutral, text: String(localized: "What about the crossed pipes?", comment: "Story, distillery stage 2 (Copper and Steam)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Two pipes, one tile. They pass over each other and never mix.", comment: "Story, distillery stage 2 (Copper and Steam)")),
            ]
        case .distillery(3):
            return [
                L(speaker: .alchemist, mood: .happy, text: String(localized: "The Great Alembic, the heart of the old lab. Get it running and we can brew anything.", comment: "Story, distillery stage 3 (The Great Alembic)")),
                L(speaker: .apprentice, mood: .neutral, text: String(localized: "These copper coils are hot to the touch.", comment: "Story, distillery stage 3 (The Great Alembic)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Heat coils. A potion that runs through one comes out changed, like red turning to orange. Read the little tag.", comment: "Story, distillery stage 3 (The Great Alembic)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "And the red wheels? They won't let anything through.", comment: "Story, distillery stage 3 (The Great Alembic)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Valves. Fill the flask with the same number and its valve swings open. One flask first, then the next.", comment: "Story, distillery stage 3 (The Great Alembic)")),
            ]
        case .distillery:
            return []
        case .hidden(1):
            return [
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Up the ladder already? It's dark up here, and everything is buried under dust and cobwebs.", comment: "Story, curiosity room 1 (The Alchemist's Attic)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "My attic! Forty years of curiosities. Somewhere in this mess are the things I need for tomorrow's brew.", comment: "Story, curiosity room 1 (The Alchemist's Attic)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "I'll give you a list. Find each thing and tap it, and it goes straight into my basket.", comment: "Story, curiosity room 1 (The Alchemist's Attic)")),
                L(speaker: .apprentice, mood: .neutral, text: String(localized: "And everything that isn't on the list?", comment: "Story, curiosity room 1 (The Alchemist's Attic)")),
                L(speaker: .alchemist, mood: .worried, text: String(localized: "Leave it be! Grabbing the wrong thing only stirs up dust. Look closely before you reach.", comment: "Story, curiosity room 1 (The Alchemist's Attic)")),
                L(speaker: .apprentice, mood: .happy, text: String(localized: "And if I can't find something, I'll light the lantern.", comment: "Story, curiosity room 1 (The Alchemist's Attic)")),
            ]
        case .hidden(2):
            return [
                L(speaker: .apprentice, mood: .happy, text: String(localized: "Market day! Look at all these stalls, there's fruit stacked to the awnings.", comment: "Story, curiosity room 2 (The Market Stall)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Old Berta keeps the best stall in town, and the most crowded. My list is long today.", comment: "Story, curiosity room 2 (The Market Stall)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Pears, pots, a skein of wool… she has all of it somewhere. Just don't buy her cheese by mistake.", comment: "Story, curiosity room 2 (The Market Stall)")),
                L(speaker: .apprentice, mood: .worried, text: String(localized: "Everything looks like everything else in this heap.", comment: "Story, curiosity room 2 (The Market Stall)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Then come closer and look again. Small things hide in plain sight.", comment: "Story, curiosity room 2 (The Market Stall)")),
            ]
        case .hidden(3):
            return [
                L(speaker: .apprentice, mood: .worried, text: String(localized: "We're in the dragon's cave. On purpose. Tell me again why we're in the dragon's cave?", comment: "Story, curiosity room 3 (The Dragon's Hoard)")),
                L(speaker: .alchemist, mood: .happy, text: String(localized: "Because she sleeps after a good meal, and she owes me a favour. I want a few things from her hoard.", comment: "Story, curiosity room 3 (The Dragon's Hoard)")),
                L(speaker: .alchemist, mood: .neutral, text: String(localized: "Gold on gold, mind you. A golden key is hard to see on a pile of coins.", comment: "Story, curiosity room 3 (The Dragon's Hoard)")),
                L(speaker: .apprentice, mood: .neutral, text: String(localized: "And if I touch the wrong treasure?", comment: "Story, curiosity room 3 (The Dragon's Hoard)")),
                L(speaker: .alchemist, mood: .worried, text: String(localized: "She'll snore a little louder. Find what's on the list, take nothing else, and keep your voice down.", comment: "Story, curiosity room 3 (The Dragon's Hoard)")),
            ]
        case .hidden:
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
        case .gathering(let n):
            let name = Match3Library.shared.episodes.first { $0.episode.number == n }?.episode.name ?? ""
            return String(localized: "Gathering · \(name)", comment: "Story scene heading of an ingredient-gathering episode")
        case .distillery(let n):
            return String(localized: "Distillery · \(DistillWing.stageTitle(n))", comment: "Story scene heading of a distillery workshop stage")
        case .hidden(let n):
            let name = HiddenSceneID(number: n).map { HiddenNames.title($0) } ?? ""
            return String(localized: "Curiosity Rooms · \(name)", comment: "Story scene heading of a hidden-object room")
        }
    }

    /// The painting behind a scene.
    static func backdrop(_ scene: StoryScene) -> ImageResource {
        switch scene {
        case .chapter(let n): ChapterArt.vignette(n) ?? .bgWorkbenchLandscape
        case .ending: .chapter10
        // Where the gathered ingredients are going: the next chapter (the larder is the hoard's own).
        case .gathering(let n): ChapterArt.vignette(min(n + 1, 10)) ?? .bgWorkbenchLandscape
        // The old lab's workbench; the Great Alembic stands in the alchemist's hall.
        case .distillery(let n): n >= 3 ? .chapter09 : .bgWorkbenchLandscape
        // The room's own painting is drawn instead (`backdropImage`).
        case .hidden: .bgWorkbenchLandscape
        }
    }

    /// The painting behind a scene: a hidden-object room shows the room itself.
    static func backdropImage(_ scene: StoryScene) -> Image {
        if case .hidden(let n) = scene, let room = HiddenSceneID(number: n) { return HiddenArt.backdropImage(room) }
        return Image(backdrop(scene))
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
