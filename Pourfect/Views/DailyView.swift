import BottleSortCore
import SwiftUI

/// The Daily Brew screen: today's puzzle (Play / Replay), streak numbers and a month calendar of
/// solved and perfect days. Every day here is a UTC calendar day (the puzzle changes at
/// midnight UTC for everyone).
struct DailyView: View {
    let onPlay: (_ level: LevelDefinition, _ date: DailyDate) -> Void

    @Environment(DailyModel.self) private var daily
    /// First day of the month on show; nil = today's month.
    @State private var shownMonth: DailyDate?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                todayCard
                statsGrid
                DailyCalendar(month: month, today: daily.today, stats: daily.stats,
                              canGoBack: month > earliestMonth, canGoForward: month < daily.today.firstOfMonth,
                              onMove: move(by:))
                Label("Days follow UTC. A new brew appears at midnight UTC.", systemImage: "globe")
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
        .navigationTitle("Daily Brew")
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

    // MARK: Months

    private var month: DailyDate { shownMonth ?? daily.today.firstOfMonth }

    /// The calendar goes back to the month of the first saved result (or today's month).
    private var earliestMonth: DailyDate {
        min(daily.history.results.first?.date ?? daily.today, daily.today).firstOfMonth
    }

    private func move(by months: Int) {
        let target = months < 0 ? month.previous.firstOfMonth : month.adding(days: month.daysInMonth)
        let clamped = min(max(target, earliestMonth), daily.today.firstOfMonth)
        withAnimation(.easeInOut(duration: 0.2)) {
            shownMonth = clamped == daily.today.firstOfMonth ? nil : clamped
        }
    }

    // MARK: Today

    private var todayCard: some View {
        let spec = daily.spec
        let result = daily.todayResult
        return VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Text("Today · \(DailyText.longDate(daily.today))")
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
            Text(spec.localizedLabel)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            HStack(spacing: 14) {
                Label(spec.mode.localizedName, systemImage: spec.mode.symbol)
                    .font(.headline)
                DifficultyPips(level: spec.difficulty)
            }
            .foregroundStyle(.white)
            if let result {
                HStack(spacing: 10) {
                    if result.isPerfect {
                        PerfectBadge()
                    } else {
                        Label("Solved", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    Text("\(result.moves) moves · perfect is \(result.minMoves)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            HStack(spacing: 14) {
                playButton(solved: result != nil)
                VStack(alignment: .leading, spacing: 2) {
                    DailyCountdown()
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Resets at midnight UTC")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .bottomLeading)
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

    @ViewBuilder private func playButton(solved: Bool) -> some View {
        if let level = daily.level {
            Button { onPlay(level, daily.today) } label: {
                Label(solved ? "Replay" : "Play", systemImage: solved ? "arrow.counterclockwise" : "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        } else {
            Button {} label: {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Brewing…")
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(true)
        }
    }

    // MARK: Stats

    private var statsGrid: some View {
        let stats = daily.stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            StatTile(value: stats.currentStreak, title: "Current streak", symbol: "flame.fill", tint: .orange)
            StatTile(value: stats.bestStreak, title: "Best streak", symbol: "trophy.fill", tint: .yellow)
            StatTile(value: stats.totalSolved, title: "Brews solved", symbol: "checkmark.circle.fill", tint: .green)
            StatTile(value: stats.perfectCount, title: "Perfect", symbol: "checkmark.seal.fill", tint: .yellow)
        }
    }
}

// MARK: - Calendar

/// One UTC month, Monday first: solved days filled, perfect days gold with a seal, today ringed,
/// future days dimmed.
struct DailyCalendar: View {
    let month: DailyDate
    let today: DailyDate
    let stats: DailyStats
    let canGoBack: Bool
    let canGoForward: Bool
    let onMove: (_ months: Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { onMove(-1) } label: { Image(systemName: "chevron.left").padding(6) }
                    .disabled(!canGoBack)
                    .accessibilityLabel(Text("Previous month"))
                Spacer()
                Text(DailyText.monthTitle(month))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button { onMove(1) } label: { Image(systemName: "chevron.right").padding(6) }
                    .disabled(!canGoForward)
                    .accessibilityLabel(Text("Next month"))
            }
            .buttonStyle(.borderless)
            .font(.headline)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Text(day.shortSymbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                // Leading blanks (negative ids, so they never clash with the day offsets).
                ForEach((0..<(month.weekday.rawValue - 1)).map { -1 - $0 }, id: \.self) { _ in
                    Color.clear.frame(height: 1)
                }
                ForEach(0..<month.daysInMonth, id: \.self) { offset in
                    let date = month.adding(days: offset)
                    DayCell(date: date, isSolved: stats.solvedDates.contains(date),
                            isPerfect: stats.perfectDates.contains(date),
                            isToday: date == today, isFuture: date > today)
                }
            }
            .id(month)

            HStack(spacing: 16) {
                legend(Circle().fill(Color.orange.opacity(0.85)), "Solved")
                legend(Circle().fill(PerfectBadge.gold), "Perfect")
                legend(Circle().strokeBorder(.white, lineWidth: 2), "Today")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
    }

    private func legend(_ swatch: some View, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            swatch.frame(width: 12, height: 12)
            Text(title)
        }
    }
}

private struct DayCell: View {
    let date: DailyDate
    let isSolved: Bool
    let isPerfect: Bool
    let isToday: Bool
    let isFuture: Bool

    var body: some View {
        ZStack {
            if isPerfect {
                Circle().fill(PerfectBadge.gold)
            } else if isSolved {
                Circle().fill(Color.orange.opacity(0.85))
            } else {
                Circle().fill(Color.white.opacity(isFuture ? 0.03 : 0.07))
            }
            if isToday {
                Circle().strokeBorder(.white, lineWidth: 2)
                    .shadow(color: .orange.opacity(0.9), radius: 6)
            }
            Text(date.day, format: .number)
                .font(.callout.weight(isToday || isSolved ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isPerfect ? Color.black : Color.white)
        }
        .overlay(alignment: .topTrailing) {
            if isPerfect {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, Color(red: 0.55, green: 0.38, blue: 0.05))
                    .offset(x: 3, y: -3)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 46)
        .opacity(isFuture ? 0.35 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(DailyText.longDate(date)))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: Text {
        if isPerfect { return Text("Perfect solve") }
        if isSolved { return Text("Solved") }
        if isToday { return Text("Today, not solved yet") }
        return Text(verbatim: "")
    }
}

// MARK: - Small pieces

/// Gold "Perfect" seal: solved in the solver's minimum without a hint.
struct PerfectBadge: View {
    var large = false

    static let gold = LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.4), Color(red: 0.93, green: 0.65, blue: 0.13)],
                                     startPoint: .top, endPoint: .bottom)

    var body: some View {
        Label("Perfect", systemImage: "checkmark.seal.fill")
            .font(large ? .title3.weight(.bold) : .subheadline.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, large ? 14 : 10).padding(.vertical, large ? 7 : 4)
            .background(Self.gold, in: Capsule())
            .shadow(color: .yellow.opacity(0.4), radius: large ? 8 : 4)
            .accessibilityLabel(Text("Perfect solve"))
    }
}

/// Flame with the current streak.
struct StreakFlame: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundStyle(count > 0 ? Color.orange : Color.secondary)
            Text("Streak \(count)").monospacedDigit()
        }
        .font(.headline)
        .accessibilityElement(children: .combine)
    }
}

/// Seven pips, filled up to the day's difficulty (Monday 1 … Sunday 7).
struct DifficultyPips: View {
    let level: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...7, id: \.self) { i in
                Circle()
                    .fill(i <= level ? Color.orange : Color.white.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Difficulty \(level) of 7"))
    }
}

/// "New brew in 3 h 12 m", updated every 30 seconds.
struct DailyCountdown: View {
    @Environment(DailyModel.self) private var daily

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(DailyText.countdown(seconds: daily.secondsUntilNextPuzzle(at: context.date)))
        }
    }
}

private struct StatTile: View {
    let value: Int
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            Text(value, format: .number)
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}
