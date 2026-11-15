import BottleSortCore
import SwiftUI

struct LevelSelectView: View {
    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    let onSelect: (Int) -> Void
    let onRandom: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 14)]

    var body: some View {
        ScrollView {
            if let error = catalog.loadError {
                ContentUnavailableView("Levels unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            }
            randomButton
                .padding([.horizontal, .top])
            let ids = catalog.levels.map(\.id)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(catalog.levels.indices, id: \.self) { index in
                    let unlocked = progress.isUnlocked(index: index, ids: ids)
                    Button { onSelect(index) } label: {
                        LevelCell(number: index + 1, stars: progress.stars(for: ids[index]), unlocked: unlocked)
                    }
                    .buttonStyle(.plain)
                    .disabled(!unlocked)
                }
            }
            .padding()
        }
        .navigationTitle("LiquidPour")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onRandom) { Label("Random Level", systemImage: "dice") }
                    .help("Play a randomly generated level")
            }
        }
    }

    /// Large entry point for random levels, visible on every device above the level grid.
    private var randomButton: some View {
        Button(action: onRandom) {
            HStack(spacing: 14) {
                Image(systemName: "dice.fill").font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Random Level").font(.headline)
                    Text("Classic · Locks & Keys · Hidden layers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.22)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose a mode and board size, then generate a level")
    }
}

private struct LevelCell: View {
    let number: Int
    let stars: Int
    let unlocked: Bool

    var body: some View {
        VStack(spacing: 4) {
            if unlocked {
                Text("\(number)").font(.title2.bold().monospacedDigit())
                StarsView(count: stars, size: 10)
            } else {
                Image(systemName: "lock.fill").font(.title3)
                Text("\(number)").font(.caption.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .foregroundStyle(unlocked ? Color.primary : Color.secondary)
        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12)))
        .contentShape(Rectangle())
        .accessibilityLabel(unlocked ? "Level \(number), \(stars) stars" : "Level \(number), locked")
    }
}

struct StarsView: View {
    let count: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i < count ? Color.yellow : Color.secondary)
            }
        }
    }
}
