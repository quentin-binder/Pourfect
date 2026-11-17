import SecretRecipeCore
import SwiftUI

/// The pictures of the Secret Recipe tip (R10b).
enum RecipeTipScene: Equatable {
    case slots, drops, notes
}

/// The first-time tip of Secret Recipe (also behind "?" in the game).
enum RecipeTips {
    static func steps() -> [TutorialStep] {
        func step(_ id: String, _ title: String, _ text: String, _ scene: RecipeTipScene) -> TutorialStep {
            TutorialStep(id: id, topic: .recipe, title: title, text: text, scene: .recipe(scene))
        }
        return [
            step("recipe.slots", String(localized: "Crack the recipe", comment: "Secret Recipe tip title"),
                 String(localized: "The alchemist has locked away a recipe: five different ingredients, in order, out of the eight on the tray. Fill the five slots and brew. You have eight tries.",
                        comment: "Secret Recipe tip: the goal"), .slots),
            step("recipe.drops", String(localized: "Gold and silver drops", comment: "Secret Recipe tip title"),
                 String(localized: "Each gold drop means one ingredient sits in its right slot. Each silver drop means one is in the recipe, but in another slot. The drops never tell you which ones.",
                        comment: "Secret Recipe tip: the feedback"), .drops),
            step("recipe.notes", String(localized: "Keep notes", comment: "Secret Recipe tip title"),
                 String(localized: "Turn on Notes and tap an ingredient to mark it ruled out, then maybe. With a keyboard: 1 to 8 pick, Delete clears, Return brews.",
                        comment: "Secret Recipe tip: notes and keyboard"), .notes),
        ]
    }
}

/// A small still life of the tray, slots and drops for one tip page.
struct RecipeTipSceneView: View {
    let scene: RecipeTipScene
    @Environment(\.colorRunesEnabled) private var runes

    var body: some View {
        switch scene {
        case .slots:
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach([RecipeIngredient.ember, .crystal], id: \.self) { slot($0) }
                    ForEach(0..<3, id: \.self) { _ in slot(nil) }
                }
                HStack(spacing: 4) {
                    ForEach(RecipeIngredient.allCases, id: \.self) { RecipeIngredientIcon(ingredient: $0, size: 26, runes: runes) }
                }
            }
        case .drops:
            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach([RecipeIngredient.mushroom, .starleaf, .drop, .honeycomb, .feather], id: \.self) {
                        RecipeIngredientIcon(ingredient: $0, size: 32, runes: runes)
                    }
                }
                RecipeDropsView(feedback: RecipeFeedback(exact: 2, misplaced: 1), size: 22)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RecipeBook.ink.opacity(0.9), in: Capsule())
            }
        case .notes:
            HStack(spacing: 10) {
                note(.moonflower, mark: nil)
                note(.feather, mark: "xmark")
                note(.honeycomb, mark: "questionmark.circle.fill")
                note(.ember, mark: "xmark")
            }
        }
    }

    private func slot(_ ingredient: RecipeIngredient?) -> some View {
        ZStack {
            Circle().fill(Color(white: 0.1))
            Circle().strokeBorder(ingredient == nil ? .white.opacity(0.3) : RecipeBook.brass, lineWidth: 1.5)
            if let ingredient { RecipeIngredientIcon(ingredient: ingredient, size: 32, runes: runes) }
        }
        .frame(width: 44, height: 44)
    }

    private func note(_ ingredient: RecipeIngredient, mark: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.08))
            RecipeIngredientIcon(ingredient: ingredient, size: 40, runes: runes)
                .opacity(mark == "xmark" ? 0.3 : 1)
            if mark == "xmark" {
                Image(systemName: "xmark").font(.system(size: 24, weight: .bold)).foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.3))
            }
        }
        .frame(width: 50, height: 50)
        .overlay(alignment: .topTrailing) {
            if mark == "questionmark.circle.fill" {
                Image(systemName: "questionmark.circle.fill").font(.system(size: 16)).foregroundStyle(.black, RecipeBook.brass).offset(x: 4, y: -4)
            }
        }
    }
}
