import BottleSortCore
import SecretRecipeCore
import SwiftUI

/// Colors of the alchemist's recipe book.
enum RecipeBook {
    static let leatherLight = Color(red: 0.46, green: 0.17, blue: 0.12)
    static let leatherDark = Color(red: 0.22, green: 0.07, blue: 0.06)
    static let brass = Color(red: 0.93, green: 0.74, blue: 0.36)
    static let parchmentLight = Color(red: 0.97, green: 0.91, blue: 0.78)
    static let parchmentDark = Color(red: 0.88, green: 0.78, blue: 0.6)
    static let ink = Color(red: 0.24, green: 0.14, blue: 0.08)
    static let rule = Color(red: 0.55, green: 0.38, blue: 0.22).opacity(0.35)
    static let tint = Color(red: 0.78, green: 0.45, blue: 0.2)
}

/// A Secret Recipe game (R10b): the locked recipe book with every guess and its drops, the brewing
/// bench (five slots), the ingredient tray with notes, and Brew. The daily is saved after every
/// brew; a practice recipe can be swapped for a new one at any time.
struct RecipeGameView: View {
    @State private var play: RecipePlay
    @State private var model: RecipeBoardModel?
    @State private var showsEndCard = false
    @State private var tip: [TutorialTopic]?
    @Environment(RecipeDailyModel.self) private var daily
    @Environment(TutorialModel.self) private var tutorials
    @Environment(AppSettings.self) private var settings
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @Environment(\.colorRunesEnabled) private var runes
    @Environment(\.dismiss) private var dismiss
    @AppStorage("recipe.practice.showsCount") private var showsCount = true

    init(play: RecipePlay) {
        _play = State(initialValue: play)
    }

    var body: some View {
        ZStack {
            Color.clear
            if let model {
                GeometryReader { geo in
                    let wide = geo.size.width >= 760
                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: 28) {
                                book(model, rowHeight: min(46, max(34, (geo.size.height - 150) / 9)))
                                    .frame(maxWidth: 460)
                                VStack(spacing: 18) {
                                    bench(model, slot: 56)
                                    tray(model, cell: 62, columns: 4)
                                    controls(model)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: 340)
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity)
                        } else {
                            let cell = min(54, (geo.size.width - 32 - 16 - 7 * 6) / 8)
                            ScrollView {
                                VStack(spacing: 14) {
                                    book(model, rowHeight: 31)
                                    bench(model, slot: min(58, (geo.size.width - 32 - 4 * 9) / 5.6))
                                    tray(model, cell: cell, columns: 8)
                                    controls(model)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: 560)
                                .frame(maxWidth: .infinity)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                    }
                }
                .overlay { if showsEndCard, model.showsEnd { endCard(model) } }
                .overlay {
                    if let tip {
                        TutorialOverlay(topics: tip) {
                            tutorials.markSeen(tip)
                            withAnimation(reduceMotion ? nil : .default) { self.tip = nil }
                        }
                        .transition(.opacity)
                    }
                }
                .background { keyboardShortcuts(model) }
                .onChange(of: model.showsEnd) { _, ended in
                    if ended { withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) { showsEndCard = true } }
                }
            }
        }
        .background { WorkbenchBackground(style: .game) }
        .environment(\.colorScheme, .dark)
        .navigationTitle(play.isDaily ? Text("Daily Secret Recipe", comment: "Title of the daily Secret Recipe game")
                                      : Text("Secret Recipe Practice", comment: "Title of a practice Secret Recipe game"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.25), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation(reduceMotion ? nil : .default) { tip = [.recipe] } } label: {
                    Label("How to play", systemImage: "questionmark.circle")
                }
                .keyboardShortcut("/", modifiers: .command)
                .help(Text("How Secret Recipe works", comment: "Tooltip of the Secret Recipe help button"))
            }
            if case .practice = play {
                ToolbarItem(placement: .primaryAction) {
                    Button { newPractice() } label: {
                        Label { Text("New recipe", comment: "Starts another practice Secret Recipe") } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help(Text("Hide a new practice recipe", comment: "Tooltip of the new practice recipe button"))
                }
            }
        }
        .task(id: play) { load() }
        .task {
            let unseen = tutorials.unseen([.recipe])
            guard tip == nil, !unseen.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(reduceMotion ? nil : .default) { tip = unseen }
        }
        .onChange(of: settings.value, initial: true) { _, value in model?.settings = value }
        .onChange(of: reduceMotion, initial: true) { _, value in model?.reduceMotion = value }
        .task { if settings.value.soundEnabled { SoundEngine.shared.warmUp() } }
        .onDisappear { model?.stop() }
    }

    // MARK: Setup

    private func load() {
        model?.stop()
        #if DEBUG
        let demo = UserDefaults.standard.integer(forKey: "LPRecipeDemo")
        #else
        let demo = 0
        #endif
        let game: RecipeGame
        switch play {
        case .daily(let date): game = daily.game(for: date)
        case .practice(let seed): game = RecipePractice.game(seed: seed)
        }
        let fresh = RecipeBoardModel(play: play, game: game, isDemo: demo > 0)
        if case .daily(let date) = play {
            fresh.onBrew = { [daily] guesses in daily.save(date: date, guesses: guesses) }
        }
        fresh.settings = settings.value
        fresh.reduceMotion = reduceMotion
        model = fresh
        showsEndCard = false
        #if DEBUG
        if demo > 0 { Task { await fresh.debugAutoplay(guesses: demo) } }
        #endif
    }

    private func newPractice() {
        withAnimation(reduceMotion ? nil : .default) { play = .practice(RecipeGameView.randomSeed()) }
    }

    static func randomSeed() -> UInt64 { UInt64.random(in: 1...999_999_999) }

    // MARK: The book

    private func book(_ model: RecipeBoardModel, rowHeight: CGFloat) -> some View {
        let game = model.game
        let icon = rowHeight * 0.8
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: game.status == .won ? "lock.open.fill" : "lock.fill")
                    .font(.title2)
                    .foregroundStyle(RecipeBook.brass)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("The Alchemist's Recipe", comment: "Heading of the Secret Recipe book")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(RecipeBook.parchmentLight)
                    Text(subtitle(model))
                        .font(.caption)
                        .foregroundStyle(RecipeBook.parchmentLight.opacity(0.75))
                }
                Spacer(minLength: 4)
                Text("\(game.guessesLeft) left", comment: "Secret Recipe: guesses left")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(RecipeBook.brass)
                    .opacity(game.isOver ? 0 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .accessibilityElement(children: .combine)
            VStack(spacing: 0) {
                ForEach(0..<RecipeGame.maxGuesses, id: \.self) { index in
                    bookRow(model, index: index, icon: icon)
                        .frame(height: rowHeight)
                    if index < RecipeGame.maxGuesses - 1 {
                        Rectangle().fill(RecipeBook.rule).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LinearGradient(colors: [RecipeBook.parchmentLight, RecipeBook.parchmentDark],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .bottom], 8)
            if case .practice = model.play, !model.game.turns.isEmpty, !model.isOver {
                candidatesLine(model)
            }
        }
        .background(LinearGradient(colors: [RecipeBook.leatherLight, RecipeBook.leatherDark],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(RecipeBook.brass.opacity(0.7), lineWidth: 1.5))
        .overlay(alignment: .topLeading) { corner }
        .overlay(alignment: .topTrailing) { corner.scaleEffect(x: -1) }
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }

    /// A small brass corner fitting on the leather cover.
    private var corner: some View {
        Canvas { context, size in
            let path = Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: size.width, y: 0))
                p.addQuadCurve(to: CGPoint(x: 0, y: size.height), control: CGPoint(x: size.width * 0.25, y: size.height * 0.25))
                p.closeSubpath()
            }
            context.fill(path, with: .color(RecipeBook.brass.opacity(0.85)))
        }
        .frame(width: 16, height: 16)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func subtitle(_ model: RecipeBoardModel) -> String {
        switch model.play {
        case .daily(let date): String(localized: "Today's recipe · \(M3DailyText.shortDate(date))", comment: "Secret Recipe book subtitle: the daily and its date")
        case .practice: String(localized: "Practice recipe", comment: "Secret Recipe book subtitle")
        }
    }

    private func bookRow(_ model: RecipeBoardModel, index: Int, icon: CGFloat) -> some View {
        let turns = model.game.turns
        let isNewest = index == turns.count - 1
        return HStack(spacing: 6) {
            Text(index + 1, format: .number)
                .font(.system(size: icon * 0.5, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(RecipeBook.ink.opacity(0.6))
                .frame(width: icon * 0.6)
            if index < turns.count {
                let turn = turns[index]
                HStack(spacing: icon * 0.12) {
                    ForEach(Array(turn.guess.slots.enumerated()), id: \.offset) { _, ingredient in
                        RecipeIngredientIcon(ingredient: ingredient, size: icon, runes: runes)
                    }
                }
                Spacer(minLength: 4)
                RecipeDropsView(feedback: turn.feedback, size: icon * 0.55,
                                revealed: isNewest ? model.revealedDrops : RecipeCode.length)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RecipeBook.ink.opacity(0.85), in: Capsule())
            } else {
                HStack(spacing: icon * 0.12) {
                    ForEach(0..<RecipeCode.length, id: \.self) { _ in
                        Circle().strokeBorder(RecipeBook.ink.opacity(index == turns.count && !model.isOver ? 0.35 : 0.12),
                                              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: icon * 0.7, height: icon * 0.7)
                            .frame(width: icon, height: icon)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(turns, index: index))
    }

    private func rowLabel(_ turns: [RecipeTurn], index: Int) -> Text {
        guard index < turns.count else {
            return Text("Guess \(index + 1): not brewed yet", comment: "VoiceOver: an empty line of the Secret Recipe book")
        }
        let turn = turns[index]
        return Text("Guess \(index + 1): \(RecipeText.ingredients(turn.guess)). \(RecipeText.feedback(turn.feedback))",
                    comment: "VoiceOver: a line of the Secret Recipe book: number, the five ingredients, the feedback")
    }

    private func candidatesLine(_ model: RecipeBoardModel) -> some View {
        HStack(spacing: 8) {
            if showsCount {
                Text("Possible recipes left: \(model.candidatesLeft)", comment: "Secret Recipe practice helper: recipes still consistent with every clue")
                    .monospacedDigit()
            } else {
                Text("Possible recipes left: hidden", comment: "Secret Recipe practice helper, turned off")
            }
            Spacer(minLength: 0)
            Button { showsCount.toggle() } label: {
                Image(systemName: showsCount ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(showsCount ? Text("Hide the count", comment: "VoiceOver: hide possible recipes count")
                                           : Text("Show the count", comment: "VoiceOver: show possible recipes count"))
        }
        .font(.caption)
        .foregroundStyle(RecipeBook.parchmentLight.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: The bench (draft or the revealed recipe)

    private func bench(_ model: RecipeBoardModel, slot: CGFloat) -> some View {
        let revealed = model.showsEnd ? model.game.revealed : nil
        return VStack(spacing: 6) {
            HStack(spacing: slot * 0.14) {
                ForEach(0..<RecipeCode.length, id: \.self) { index in
                    if let revealed {
                        slotView(revealed.slots[index], size: slot, active: false, solved: true)
                            .accessibilityLabel(Text("Slot \(index + 1): \(revealed.slots[index].displayName)",
                                                     comment: "VoiceOver: a slot of the revealed recipe"))
                    } else {
                        let ingredient = model.draft[index]
                        Button { model.tapSlot(index) } label: {
                            slotView(ingredient, size: slot, active: index == model.cursor && !model.isOver, solved: false)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isOver)
                        .dropDestination(for: String.self) { items, _ in
                            guard let raw = items.first.flatMap(Int.init), let ingredient = RecipeIngredient(rawValue: raw) else { return false }
                            model.drop(ingredient, at: index)
                            return true
                        }
                        .accessibilityLabel(ingredient.map { Text("Slot \(index + 1): \($0.displayName)", comment: "VoiceOver: a filled slot of the brewing bench") }
                                            ?? Text("Slot \(index + 1): empty", comment: "VoiceOver: an empty slot of the brewing bench"))
                        .accessibilityHint(ingredient == nil ? Text("The next ingredient you pick goes here", comment: "VoiceOver hint: empty slot")
                                                             : Text("Clears this slot", comment: "VoiceOver hint: filled slot"))
                        .accessibilityAddTraits(index == model.cursor ? .isSelected : [])
                    }
                }
            }
            .modifier(Shake(amount: reduceMotion ? 0 : 8, trigger: model.refusals))
            Text(benchCaption(model))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func benchCaption(_ model: RecipeBoardModel) -> String {
        switch model.game.status {
        case .won: String(localized: "The book opens: this is the recipe.", comment: "Secret Recipe bench caption after a win")
        case .lost: String(localized: "The book stays shut. The recipe was:", comment: "Secret Recipe bench caption after a loss, above the revealed recipe")
        case .playing:
            model.isRevealing ? String(localized: "Brewing…", comment: "Secret Recipe: the drops of a guess are appearing")
                : String(localized: "Pick five different ingredients, then brew.", comment: "Secret Recipe bench caption")
        }
    }

    private func slotView(_ ingredient: RecipeIngredient?, size: CGFloat, active: Bool, solved: Bool) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.2), Color(white: 0.06)], center: .center, startRadius: 2, endRadius: size * 0.6))
            Circle()
                .strokeBorder(solved ? RecipeDrop.goldLight : active ? RecipeBook.brass : .white.opacity(0.25),
                              lineWidth: active || solved ? 2.5 : 1.2)
            if let ingredient {
                RecipeIngredientIcon(ingredient: ingredient, size: size * 0.74, runes: runes)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }

    // MARK: The tray

    private func tray(_ model: RecipeBoardModel, cell: CGFloat, columns: Int) -> some View {
        let grid = Array(repeating: GridItem(.fixed(cell), spacing: 6), count: columns)
        return VStack(spacing: 8) {
            LazyVGrid(columns: grid, spacing: 6) {
                ForEach(RecipeIngredient.allCases, id: \.self) { ingredient in
                    trayItem(model, ingredient, cell: cell)
                }
            }
            .padding(8)
            .background(M3Colors.tray.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(M3Colors.woodLight.opacity(0.6), lineWidth: 1.5))
        }
    }

    private func trayItem(_ model: RecipeBoardModel, _ ingredient: RecipeIngredient, cell: CGFloat) -> some View {
        let note = model.note(ingredient)
        let placed = model.draft.contains(ingredient)
        return Button { model.tap(ingredient) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: cell * 0.2)
                    .fill(placed ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                RecipeIngredientIcon(ingredient: ingredient, size: cell * 0.8, runes: runes)
                    .opacity(note == .ruledOut ? 0.3 : 1)
                if note == .ruledOut {
                    Image(systemName: "xmark")
                        .font(.system(size: cell * 0.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.3).opacity(0.9))
                }
            }
            .frame(width: cell, height: cell)
            .overlay(alignment: .topTrailing) {
                if note == .maybe {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: cell * 0.3))
                        .foregroundStyle(.black, RecipeBook.brass)
                        .offset(x: 3, y: -3)
                }
            }
            .overlay(alignment: .bottom) {
                if placed {
                    Capsule().fill(RecipeBook.brass).frame(width: cell * 0.35, height: 3).offset(y: 2)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: cell * 0.2)
                .strokeBorder(model.notesMode ? RecipeBook.brass.opacity(0.6) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isOver)
        .draggable(String(ingredient.rawValue)) {
            RecipeIngredientIcon(ingredient: ingredient, size: cell * 0.8, runes: runes)
        }
        .contextMenu {
            Button { setNote(model, ingredient, .ruledOut) } label: { Label("Ruled out", systemImage: "xmark") }
            Button { setNote(model, ingredient, .maybe) } label: { Label("Maybe", systemImage: "questionmark") }
            Button { setNote(model, ingredient, .none) } label: { Label("No note", systemImage: "circle") }
        }
        .help(Text("\(ingredient.displayName) (\(String(ingredient.key)))", comment: "Tooltip of a tray ingredient: its name and Mac keyboard key"))
        .accessibilityLabel(trayLabel(ingredient, note: note, placed: placed))
        .accessibilityHint(model.notesMode ? Text("Changes its note", comment: "VoiceOver hint: tray ingredient in notes mode")
                                           : Text("Puts it in the selected slot", comment: "VoiceOver hint: tray ingredient"))
        .accessibilityAction(named: Text("Change note", comment: "VoiceOver action: cycle a tray ingredient's note")) {
            model.cycleNote(ingredient)
        }
    }

    private func setNote(_ model: RecipeBoardModel, _ ingredient: RecipeIngredient, _ note: RecipeNote) {
        while model.note(ingredient) != note { model.cycleNote(ingredient) }
    }

    private func trayLabel(_ ingredient: RecipeIngredient, note: RecipeNote, placed: Bool) -> Text {
        let state: String
        switch note {
        case .ruledOut: state = String(localized: "noted: ruled out", comment: "VoiceOver: a tray ingredient's note")
        case .maybe: state = String(localized: "noted: maybe", comment: "VoiceOver: a tray ingredient's note")
        case .none: state = ""
        }
        let onBench = placed ? String(localized: "on the bench", comment: "VoiceOver: this tray ingredient is in the draft") : ""
        return Text([ingredient.displayName, onBench, state].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    // MARK: Controls

    @ViewBuilder private func controls(_ model: RecipeBoardModel) -> some View {
        if model.showsEnd {
            endButtons(model)
        } else {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { model.notesMode }, set: { model.notesMode = $0 })) {
                    Label { Text("Notes", comment: "Secret Recipe: notes mode toggle") } icon: { Image(systemName: "pencil") }
                }
                .toggleStyle(.button)
                .accessibilityHint(Text("When on, tapping an ingredient marks it ruled out, then maybe, then clears the mark",
                                        comment: "VoiceOver hint: Secret Recipe notes toggle"))
                Button { model.clearDraft() } label: {
                    Label { Text("Clear", comment: "Secret Recipe: empty the five slots") } icon: { Image(systemName: "xmark.circle") }
                }
                .disabled(!model.draft.contains { $0 != nil } || model.isOver)
                Spacer(minLength: 0)
                Button { model.brew() } label: {
                    Label { Text("Brew", comment: "Secret Recipe: submit the guess") } icon: { Image(systemName: "flame.fill") }
                        .font(.headline)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(RecipeBook.tint)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isOver || model.isRevealing)
                .accessibilityHint(Text("Tries these five ingredients as the recipe", comment: "VoiceOver hint: Brew"))
            }
            .buttonStyle(.bordered)
            .lineLimit(1)
        }
    }

    @ViewBuilder private func endButtons(_ model: RecipeBoardModel) -> some View {
        HStack(spacing: 12) {
            if case .daily(let date) = model.play {
                ShareLink(item: RecipeText.share(date: date, game: model.game)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button { dismiss() } label: { Label { Text("Done", comment: "Leaves the finished Secret Recipe") } icon: { Image(systemName: "checkmark") } }
                    .buttonStyle(.borderedProminent)
                    .tint(RecipeBook.tint)
            } else {
                Spacer(minLength: 0)
                Button { newPractice() } label: {
                    Label { Text("New recipe", comment: "Starts another practice Secret Recipe") } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                }
                .buttonStyle(.borderedProminent)
                .tint(RecipeBook.tint)
            }
        }
        .controlSize(.large)
    }

    // MARK: End card

    private func endCard(_ model: RecipeBoardModel) -> some View {
        let game = model.game
        let won = game.status == .won
        return ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { showsEndCard = false }
            VStack(spacing: 14) {
                Image(systemName: won ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(RecipeBook.brass)
                    .symbolEffect(.bounce, value: reduceMotion ? false : won)
                    .accessibilityHidden(true)
                Text(won ? String(localized: "Recipe cracked!", comment: "Secret Recipe win card title")
                         : String(localized: "The book stays shut", comment: "Secret Recipe loss card title"))
                    .font(.system(.title, design: .serif).bold())
                Text(won ? String(localized: "Found in \(game.turns.count) of \(RecipeGame.maxGuesses) guesses", comment: "Secret Recipe win card: guesses used")
                         : String(localized: "The alchemist's recipe was:", comment: "Secret Recipe loss card, above the revealed recipe"))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Array(game.secret.slots.enumerated()), id: \.offset) { _, ingredient in
                        VStack(spacing: 2) {
                            RecipeIngredientIcon(ingredient: ingredient, size: 40, runes: runes)
                            Text(ingredient.displayName).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(width: 58)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("The recipe: \(RecipeText.ingredients(game.secret))", comment: "VoiceOver: the revealed Secret Recipe"))
                if case .daily = model.play {
                    let stats = daily.stats
                    HStack(spacing: 18) {
                        Label { Text("Streak \(stats.currentStreak)", comment: "Secret Recipe end card: current streak").monospacedDigit() } icon: {
                            Image(systemName: "flame.fill").foregroundStyle(.orange)
                        }
                        Label { Text("Won \(stats.winPercent)%", comment: "Secret Recipe end card: win percentage").monospacedDigit() } icon: {
                            Image(systemName: "chart.bar.fill").foregroundStyle(RecipeBook.brass)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    Text(RecipeShare.grid(game.turns))
                        .font(.system(size: 13))
                        .lineSpacing(1)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 12) {
                    Button { withAnimation(reduceMotion ? nil : .default) { showsEndCard = false } } label: {
                        Text("See the book", comment: "Secret Recipe end card: close it to look at the guesses")
                    }
                    .buttonStyle(.bordered)
                    if case .daily(let date) = model.play {
                        ShareLink(item: RecipeText.share(date: date, game: game)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RecipeBook.tint)
                    } else {
                        Button { newPractice() } label: { Text("New recipe", comment: "Starts another practice Secret Recipe") }
                            .buttonStyle(.borderedProminent)
                            .tint(RecipeBook.tint)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 400)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RecipeBook.brass.opacity(0.5)))
            .padding(24)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            .accessibilityAddTraits(.isModal)
        }
    }

    // MARK: Keyboard (Mac, and iPad / iPhone with a keyboard)

    /// 1–8 pick a tray ingredient, Delete clears the last slot (Return brews: the Brew button).
    private func keyboardShortcuts(_ model: RecipeBoardModel) -> some View {
        ZStack {
            ForEach(RecipeIngredient.allCases, id: \.self) { ingredient in
                Button { model.tap(ingredient) } label: { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(ingredient.key), modifiers: [])
            }
            Button { model.backspace() } label: { EmptyView() }
                .keyboardShortcut(.delete, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .disabled(model.isOver || tip != nil || showsEndCard)
    }
}

/// A small horizontal shake each time `trigger` changes.
private struct Shake: ViewModifier {
    var amount: CGFloat
    var trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(amount, duration: 0.06)
                LinearKeyframe(-amount, duration: 0.08)
                LinearKeyframe(amount * 0.5, duration: 0.08)
                LinearKeyframe(0, duration: 0.06)
            }
        }
    }
}
