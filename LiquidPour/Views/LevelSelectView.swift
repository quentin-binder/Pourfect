import BottleSortCore
import SwiftUI

struct LevelSelectView: View {
    @Environment(LevelCatalog.self) private var catalog
    @Environment(ProgressModel.self) private var progress
    let onSelect: (_ pack: String, _ index: Int) -> Void
    let onRandom: () -> Void

    #if os(iOS)
    @State private var showsSettings = false
    #endif

    /// Last viewed pack (a per-device convenience).
    @AppStorage("levelSelect.pack") private var selectedPackID = ""

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 14)]

    private var selectedPack: LevelPackInfo? {
        catalog.pack(id: selectedPackID) ?? catalog.packs.first
    }

    var body: some View {
        ScrollView {
            ForEach(catalog.loadErrors, id: \.self) { error in
                ContentUnavailableView("Recipes unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            }
            randomButton
                .padding([.horizontal, .top])
            packPicker
                .padding(.top, 8)
            if let pack = selectedPack {
                if let subtitle = pack.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
                let ids = pack.levels.map(\.id)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(pack.levels.indices, id: \.self) { index in
                        let unlocked = progress.isUnlocked(index: index, ids: ids)
                        Button { onSelect(pack.id, index) } label: {
                            LevelCell(number: index + 1, stars: progress.stars(for: ids[index]), unlocked: unlocked)
                        }
                        .buttonStyle(.plain)
                        .disabled(!unlocked)
                    }
                }
                .padding()
                .id(pack.id)
            }
        }
        .background { WorkbenchBackground(style: .menu) }
        .navigationTitle("Pourfect")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onRandom) { Label("Random Brew", systemImage: "dice") }
                    .help("Brew a randomly generated recipe")
            }
            ToolbarItem(placement: .primaryAction) {
                settingsButton
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showsSettings) {
            NavigationStack { SettingsView(showsDone: true) }
        }
        #endif
    }

    /// Opens Settings: the Settings window on the Mac (same as ⌘,), a sheet on iOS.
    @ViewBuilder private var settingsButton: some View {
        #if os(macOS)
        SettingsLink { Label("Settings", systemImage: "gearshape") }
            .help("Sound, color runes and motion")
        #else
        Button { showsSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        #endif
    }

    /// Horizontal row of chapter chips with earned/total stars.
    private var packPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(catalog.packs) { pack in
                    let selected = pack.id == selectedPack?.id
                    let earned = pack.levels.reduce(0) { $0 + progress.stars(for: $1.id) }
                    Button { selectedPackID = pack.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pack.name).font(.subheadline.weight(.semibold))
                            Text("★ \(earned)/\(pack.levels.count * 3)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(selected ? Color.primary.opacity(0.8) : Color.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(selected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(pack.name) chapter, \(earned) of \(pack.levels.count * 3) stars"))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }

    /// Large entry point for random recipes, visible on every device above the recipe grid.
    private var randomButton: some View {
        Button(action: onRandom) {
            HStack(spacing: 14) {
                Image(systemName: "dice.fill").font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Random Brew").font(.headline)
                    Text("Classic · Rune Seals · Murky Layers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.22)))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Choose a mode and workbench size, then brew a recipe"))
    }
}

private struct LevelCell: View {
    let number: Int
    let stars: Int
    let unlocked: Bool

    var body: some View {
        VStack(spacing: 4) {
            if unlocked {
                Text(number, format: .number).font(.title2.bold().monospacedDigit())
                StarsView(count: stars, size: 10)
            } else {
                Image(systemName: "lock.fill").font(.title3)
                Text(number, format: .number).font(.caption.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .foregroundStyle(unlocked ? Color.primary : Color.secondary)
        .background(RoundedRectangle(cornerRadius: 14).fill(unlocked ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12)))
        .contentShape(Rectangle())
        .accessibilityLabel(unlocked ? Text("Recipe \(number), \(stars) stars") : Text("Recipe \(number), locked"))
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
