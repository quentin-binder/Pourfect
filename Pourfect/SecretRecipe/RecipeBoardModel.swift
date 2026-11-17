import BottleSortCore
import Foundation
import Observation
import SecretRecipeCore
import SwiftUI

/// Which recipe is on the bench: today's daily (saved, counted) or a practice one (a seed, nothing saved).
enum RecipePlay: Hashable {
    case daily(DailyDate)
    case practice(UInt64)

    var isDaily: Bool { if case .daily = self { true } else { false } }
}

/// The player's own marks on a tray ingredient (purely a memory aid; the game never reads them).
enum RecipeNote: Int, Codable, CaseIterable {
    case none, ruledOut, maybe

    var next: RecipeNote { RecipeNote(rawValue: (rawValue + 1) % RecipeNote.allCases.count) ?? .none }
}

/// One Secret Recipe game on screen: the game itself (core), the five-slot draft being filled, the
/// tray notes, and the feedback events. Daily games are saved after every brew through `onBrew`.
@MainActor
@Observable
final class RecipeBoardModel {
    let play: RecipePlay
    private(set) var game: RecipeGame
    /// The draft: one ingredient per slot or nil.
    private(set) var draft: [RecipeIngredient?] = Array(repeating: nil, count: RecipeCode.length)
    /// The slot the next tray tap fills.
    private(set) var cursor = 0
    private(set) var notes: [RecipeIngredient: RecipeNote] = [:]
    /// Notes mode: a tray tap marks instead of placing.
    var notesMode = false
    /// How many drops of the newest guess are shown (they appear one by one).
    private(set) var revealedDrops = RecipeCode.length
    /// Bumps on a refused action (incomplete brew), for a small shake.
    private(set) var refusals = 0
    let isDemo: Bool

    @ObservationIgnored var settings = GameSettings()
    @ObservationIgnored var reduceMotion = false
    /// Called after each brew with the guesses so far (the daily saves them).
    @ObservationIgnored var onBrew: (([RecipeCode]) -> Void)?
    @ObservationIgnored private var revealTask: Task<Void, Never>?

    init(play: RecipePlay, game: RecipeGame, isDemo: Bool = false) {
        self.play = play
        self.game = game
        self.isDemo = isDemo
    }

    var isOver: Bool { game.isOver }
    var isDraftComplete: Bool { draft.allSatisfy { $0 != nil } }
    var draftCode: RecipeCode? { RecipeCode(draft.compactMap { $0 }) }
    /// Still animating the newest guess's drops.
    var isRevealing: Bool { revealedDrops < RecipeCode.length }
    /// The finished card waits for the last drops.
    var showsEnd: Bool { isOver && !isRevealing }

    func note(_ ingredient: RecipeIngredient) -> RecipeNote { notes[ingredient] ?? .none }

    // MARK: Draft

    /// A tray tap: places the ingredient in the cursor slot (moving it there if it's already in
    /// the draft), or in notes mode cycles its note.
    func tap(_ ingredient: RecipeIngredient) {
        guard !isOver else { return }
        if notesMode {
            cycleNote(ingredient)
            return
        }
        place(ingredient)
    }

    func place(_ ingredient: RecipeIngredient) {
        guard !isOver else { return }
        if let existing = draft.firstIndex(of: ingredient) {
            guard existing != cursor else { return }
            draft[existing] = nil
        }
        draft[cursor] = ingredient
        advanceCursor()
        feedback(.place)
    }

    /// A slot tap: clears a filled slot, and the next tray tap fills that slot.
    func tapSlot(_ index: Int) {
        guard !isOver, draft.indices.contains(index) else { return }
        if draft[index] != nil {
            draft[index] = nil
            feedback(.clear)
        }
        cursor = index
    }

    /// Delete key: clears the slot before the cursor (or the cursor's own, if filled).
    func backspace() {
        guard !isOver else { return }
        if draft[cursor] == nil {
            guard let last = draft.lastIndex(where: { $0 != nil }) else { return }
            cursor = last
        }
        draft[cursor] = nil
        feedback(.clear)
    }

    func clearDraft() {
        guard !isOver, draft.contains(where: { $0 != nil }) else { return }
        draft = Array(repeating: nil, count: RecipeCode.length)
        cursor = 0
        feedback(.clear)
    }

    /// Drag and drop: puts the ingredient in a given slot (moving it from another slot).
    func drop(_ ingredient: RecipeIngredient, at index: Int) {
        guard !isOver, draft.indices.contains(index) else { return }
        if let existing = draft.firstIndex(of: ingredient) { draft[existing] = nil }
        draft[index] = ingredient
        cursor = index
        advanceCursor()
        feedback(.place)
    }

    /// The first empty slot after the cursor (wrapping), else the cursor stays.
    private func advanceCursor() {
        for step in 1...RecipeCode.length {
            let i = (cursor + step) % RecipeCode.length
            if draft[i] == nil { cursor = i; return }
        }
    }

    func cycleNote(_ ingredient: RecipeIngredient) {
        notes[ingredient] = note(ingredient).next
        feedback(.note)
    }

    // MARK: Brew

    /// Brews the draft as a guess: needs all five slots filled.
    @discardableResult
    func brew() -> RecipeTurn? {
        guard !isOver, !isRevealing else { return nil }
        guard let code = draftCode else {
            refusals += 1
            feedback(.refused)
            return nil
        }
        guard let turn = game.brew(code) else { return nil }
        draft = Array(repeating: nil, count: RecipeCode.length)
        cursor = 0
        if !isDemo { onBrew?(game.guesses) }
        feedback(.brew)
        revealDrops(turn)
        let text = String(localized: "Guess \(game.turns.count): \(RecipeText.feedback(turn.feedback))",
                          comment: "VoiceOver announcement after a Secret Recipe guess")
        AccessibilityNotification.Announcement(text).post()
        return turn
    }

    /// Drops appear one by one (gold first), then the end of the game sounds.
    private func revealDrops(_ turn: RecipeTurn) {
        revealTask?.cancel()
        let finish = { [weak self] in
            guard let self else { return }
            self.revealedDrops = RecipeCode.length
            switch self.game.status {
            case .won: self.feedback(.won)
            case .lost: self.feedback(.lost)
            case .playing: break
            }
        }
        guard !reduceMotion else { finish(); return }
        revealedDrops = 0
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            for i in 0..<RecipeCode.length {
                guard let self, !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.25)) { self.revealedDrops = i + 1 }
                if i < turn.feedback.exact { self.feedback(.gold) } else if i < turn.feedback.common { self.feedback(.silver) }
                try? await Task.sleep(for: .milliseconds(140))
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.3)) { finish() }
        }
    }

    func stop() { revealTask?.cancel() }

    /// Recipes still possible (practice only shows it).
    var candidatesLeft: Int { game.candidatesLeft }

    // MARK: Feedback

    enum Event { case place, clear, note, refused, brew, gold, silver, won, lost }

    private func feedback(_ event: Event) {
        let sound = settings.soundEnabled, haptics = settings.hapticsEnabled
        let engine = SoundEngine.shared
        switch event {
        case .place:
            if sound { engine.play(.clink, volume: 0.55) }
            if haptics { Haptics.select() }
        case .clear:
            if sound { engine.play(.tap, volume: 0.5) }
        case .note:
            if sound { engine.play(.tap, volume: 0.35) }
            if haptics { Haptics.select() }
        case .refused:
            if sound { engine.play(.tap, volume: 0.8) }
            if haptics { Haptics.illegal() }
        case .brew:
            if sound { engine.play(.brew, volume: 0.8) }
            if haptics { Haptics.brew() }
        case .gold:
            if sound { engine.play(.keyClick, volume: 0.7) }
            if haptics { Haptics.select() }
        case .silver:
            if sound { engine.play(.clinkLow, volume: 0.5) }
        case .won:
            if sound { engine.play(.success) }
            if haptics { Haptics.levelWon() }
        case .lost:
            if sound { engine.play(.runeHum, volume: 0.7) }
            if haptics { Haptics.illegal() }
        }
    }

    #if DEBUG
    /// `-LPRecipeDemo K`: plays K guesses through the tray taps, each a recipe still consistent with
    /// the feedback so far (a fixed order), waiting for the drops between guesses.
    func debugAutoplay(guesses: Int) async {
        var rng = SplitMix64(seed: 11)
        for _ in 0..<guesses {
            while isRevealing { try? await Task.sleep(for: .milliseconds(50)) }
            let options = RecipeCandidates.consistent(with: game.turns)
            guard !isOver, !options.isEmpty else { return }
            let pick = options[rng.nextInt(below: options.count)]
            for ingredient in pick.slots {
                try? await Task.sleep(for: .milliseconds(120))
                place(ingredient)
            }
            try? await Task.sleep(for: .milliseconds(300))
            brew()
        }
    }
    #endif
}
