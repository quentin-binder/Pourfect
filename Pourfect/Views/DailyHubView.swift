import BottleSortCore
import DistilleryCore
import Match3Core
import SwiftUI

/// One daily game as the "Today" card and the daily hub show it (R10): its name, today's flavour,
/// whether today's level is won, and its own streak. Each game keeps its own screen (`route`).
struct DailyGameSummary: Identifiable {
    enum Status: Equatable {
        case notPlayed
        case solved
        case perfect
        case stars(Int)

        var isDone: Bool { self != .notPlayed }
    }

    enum Art: Equatable {
        case symbol(String)
        case basket
        case still
    }

    let id: String
    let title: String
    /// Today's flavour: "Monday · Gentle".
    let label: String
    /// What the game asks for, one line.
    let blurb: String
    let art: Art
    let tint: Color
    let status: Status
    let streak: Int
    let bestStreak: Int
    let route: Route
    let accessibility: Text
}

/// The daily games, in the order the hub lists them. To add a daily: give it a summary here (and a
/// route); the Today card and the hub pick it up.
@MainActor
enum DailyGames {
    static func today(brew: DailyModel, gathering: M3DailyModel, distill: DistillDailyModel) -> [DailyGameSummary] {
        let brewStatus: DailyGameSummary.Status = brew.todayResult.map { $0.isPerfect ? .perfect : .solved } ?? .notPlayed
        return [
            DailyGameSummary(
                id: "brew", title: String(localized: "Daily Brew"), label: brew.spec.localizedLabel,
                blurb: brew.spec.mode.localizedName, art: .symbol(brew.spec.mode.symbol), tint: .orange,
                status: brewStatus, streak: brew.stats.currentStreak, bestStreak: brew.stats.bestStreak,
                route: .daily, accessibility: DailyAccessibility.summary(brew)),
            DailyGameSummary(
                id: "gathering", title: String(localized: "Daily Gathering", comment: "Title of the daily match-3 level"),
                label: M3DailyText.label(gathering.spec),
                blurb: String(localized: "Match three, gather today's basket", comment: "Daily gathering card: what to do"),
                art: .basket, tint: M3DailyStyle.tint,
                status: gathering.todayDetail.map { .stars($0.stars) } ?? .notPlayed,
                streak: gathering.stats.currentStreak, bestStreak: gathering.stats.bestStreak,
                route: .m3Daily, accessibility: M3DailyStyle.summary(gathering)),
            DailyGameSummary(
                id: "distillery", title: String(localized: "Daily Distillery", comment: "Title of the daily distillery level"),
                label: DistillDailyText.label(distill.spec),
                blurb: String(localized: "Turn the pipes, fill every flask", comment: "Daily Distillery card: what to do"),
                art: .still, tint: DistillDailyStyle.tint,
                status: distill.todayDetail.map { .stars($0.stars) } ?? .notPlayed,
                streak: distill.stats.currentStreak, bestStreak: distill.stats.bestStreak,
                route: .distillDaily, accessibility: DistillDailyStyle.summary(distill)),
        ]
    }
}

/// Reads the daily models and hands their summaries to `content`.
private struct DailyGamesReader<Content: View>: View {
    @ViewBuilder let content: (_ games: [DailyGameSummary]) -> Content

    @Environment(DailyModel.self) private var brew
    @Environment(M3DailyModel.self) private var gathering
    @Environment(DistillDailyModel.self) private var distill

    var body: some View {
        content(DailyGames.today(brew: brew, gathering: gathering, distill: distill))
    }
}

/// A daily's small picture: an SF Symbol, the gathering basket or the distillery still.
struct DailyGameIcon: View {
    let game: DailyGameSummary
    var size: CGFloat = 28

    var body: some View {
        Group {
            switch game.art {
            case .symbol(let name): Image(systemName: name).font(.system(size: size * 0.62)).foregroundStyle(.white)
            case .basket: IngredientBasket(kinds: [.moonflower, .mushroom, .crystal], size: size)
            case .still: StillIcon(liquid: Palette.color(0), size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Today's state of a daily: a check, a gold seal, or its stars; nothing while unplayed.
private struct DailyStatusMark: View {
    let status: DailyGameSummary.Status
    var size: CGFloat = 13

    var body: some View {
        switch status {
        case .notPlayed:
            EmptyView()
        case .solved:
            Image(systemName: "checkmark.circle.fill").font(.system(size: size)).foregroundStyle(.white, .green)
        case .perfect:
            Image(systemName: "checkmark.seal.fill").font(.system(size: size)).foregroundStyle(PerfectBadge.gold)
        case .stars(let n):
            StarsView(count: n, size: size * 0.8)
        }
    }
}

/// A daily's medallion with a check once today's level is won.
private struct DailyMedallion: View {
    let game: DailyGameSummary
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [game.tint.opacity(0.8), game.tint.opacity(0.2)],
                                         center: .center, startRadius: 2, endRadius: size * 0.6))
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
            DailyGameIcon(game: game, size: size * 0.72)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if game.status.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.34))
                    .foregroundStyle(.white, .green)
                    .offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DailyFlame: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").foregroundStyle(count > 0 ? Color.orange : Color.secondary)
            Text(count, format: .number).monospacedDigit()
        }
        .font(.headline)
    }
}

private enum TodayText {
    static func done(_ games: [DailyGameSummary]) -> String {
        let done = games.filter(\.status.isDone).count
        if done == games.count {
            return String(localized: "All \(games.count) dailies done", comment: "Today card: every daily won today")
        }
        return String(localized: "\(done) of \(games.count) done", comment: "Today card: dailies won today of all dailies")
    }

    nonisolated static func countdown(seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return String(localized: "New dailies in \(m) m", comment: "Countdown to the next dailies, minutes") }
        return String(localized: "New dailies in \(h) h \(m) m", comment: "Countdown to the next dailies, hours and minutes")
    }

    static func accessibility(_ games: [DailyGameSummary]) -> Text {
        let names = games.map { "\($0.title) \($0.status.isDone ? String(localized: "won") : String(localized: "not played"))" }
            .joined(separator: ", ")
        return Text("Today's dailies, \(done(games)). \(names)", comment: "VoiceOver: the Today card on the map")
    }
}

// MARK: Map

/// "Today" on the home screen's side panel (wide windows): one card for every daily game, each
/// with today's state and streak; opens the daily hub.
struct TodayHomeCard: View {
    let action: () -> Void

    var body: some View {
        DailyGamesReader { games in
            Button(action: action) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Label {
                            Text("Today", comment: "Title of the card / screen with every daily game")
                        } icon: {
                            Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
                        }
                        .font(.title3.bold())
                        Spacer(minLength: 0)
                        Text(TodayText.done(games))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    ForEach(games) { game in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(game.tint.opacity(0.55))
                                DailyGameIcon(game: game, size: 22)
                            }
                            .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(game.title).font(.subheadline.weight(.semibold))
                                Text(game.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            DailyStatusMark(status: game.status)
                            DailyFlame(count: game.streak).font(.subheadline)
                                .frame(minWidth: 34, alignment: .trailing)
                        }
                    }
                    DailyCountdown(format: TodayText.countdown(seconds:))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(LinearGradient(colors: [Color.orange.opacity(0.26), Color.orange.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.orange.opacity(0.35)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TodayText.accessibility(games))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Opens the daily games", comment: "VoiceOver hint of the Today card"))
        }
    }
}

/// "Today" in the iPhone bottom bar (narrow windows): one row with each daily's icon and state.
struct TodayBarRow: View {
    let action: () -> Void

    var body: some View {
        DailyGamesReader { games in
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max.fill").font(.title3).foregroundStyle(.yellow).frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Today", comment: "Title of the card / screen with every daily game")
                            .font(.subheadline.weight(.semibold))
                        Text(TodayText.done(games)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        ForEach(games) { game in
                            ZStack {
                                Circle().fill(game.tint.opacity(game.status.isDone ? 0.75 : 0.35))
                                DailyGameIcon(game: game, size: 20)
                                    .opacity(game.status.isDone ? 1 : 0.8)
                            }
                            .frame(width: 30, height: 30)
                            .overlay(alignment: .bottomTrailing) {
                                if game.status.isDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white, .green)
                                        .offset(x: 2, y: 2)
                                }
                            }
                        }
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TodayText.accessibility(games))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Opens the daily games", comment: "VoiceOver hint of the Today card"))
        }
    }
}

// MARK: Hub

/// The daily hub (R10): every daily game in one list, each with today's flavour, its state and its
/// own streak; a row opens that game's own screen. All dailies turn over at midnight UTC.
struct DailyHubView: View {
    let onOpen: (_ route: Route) -> Void

    @Environment(DailyModel.self) private var brew
    @Environment(M3DailyModel.self) private var gathering
    @Environment(DistillDailyModel.self) private var distill

    var body: some View {
        DailyGamesReader { games in
            ScrollView {
                VStack(spacing: 14) {
                    header(games)
                    ForEach(games) { game in row(game) }
                    Label("Days follow UTC. New dailies appear at midnight UTC.", systemImage: "globe")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background { WorkbenchBackground(style: .game) }
        .environment(\.colorScheme, .dark)
        .navigationTitle(Text("Today", comment: "Title of the card / screen with every daily game"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.3), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) { SettingsButton() }
        }
        .onAppear { brew.refresh(); gathering.refresh(); distill.refresh() }
    }

    private func header(_ games: [DailyGameSummary]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text(DailyText.longDate(brew.today))
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
            Text("Today's dailies", comment: "Daily hub header title")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                Label(TodayText.done(games), systemImage: games.allSatisfy(\.status.isDone) ? "checkmark.seal.fill" : "sun.max.fill")
                    .font(.headline)
                    .foregroundStyle(games.allSatisfy(\.status.isDone) ? Color.yellow : Color.white)
                Spacer(minLength: 0)
                DailyCountdown(format: TodayText.countdown(seconds:))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .bottomLeading)
        .background {
            Image(.bgWorkbenchLandscape)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                }
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    private func row(_ game: DailyGameSummary) -> some View {
        Button { onOpen(game.route) } label: {
            HStack(alignment: .center, spacing: 14) {
                DailyMedallion(game: game)
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(game.label).font(.headline)
                    switch game.status {
                    case .notPlayed:
                        Text(game.blurb).font(.subheadline).foregroundStyle(.secondary)
                    case .solved:
                        Label("Solved", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    case .perfect:
                        PerfectBadge()
                    case .stars(let n):
                        StarsView(count: n, size: 14)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    DailyFlame(count: game.streak)
                    Text("Best \(game.bestStreak)", comment: "Daily hub row: the game's best streak")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .background(LinearGradient(colors: [game.tint.opacity(0.3), game.tint.opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(game.tint.opacity(0.4)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.accessibility)
        .accessibilityAddTraits(.isButton)
    }
}
