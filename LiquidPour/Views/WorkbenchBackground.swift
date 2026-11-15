import SwiftUI

/// The painted alchemist's workbench (asset catalog `bg_workbench_landscape` /
/// `bg_workbench_portrait`), aspect-filled behind a screen. Picks the landscape painting for
/// wide areas (Mac, iPad and iPhone in landscape) and the portrait one for tall ones.
///
/// - `.game`: the workbench as the play surface. Slightly softened and dimmed, darkest in the
///   middle band where the flasks stand, so glass, glow and runes read clearly. Put the game
///   content in a dark color scheme on top (`.environment(\.colorScheme, .dark)`).
/// - `.menu`: a quiet backdrop for lists (level select, chapters): strongly blurred and washed
///   with the system background, so it adapts to light and dark mode and text stays legible.
///
/// Use as `.background { WorkbenchBackground(style: .game) }`; it ignores the safe area and is
/// hidden from accessibility.
struct WorkbenchBackground: View {
    enum Style { case game, menu }

    var style: Style = .game

    /// Wider than this aspect ratio (width / height) uses the landscape painting.
    static let landscapeThreshold: CGFloat = 0.9

    static func image(for size: CGSize) -> ImageResource {
        size.width >= size.height * landscapeThreshold ? .bgWorkbenchLandscape : .bgWorkbenchPortrait
    }

    var body: some View {
        GeometryReader { proxy in
            Image(Self.image(for: proxy.size))
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .blur(radius: style == .game ? 1.5 : 18, opaque: true)
                .clipped()
                .overlay { wash }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var wash: some View {
        switch style {
        case .game:
            ZStack {
                Color.black.opacity(0.28)
                // Darker band across the middle, where the flasks stand.
                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.05),
                                       .init(color: .black.opacity(0.32), location: 0.35),
                                       .init(color: .black.opacity(0.32), location: 0.75),
                                       .init(color: .black.opacity(0.1), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                // Soft vignette towards the edges.
                RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center,
                               startRadius: 120, endRadius: 900)
            }
        case .menu:
            Rectangle().fill(.background.opacity(0.78))
        }
    }
}

/// Any painting as a full-screen backdrop, with the same washes as `WorkbenchBackground`
/// (`.menu`: strongly blurred and washed with the system background; `.game`: a soft dark scene).
struct PaintedBackdrop: View {
    let image: ImageResource
    var style: WorkbenchBackground.Style = .menu

    var body: some View {
        GeometryReader { proxy in
            Image(image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .blur(radius: style == .game ? 24 : 30, opaque: true)
                .clipped()
                .overlay {
                    switch style {
                    case .menu: Rectangle().fill(.background.opacity(0.72))
                    case .game: Color.black.opacity(0.5)
                    }
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
