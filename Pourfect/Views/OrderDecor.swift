import BottleSortCore
import SwiftUI

// R7 customer orders: the villager card above the board and the ticket on each ordered flask.

/// A potion-shop customer (`Art/characters/villager_N`, in the asset catalog as `villager_N`).
enum Villager: Int, CaseIterable {
    case baker = 1, knight, farmer, merchant, child, herbalist

    var imageName: String { "villager_\(rawValue)" }

    var name: String {
        switch self {
        case .baker: String(localized: "Bram", comment: "Name of the village baker who orders potions")
        case .knight: String(localized: "Sir Rowan", comment: "Name of the young knight who orders potions")
        case .farmer: String(localized: "Mira", comment: "Name of the farmer who orders potions")
        case .merchant: String(localized: "Orrin", comment: "Name of the travelling merchant who orders potions")
        case .child: String(localized: "Pip", comment: "Name of the child with a cat who orders potions")
        case .herbalist: String(localized: "Old Hazel", comment: "Name of the elderly herbalist who orders potions")
        }
    }

    /// The customer of a recipe: always the same one for the same recipe id (FNV-1a of the id,
    /// so it never depends on Swift's per-launch hash seed).
    static func forRecipe(_ id: String) -> Villager {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return Villager(rawValue: 1 + Int(hash % UInt64(allCases.count))) ?? .farmer
    }
}

extension GoalTarget {
    /// The request for one target, e.g. "a flask of Dragon's Blood" (an order) or "a layered
    /// brew" (a pattern), for the card's line.
    var spokenWanted: String {
        if let color {
            return String(localized: "\(layers.count) layers of \(Palette.potionName(color.rawValue))",
                          comment: "VoiceOver: what an order flask wants; the arguments are the layer count and the potion")
        }
        let parts = runs.map { run in
            String(localized: "\(run.count) \(Palette.potionName(run.color.rawValue))",
                   comment: "Layer count and potion name, e.g. 2 Moonshade")
        }
        return String(localized: "bottom to top \(parts.joined(separator: ", "))",
                      comment: "VoiceOver: the layers a layered-recipe flask wants, listed from the bottom; the argument lists them")
    }
}

/// The order card above the board: the customer's portrait, their request and the wanted
/// potions (a drop with its rune per order, the stacked layers of a layered recipe), each
/// ticked off while its flask holds it.
struct OrderCard: View {
    let villager: Villager
    let targets: [GoalTarget]
    /// Target flasks currently filled (shown ticked).
    let filled: Set<Int>
    /// Per bottle: how often its order was filled (each change replays the tick).
    let ticks: [Int]
    var compact = false
    var reduceMotion = false

    var body: some View {
        let portrait: CGFloat = compact ? 44 : 58
        HStack(spacing: 12) {
            Image(villager.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: portrait, height: portrait)
                .background(Circle().fill(Color(red: 0.93, green: 0.86, blue: 0.70)))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(red: 0.78, green: 0.62, blue: 0.32), lineWidth: 2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(request)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ForEach(targets, id: \.bottle) { target in
                        OrderWant(target: target, size: compact ? 14 : 17, filled: filled.contains(target.bottle),
                                  tick: ticks.indices.contains(target.bottle) ? ticks[target.bottle] : 0,
                                  reduceMotion: reduceMotion)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, compact ? 6 : 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    /// "Mira needs a flask of Dragon's Blood", "… needs flasks of A and B", or a layered brew.
    private var request: String {
        let name = villager.name
        if targets.contains(where: \.isLayered) {
            return String(localized: "\(name) wants a layered brew, bottom to top as shown",
                          comment: "Order card: a villager asks for a flask with an exact layer pattern; the argument is the villager's name")
        }
        let potions = targets.compactMap(\.color).map { Palette.potionName($0.rawValue) }
        if potions.count == 1 {
            return String(localized: "\(name) needs a flask of \(potions[0])",
                          comment: "Order card: a villager orders one flask of a potion; the arguments are the villager's name and the potion")
        }
        let list = ListFormatter.localizedString(byJoining: potions)
        return String(localized: "\(name) needs flasks of \(list)",
                      comment: "Order card: a villager orders several flasks; the arguments are the villager's name and the list of potions")
    }

    private var accessibilitySummary: String {
        let done = targets.filter { filled.contains($0.bottle) }.count
        return request + ". " + String(localized: "\(done) of \(targets.count) filled",
                                       comment: "VoiceOver: how many order flasks hold what they should")
    }
}

/// One wanted potion on the card: a drop (an order) or a stack of chips (a layered recipe),
/// with a tick once its flask holds it.
private struct OrderWant: View {
    let target: GoalTarget
    let size: CGFloat
    let filled: Bool
    let tick: Int
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 3) {
            if let color = target.color {
                PotionDrop(color: color, size: size)
                Text(verbatim: "×\(target.layers.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                LayerChips(layers: target.layers, width: size * 1.1)
            }
            Image(systemName: filled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(filled ? Color.green : Color.secondary)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : tick)
        }
    }
}

/// A layered recipe as small chips, one per layer, bottom layer at the bottom, each with its rune.
struct LayerChips: View {
    let layers: [Layer]
    let width: CGFloat

    var body: some View {
        let chip = width * 0.42
        VStack(spacing: max(0.5, chip * 0.08)) {
            ForEach(Array(layers.enumerated().reversed()), id: \.offset) { _, layer in
                RoundedRectangle(cornerRadius: chip * 0.25, style: .continuous)
                    .fill(layer.liquidColor)
                    .overlay {
                        if let id = layer.colorID, let rune = Rune(colorIndex: id.rawValue) {
                            RuneView(rune: rune, scale: 0.75)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: chip * 0.25, style: .continuous)
                        .strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
                    .frame(width: width, height: chip)
            }
        }
    }
}

/// The paper ticket tied to an ordered flask: the wanted potion (a drop) or pattern (chips), and
/// a green tick that pops in when the flask holds it.
struct OrderTag: View {
    let target: GoalTarget
    let width: CGFloat
    let filled: Bool
    let tick: Int
    var reduceMotion = false

    /// Width of the ticket for a flask of width `w`.
    static func size(_ w: CGFloat) -> CGFloat { max(18, w * 0.5) }

    var body: some View {
        let s = Self.size(width)
        VStack(spacing: s * 0.08) {
            if let color = target.color {
                PotionDrop(color: color, size: s * 0.62)
            } else {
                LayerChips(layers: target.layers, width: s * 0.62)
            }
        }
        .padding(s * 0.12)
        .background {
            RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                .fill(Color(red: 0.96, green: 0.90, blue: 0.76))
                .overlay(RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                    .strokeBorder(Color(red: 0.55, green: 0.40, blue: 0.20), lineWidth: max(0.75, s * 0.05)))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .overlay(alignment: .topTrailing) {
            if filled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: s * 0.42, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .offset(x: s * 0.2, y: -s * 0.2)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : tick)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.55), value: filled)
        .rotationEffect(.degrees(-8))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
