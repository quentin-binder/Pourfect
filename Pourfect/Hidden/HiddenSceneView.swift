import HiddenCore
import Observation
import QuartzCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Where the scene sits on screen: a background pixel `p` is drawn at `(p − origin) · scale` in the viewer's
/// coordinates. Published by the platform scroll view so SwiftUI overlays (sparkles, puffs, the lantern) follow
/// zoom and pan.
@Observable
final class HiddenViewport {
    var scale: CGFloat = 0.3
    var origin: CGPoint = .zero
    var size: CGSize = .zero

    func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) * scale, y: (p.y - origin.y) * scale) }
    func toScene(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / scale + origin.x, y: p.y / scale + origin.y) }

    /// Commands for the platform view (zoom buttons, keyboard, the lantern bringing its glow into view).
    @ObservationIgnored weak var scroller: HiddenScroller?
    func zoom(by factor: CGFloat) { scroller?.zoom(by: factor) }
    func reveal(_ p: CGPoint) { scroller?.reveal(p) }
    func zoomToFill() { scroller?.zoomToFill() }
}

/// The platform scroll view's commands.
@MainActor protocol HiddenScroller: AnyObject {
    func zoom(by factor: CGFloat)
    func reveal(_ p: CGPoint)
    func zoomToFill()
}

/// The layers of one round: background, then per object (back to front) its shadow, the tinted object and its
/// occluder, positioned in background pixels (1 point = 1 background pixel; the scroll view zooms).
@MainActor
final class HiddenSceneLayers {
    let root = CALayer()
    private let background = CALayer()
    private var objectLayers: [String: (shadow: CALayer, object: CALayer)] = [:]
    private var outlines: [CALayer] = []
    private var shownLayers: [HiddenLayerSet] = []
    private var full: CGImage?
    private var small: CGImage?
    private var usesSmall = false
    private(set) var found: Set<String> = []

    init() {
        root.masksToBounds = true
        background.contentsGravity = .resize
        background.minificationFilter = .trilinear
        background.magnificationFilter = .linear
        root.addSublayer(background)
        root.actions = Self.noActions
        background.actions = Self.noActions
    }

    static let noActions: [String: any CAAction] = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(),
                                                    "opacity": NSNull(), "sublayers": NSNull(), "hidden": NSNull()]

    func setBackground(full: CGImage, small: CGImage?, size: CGSize) {
        self.full = full
        self.small = small
        root.frame = CGRect(origin: .zero, size: size)
        background.frame = root.bounds
        background.contents = usesSmall ? (small ?? full) : full
    }

    /// Uses the half-size background while the scene is shown at half a device pixel per background pixel or less.
    func updateResolution(devicePixelsPerPixel: CGFloat) {
        let wantsSmall = small != nil && devicePixelsPerPixel <= 0.5
        guard wantsSmall != usesSmall else { return }
        usesSmall = wantsSmall
        background.contents = usesSmall ? (small ?? full) : full
    }

    func show(_ layers: [HiddenLayerSet], outlineTargets: Bool) {
        guard layers.map(\.placement) != shownLayers.map(\.placement) else { return }
        shownLayers = layers
        root.sublayers?.filter { $0 !== background }.forEach { $0.removeFromSuperlayer() }
        objectLayers = [:]
        found = []
        func add(_ image: CGImage?, at origin: CGPoint) -> CALayer {
            let l = CALayer()
            l.actions = Self.noActions
            l.contents = image
            l.contentsGravity = .resize
            l.minificationFilter = .trilinear
            if let image { l.frame = CGRect(origin: origin, size: CGSize(width: image.width, height: image.height)) }
            root.addSublayer(l)
            return l
        }
        for set in layers {
            let p = set.placement
            let shadow = add(set.shadow, at: set.shadowOrigin)
            let object = add(set.object, at: CGPoint(x: p.x, y: p.y))
            if set.occluder != nil { _ = add(set.occluder, at: set.occluderOrigin) }
            objectLayers[p.objectID] = (shadow, object)
        }
        if outlineTargets {
            for set in layers where set.placement.role == .target {
                let p = set.placement
                let l = CALayer()
                l.frame = CGRect(x: p.x - 3, y: p.y - 3, width: p.width + 6, height: p.height + 6)
                l.borderColor = CGColor(red: 1, green: 0.2, blue: 0.6, alpha: 0.95)
                l.borderWidth = 3
                l.cornerRadius = 6
                root.addSublayer(l)
            }
        }
    }

    /// Fades found objects (and their shadows) out of the picture; the occluder stays, it is the background.
    func setFound(_ ids: Set<String>, animated: Bool) {
        let fresh = ids.subtracting(found)
        let back = found.subtracting(ids)
        found = ids
        for id in fresh {
            guard let l = objectLayers[id] else { continue }
            for layer in [l.shadow, l.object] {
                if animated {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = 1
                    fade.toValue = 0
                    fade.duration = 0.55
                    fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    layer.add(fade, forKey: "found")
                    if layer === l.object {
                        let grow = CABasicAnimation(keyPath: "transform.scale")
                        grow.fromValue = 1
                        grow.toValue = 1.25
                        grow.duration = 0.55
                        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        layer.add(grow, forKey: "foundScale")
                    }
                }
                layer.opacity = 0
            }
        }
        // A replayed state (a wrong tap taken back never un-finds, but a new round resets everything).
        for id in back { objectLayers[id].map { $0.shadow.opacity = 1; $0.object.opacity = 1 } }
    }
}

/// The zoomable, pannable scene: pinch / double tap on iPhone and iPad, pinch, scroll wheel and drag on the Mac.
struct HiddenSceneView: View {
    let model: HiddenGameModel
    let viewport: HiddenViewport
    var outlineTargets = false

    var body: some View {
        HiddenSceneRepresentable(model: model, viewport: viewport, outlineTargets: outlineTargets,
                                 layers: model.layers, found: model.found, focus: model.focusRequest?.id ?? 0)
    }
}

#if os(iOS)
private struct HiddenSceneRepresentable: UIViewRepresentable {
    let model: HiddenGameModel
    let viewport: HiddenViewport
    let outlineTargets: Bool
    let layers: [HiddenLayerSet]
    let found: Set<String>
    let focus: Int
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> HiddenUIScrollView {
        let v = HiddenUIScrollView(viewport: viewport)
        viewport.scroller = v
        return v
    }

    func updateUIView(_ v: HiddenUIScrollView, context: Context) {
        v.onTap = { [model] p, ppp in model.tap(at: p, pointsPerPixel: ppp) }
        v.onDoubleTap = { [model] p, ppp in model.doubleTapped(at: p, pointsPerPixel: ppp) }
        v.reduceMotion = reduceMotion
        if let assets = model.assets {
            v.setScene(assets: assets)
            v.sceneLayers.show(layers, outlineTargets: outlineTargets)
            v.sceneLayers.setFound(found, animated: !reduceMotion)
        }
        if focus != v.lastFocus, let request = model.focusRequest {
            v.lastFocus = focus
            v.reveal(request.point)
        }
    }
}

final class HiddenUIScrollView: UIScrollView, UIScrollViewDelegate, HiddenScroller {
    let content = UIView()
    let sceneLayers = HiddenSceneLayers()
    let viewport: HiddenViewport
    var onTap: ((CGPoint, CGFloat) -> Void)?
    var onDoubleTap: ((CGPoint, CGFloat) -> Void)?
    var reduceMotion = false
    var lastFocus = 0
    private var sceneSize: CGSize = .zero
    private var lastBounds: CGSize = .zero
    private var sceneID: HiddenSceneID?

    init(viewport: HiddenViewport) {
        self.viewport = viewport
        super.init(frame: .zero)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .normal
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .black
        addSubview(content)
        content.layer.addSublayer(sceneLayers.root)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(tap)
        addGestureRecognizer(double)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setScene(assets: HiddenRoomAssets) {
        guard sceneID != assets.scene.id else { return }
        sceneID = assets.scene.id
        sceneSize = CGSize(width: assets.scene.width, height: assets.scene.height)
        zoomScale = 1
        content.frame = CGRect(origin: .zero, size: sceneSize)
        contentSize = sceneSize
        sceneLayers.setBackground(full: assets.background, small: assets.backgroundSmall, size: sceneSize)
        lastBounds = .zero
        setNeedsLayout()
    }

    private var fitScale: CGFloat {
        guard sceneSize.width > 0, bounds.width > 0 else { return 1 }
        return min(bounds.width / sceneSize.width, bounds.height / sceneSize.height)
    }

    private var fillScale: CGFloat {
        guard sceneSize.width > 0, bounds.width > 0 else { return 1 }
        return max(bounds.width / sceneSize.width, bounds.height / sceneSize.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard sceneSize.width > 0, bounds.size != lastBounds, bounds.width > 0 else { return }
        let first = lastBounds == .zero
        lastBounds = bounds.size
        minimumZoomScale = fitScale
        // Three device pixels per background pixel at most: about 4× the iPhone's fill zoom.
        maximumZoomScale = max(fillScale * 4, 3 / max(1, traitCollection.displayScale) * 1.5)
        if first || zoomScale < minimumZoomScale {
            setZoomScale(fillScale, animated: false)
            contentOffset = CGPoint(x: max(0, (contentSize.width - bounds.width) / 2),
                                    y: max(0, (contentSize.height - bounds.height) / 2))
        }
        centerContent()
        publish()
    }

    private func centerContent() {
        let dx = max(0, (bounds.width - contentSize.width) / 2)
        let dy = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    private func publish() {
        viewport.scale = zoomScale
        viewport.origin = CGPoint(x: contentOffset.x / zoomScale, y: contentOffset.y / zoomScale)
        viewport.size = bounds.size
        sceneLayers.updateResolution(devicePixelsPerPixel: zoomScale * traitCollection.displayScale)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent(); publish() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { publish() }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        onTap?(g.location(in: content), zoomScale)
    }

    @objc private func doubleTapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: content)
        onDoubleTap?(p, zoomScale)
        let target = zoomScale < fillScale * 1.9 ? min(maximumZoomScale, fillScale * 2.5) : fillScale
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height),
             animated: !reduceMotion)
    }

    func zoom(by factor: CGFloat) {
        let target = min(maximumZoomScale, max(minimumZoomScale, zoomScale * factor))
        let center = CGPoint(x: (contentOffset.x + bounds.width / 2) / zoomScale, y: (contentOffset.y + bounds.height / 2) / zoomScale)
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        zoom(to: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
             animated: !reduceMotion)
    }

    func zoomToFill() { setZoomScale(fillScale, animated: !reduceMotion) }

    /// Pans so `p` is in view (not too close to the edge); keeps the zoom.
    func reveal(_ p: CGPoint) {
        let v = CGPoint(x: p.x * zoomScale - contentOffset.x, y: p.y * zoomScale - contentOffset.y)
        let margin = min(bounds.width, bounds.height) * 0.25
        guard v.x < margin || v.y < margin || v.x > bounds.width - margin || v.y > bounds.height - margin else { return }
        var offset = CGPoint(x: p.x * zoomScale - bounds.width / 2, y: p.y * zoomScale - bounds.height / 2)
        offset.x = min(max(-contentInset.left, offset.x), contentSize.width - bounds.width + contentInset.right)
        offset.y = min(max(-contentInset.top, offset.y), contentSize.height - bounds.height + contentInset.bottom)
        setContentOffset(offset, animated: !reduceMotion)
    }
}

#else

private struct HiddenSceneRepresentable: NSViewRepresentable {
    let model: HiddenGameModel
    let viewport: HiddenViewport
    let outlineTargets: Bool
    let layers: [HiddenLayerSet]
    let found: Set<String>
    let focus: Int
    @Environment(\.effectiveReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> HiddenNSScrollView {
        let v = HiddenNSScrollView(viewport: viewport)
        viewport.scroller = v
        return v
    }

    func updateNSView(_ v: HiddenNSScrollView, context: Context) {
        v.onTap = { [model] p, ppp in model.tap(at: p, pointsPerPixel: ppp) }
        v.onDoubleTap = { [model] p, ppp in model.doubleTapped(at: p, pointsPerPixel: ppp) }
        v.reduceMotion = reduceMotion
        if let assets = model.assets {
            v.setScene(assets: assets)
            v.sceneLayers.show(layers, outlineTargets: outlineTargets)
            v.sceneLayers.setFound(found, animated: !reduceMotion)
        }
        if focus != v.lastFocus, let request = model.focusRequest {
            v.lastFocus = focus
            v.reveal(request.point)
        }
    }
}

/// Keeps a document smaller than the view centred.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

/// The scene's document view: flipped (y down, like background pixels), click to tap, drag to pan.
final class HiddenSceneNSView: NSView {
    weak var owner: HiddenNSScrollView?
    private var downAt: NSPoint?
    private var dragged = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let owner, let start = downAt else { return }
        if !dragged, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) < 4 { return }
        if !dragged { NSCursor.closedHand.push() }
        dragged = true
        owner.pan(dx: event.deltaX, dy: event.deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        if dragged {
            NSCursor.pop()
            dragged = false
            return
        }
        guard let owner else { return }
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount >= 2 {
            owner.doubleClicked(at: p)
        } else {
            owner.onTap?(p, owner.magnification)
        }
    }
}

final class HiddenNSScrollView: NSScrollView, HiddenScroller {
    let scene = HiddenSceneNSView()
    let sceneLayers = HiddenSceneLayers()
    let viewport: HiddenViewport
    var onTap: ((CGPoint, CGFloat) -> Void)?
    var onDoubleTap: ((CGPoint, CGFloat) -> Void)?
    var reduceMotion = false
    var lastFocus = 0
    private var sceneSize: CGSize = .zero
    private var lastSize: CGSize = .zero
    private var sceneID: HiddenSceneID?

    init(viewport: HiddenViewport) {
        self.viewport = viewport
        super.init(frame: .zero)
        contentView = CenteringClipView()
        hasHorizontalScroller = false
        hasVerticalScroller = false
        automaticallyAdjustsContentInsets = false
        allowsMagnification = true
        drawsBackground = true
        backgroundColor = .black
        scene.owner = self
        scene.wantsLayer = true
        documentView = scene
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification,
                                               object: contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSScrollView.didEndLiveMagnifyNotification,
                                               object: self)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setScene(assets: HiddenRoomAssets) {
        guard sceneID != assets.scene.id else { return }
        sceneID = assets.scene.id
        sceneSize = CGSize(width: assets.scene.width, height: assets.scene.height)
        magnification = 1
        scene.frame = CGRect(origin: .zero, size: sceneSize)
        if sceneLayers.root.superlayer == nil { scene.layer?.addSublayer(sceneLayers.root) }
        sceneLayers.setBackground(full: assets.background, small: assets.backgroundSmall, size: sceneSize)
        lastSize = .zero
        needsLayout = true
    }

    private var fitScale: CGFloat {
        guard sceneSize.width > 0, bounds.width > 0 else { return 1 }
        return min(bounds.width / sceneSize.width, bounds.height / sceneSize.height)
    }

    private var fillScale: CGFloat {
        guard sceneSize.width > 0, bounds.width > 0 else { return 1 }
        return max(bounds.width / sceneSize.width, bounds.height / sceneSize.height)
    }

    override func layout() {
        super.layout()
        guard sceneSize.width > 0, bounds.width > 0, bounds.size != lastSize else { return }
        let first = lastSize == .zero
        lastSize = bounds.size
        minMagnification = fitScale
        maxMagnification = max(fillScale * 4, 2)
        if first || magnification < minMagnification {
            magnification = fillScale
            let visible = contentView.bounds.size
            contentView.scroll(to: CGPoint(x: (sceneSize.width - visible.width) / 2, y: (sceneSize.height - visible.height) / 2))
            reflectScrolledClipView(contentView)
        }
        publish()
    }

    @objc private func boundsChanged() { publish() }

    private func publish() {
        viewport.scale = magnification
        viewport.origin = contentView.bounds.origin
        viewport.size = bounds.size
        sceneLayers.updateResolution(devicePixelsPerPixel: magnification * (window?.backingScaleFactor ?? 2))
    }

    /// A mouse wheel (or ⌘ / ⌥ with a trackpad) zooms around the pointer; a trackpad scroll pans.
    override func scrollWheel(with event: NSEvent) {
        let zoomKeys = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
        guard !event.hasPreciseScrollingDeltas || zoomKeys else { super.scrollWheel(with: event); return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        guard delta != 0 else { return }
        let target = min(maxMagnification, max(minMagnification, magnification * (1 + delta)))
        setMagnification(target, centeredAt: scene.convert(event.locationInWindow, from: nil))
        publish()
    }

    func pan(dx: CGFloat, dy: CGFloat) {
        var origin = contentView.bounds.origin
        origin.x -= dx / magnification
        origin.y -= dy / magnification
        contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: origin, size: contentView.bounds.size)).origin)
        reflectScrolledClipView(contentView)
    }

    func doubleClicked(at p: CGPoint) {
        onDoubleTap?(p, magnification)
        let target = magnification < fillScale * 1.9 ? min(maxMagnification, fillScale * 2.5) : fillScale
        if reduceMotion {
            setMagnification(target, centeredAt: p)
        } else {
            animator().setMagnification(target, centeredAt: p)
        }
        publish()
    }

    func zoom(by factor: CGFloat) {
        let b = contentView.bounds
        let target = min(maxMagnification, max(minMagnification, magnification * factor))
        setMagnification(target, centeredAt: CGPoint(x: b.midX, y: b.midY))
        publish()
    }

    func zoomToFill() {
        let b = contentView.bounds
        setMagnification(fillScale, centeredAt: CGPoint(x: b.midX, y: b.midY))
        publish()
    }

    func reveal(_ p: CGPoint) {
        let b = contentView.bounds
        let margin = min(b.width, b.height) * 0.25
        guard p.x < b.minX + margin || p.y < b.minY + margin || p.x > b.maxX - margin || p.y > b.maxY - margin else { return }
        let origin = CGPoint(x: p.x - b.width / 2, y: p.y - b.height / 2)
        contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: origin, size: b.size)).origin)
        reflectScrolledClipView(contentView)
        publish()
    }
}
#endif
