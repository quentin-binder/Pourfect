import BottleSortCore
import SwiftUI

// Cosmetic rewards (R7) as drawn by the app: the workbench theme behind the board, the flask
// silhouette and the completion effect. The choice comes from `GameSettings.cosmetics`, resolved
// against the unlocked rewards at the root (`RootView`) and published in the environment.
// Nothing here changes a flask's frame, capacity or hit area: the silhouette is drawn inside
// the same `width × height` frame and the layers keep their heights. Potion Bottle and
// Round-Bottom are full width wherever a full flask's potion stands (their shoulders fit in the
// 0.45 w headroom above it; the rounded bottom is like the classic one). Conical is the one
// exception: its sloping sides are the silhouette, so its higher layers are drawn narrower.

// MARK: Environment

private struct WorkbenchThemeKey: EnvironmentKey { static let defaultValue = WorkbenchTheme.workbench }
private struct FlaskStyleKey: EnvironmentKey { static let defaultValue = FlaskShapeStyle.classic }
private struct PotionEffectKey: EnvironmentKey { static let defaultValue = PotionEffect.sparkle }

extension EnvironmentValues {
    /// The painted workbench behind the board and the menus.
    var workbenchTheme: WorkbenchTheme {
        get { self[WorkbenchThemeKey.self] }
        set { self[WorkbenchThemeKey.self] = newValue }
    }

    /// The silhouette of every flask (at rest, in flight and in the tips).
    var flaskStyle: FlaskShapeStyle {
        get { self[FlaskStyleKey.self] }
        set { self[FlaskStyleKey.self] = newValue }
    }

    /// What bursts out of a flask when it is completed.
    var potionEffect: PotionEffect {
        get { self[PotionEffectKey.self] }
        set { self[PotionEffectKey.self] = newValue }
    }
}

extension View {
    /// Publishes a resolved cosmetic selection.
    func cosmetics(_ selection: CosmeticSelection) -> some View {
        environment(\.workbenchTheme, selection.theme)
            .environment(\.flaskStyle, selection.flask)
            .environment(\.potionEffect, selection.effect)
    }

    /// Clips to the flask body in the current flask style (`BottleView.shape`).
    func flaskClip(width: CGFloat) -> some View {
        modifier(FlaskClip(width: width))
    }
}

private struct FlaskClip: ViewModifier {
    let width: CGFloat
    @Environment(\.flaskStyle) private var style

    func body(content: Content) -> some View {
        content.clipShape(BottleView.shape(width: width, style: style))
    }
}

// MARK: Flask silhouettes

extension FlaskShapeStyle {
    /// Width of the mouth as a fraction of the flask width.
    var mouth: CGFloat {
        switch self {
        case .classic: 1
        case .potionBottle: 0.52
        case .roundBottom: 0.58
        case .conical: 0.48
        }
    }

    /// How far the pouring lip sits inward from the frame's top corner (the stream leaves the
    /// mouth, not the frame).
    func lipInset(_ w: CGFloat) -> CGFloat { (1 - mouth) * w / 2 }

    /// The `Cork` width parameter for a plain (not narrow-neck) flask: the classic cork, or one
    /// sized to the narrower mouth (like the narrow neck's cork).
    func corkWidth(_ w: CGFloat) -> CGFloat { self == .classic ? w : mouth * w * 1.3 }

    /// The rim's width parameter (`FlaskRim` draws 1.1 × it).
    func rimWidth(_ w: CGFloat) -> CGFloat { mouth * w }
}

/// The flask body in one of the styles, filling its frame (`width × height`). The classic style
/// is the original rounded tube. Insettable, so outlines can sit just inside the edge like before.
struct FlaskShape: InsettableShape {
    var style: FlaskShapeStyle
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> FlaskShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in frame: CGRect) -> Path {
        let rect = frame.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let w = frame.width   // proportions follow the frame, so insets are parallel
        switch style {
        case .classic:
            return UnevenRoundedRectangle(topLeadingRadius: max(0, w * 0.12 - inset),
                                          bottomLeadingRadius: max(0, w * 0.45 - inset),
                                          bottomTrailingRadius: max(0, w * 0.45 - inset),
                                          topTrailingRadius: max(0, w * 0.12 - inset)).path(in: rect)
        case .potionBottle:
            // A short neck, round shoulders that reach full width at the top of a full flask's
            // liquid (0.45 w down), straight sides and a flat bottom with soft corners.
            return Self.symmetric(rect) { half, x, y in
                let neck = half * self.style.mouth
                let corner = w * 0.2
                return [
                    .move(x(-neck), y(0)),
                    .line(x(-neck), y(w * 0.12)),
                    .curve(x(-half), y(w * 0.45), c1: (x(-neck), y(w * 0.26)), c2: (x(-half), y(w * 0.22))),
                    .line(x(-half), rect.maxY - corner),
                    .quad(x(-half + corner), rect.maxY, control: (x(-half), rect.maxY)),
                ]
            }
        case .roundBottom:
            // A neck flowing into wide, sloping round shoulders (full width at the top of a full
            // flask's liquid, 0.45 w down) and a round bottom.
            return Self.symmetric(rect) { half, x, y in
                let neck = half * self.style.mouth
                return [
                    .move(x(-neck), y(0)),
                    .line(x(-neck), y(w * 0.06)),
                    .curve(x(-half), y(w * 0.45), c1: (x(-neck - w * 0.12), y(w * 0.12)), c2: (x(-half), y(w * 0.2))),
                    .line(x(-half), rect.maxY - half),
                    .quad(x(0), rect.maxY, control: (x(-half), rect.maxY)),
                ]
            }
        case .conical:
            // Erlenmeyer: a straight neck, then sloping sides to a wide flat bottom.
            return Self.symmetric(rect) { half, x, y in
                let neck = half * self.style.mouth
                let corner = w * 0.16
                return [
                    .move(x(-neck), y(0)),
                    .line(x(-neck), y(w * 0.28)),
                    .line(x(-half), rect.maxY - corner),
                    .quad(x(-half + corner * 0.9), rect.maxY, control: (x(-half), rect.maxY)),
                ]
            }
        }
    }

    private enum Step {
        case move(CGFloat, CGFloat)
        case line(CGFloat, CGFloat)
        case quad(CGFloat, CGFloat, control: (CGFloat, CGFloat))
        case curve(CGFloat, CGFloat, c1: (CGFloat, CGFloat), c2: (CGFloat, CGFloat))
    }

    /// A left-right symmetric outline: `left` lists the left half from the mouth's top-left
    /// corner down to the bottom; the right half is its mirror image, drawn back up.
    private static func symmetric(_ rect: CGRect,
                                  left: (_ half: CGFloat, _ x: (CGFloat) -> CGFloat, _ y: (CGFloat) -> CGFloat) -> [Step]) -> Path {
        let half = rect.width / 2
        let x = { (dx: CGFloat) in rect.midX + dx }
        let y = { (dy: CGFloat) in rect.minY + dy }
        let steps = left(half, x, y)
        let mirror = { (px: CGFloat) in 2 * rect.midX - px }
        var points: [CGPoint] = []   // end point of each step, to walk the right side back up
        return Path { p in
            for step in steps {
                switch step {
                case .move(let a, let b): p.move(to: CGPoint(x: a, y: b))
                case .line(let a, let b): p.addLine(to: CGPoint(x: a, y: b))
                case .quad(let a, let b, let c): p.addQuadCurve(to: CGPoint(x: a, y: b), control: CGPoint(x: c.0, y: c.1))
                case .curve(let a, let b, let c1, let c2):
                    p.addCurve(to: CGPoint(x: a, y: b), control1: CGPoint(x: c1.0, y: c1.1), control2: CGPoint(x: c2.0, y: c2.1))
                }
                switch step {
                case .move(let a, let b), .line(let a, let b), .quad(let a, let b, _), .curve(let a, let b, _, _):
                    points.append(CGPoint(x: a, y: b))
                }
            }
            // Across the bottom, then the mirrored steps in reverse order.
            if let last = points.last { p.addLine(to: CGPoint(x: mirror(last.x), y: last.y)) }
            for index in stride(from: steps.count - 1, through: 1, by: -1) {
                let to = points[index - 1]
                let target = CGPoint(x: mirror(to.x), y: to.y)
                switch steps[index] {
                case .move, .line: p.addLine(to: target)
                case .quad(_, _, let c): p.addQuadCurve(to: target, control: CGPoint(x: mirror(c.0), y: c.1))
                case .curve(_, _, let c1, let c2):
                    // Reversed: the controls swap.
                    p.addCurve(to: target, control1: CGPoint(x: mirror(c2.0), y: c2.1),
                               control2: CGPoint(x: mirror(c1.0), y: c1.1))
                }
            }
            p.closeSubpath()
        }
    }
}

// MARK: Workbench themes

extension WorkbenchTheme {
    /// The painting for a wide (`landscape`) or tall area.
    func image(landscape: Bool) -> ImageResource {
        switch self {
        case .workbench: landscape ? .bgWorkbenchLandscape : .bgWorkbenchPortrait
        case .forestHut: landscape ? .themeForestHutLandscape : .themeForestHutPortrait
        case .frostLab: landscape ? .themeFrostLabLandscape : .themeFrostLabPortrait
        case .dragonLair: landscape ? .themeDragonLairLandscape : .themeDragonLairPortrait
        }
    }
}

// MARK: Names

extension Reward.Item {
    var title: String {
        switch self {
        case .theme(.workbench): String(localized: "Alchemist's Workbench", comment: "Workbench theme name")
        case .theme(.forestHut): String(localized: "Forest Hut", comment: "Workbench theme name")
        case .theme(.frostLab): String(localized: "Frost Lab", comment: "Workbench theme name")
        case .theme(.dragonLair): String(localized: "Dragon's Lair", comment: "Workbench theme name")
        case .flask(.classic): String(localized: "Classic Flask", comment: "Flask shape name")
        case .flask(.potionBottle): String(localized: "Potion Bottle", comment: "Flask shape name")
        case .flask(.roundBottom): String(localized: "Round-Bottom Flask", comment: "Flask shape name")
        case .flask(.conical): String(localized: "Conical Flask", comment: "Flask shape name")
        case .effect(.sparkle): String(localized: "Sparkles", comment: "Completion effect name")
        case .effect(.bubbles): String(localized: "Bubble Pop", comment: "Completion effect name")
        case .effect(.fireflies): String(localized: "Fireflies", comment: "Completion effect name")
        case .effect(.starburst): String(localized: "Starburst", comment: "Completion effect name")
        }
    }
}

extension CosmeticCategory {
    var title: String {
        switch self {
        case .theme: String(localized: "Workbench", comment: "Lab Style section: workbench themes")
        case .flask: String(localized: "Flasks", comment: "Lab Style section: flask shapes")
        case .effect: String(localized: "Potion Effects", comment: "Lab Style section: completion effects")
        }
    }

    var footnote: String {
        switch self {
        case .theme: String(localized: "The painting behind your flasks.")
        case .flask: String(localized: "The shape of every flask on the board. Flasks hold just as much in any shape.")
        case .effect: String(localized: "What bursts out of a flask when you cork it. Reduce Motion shows none.")
        }
    }
}

extension Milestone {
    /// How to earn a reward, e.g. "Finish every recipe in Misty Marsh".
    func howToEarn(catalog: LevelCatalog) -> String {
        switch self {
        case .starter:
            return String(localized: "Yours from the start", comment: "Lab Style: a reward everyone owns")
        case .finishChapter(let n):
            let name = ChapterArt.name(of: n, in: catalog) ?? String(localized: "Chapter \(n)")
            return String(localized: "Solve every recipe in \(name)", comment: "Lab Style milestone; the argument is a chapter name")
        case .totalStars(let n):
            return String(localized: "Earn \(n) stars in the chapters", comment: "Lab Style milestone")
        case .goldSeals(let n):
            return String(localized: "Earn \(n) gold seals", comment: "Lab Style milestone")
        case .rushBest(let n):
            return String(localized: "Brew \(n) recipes in one Rush", comment: "Lab Style milestone")
        case .dailyStreak(let n):
            return String(localized: "Solve the Daily Brew \(n) days in a row", comment: "Lab Style milestone")
        }
    }
}

// MARK: Completion effects

/// The burst out of a completed flask's mouth in the chosen effect. The view is
/// `CompletionBurst.size(width:)`; center it on the mouth. Starts at `start`.
struct CompletionBurst: View {
    let effect: PotionEffect
    let start: Date
    let color: Color
    let width: CGFloat

    static func size(width: CGFloat) -> CGSize { SparkleBurst.size(width: width) }

    static func duration(_ effect: PotionEffect) -> Double {
        switch effect {
        case .sparkle: SparkleBurst.duration
        case .bubbles: 0.9
        case .fireflies: 1.6
        case .starburst: 0.7
        }
    }

    var body: some View {
        if effect == .sparkle {
            SparkleBurst(start: start, color: color, width: width)
        } else {
            let duration = Self.duration(effect)
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    guard t >= 0, t <= duration else { return }
                    let origin = CGPoint(x: size.width / 2, y: size.height / 2)
                    let progress = t / duration
                    switch effect {
                    case .bubbles: drawBubbles(&context, origin: origin, t: t, progress: progress)
                    case .fireflies: drawFireflies(&context, origin: origin, t: t, progress: progress)
                    case .starburst: drawStarburst(&context, origin: origin, progress: progress)
                    case .sparkle: break
                    }
                }
            }
            .frame(width: Self.size(width: width).width, height: Self.size(width: width).height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Deterministic 0…1 values per particle.
    private static func unit(_ i: Int, _ k: Double) -> Double {
        (Double(i) * k + 0.17).truncatingRemainder(dividingBy: 1)
    }

    /// Bubbles in the potion's color float up from the mouth, wobble, swell and pop into a ring.
    private func drawBubbles(_ context: inout GraphicsContext, origin: CGPoint, t: Double, progress: Double) {
        for i in 0..<11 {
            let u = Self.unit(i, 0.618_034), v = Self.unit(i, 0.414_214)
            let delay = 0.25 * v
            let life = 0.55 + 0.1 * u
            let local = (t - delay) / life
            guard local >= 0 else { continue }
            let x = origin.x + width * CGFloat((u - 0.5) * 1.3 + 0.12 * sin((t + u) * 14))
            let y = origin.y - width * CGFloat(0.2 + 1.3 * min(local, 1) * (0.7 + 0.5 * v))
            let r = width * CGFloat(0.07 + 0.08 * v) * CGFloat(0.6 + 0.5 * min(local, 1))
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            if local < 1 {
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.35)))
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.8)), lineWidth: max(0.8, r * 0.18))
                context.fill(Path(ellipseIn: CGRect(x: x - r * 0.5, y: y - r * 0.6, width: r * 0.45, height: r * 0.35)),
                             with: .color(.white.opacity(0.85)))
            } else if local < 1.35 {
                // Pop: a fading ring.
                let pop = (local - 1) / 0.35
                let ring = rect.insetBy(dx: -r * CGFloat(pop) * 0.8, dy: -r * CGFloat(pop) * 0.8)
                context.stroke(Path(ellipseIn: ring), with: .color(.white.opacity(0.7 * (1 - pop))),
                               lineWidth: max(0.6, r * 0.12))
            }
        }
    }

    /// Glowing motes drift up out of the flask on lazy curves and blink out.
    private func drawFireflies(_ context: inout GraphicsContext, origin: CGPoint, t: Double, progress: Double) {
        var glow = context
        glow.addFilter(.blur(radius: width * 0.08))
        for i in 0..<9 {
            let u = Self.unit(i, 0.618_034), v = Self.unit(i, 0.414_214)
            let rise = CGFloat(t) * width * CGFloat(0.55 + 0.45 * v)
            let sway = width * CGFloat(0.9 * (u - 0.5) * min(1, t * 1.6) + 0.2 * sin(t * (3 + 2 * u) + u * 6))
            let center = CGPoint(x: origin.x + sway, y: origin.y - width * 0.1 - rise)
            let twinkle = 0.55 + 0.45 * sin(t * (9 + 5 * v) + v * 6)
            let fade = min(1, t * 5) * (1 - progress * progress)
            let r = width * CGFloat(0.05 + 0.03 * u)
            let amber = Color(red: 1, green: 0.86, blue: 0.4)
            glow.opacity = fade * twinkle
            glow.fill(Path(ellipseIn: CGRect(x: center.x - r * 2.4, y: center.y - r * 2.4, width: r * 4.8, height: r * 4.8)),
                      with: .color(i % 3 == 0 ? color : amber))
            var core = context
            core.opacity = fade * twinkle
            core.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                      with: .color(.white))
        }
    }

    /// A ring of rays flashes out from the mouth, with a soft glow and an expanding ring.
    private func drawStarburst(_ context: inout GraphicsContext, origin: CGPoint, progress: Double) {
        let ease = 1 - pow(1 - progress, 3)
        let fade = 1 - progress
        var glow = context
        glow.addFilter(.blur(radius: width * 0.18))
        glow.opacity = fade
        let g = width * CGFloat(0.4 + 0.5 * ease)
        glow.fill(Path(ellipseIn: CGRect(x: origin.x - g, y: origin.y - g, width: g * 2, height: g * 2)),
                  with: .color(color))
        let rays = 12
        for i in 0..<rays {
            let angle = Double(i) / Double(rays) * 2 * .pi + 0.13
            let long = i % 2 == 0
            let inner = width * CGFloat(0.15 + 0.6 * ease)
            let outer = inner + width * CGFloat(long ? 0.65 : 0.4) * CGFloat(1 - 0.5 * progress)
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            var ray = Path()
            ray.move(to: CGPoint(x: origin.x + dir.x * inner, y: origin.y + dir.y * inner))
            ray.addLine(to: CGPoint(x: origin.x + dir.x * outer, y: origin.y + dir.y * outer))
            var c = context
            c.opacity = fade
            c.stroke(ray, with: .color(long ? .white : color),
                     style: StrokeStyle(lineWidth: max(1, width * (long ? 0.07 : 0.05)), lineCap: .round))
        }
        let ring = width * CGFloat(0.2 + 1.2 * ease)
        var c = context
        c.opacity = fade * 0.8
        c.stroke(Path(ellipseIn: CGRect(x: origin.x - ring, y: origin.y - ring, width: ring * 2, height: ring * 2)),
                 with: .color(.white), lineWidth: max(0.8, width * 0.04))
    }
}
