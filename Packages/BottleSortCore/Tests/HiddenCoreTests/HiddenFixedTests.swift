import Foundation
import Testing
@testable import HiddenCore

// MARK: - Fixed, curated rounds (rounds.json)

func roundsData(_ id: HiddenSceneID) throws -> Data {
    try Data(contentsOf: scenesURL.appendingPathComponent(id.rawValue).appendingPathComponent("rounds.json"))
}

func fixedRounds(_ id: HiddenSceneID) throws -> [HiddenRoundLayout] {
    try HiddenFixedLayouts.load(roundsData(id), scene: scene(id))
}

@Suite("Hidden: fixed curated rounds")
struct HiddenFixedTests {
    /// Every shipped round loads and keeps the rules: known objects and usable spots, a fair find list, decoys that
    /// never share a target's id or name and never cover a target, nothing outside the picture.
    @Test func shippedRoundsKeepTheRules() throws {
        for id in HiddenSceneID.allCases {
            let s = scene(id)
            let rounds = try fixedRounds(id)
            #expect(rounds.map(\.round) == Array(HiddenCurve.rounds), "\(id)")
            for l in rounds {
                let tag = "\(id) r\(l.round)"
                #expect(HiddenFixedLayouts.validate(l, scene: s).isEmpty, "\(tag)")
                #expect(l.scene == id && l.seed == HiddenGenerator.seed(id, round: l.round, variant: 0))
                #expect(HiddenFixedLayouts.targetRange.contains(l.targets.count), "\(tag)")
                // the round list shows the curve's count
                #expect(l.targets.count == HiddenCurve.spec(id, round: l.round).targets, "\(tag)")
                #expect(l.decoys.count >= 6, "\(tag): too few decoys, the targets would stand out")
                let all = l.targets + l.decoys
                #expect(Set(all.map(\.objectID)).count == all.count, "\(tag)")
                let targetIDs = Set(l.targets.map(\.objectID))
                let targetNames = Set(l.targets.map { s.object($0.objectID)!.name.lowercased() })
                for d in l.decoys {
                    #expect(!targetIDs.contains(d.objectID), "\(tag)")
                    #expect(!targetNames.contains(s.object(d.objectID)!.name.lowercased()), "\(tag) \(d.objectID)")
                    for t in l.targets {
                        #expect(!HiddenGenerator.footprint(t.rect).insetBy(-HiddenGenerator.decoyMargin)
                            .intersects(HiddenGenerator.footprint(d.rect)), "\(tag) decoy \(d.objectID) over \(t.objectID)")
                    }
                }
                for p in all {
                    let o = s.object(p.objectID)!, sp = s.spot(p.spotID)!
                    #expect(!sp.unusable && sp.accepts(o.sizeClass), "\(tag) \(p.objectID)@\(p.spotID)")
                    #expect(p.rect.x >= 0 && p.rect.y >= 0 && p.rect.maxX <= s.width && p.rect.maxY <= s.height)
                    #expect(p.anchorX == sp.x + p.dx && p.anchorY == sp.y + p.dy)
                }
                let ys = l.drawOrder.map(\.anchorY)
                #expect(ys == ys.sorted(), "\(tag): drawn back to front")
            }
            // the curve rises: more to find at the end than at the start
            #expect(rounds.last!.targets.count > rounds.first!.targets.count, "\(id)")
        }
    }

    /// Gold-on-gold only in the hoard's harder rounds.
    @Test func hoardGoldComesLate() throws {
        let gold = HiddenCurve.goldish(.hoard)
        let rounds = try fixedRounds(.hoard)
        for l in rounds where l.round <= 5 {
            #expect(!l.targets.contains { gold.contains($0.objectID) }, "hoard r\(l.round)")
        }
        #expect(rounds.filter { $0.round >= 6 }.allSatisfy { l in l.targets.contains { gold.contains($0.objectID) } })
        for id in [HiddenSceneID.attic, .market] {
            #expect(try fixedRounds(id).allSatisfy { l in !l.targets.contains { gold.contains($0.objectID) } })
        }
    }

    /// The same bytes give the same rounds, and writing them back gives the same rounds again.
    @Test func deterministicAndRoundTrips() throws {
        for id in HiddenSceneID.allCases {
            let a = try fixedRounds(id), b = try fixedRounds(id)
            #expect(a == b)
            #expect(a.map(\.fingerprint) == b.map(\.fingerprint))
            let file = HiddenFixedFile(proposing: a)
            let again = try HiddenFixedLayouts.load(JSONEncoder().encode(file), scene: scene(id))
            #expect(again == a, "\(id)")
            // a round's state is the same for every player
            #expect(HiddenRoundState(layout: a[2]) == HiddenRoundState(layout: b[2]))
        }
    }

    /// The generator's proposals pass the same checks (hiddengen propose writes them).
    @Test func proposalsAreValid() throws {
        for id in HiddenSceneID.allCases {
            let file = HiddenFixedFile(proposing: HiddenCurve.rounds.map { HiddenGenerator.round(scene(id), round: $0) })
            let layouts = try HiddenFixedLayouts.load(JSONEncoder().encode(file), scene: scene(id))
            #expect(layouts.count == 10)
        }
    }

    @Test func refusesBrokenRounds() throws {
        let s = scene(.attic)
        let base = try JSONDecoder().decode(HiddenFixedFile.self, from: roundsData(.attic))
        func problems(_ edit: (inout HiddenFixedFile) -> Void) -> [String] {
            var f = base
            edit(&f)
            do {
                _ = try HiddenFixedLayouts.load(JSONEncoder().encode(f), scene: s)
                return []
            } catch let HiddenFixedError.invalid(p) {
                return p
            } catch {
                return ["\(error)"]
            }
        }
        #expect(problems { _ in }.isEmpty)
        #expect(!problems { f in f.format = "pourfect-hidden-rounds-v2" }.isEmpty)
        #expect(!problems { f in f.scene = "market" }.isEmpty)
        #expect(!problems { f in f.rounds.removeLast() }.isEmpty)
        #expect(problems { f in f.rounds[0].objects[0].id = "unicorn" }.contains { $0.contains("unknown object") })
        #expect(problems { f in f.rounds[0].objects[0].spot = "z99" }.contains { $0.contains("unknown spot") })
        // a decoy that is a target's object
        #expect(!problems { f in
            var d = f.rounds[0].objects[0]
            d.role = .decoy
            d.spot = f.rounds[0].objects.last!.spot
            f.rounds[0].objects[f.rounds[0].objects.count - 1] = d
        }.isEmpty)
        // a decoy moved onto a target
        #expect(problems { f in
            let t = f.rounds[0].objects[0]
            let i = f.rounds[0].objects.lastIndex { $0.role == .decoy }!
            f.rounds[0].objects[i].spot = t.spot
        }.contains { $0.contains("touches target") || $0.contains("spot is used twice") })
        // a decoy pushed over a target with an offset
        let r0 = try HiddenFixedLayouts.load(roundsData(.attic), scene: s)[0]
        if let t = r0.targets.first, let di = base.rounds[0].objects.firstIndex(where: { $0.role == .decoy }) {
            let d = r0.decoys[0]
            let dx = t.anchorX - d.anchorX, dy = t.anchorY - d.anchorY
            if abs(dx) <= HiddenFixedLayouts.maxOffset && abs(dy) <= HiddenFixedLayouts.maxOffset {
                #expect(problems { f in f.rounds[0].objects[di].dx = dx; f.rounds[0].objects[di].dy = dy }
                    .contains { $0.contains("touches target") })
            }
        }
        #expect(!problems { f in f.rounds[0].objects[0].longSide = 400 }.isEmpty)
        #expect(!problems { f in f.rounds[0].objects[0].dx = 500 }.isEmpty)
        #expect(!problems { f in f.rounds[0].objects[0].rotation = 270 }.isEmpty)
        #expect(!problems { f in f.rounds[0].objects = Array(f.rounds[0].objects.suffix(3)) }.isEmpty)
        // an unusable spot
        let unusable = s.spots.first { $0.unusable }
        if let u = unusable {
            #expect(problems { f in f.rounds[0].objects[0].spot = u.id }.contains { $0.contains("unusable") })
        }
    }
}

// MARK: - Turned objects

@Suite("Hidden: turned objects")
struct HiddenRotationTests {
    @Test func canvas() {
        #expect(HiddenRotation.canvasSize(width: 20, height: 10, degrees: 0) == (20, 10))
        #expect(HiddenRotation.canvasSize(width: 20, height: 10, degrees: 90) == (10, 20))
        #expect(HiddenRotation.canvasSize(width: 20, height: 10, degrees: -90) == (10, 20))
        let c = HiddenRotation.canvasSize(width: 20, height: 10, degrees: 45)
        #expect(c.width == 22 && c.height == 22)   // (20 + 10) / √2 = 21.2, rounded up
    }

    @Test func alphaTurnsClockwise() {
        // 4 × 2, only the top-left pixel opaque; a clockwise quarter turn puts it at the top-right of a 2 × 4 canvas.
        var a = [UInt8](repeating: 0, count: 8)
        a[0] = 255
        let r = HiddenRotation.rotateAlpha(a, width: 4, height: 2, degrees: 90)
        #expect(r.width == 2 && r.height == 4)
        #expect(r.alpha[1] == 255 && r.alpha.filter { $0 > 0 }.count == 1)
    }

    @Test func placementSizeAndAnchor() {
        let o = HiddenObject(id: "w", name: "Wand", sizeClass: .medium, png: "", pixelWidth: 40, pixelHeight: 200)
        let s = HiddenSpot(id: "a", x: 500, y: 400, maxSize: 100, sizeClasses: [.medium], surface: "floor", occlusion: nil)
        let flat = HiddenPlacement(object: o, spot: s, role: .target, longSide: 100, flipped: false, tint: 0.2,
                                   dx: 6, dy: -3, rotation: 90)
        #expect(flat.width == 100 && flat.height == 20)
        #expect(flat.anchorX == 506 && flat.anchorY == 397)
        #expect(flat.x == 456 && flat.y == 377)
        let stored = HiddenFixedObject(flat)
        #expect(stored.rotation == 90 && stored.dx == 6 && stored.dy == -3)
        let plain = HiddenFixedObject(HiddenPlacement(object: o, spot: s, role: .decoy, longSide: 100, flipped: true, tint: 0.2))
        #expect(plain.rotation == nil && plain.dx == nil && plain.dy == nil && plain.flip)
    }

    /// Hit testing on a turned object uses the turned alpha (what the app builds with `rotateAlpha`).
    @Test func hitsATurnedObject() {
        // 10 × 40 upright bar, the top half opaque; turned 90° clockwise it lies with the opaque half on the right.
        let w = 10, h = 40
        let alpha: [UInt8] = (0..<(w * h)).map { $0 / w < h / 2 ? 255 : 0 }
        let o = HiddenObject(id: "bar", name: "Bar", sizeClass: .small, png: "", pixelWidth: w, pixelHeight: h)
        let s = HiddenSpot(id: "a", x: 100, y: 100, maxSize: 40, sizeClasses: [.small], surface: "floor", occlusion: nil)
        let p = HiddenPlacement(object: o, spot: s, role: .target, longSide: 40, flipped: false, tint: 0.2, rotation: 90)
        #expect(p.width == 40 && p.height == 10)      // x 80…120, y 90…100
        let l = HiddenRoundLayout(scene: .attic, round: 1, variant: 0, seed: 1, targets: [p], decoys: [], placedOrder: [p])
        let turned = HiddenRotation.rotateAlpha(alpha, width: w, height: h, degrees: 90)
        let tester = HiddenHitTester(layout: l, masks: ["bar": HiddenAlphaMask(alpha: turned.alpha, width: turned.width, height: turned.height)])
        #expect(tester.hit(at: HiddenPoint(x: 112, y: 95), slop: 0) == .target("bar"))
        #expect(tester.hit(at: HiddenPoint(x: 88, y: 95), slop: 0) == .nothing)
        #expect(tester.hit(at: HiddenPoint(x: 112, y: 70), slop: 0) == .nothing)
    }
}
