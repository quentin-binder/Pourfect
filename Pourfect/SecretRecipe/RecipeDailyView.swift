import BottleSortCore
import SecretRecipeCore
import SwiftUI

/// The daily Secret Recipe screen: today's recipe (Play / Continue / See the book, Share once
/// finished), the stats, the guess distribution, a calendar of won days, and Practice.
struct RecipeDailyView: View {
    let onPlay: (_ play: RecipePlay) -> Void

    @Environment(RecipeDailyModel.self) private var daily
    @State private var shownMonth: DailyDate?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                todayCard
                statsGrid
                RecipeDistribution(stats: daily.stats, today: daily.todayRecord?.isFinished == true ? daily.todayGame : nil)
                DailyCalendar(month: month, today: daily.today, stats: daily.stats.calendar,
                              canGoBack: month > earliestMonth, canGoForward: month < daily.today.firstOfMonth,
                              onMove: move(by:), perfectTitle: "4 guesses or fewer")
                Button { onPlay(.practice(RecipeGameView.randomSeed())) } label: {
                    Label { Text("Practice recipe", comment: "Opens an unlimited practice Secret Recipe") } icon: { Image(systemName: "book.closed") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Label("Days follow UTC. A new recipe is hidden at midnight UTC. Secret Recipe never counts toward the chapter map.",
                      systemImage: "globe")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background { WorkbenchBackground(style: .game) }
        .environment(\.colorScheme, .dark)
        .navigationTitle(Text("Secret Recipe", comment: "Title of the code-breaking recipe game"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.3), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) { SettingsButton() }
        }
        .onAppear { daily.refresh() }
    }

    private var month: DailyDate { shownMonth ?? daily.today.firstOfMonth }

    private var earliestMonth: DailyDate {
        min(daily.history.records.first?.date ?? daily.today, daily.today).firstOfMonth
    }

    private func move(by months: Int) {
        let target = months < 0 ? month.previous.firstOfMonth : month.adding(days: month.daysInMonth)
        let clamped = min(max(target, earliestMonth), daily.today.firstOfMonth)
        withAnimation(.easeInOut(duration: 0.2)) {
            shownMonth = clamped == daily.today.firstOfMonth ? nil : clamped
        }
    }

    private var todayCard: some View {
        let game = daily.todayGame
        let started = !game.turns.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Text("Today · \(DailyText.longDate(daily.today))")
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .center, spacing: 12) {
                Text("Secret Recipe", comment: "Title of the code-breaking recipe game")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Image(systemName: game.status == .won ? "lock.open.fill" : "lock.fill")
                    .font(.title)
                    .foregroundStyle(RecipeBook.brass)
                    .accessibilityHidden(true)
            }
            Text(RecipeDailyStatus.text(game))
                .font(.headline)
                .foregroundStyle(.white)
            if game.isOver {
                Text(RecipeShare.grid(game.turns))
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
            }
            HStack(spacing: 14) {
                Button { onPlay(.daily(daily.today)) } label: {
                    Label(game.isOver ? String(localized: "See the book", comment: "Opens the finished daily Secret Recipe")
                          : started ? String(localized: "Continue", comment: "Continues today's Secret Recipe")
                          : String(localized: "Play", comment: "Starts today's Secret Recipe"),
                          systemImage: game.isOver ? "book.fill" : "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(RecipeBook.tint)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                if game.isOver {
                    ShareLink(item: RecipeText.share(date: daily.today, game: game)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Spacer(minLength: 0)
                RecipeCountdown()
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .bottomLeading)
        .background {
            Image(.chapter06)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(RecipeBook.brass.opacity(0.35)))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    private var statsGrid: some View {
        let stats = daily.stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            RecipeStatTile(value: Text(stats.played, format: .number), title: Text("Played", comment: "Secret Recipe stat"),
                           symbol: "book.closed.fill", tint: RecipeBook.tint)
            RecipeStatTile(value: Text("\(stats.winPercent)%", comment: "Secret Recipe stat value: win percentage"),
                           title: Text("Cracked", comment: "Secret Recipe stat: share of days won"), symbol: "lock.open.fill", tint: RecipeBook.brass)
            RecipeStatTile(value: Text(stats.currentStreak, format: .number), title: Text("Current streak"), symbol: "flame.fill", tint: .orange)
            RecipeStatTile(value: Text(stats.bestStreak, format: .number), title: Text("Best streak"), symbol: "trophy.fill", tint: .yellow)
        }
    }
}

enum RecipeDailyStatus {
    static func text(_ game: RecipeGame) -> String {
        switch game.status {
        case .won: String(localized: "Cracked in \(game.turns.count) of \(RecipeGame.maxGuesses)", comment: "Daily Secret Recipe status: won")
        case .lost: String(localized: "Not cracked today", comment: "Daily Secret Recipe status: lost")
        case .playing:
            game.turns.isEmpty
                ? String(localized: "Eight guesses to open the alchemist's book", comment: "Daily Secret Recipe status: not started")
                : String(localized: "\(game.turns.count) of \(RecipeGame.maxGuesses) guesses brewed", comment: "Daily Secret Recipe status: in progress")
        }
    }
}

/// Bars of how many guesses each won day took (and the days not cracked); today's bar is lit.
struct RecipeDistribution: View {
    let stats: RecipeStats
    /// Today's finished game, to highlight its bar.
    let today: RecipeGame?

    var body: some View {
        let rows = Array(stats.distribution.enumerated()) + [(RecipeGame.maxGuesses, stats.lost)]
        let top = max(1, rows.map(\.1).max() ?? 1)
        VStack(alignment: .leading, spacing: 6) {
            Text("Guesses", comment: "Heading of the Secret Recipe guess distribution")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 4)
            ForEach(rows, id: \.0) { index, count in
                let lit = today.map { $0.status == .won ? $0.turns.count - 1 == index : index == RecipeGame.maxGuesses } ?? false
                HStack(spacing: 8) {
                    Text(index < RecipeGame.maxGuesses ? String(index + 1) : "✕")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(width: 18)
                    GeometryReader { geo in
                        let width = max(22, geo.size.width * CGFloat(count) / CGFloat(top))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(lit ? RecipeBook.tint : Color.white.opacity(0.18))
                            .frame(width: width)
                            .overlay(alignment: .trailing) {
                                Text(count, format: .number)
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .padding(.trailing, 6)
                            }
                    }
                    .frame(height: 20)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(index < RecipeGame.maxGuesses
                    ? Text("In \(index + 1) guesses: \(count) days", comment: "VoiceOver: a bar of the Secret Recipe guess distribution")
                    : Text("Not cracked: \(count) days", comment: "VoiceOver: the lost-days bar of the Secret Recipe guess distribution"))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
    }
}

private struct RecipeStatTile: View {
    let value: Text
    let title: Text
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            value.font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
            title.font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

struct RecipeCountdown: View {
    @Environment(RecipeDailyModel.self) private var daily

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(RecipeText.countdown(seconds: daily.secondsUntilNextRecipe(at: context.date)))
        }
    }
}

/// The temporary entry card (Challenges hub and the Daily Brew screen; it moves to the Today hub
/// later): today's status and streak, opening the daily screen, plus a Practice button.
struct RecipeEntryCard: View {
    let onDaily: () -> Void
    var onPractice: (() -> Void)?

    @Environment(RecipeDailyModel.self) private var daily
    @Environment(\.colorRunesEnabled) private var runes

    var body: some View {
        let game = daily.todayGame
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onDaily) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [RecipeBook.leatherLight, RecipeBook.leatherDark], startPoint: .top, endPoint: .bottom))
                        Image(systemName: game.status == .won ? "lock.open.fill" : "lock.fill")
                            .font(.title3)
                            .foregroundStyle(RecipeBook.brass)
                    }
                    .frame(width: 44, height: 52)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Secret Recipe", comment: "Title of the code-breaking recipe game")
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        Text(RecipeDailyStatus.text(game)).font(.headline)
                        HStack(spacing: 3) {
                            ForEach([RecipeIngredient.honeycomb, .moonflower, .starleaf, .crystal, .ember], id: \.self) {
                                RecipeIngredientIcon(ingredient: $0, size: 18, runes: runes)
                            }
                        }
                        RecipeCountdown()
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill").foregroundStyle(daily.stats.currentStreak > 0 ? Color.orange : Color.secondary)
                            Text(daily.stats.currentStreak, format: .number).monospacedDigit()
                        }
                        .font(.headline)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Secret Recipe, \(RecipeDailyStatus.text(game)), streak \(daily.stats.currentStreak)",
                                     comment: "VoiceOver: the Secret Recipe card"))
            .accessibilityAddTraits(.isButton)
            if let onPractice {
                Button(action: onPractice) {
                    Label { Text("Practice recipe", comment: "Opens an unlimited practice Secret Recipe") } icon: { Image(systemName: "book.closed") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint(Text("A new recipe to crack, as many times as you like. Nothing is saved.",
                                        comment: "VoiceOver hint: Secret Recipe practice"))
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [RecipeBook.tint.opacity(0.3), RecipeBook.tint.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RecipeBook.tint.opacity(0.4)))
    }
}
