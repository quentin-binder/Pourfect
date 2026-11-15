import BottleSortCore
import SwiftUI

/// Collects each bottle's layout frame so the pour animation knows where bottles sit.
struct BottleFramesKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Where every moving part of a pour is at one instant. All values are 0…1 unless noted.
struct PourPose {
    var travel: Double = 0        // source, horizontal: 0 = in its slot, 1 = mouth above the target
    var rise: Double = 0          // source, vertical (leads on the way out, lags on the way back,
                                  // so the bottle crosses the board high above the others)
    var returning = false         // second half: travel back to the resting (unlifted) slot
    var tilt: Double = 0          // 0 = upright, 1 = fully tilted
    var flow: Double = 0          // share of the poured layers already moved
    var streamHead: Double = 0    // stream drawn along its path from `streamTail` to `streamHead`
    var streamTail: Double = 0
    var sourceSlosh: Double = 0   // surface rock, radians
    var targetSlosh: Double = 0

    static let duration = 1.1
    static let reducedDuration = 0.4

    /// The choreography. Lift & fly (0–0.32 s), tilt, stream + flow (0.32–0.74 s),
    /// straighten & return (0.72–1.0 s), surfaces settle (to 1.1 s).
    static func at(_ t: Double, reduceMotion: Bool) -> PourPose {
        var p = PourPose()
        if reduceMotion {
            p.returning = true   // source stays in its resting slot
            p.flow = ease(t, 0, reducedDuration)
            return p
        }
        p.returning = t > 0.6
        p.travel = p.returning ? 1 - ease(t, 0.76, 0.96) : ease(t, 0.06, 0.32)
        p.rise = p.returning ? 1 - ease(t, 0.84, 1.0) : ease(t, 0, 0.24)
        p.tilt = t < 0.6 ? ease(t, 0.12, 0.36) : 1 - ease(t, 0.72, 0.95)
        p.flow = ease(t, 0.34, 0.74)
        p.streamHead = ease(t, 0.30, 0.42)
        p.streamTail = ease(t, 0.64, 0.78)   // leaves the lip before the bottle moves away
        let settle = 1 - ease(t, 1.0, duration)   // guarantees a flat surface at the end
        p.targetSlosh = (0.03 * sin(t * 45) * (p.flow > 0 && p.flow < 1 ? 1 : 0)
                         + damped(t, from: 0.74, amplitude: 0.12)) * settle
        p.sourceSlosh = damped(t, from: 0.9, amplitude: 0.12) * settle
        return p
    }

    private static func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(max((t - a) / (b - a), 0), 1)
        return x * x * (3 - 2 * x)
    }

    private static func damped(_ t: Double, from start: Double, amplitude: Double) -> Double {
        guard t > start else { return 0 }
        let dt = t - start
        return amplitude * exp(-dt * 10) * sin(dt * 30)
    }
}

/// Animates one `PourEvent`: the source bottle flies over the target, tilts, a stream falls
/// while both levels change continuously, and the source flies back. Draws on top of the board
/// (the board hides the two real bottles meanwhile). Purely visual: the move is already applied.
struct PourAnimationView: View {
    let event: GameViewModel.PourEvent
    let sourceFrame: CGRect
    let targetFrame: CGRect
    let boardSize: CGSize
    let reduceMotion: Bool
    let onFinish: () -> Void

    @State private var start = Date()

    private var duration: Double { reduceMotion ? PourPose.reducedDuration : PourPose.duration }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = min(timeline.date.timeIntervalSince(start), duration)
            frame(PourPose.at(t, reduceMotion: reduceMotion))
        }
        .allowsHitTesting(false)
        .task(id: event.id) {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }

    // MARK: One frame

    private var width: CGFloat { sourceFrame.width }
    private var height: CGFloat { sourceFrame.height }
    private var layerHeight: CGFloat { BottleView.layerHeight(width: targetFrame.width) }
    private var color: Color { event.layer.liquidColor }

    private func frame(_ pose: PourPose) -> some View {
        let right = pourToRight
        let sign: Double = right ? 1 : -1
        let angle = sign * pose.tilt * pourAngle(flow: pose.flow)      // degrees
        let lip = lipPosition(pose, right: right)
        let surfaceY = targetFrame.maxY - layerHeight
            * (CGFloat(event.targetBefore.layers.count) + CGFloat(event.amount) * pose.flow)

        return ZStack(alignment: .topLeading) {
            stream(from: pourPoint(right: right), toY: surfaceY, right: right, pose: pose)

            bottle(segments: targetSegments(pose.flow), frame: targetFrame, gravity: pose.targetSlosh)
                .position(x: targetFrame.midX, y: targetFrame.midY)

            bottle(segments: sourceSegments(pose.flow), frame: sourceFrame,
                   gravity: angle * .pi / 180 + pose.sourceSlosh)
                .shadow(color: .black.opacity(0.2 * pose.rise), radius: 6, y: 3)   // lifts it off the board
                .rotationEffect(.degrees(angle), anchor: right ? .topTrailing : .topLeading)
                // The rotation anchor is the pouring lip, so place the frame by that corner.
                .position(x: lip.x + (right ? -width / 2 : width / 2), y: lip.y + height / 2)
        }
        .frame(width: boardSize.width, height: boardSize.height, alignment: .topLeading)
    }

    private func bottle(segments: [LiquidSegment], frame: CGRect, gravity: Double) -> some View {
        let shape = BottleView.shape(width: frame.width)
        return ZStack {
            // Opaque backing so bottles the flying one passes in front of don't show through.
            shape.fill(.background)
            shape.fill(BottleView.glassColor)
            TiltedLiquid(segments: segments, layerHeight: BottleView.layerHeight(width: frame.width),
                         gravity: gravity)
                .clipShape(shape)
            shape.strokeBorder(BottleView.outlineColor, lineWidth: 2)
        }
        .frame(width: frame.width, height: frame.height)
    }

    /// Source keeps its layers; the poured top layers shrink as `flow` grows.
    private func sourceSegments(_ flow: Double) -> [LiquidSegment] {
        let layers = event.sourceBefore.layers
        return layers.enumerated().map { i, layer in
            LiquidSegment(color: layer.liquidColor,
                          fraction: i >= layers.count - event.amount ? 1 - flow : 1)
        }
    }

    /// Target keeps its layers and gains `amount` layers that grow with `flow`.
    private func targetSegments(_ flow: Double) -> [LiquidSegment] {
        event.targetBefore.layers.map { LiquidSegment(color: $0.liquidColor, fraction: 1) }
            + Array(repeating: LiquidSegment(color: color, fraction: flow), count: event.amount)
    }

    // MARK: Positions

    /// Mouth corner the liquid leaves from, in board coordinates.
    private func lipPosition(_ pose: PourPose, right: Bool) -> CGPoint {
        let corner = { (r: CGRect, lift: CGFloat) in
            CGPoint(x: right ? r.maxX : r.minX, y: r.minY - lift)
        }
        // Starts from the selection lift (see BottleView), lands back at rest.
        let home = pose.returning ? corner(sourceFrame, 0) : corner(sourceFrame, width * 0.3)
        let over = pourPoint(right: right)
        // Going up: rise first, then across. Going down (top row → bottom row): across first.
        let up = over.y <= home.y
        return CGPoint(x: home.x + (over.x - home.x) * (up ? pose.travel : pose.rise),
                       y: home.y + (over.y - home.y) * (up ? pose.rise : pose.travel))
    }

    /// Tilt (degrees from upright) at which the liquid left in the source just reaches the lip,
    /// so the stream always leaves from the liquid surface. Steeper as the bottle empties.
    /// Uses the bottle's bounding rectangle tilted about its top corner.
    private func pourAngle(flow: Double) -> Double {
        let layers = CGFloat(event.sourceBefore.layers.count) - CGFloat(event.amount) * flow
        let liquid = layers * BottleView.layerHeight(width: width) * width
        let w = width, h = height
        let belowLip = { (radians: Double) -> CGFloat in
            let t = tan(radians)
            return w * t <= h ? w * h - w * w * t / 2 : h * h / (2 * t)
        }
        var low = 0.0, high = Double.pi / 2 - 0.01
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if belowLip(mid) > liquid { low = mid } else { high = mid }
        }
        return min(max(low * 180 / .pi + 4, 55), 86)
    }

    /// Where the lip hovers while pouring: just off-center over the target's mouth, high enough
    /// that the tilted body clears the bottles below.
    private func pourPoint(right: Bool) -> CGPoint {
        let gap = height * cos(pourAngle(flow: 0) * .pi / 180) + width * 0.15
        return CGPoint(x: targetFrame.midX + (right ? -1 : 1) * width * 0.12, y: targetFrame.minY - gap)
    }

    /// Pour toward the target from the side the source comes from, unless the tilted body would
    /// leave the board on that side.
    private var pourToRight: Bool {
        let preferred: Bool
        if abs(sourceFrame.midX - targetFrame.midX) > 1 {
            preferred = sourceFrame.midX < targetFrame.midX
        } else {
            preferred = targetFrame.midX > boardSize.width / 2
        }
        let reach = height + width * 0.25                               // body extent from the lip
        let fits = { (right: Bool) -> Bool in
            let x = pourPoint(right: right).x
            return right ? x - reach >= -16 : x + reach <= boardSize.width + 16
        }
        return fits(preferred) || !fits(!preferred) ? preferred : !preferred
    }

    // MARK: Stream

    @ViewBuilder
    private func stream(from lip: CGPoint, toY surfaceY: CGFloat, right: Bool, pose: PourPose) -> some View {
        if pose.streamHead > pose.streamTail + 0.001 {
            let dir: CGFloat = right ? 1 : -1
            let start = CGPoint(x: lip.x + dir * width * 0.04, y: lip.y)
            let end = CGPoint(x: lip.x + dir * width * 0.16, y: max(surfaceY, lip.y + width * 0.3))
            let path = Path { p in
                p.move(to: start)
                p.addQuadCurve(to: end, control: CGPoint(x: lip.x + dir * width * 0.16, y: lip.y + width * 0.08))
            }
            .trimmedPath(from: pose.streamTail, to: pose.streamHead)
            path.stroke(color.gradient, style: StrokeStyle(lineWidth: width * 0.14, lineCap: .round))
        }
    }
}
