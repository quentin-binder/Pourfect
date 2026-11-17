import BottleSortCore
import Match3Core
import SwiftUI

/// The Daily Gathering screen: today's level (Play / Replay, Share once won), streak numbers and a
/// month calendar of won days (three-star days gold), all in UTC days like the Daily Brew.
struct M3DailyView: View {
    let onPlay: (_ level: M3Level, _ date: DailyDate) -> Void

    @Environment(M3DailyModel.self) private var daily
    @Environment(\.colorRunesEnabled) private var runes
    @State private var shownMonth: DailyDate?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                todayCard
                statsGrid
                DailyCalendar(month: month, today: daily.today, stats: daily.stats,
                              canGoBack: month > earliestMonth, canGoForward: month < daily.today.firstOfMonth,
                              onMove: move(by:), perfectTitle: "3 stars")
                Label("Days follow UTC. A new gathering appears at midnight UTC.", systemImage: "globe")
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
        .navigationTitle(Text("Daily Gathering", comment: "Title of the daily match-3 level"))
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
        min(daily.history.results.first?.date ?? daily.today, daily.today).firstOfMonth
    }

    private func move(by months: Int) {
        let target = months < 0 ? month.previous.firstOfMonth : month.adding(days: month.daysInMonth)
        let clamped = min(max(target, earliestMonth), daily.today.firstOfMonth)
        withAnimation(.easeInOut(duration: 0.2)) {
            shownMonth = clamped == daily.today.firstOfMonth ? nil : clamped
        }
    }

    private var todayCard: some View {
        let spec = daily.spec
        let detail = daily.todayDetail
        return VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Text("Today · \(DailyText.longDate(daily.today))")
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .bottom) {
                Text(M3DailyText.label(spec))
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if let level = daily.level {
                    HStack(spacing: 4) {
                        ForEach(level.kinds, id: \.self) { M3KindIcon(kind: $0, size: 22, runes: runes) }
                    }
                }
            }
            HStack(spacing: 14) {
                Label(M3DailyText.tierName(spec.tier), systemImage: M3DailyText.symbol(spec.tier))
                    .font(.headline)
                DifficultyPips(level: spec.weekday.rawValue)
            }
            .foregroundStyle(.white)
            if let detail {
                HStack(spacing: 10) {
                    StarsView(count: detail.stars, size: 18)
                    Text("Score \(detail.score) · \(detail.movesLeft) moves left",
                         comment: "Daily gathering result: score and moves left at the win")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            HStack(spacing: 14) {
                playButton(solved: detail != nil)
                if let detail {
                    ShareLink(item: M3DailyText.share(date: daily.today, detail: detail)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Spacer(minLength: 0)
                DailyCountdown(gathering: true)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .bottomLeading)
        .background {
            Image(.chapter03)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
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
            .tint(M3DailyStyle.tint)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        } else {
            Button {} label: {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Gathering…", comment: "Daily gathering level is being generated")
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(true)
        }
    }

    private var statsGrid: some View {
        let stats = daily.stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            M3StatTile(value: stats.currentStreak, title: Text("Current streak"), symbol: "flame.fill", tint: .orange)
            M3StatTile(value: stats.bestStreak, title: Text("Best streak"), symbol: "trophy.fill", tint: .yellow)
            M3StatTile(value: stats.totalSolved, title: Text("Days gathered", comment: "Daily gathering stat: days won"),
                       symbol: "basket.fill", tint: M3DailyStyle.tint)
            M3StatTile(value: stats.perfectCount, title: Text("Three-star days", comment: "Daily gathering stat"),
                       symbol: "star.fill", tint: .yellow)
        }
    }
}

enum M3DailyStyle {
    static let tint = Color(red: 0.42, green: 0.72, blue: 0.4)

    static func summary(_ daily: M3DailyModel) -> Text {
        let streak = daily.stats.currentStreak
        if let detail = daily.todayDetail {
            return Text("Daily Gathering, \(M3DailyText.label(daily.spec)), won with \(detail.stars) stars, streak \(streak)",
                        comment: "VoiceOver: the daily gathering card, won today")
        }
        return Text("Daily Gathering, \(M3DailyText.label(daily.spec)), not played yet, streak \(streak)",
                    comment: "VoiceOver: the daily gathering card")
    }
}

private struct M3StatTile: View {
    let value: Int
    let title: Text
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            Text(value, format: .number)
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
            title.font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}
