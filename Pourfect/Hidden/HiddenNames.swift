import HiddenCore
import Foundation

/// English names of the hidden-object rooms and their objects, through the String Catalog (R11). Generated from
/// `HiddenScenes/<room>/scene.json`; an object missing here falls back to its scene.json name.
enum HiddenNames {
    static func title(_ room: HiddenSceneID) -> String {
        switch room {
        case .attic: String(localized: "The Alchemist's Attic", comment: "Hidden-object room 1 title")
        case .market: String(localized: "The Market Stall", comment: "Hidden-object room 2 title")
        case .hoard: String(localized: "The Dragon's Hoard", comment: "Hidden-object room 3 title")
        }
    }

    /// The find-list name of `id` in `room` (scene.json `name` if the catalog has none).
    static func object(_ id: String, in room: HiddenSceneID, fallback: String) -> String {
        switch room {
        case .attic: attic[id] ?? fallback
        case .market: market[id] ?? fallback
        case .hoard: hoard[id] ?? fallback
        }
    }

    private static var attic: [String: String] {
        [
            "key": String(localized: "Silver key", comment: "Hidden object to find (The Alchemist's Attic)"),
            "hourglass": String(localized: "Hourglass", comment: "Hidden object to find (The Alchemist's Attic)"),
            "owl": String(localized: "Wooden owl", comment: "Hidden object to find (The Alchemist's Attic)"),
            "mushroom": String(localized: "Toadstool", comment: "Hidden object to find (The Alchemist's Attic)"),
            "crystal": String(localized: "Amethyst", comment: "Hidden object to find (The Alchemist's Attic)"),
            "quill": String(localized: "Quill", comment: "Hidden object to find (The Alchemist's Attic)"),
            "watch": String(localized: "Pocket watch", comment: "Hidden object to find (The Alchemist's Attic)"),
            "potion": String(localized: "Green potion", comment: "Hidden object to find (The Alchemist's Attic)"),
            "horseshoe": String(localized: "Horseshoe", comment: "Hidden object to find (The Alchemist's Attic)"),
            "teacup": String(localized: "Teacup", comment: "Hidden object to find (The Alchemist's Attic)"),
            "scroll": String(localized: "Scroll", comment: "Hidden object to find (The Alchemist's Attic)"),
            "egg": String(localized: "Dragon egg", comment: "Hidden object to find (The Alchemist's Attic)"),
            "candle": String(localized: "Candle", comment: "Hidden object to find (The Alchemist's Attic)"),
            "magnifier": String(localized: "Magnifying glass", comment: "Hidden object to find (The Alchemist's Attic)"),
            "starfish": String(localized: "Starfish", comment: "Hidden object to find (The Alchemist's Attic)"),
            "spectacles": String(localized: "Spectacles", comment: "Hidden object to find (The Alchemist's Attic)"),
            "inkwell": String(localized: "Inkwell", comment: "Hidden object to find (The Alchemist's Attic)"),
            "mortar": String(localized: "Mortar and pestle", comment: "Hidden object to find (The Alchemist's Attic)"),
            "book": String(localized: "Red book", comment: "Hidden object to find (The Alchemist's Attic)"),
            "frog": String(localized: "Frog figurine", comment: "Hidden object to find (The Alchemist's Attic)"),
            "flask": String(localized: "Blue flask", comment: "Hidden object to find (The Alchemist's Attic)"),
            "telescope": String(localized: "Telescope", comment: "Hidden object to find (The Alchemist's Attic)"),
            "globe": String(localized: "Desk globe", comment: "Hidden object to find (The Alchemist's Attic)"),
            "die": String(localized: "Bone die", comment: "Hidden object to find (The Alchemist's Attic)"),
            "ring": String(localized: "Ruby ring", comment: "Hidden object to find (The Alchemist's Attic)"),
            "pinecone": String(localized: "Pinecone", comment: "Hidden object to find (The Alchemist's Attic)"),
            "acorn": String(localized: "Acorn", comment: "Hidden object to find (The Alchemist's Attic)"),
            "shell": String(localized: "Seashell", comment: "Hidden object to find (The Alchemist's Attic)"),
            "lavender": String(localized: "Lavender bundle", comment: "Hidden object to find (The Alchemist's Attic)"),
            "lamp": String(localized: "Oil lamp", comment: "Hidden object to find (The Alchemist's Attic)"),
            "scissors": String(localized: "Scissors", comment: "Hidden object to find (The Alchemist's Attic)"),
            "paintbrush": String(localized: "Paintbrush", comment: "Hidden object to find (The Alchemist's Attic)"),
            "firefly_jar": String(localized: "Firefly jar", comment: "Hidden object to find (The Alchemist's Attic)"),
            "chess_knight": String(localized: "Chess knight", comment: "Hidden object to find (The Alchemist's Attic)"),
            "butterfly": String(localized: "Butterfly", comment: "Hidden object to find (The Alchemist's Attic)"),
            "pumpkin": String(localized: "Pumpkin", comment: "Hidden object to find (The Alchemist's Attic)"),
            "broom": String(localized: "Broom", comment: "Hidden object to find (The Alchemist's Attic)"),
            "wand": String(localized: "Magic wand", comment: "Hidden object to find (The Alchemist's Attic)"),
            "mirror": String(localized: "Hand mirror", comment: "Hidden object to find (The Alchemist's Attic)"),
            "padlock": String(localized: "Padlock", comment: "Hidden object to find (The Alchemist's Attic)"),
        ]
    }

    private static var market: [String: String] {
        [
            "scale": String(localized: "Brass scale", comment: "Hidden object to find (The Market Stall)"),
            "purse": String(localized: "Coin purse", comment: "Hidden object to find (The Market Stall)"),
            "lantern": String(localized: "Lantern", comment: "Hidden object to find (The Market Stall)"),
            "wool": String(localized: "Wool skein", comment: "Hidden object to find (The Market Stall)"),
            "carrot": String(localized: "Carrot", comment: "Hidden object to find (The Market Stall)"),
            "bell": String(localized: "Hand bell", comment: "Hidden object to find (The Market Stall)"),
            "apple": String(localized: "Red apple", comment: "Hidden object to find (The Market Stall)"),
            "marble": String(localized: "Glass marble", comment: "Hidden object to find (The Market Stall)"),
            "pear": String(localized: "Pear", comment: "Hidden object to find (The Market Stall)"),
            "cheese": String(localized: "Cheese wedge", comment: "Hidden object to find (The Market Stall)"),
            "bread": String(localized: "Bread loaf", comment: "Hidden object to find (The Market Stall)"),
            "fish": String(localized: "Fish", comment: "Hidden object to find (The Market Stall)"),
            "eggplant": String(localized: "Eggplant", comment: "Hidden object to find (The Market Stall)"),
            "lemon": String(localized: "Lemon", comment: "Hidden object to find (The Market Stall)"),
            "grapes": String(localized: "Grapes", comment: "Hidden object to find (The Market Stall)"),
            "cherries": String(localized: "Cherries", comment: "Hidden object to find (The Market Stall)"),
            "strawberry": String(localized: "Strawberry", comment: "Hidden object to find (The Market Stall)"),
            "melon_slice": String(localized: "Melon slice", comment: "Hidden object to find (The Market Stall)"),
            "corn": String(localized: "Corn cob", comment: "Hidden object to find (The Market Stall)"),
            "pepper": String(localized: "Red pepper", comment: "Hidden object to find (The Market Stall)"),
            "radish": String(localized: "Radish bunch", comment: "Hidden object to find (The Market Stall)"),
            "honey": String(localized: "Honey pot", comment: "Hidden object to find (The Market Stall)"),
            "jug": String(localized: "Clay jug", comment: "Hidden object to find (The Market Stall)"),
            "hen_egg": String(localized: "Brown egg", comment: "Hidden object to find (The Market Stall)"),
            "peacock_feather": String(localized: "Peacock feather", comment: "Hidden object to find (The Market Stall)"),
            "straw_hat": String(localized: "Straw hat", comment: "Hidden object to find (The Market Stall)"),
            "boot": String(localized: "Leather boot", comment: "Hidden object to find (The Market Stall)"),
            "spoon": String(localized: "Wooden spoon", comment: "Hidden object to find (The Market Stall)"),
            "ladle": String(localized: "Copper ladle", comment: "Hidden object to find (The Market Stall)"),
            "teapot": String(localized: "Copper teapot", comment: "Hidden object to find (The Market Stall)"),
            "spool": String(localized: "Thread spool", comment: "Hidden object to find (The Market Stall)"),
            "pretzel": String(localized: "Pretzel", comment: "Hidden object to find (The Market Stall)"),
            "toy_horse": String(localized: "Toy horse", comment: "Hidden object to find (The Market Stall)"),
            "sunflower": String(localized: "Sunflower", comment: "Hidden object to find (The Market Stall)"),
            "rose": String(localized: "Rose", comment: "Hidden object to find (The Market Stall)"),
            "tankard": String(localized: "Tankard", comment: "Hidden object to find (The Market Stall)"),
            "wine_bottle": String(localized: "Green bottle", comment: "Hidden object to find (The Market Stall)"),
            "hammer": String(localized: "Hammer", comment: "Hidden object to find (The Market Stall)"),
            "lute": String(localized: "Lute", comment: "Hidden object to find (The Market Stall)"),
            "glove": String(localized: "Leather glove", comment: "Hidden object to find (The Market Stall)"),
        ]
    }

    private static var hoard: [String: String] {
        [
            "goblet": String(localized: "Golden goblet", comment: "Hidden object to find (The Dragon's Hoard)"),
            "crown": String(localized: "Crown", comment: "Hidden object to find (The Dragon's Hoard)"),
            "ruby": String(localized: "Ruby", comment: "Hidden object to find (The Dragon's Hoard)"),
            "emerald": String(localized: "Emerald", comment: "Hidden object to find (The Dragon's Hoard)"),
            "sapphire": String(localized: "Sapphire", comment: "Hidden object to find (The Dragon's Hoard)"),
            "coin_pouch": String(localized: "Coin pouch", comment: "Hidden object to find (The Dragon's Hoard)"),
            "dragon_scale": String(localized: "Dragon scale", comment: "Hidden object to find (The Dragon's Hoard)"),
            "rune_stone": String(localized: "Rune stone", comment: "Hidden object to find (The Dragon's Hoard)"),
            "dagger": String(localized: "Jewelled dagger", comment: "Hidden object to find (The Dragon's Hoard)"),
            "dragon_egg": String(localized: "Red dragon egg", comment: "Hidden object to find (The Dragon's Hoard)"),
            "tiara": String(localized: "Tiara", comment: "Hidden object to find (The Dragon's Hoard)"),
            "pearl_necklace": String(localized: "Pearl necklace", comment: "Hidden object to find (The Dragon's Hoard)"),
            "amulet": String(localized: "Amulet", comment: "Hidden object to find (The Dragon's Hoard)"),
            "round_shield": String(localized: "Round shield", comment: "Hidden object to find (The Dragon's Hoard)"),
            "helmet": String(localized: "Knight's helmet", comment: "Hidden object to find (The Dragon's Hoard)"),
            "gold_plate": String(localized: "Golden plate", comment: "Hidden object to find (The Dragon's Hoard)"),
            "jewel_box": String(localized: "Jewel box", comment: "Hidden object to find (The Dragon's Hoard)"),
            "scepter": String(localized: "Scepter", comment: "Hidden object to find (The Dragon's Hoard)"),
            "royal_orb": String(localized: "Royal orb", comment: "Hidden object to find (The Dragon's Hoard)"),
            "gold_bar": String(localized: "Gold bar", comment: "Hidden object to find (The Dragon's Hoard)"),
            "oyster_pearl": String(localized: "Oyster pearl", comment: "Hidden object to find (The Dragon's Hoard)"),
            "harp": String(localized: "Golden harp", comment: "Hidden object to find (The Dragon's Hoard)"),
            "drinking_horn": String(localized: "Drinking horn", comment: "Hidden object to find (The Dragon's Hoard)"),
            "bracelet": String(localized: "Bracelet", comment: "Hidden object to find (The Dragon's Hoard)"),
            "brooch": String(localized: "Brooch", comment: "Hidden object to find (The Dragon's Hoard)"),
            "candelabra": String(localized: "Candelabra", comment: "Hidden object to find (The Dragon's Hoard)"),
            "blue_vase": String(localized: "Blue vase", comment: "Hidden object to find (The Dragon's Hoard)"),
            "mini_chest": String(localized: "Little chest", comment: "Hidden object to find (The Dragon's Hoard)"),
            "golden_mask": String(localized: "Golden mask", comment: "Hidden object to find (The Dragon's Hoard)"),
            "jade_dragon": String(localized: "Jade dragon", comment: "Hidden object to find (The Dragon's Hoard)"),
            "golden_apple": String(localized: "Golden apple", comment: "Hidden object to find (The Dragon's Hoard)"),
            "crystal_ball": String(localized: "Crystal ball", comment: "Hidden object to find (The Dragon's Hoard)"),
            "phoenix_feather": String(localized: "Phoenix feather", comment: "Hidden object to find (The Dragon's Hoard)"),
            "battle_axe": String(localized: "Battle axe", comment: "Hidden object to find (The Dragon's Hoard)"),
            "gauntlet": String(localized: "Gauntlet", comment: "Hidden object to find (The Dragon's Hoard)"),
            "golden_key": String(localized: "Golden key", comment: "Hidden object to find (The Dragon's Hoard)"),
            "medallion": String(localized: "Medallion", comment: "Hidden object to find (The Dragon's Hoard)"),
            "golden_bird": String(localized: "Golden bird", comment: "Hidden object to find (The Dragon's Hoard)"),
            "jeweled_egg": String(localized: "Jewelled egg", comment: "Hidden object to find (The Dragon's Hoard)"),
            "treasure_map": String(localized: "Treasure map", comment: "Hidden object to find (The Dragon's Hoard)"),
        ]
    }
}
