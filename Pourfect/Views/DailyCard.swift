import BottleSortCore
import SwiftUI

/// "Daily Brew" on the home screen's side panel: today's label and mode, streak, solved /
/// perfect state and the countdown to the next puzzle.
struct DailyHomeCard: View {
    let action: () -> Void

    @Environment(DailyModel.self) private var daily

    var body: some View {
        let spec = daily.spec
        let result = daily.todayResult
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                DailyModeMedallion(mode: spec.mode, solved: result != nil)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Brew")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(spec.localizedLabel).font(.headline)
                    HStack(spacing: 8) {
                        if let result {
                            if result.isPerfect {
                                PerfectBadge()
                            } else {
                                Label("Solved", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        } else {
                            Label(spec.mode.localizedName, systemImage: spec.mode.symbol)
                                .font(.subheadline)
                        }
                    }
                    DailyCountdown()
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    FlameCount(count: daily.stats.currentStreak)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(LinearGradient(colors: [Color.orange.opacity(0.28), Color.orange.opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.orange.opacity(0.35)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DailyAccessibility.summary(daily))
        .accessibilityAddTraits(.isButton)
    }
}

/// The Daily Brew row in the iPhone bottom bar (narrow windows).
struct DailyBarRow: View {
    let action: () -> Void

    @Environment(DailyModel.self) private var daily

    var body: some View {
        let spec = daily.spec
        let result = daily.todayResult
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: result.map { $0.isPerfect ? "checkmark.seal.fill" : "checkmark.circle.fill" } ?? spec.mode.symbol)
                    .font(.title3)
                    .foregroundStyle(result.map { $0.isPerfect ? Color.yellow : Color.green } ?? Color.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Daily Brew · \(spec.weekday.localizedName)").font(.subheadline.weight(.semibold))
                    DailyCountdown()
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                FlameCount(count: daily.stats.currentStreak)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DailyAccessibility.summary(daily))
        .accessibilityAddTraits(.isButton)
    }
}

/// Mode icon in a round potion-glass medallion (checked once today's brew is solved).
private struct DailyModeMedallion: View {
    let mode: DailyMode
    let solved: Bool

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color.orange.opacity(0.75), Color.orange.opacity(0.2)],
                                         center: .center, startRadius: 2, endRadius: 30))
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
            Image(systemName: mode.symbol).font(.title2).foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
        .overlay(alignment: .bottomTrailing) {
            if solved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .green)
                    .offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Flame + number, compact.
private struct FlameCount: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").foregroundStyle(count > 0 ? Color.orange : Color.secondary)
            Text(count, format: .number).monospacedDigit()
        }
        .font(.headline)
    }
}

enum DailyAccessibility {
    static func summary(_ daily: DailyModel) -> Text {
        let spec = daily.spec
        let streak = daily.stats.currentStreak
        let state: String
        if let result = daily.todayResult {
            state = result.isPerfect ? String(localized: "solved perfectly") : String(localized: "solved")
        } else {
            state = spec.mode.localizedName
        }
        return Text("Daily Brew, \(spec.localizedLabel), \(state), streak \(streak)")
    }
}
