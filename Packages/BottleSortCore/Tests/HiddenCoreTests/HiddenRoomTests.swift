import Foundation
import Testing
@testable import HiddenCore
#if canImport(ImageIO)
import ImageIO
#endif

// MARK: - Helpers

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let scenesURL = repoRoot.appendingPathComponent("HiddenScenes")
let goldensURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Goldens/poc_layouts.json")

let loadedScenes: [HiddenSceneID: HiddenScene] = {
    var out: [HiddenSceneID: HiddenScene] = [:]
    for id in HiddenSceneID.allCases {
        let url = scenesURL.appendingPathComponent(id.rawValue).appendingPathComponent("scene.json")
        out[id] = try? HiddenScene(data: Data(contentsOf: url))
    }
    return out
}()

func scene(_ id: HiddenSceneID) -> HiddenScene { loadedScenes[id]! }

struct Goldens: Decodable {
    struct RandomG: Decodable {
        let seed1_random: [Double]
        let seed123456789012_bits_1_5_13_32: [UInt32]
        let seed42_shuffle20: [Int]
        let seed42_then_sample40_12: [Int]
        let seed42_then_sample200_4: [Int]
        let seed42_then_uniform: Double
        let seed0_random: [Double]
        let seed2p40p5_random: [Double]
    }
    struct Occ: Decodable { let x: Int; let y: Int; let w: Int; let h: Int; let rows: [Int]; let uniformColumns: Bool }
    struct Placement: Decodable {
        let object: String; let spot: String; let longSide: Int; let w: Int; let h: Int; let flip: Bool
        let x: Int; let y: Int; let tint: Double; let tintBox: [Int]; let mean: [Double]; let samples: [[[Int]]]
        let shadow: [Int]; let occluder: Occ?
    }
    struct Layout: Decodable { let scene: String; let seed: UInt64; let count: Int; let placements: [Placement] }
    let random: RandomG
    let layouts: [Layout]
}

let goldens: Goldens = try! JSONDecoder().decode(Goldens.self, from: Data(contentsOf: goldensURL))

/// Keeps `#expect` free of mutating calls.
func tapping(_ s: inout HiddenRoundState, _ hit: HiddenHit) -> HiddenTapOutcome { s.tap(hit) }
func hinting(_ s: inout HiddenRoundState, _ now: Double, _ l: HiddenRoundLayout) -> HiddenHintGlow? { s.useHint(now: now, layout: l) }
func revealing(_ s: inout HiddenRoundState) -> String? { s.revealNext() }
func recording(_ p: inout HiddenProgress, _ s: HiddenSceneID, _ r: Int, _ st: Int) -> Bool { p.record(s, round: r, stars: st) }

// MARK: - Python random

@Suite("Hidden: Python-compatible random")
struct PythonRandomTests {
    @Test func matchesCPython() {
        let g = goldens.random
        var r = PythonRandom(seed: 1)
        #expect((0..<5).map { _ in r.random() } == g.seed1_random)
        r = PythonRandom(seed: 123_456_789_012)
        #expect([1, 5, 13, 32].map { r.getrandbits($0) } == g.seed123456789012_bits_1_5_13_32)
        r = PythonRandom(seed: 42)
        var a = Array(0..<20)
        r.shuffle(&a)
        #expect(a == g.seed42_shuffle20)
        #expect(r.sample(Array(0..<40), 12) == g.seed42_then_sample40_12)     // pool strategy
        #expect(r.sample(Array(0..<200), 4) == g.seed42_then_sample200_4)     // set strategy
        #expect(r.uniform(0.88, 1.0) == g.seed42_then_uniform)
        r = PythonRandom(seed: 0)
        #expect((0..<2).map { _ in r.random() } == g.seed0_random)
        r = PythonRandom(seed: (1 << 40) + 5)
        #expect((0..<2).map { _ in r.random() } == g.seed2p40p5_random)
    }
}

// MARK: - Scene files

@Suite("Hidden: scene files")
struct HiddenSceneTests {
    @Test func shippedScenesLoad() {
        for id in HiddenSceneID.allCases {
            let s = scene(id)
            #expect(s.id == id)
            #expect(s.width == 2752 && s.height == 1536)
            #expect(s.objects.count == 40)
            #expect(s.images.map(\.scale) == [1.0, 0.5])
            for o in s.objects {
                #expect(o.longSide <= 220)
                #expect(FileManager.default.fileExists(atPath: scenesURL.appendingPathComponent("\(id.rawValue)/\(o.png)").path))
            }
            for im in s.images {
                #expect(FileManager.default.fileExists(atPath: scenesURL.appendingPathComponent("\(id.rawValue)/\(im.file)").path))
            }
        }
        #expect(scene(.attic).spots.count == 65)
        #expect(scene(.market).spots.count == 61)
        #expect(scene(.hoard).spots.count == 59)
        #expect(scene(.attic).title == "Alchemist's Attic")
        #expect(scene(.hoard).object("golden_key")?.name == "Golden key")
        #expect(scene(.market).spot("m01")?.occlusion?.feather == 6)
    }

    @Test func goldListIsInTheHoard() {
        let ids = Set(scene(.hoard).objects.map(\.id))
        #expect(HiddenCurve.goldish(.hoard).isSubset(of: ids))
        #expect(HiddenCurve.goldish(.hoard).count == 16)
        #expect(HiddenCurve.goldish(.attic).isEmpty && HiddenCurve.goldish(.market).isEmpty)
    }

    @Test func refusesBrokenFiles() throws {
        let url = scenesURL.appendingPathComponent("attic/scene.json")
        let base = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        func load(_ edit: (inout [String: Any]) -> Void) -> HiddenSceneError? {
            var d = base
            edit(&d)
            do { _ = try HiddenScene(data: JSONSerialization.data(withJSONObject: d)); return nil } catch {
                return error as? HiddenSceneError
            }
        }
        let ok = load { _ in }
        #expect(ok == nil)
        let v2 = load { d in d["format"] = "pourfect-hidden-v2" }
        #expect(v2 == .badFormat("pourfect-hidden-v2"))
        let cellar = load { d in d["scene"] = "cellar" }
        #expect(cellar == .unknownScene("cellar"))
        var objects = base["objects"] as! [[String: Any]]
        objects[1]["id"] = objects[0]["id"]
        let dupID = load { [objects] d in d["objects"] = objects }
        #expect(dupID != nil)
        objects = base["objects"] as! [[String: Any]]
        objects[0]["sizeClass"] = "huge"
        let badClass = load { [objects] d in d["objects"] = objects }
        #expect(badClass != nil)
        var spots = base["spots"] as! [[String: Any]]
        spots[0]["x"] = 9999
        let outside = load { [spots] d in d["spots"] = spots }
        #expect(outside != nil)
        spots = (base["spots"] as! [[String: Any]]).map { var s = $0; s["sizeClass"] = ["small"]; return s }
        let noMedium = load { [spots] d in d["spots"] = spots }
        #expect(noMedium != nil)
        let few = Array((base["objects"] as! [[String: Any]]).prefix(10))
        let tooFew = load { d in d["objects"] = few }
        #expect(tooFew != nil)
        #expect(throws: HiddenSceneError.self) { try HiddenScene(data: Data("{}".utf8)) }
    }
}

// MARK: - layout.py goldens

@Suite("Hidden: placement and blending match layout.py")
struct HiddenPoCGoldenTests {
    @Test func layoutsMatchPython() throws {
        #expect(goldens.layouts.count == 9)
        for g in goldens.layouts {
            let s = scene(HiddenSceneID(rawValue: g.scene)!)
            let placements = try #require(HiddenPoC.layout(s, seed: g.seed, count: g.count))
            #expect(placements.count == g.placements.count)
            for (p, e) in zip(placements, g.placements) {
                #expect(p.objectID == e.object && p.spotID == e.spot, "\(g.scene) seed \(g.seed)")
                #expect(p.longSide == e.longSide && p.width == e.w && p.height == e.h, "\(e.object)")
                #expect(p.flipped == e.flip && p.x == e.x && p.y == e.y, "\(e.object)")
                #expect(p.tint == e.tint, "\(e.object)")
                let box = p.tintSampleRect(sceneWidth: s.width, sceneHeight: s.height)
                let boxList: [Int] = [box.x, box.y, box.maxX, box.maxY]
                #expect(boxList == e.tintBox, "\(e.object)")
                let sh = p.shadowRect
                let shadowList: [Int] = [sh.x, sh.y, sh.width, sh.height]
                #expect(shadowList == e.shadow, "\(e.object)")
                let tint = HiddenBlend.tint(mean: HiddenRGB(r: e.mean[0], g: e.mean[1], b: e.mean[2]), strength: p.tint)
                for sample in e.samples {
                    let out = tint.apply(sample[0][0], sample[0][1], sample[0][2])
                    #expect(abs(Int(out.r) - sample[1][0]) <= 1 && abs(Int(out.g) - sample[1][1]) <= 1
                            && abs(Int(out.b) - sample[1][2]) <= 1, "\(e.object) \(sample) → \(out)")
                }
                #expect((p.occlusion == nil) == (e.occluder == nil), "\(e.object)")
                if let occ = p.occlusion, let eo = e.occluder {
                    let occList: [Int] = [occ.rect.x, occ.rect.y, occ.rect.width, occ.rect.height]
                    #expect(occList == [eo.x, eo.y, eo.w, eo.h])
                    let mask = HiddenBlend.occluderMask(occ)
                    #expect((0..<occ.rect.height).map { Int(mask.alpha(x: 0, y: $0)) } == eo.rows, "\(e.object)")
                    if eo.uniformColumns {
                        let w = occ.rect.width
                        #expect((0..<occ.rect.height).allSatisfy { y in (0..<w).allSatisfy { mask.alpha(x: $0, y: y) == mask.alpha(x: 0, y: y) } })
                    }
                }
            }
        }
    }

    @Test func occluderHasTheWrappedTopFade() throws {
        let spot = try #require(scene(.market).spot("m01"))
        let mask = HiddenBlend.occluderMask(HiddenOcclusionGeometry(spot.occlusion!))
        let col = (0..<mask.rect.height).map { mask.alpha(x: 0, y: $0) }
        // rows 0-5 wrap in the opaque bottom; the hard edge sits 2·feather below the patch top; the bottom rows
        // wrap in the empty top rows (below the object's foot, so they never show)
        #expect(Array(col.prefix(7)) == [117, 98, 78, 58, 39, 19, 19])
        #expect(col[12] == 137 && col[18] == 255 && col.last == 137)
    }

    @Test func tintMatrixIsTheFormula() {
        let m = HiddenRGB(r: 120, g: 90, b: 60)
        let t = HiddenBlend.tint(mean: m, strength: 0.2)
        for (r, g, b) in [(10, 200, 30), (255, 255, 255), (0, 0, 0), (77, 66, 55)] {
            let k = 0.72 + 0.35 * m.luminance / 255
            let c = [Double(r), Double(g), Double(b)].enumerated().map { i, v in
                k * (v * 0.8 + [m.r, m.g, m.b][i] * 0.2)
            }
            let grey = c.reduce(0, +) / 3
            let want = c.map { UInt8(min(255, max(0, grey + ($0 - grey) * 0.85)).rounded(.towardZero)) }
            let got = t.apply(r, g, b)
            #expect([got.r, got.g, got.b].enumerated().allSatisfy { abs(Int($1) - Int(want[$0])) <= 1 })
        }
        #expect(t.unitBias.count == 3 && t.matrix.count == 9)
    }

    #if canImport(ImageIO)
    @Test func meanColourOfTheExportedBackground() throws {
        // Means from Pillow's decode of background.jpg; Apple's JPEG decoder differs by a pixel level here and there.
        for g in goldens.layouts where g.seed == 1 {
            let url = scenesURL.appendingPathComponent("\(g.scene)/background.jpg")
            let raster = try #require(decodeRGBA(url))
            let half = try #require(decodeRGBA(scenesURL.appendingPathComponent("\(g.scene)/background_1376.jpg")))
            for e in g.placements {
                let r = HiddenRect(x: e.tintBox[0], y: e.tintBox[1], width: e.tintBox[2] - e.tintBox[0], height: e.tintBox[3] - e.tintBox[1])
                let m = raster.mean(r)
                #expect(abs(m.r - e.mean[0]) < 1 && abs(m.g - e.mean[1]) < 1 && abs(m.b - e.mean[2]) < 1, "\(e.object) \(m) \(e.mean)")
                let h = half.mean(backgroundRect: r, scale: 0.5)   // the small background is close enough for the tint
                #expect(abs(h.r - e.mean[0]) < 3 && abs(h.g - e.mean[1]) < 3 && abs(h.b - e.mean[2]) < 3, "\(e.object)")
            }
        }
    }

    @Test func realObjectMasks() throws {
        for id in HiddenSceneID.allCases {
            for o in scene(id).objects.prefix(5) {
                let r = try #require(decodeRGBA(scenesURL.appendingPathComponent("\(id.rawValue)/\(o.png)")))
                #expect(r.width == o.pixelWidth && r.height == o.pixelHeight)
                let alpha = stride(from: 3, to: r.pixels.count, by: 4).map { r.pixels[$0] }
                let mask = HiddenAlphaMask(alpha: alpha, width: r.width, height: r.height)
                #expect(mask.coverage > 0.2 && mask.coverage < 1, "\(o.id) \(mask.coverage)")
            }
        }
    }
    #endif
}

#if canImport(ImageIO)
import CoreGraphics
func decodeRGBA(_ url: URL) -> HiddenRaster? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ok = px.withUnsafeMutableBytes { buf -> Bool in
        guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    // un-premultiply is not needed: only opaque backgrounds are averaged and masks only read alpha
    return ok ? HiddenRaster(width: w, height: h, pixels: px, bytesPerPixel: 4) : nil
}
#endif

// MARK: - Rounds

@Suite("Hidden: round curve and generator")
struct HiddenRoundTests {
    @Test func curveRises() {
        for id in HiddenSceneID.allCases {
            let specs = HiddenCurve.rounds.map { HiddenCurve.spec(id, round: $0) }
            #expect(specs.map(\.round) == Array(1...10))
            for (a, b) in zip(specs, specs.dropFirst()) {
                #expect(a.targets <= b.targets && a.decoys <= b.decoys)
                #expect(a.scaleHigh >= b.scaleHigh && a.scaleLow >= b.scaleLow)
                #expect(a.maxSpotDifficulty <= b.maxSpotDifficulty && a.maxMediumTargets >= b.maxMediumTargets)
                #expect(a.goldTargets <= b.goldTargets)
            }
            #expect(specs.first!.targets == 8 && specs.last!.targets == HiddenCurve.maxTargets)
            #expect(specs.allSatisfy { (8...HiddenCurve.maxDecoys).contains($0.decoys) })
            #expect(specs.allSatisfy { $0.targets + $0.decoys <= 40 })
            #expect(specs.prefix(5).allSatisfy { $0.goldTargets == 0 })
        }
        #expect(HiddenCurve.spec(.hoard, round: 10).goldTargets == 3)
        #expect(HiddenCurve.spec(.attic, round: 10).goldTargets == 0)
        #expect(HiddenCurve.spec(.attic, round: 99).round == 10)
    }

    @Test func seedsAreStable() {
        #expect(HiddenGenerator.seed(.attic, round: 1, variant: 0) != HiddenGenerator.seed(.attic, round: 1, variant: 1))
        #expect(HiddenGenerator.seed(.attic, round: 1, variant: 0) != HiddenGenerator.seed(.market, round: 1, variant: 0))
        #expect(HiddenGenerator.seed(.attic, round: 1, variant: 0) == HiddenGenerator.seed(.attic, round: 1, variant: 0))
    }

    /// Every rule, over 3 rooms × 10 rounds × 40 variants.
    @Test func roundsFollowTheRules() {
        for id in HiddenSceneID.allCases {
            let s = scene(id)
            let gold = HiddenCurve.goldish(id)
            for round in HiddenCurve.rounds {
                let spec = HiddenCurve.spec(id, round: round)
                var fingerprints = Set<String>()
                for variant in 0..<40 {
                    let l = HiddenGenerator.round(s, round: round, variant: variant)
                    let tag = "\(id) r\(round) v\(variant)"
                    fingerprints.insert(l.fingerprint)
                    #expect(l.targets.count == spec.targets, "\(tag)")
                    // every room has room for the full count through round 6; later at least 10 (the market is tight)
                    #expect(l.decoys.count <= spec.decoys, "\(tag)")
                    #expect(l.decoys.count >= (round <= 6 ? spec.decoys : min(spec.decoys, 10)), "\(tag)")
                    let all = l.targets + l.decoys
                    #expect(Set(all.map(\.objectID)).count == all.count, "\(tag)")
                    #expect(Set(all.map(\.spotID)).count == all.count, "\(tag)")
                    #expect(all.allSatisfy { $0.role == (l.targets.contains($0) ? .target : .decoy) })
                    let targetNames = Set(l.targets.map { s.object($0.objectID)!.name.lowercased() })
                    #expect(l.decoys.allSatisfy { !targetNames.contains(s.object($0.objectID)!.name.lowercased()) }, "\(tag)")
                    // compatibility, sizes, spacing
                    for p in all {
                        let o = s.object(p.objectID)!, sp = s.spot(p.spotID)!
                        #expect(sp.accepts(o.sizeClass), "\(tag) \(p.objectID)")
                        let lo = HiddenRules.renderLongSide(o, at: sp, factor: spec.scaleLow)
                        let hi = HiddenRules.renderLongSide(o, at: sp, factor: spec.scaleHigh)
                        #expect((lo...hi).contains(p.longSide), "\(tag) \(p.objectID)")
                        #expect(max(p.width, p.height) == p.longSide || abs(max(p.width, p.height) - p.longSide) <= 1)
                        #expect(p.x == sp.x - p.width / 2 && p.y == sp.y - p.height)
                        #expect(HiddenRules.tintRange.contains(p.tint))
                    }
                    let spots = all.map { s.spot($0.spotID)! }
                    for (i, a) in spots.enumerated() {
                        #expect(HiddenRules.isSpaced(a, from: Array(spots[..<i])), "\(tag) \(a.id)")
                    }
                    // targets: difficulty, medium cap, hard spots, gold
                    let hard = l.targets.filter { s.spot($0.spotID)!.difficulty >= 2 }.count
                    let overMax = l.targets.filter { s.spot($0.spotID)!.difficulty > spec.maxSpotDifficulty }.count
                    #expect(overMax <= spec.hardSpotTargets, "\(tag)")
                    #expect(hard >= min(spec.hardSpotTargets, 1) || spec.hardSpotTargets == 0, "\(tag)")
                    #expect(l.targets.filter { s.object($0.objectID)!.sizeClass == .medium }.count <= spec.maxMediumTargets)
                    #expect(l.targets.filter { gold.contains($0.objectID) }.count == spec.goldTargets, "\(tag)")
                    // decoys never cover a target (box + shadow core + margin)
                    for d in l.decoys {
                        let db = HiddenGenerator.footprint(d.rect)
                        for t in l.targets {
                            #expect(!HiddenGenerator.footprint(t.rect).insetBy(-HiddenGenerator.decoyMargin).intersects(db),
                                    "\(tag) decoy \(d.objectID) over \(t.objectID)")
                        }
                    }
                    // draw order back to front
                    let ys = l.drawOrder.map(\.anchorY)
                    #expect(ys == ys.sorted())
                }
                #expect(fingerprints.count == 40, "\(id) r\(round): variants should differ")
            }
        }
    }

    @Test func deterministic() {
        for id in HiddenSceneID.allCases {
            let a = HiddenGenerator.round(scene(id), round: 7, variant: 3)
            let b = HiddenGenerator.round(scene(id), round: 7, variant: 3)
            #expect(a == b && a.fingerprint == b.fingerprint)
        }
    }

    @Test func goldenRounds() {
        #expect(HiddenGenerator.seed(.attic, round: 1, variant: 0) == goldenSeedAttic1)
        #expect(HiddenGenerator.round(scene(.attic), round: 1).fingerprint == goldenAttic1)
        #expect(HiddenGenerator.round(scene(.hoard), round: 10, variant: 2).fingerprint == goldenHoard10v2)
    }

    @Test func fast() {
        let start = Date()
        for id in HiddenSceneID.allCases {
            for r in HiddenCurve.rounds { _ = HiddenGenerator.round(scene(id), round: r) }
        }
        #if !DEBUG
        #expect(Date().timeIntervalSince(start) < 0.5)
        #endif
    }
}

let goldenSeedAttic1: UInt64 = 6545833932382697410
let goldenAttic1 =
    "d:mortar@a10:67x80:236 d:lavender@a02:56x80:256 T:teacup@a17:58x35f:258 T:hourglass@a04:32x60:198 T:crystal@b02:47x62f:216 T:watch@b01:48x63:223 d:mirror@b06:61x84:200 T:padlock@b09:42x61:209 d:owl@c04:56x88:232 T:magnifier@c14:82x85:182 T:horseshoe@b16:51x63f:191 d:broom@b20:75x84f:260 T:pumpkin@c07:102x102:207 d:flask@c17:51x98:212 d:globe@c20:65x91:244 d:telescope@b14:95x79:236"
let goldenHoard10v2 =
    "T:sapphire@h07:46x44:233 T:coin_pouch@h09:45x43:251 d:golden_key@h08:56x17:200 T:jeweled_egg@h06:28x46:229 T:oyster_pearl@h12:51x44:201 T:golden_bird@h39:45x33:204 d:jewel_box@h13:74x74f:221 T:emerald@h15:45x49:202 T:brooch@h37:49x38:214 d:treasure_map@h45:52x77f:224 T:tiara@h14:54x28f:245 T:dragon_scale@h38:32x50:199 T:dragon_egg@h18:38x53:190 d:golden_mask@h20:76x55f:203 d:dagger@h47:69x76:210 d:royal_orb@h56:29x57f:181 T:goblet@h42:49x85:253 d:blue_vase@h19:54x77f:239 d:drinking_horn@h57:64x71:213 T:mini_chest@h59:54x48:196 T:ruby@h33:53x48:190 d:golden_apple@h48:43x47:186 d:battle_axe@h51:48x88:243 d:pearl_necklace@h34:78x83:260 T:crystal_ball@h49:38x51f:227 d:round_shield@h32:78x82:241 d:gauntlet@h52:45x101:247 d:crown@h31:92x67:205 d:helmet@h29:62x89f:212 d:jade_dragon@h53:82x67f:244 d:candelabra@h60:50x98:218 d:scepter@h28:75x86:254 T:harp@h30:58x91:245 d:gold_plate@h27:82x81:189 d:phoenix_feather@h54:60x76f:183"

// MARK: - Hit testing

@Suite("Hidden: hit testing")
struct HiddenHitTests {
    /// A 20 × 20 object whose left half is opaque.
    static let halfMask = HiddenAlphaMask(alpha: (0..<400).map { ($0 % 20) < 10 ? 255 : 0 }, width: 20, height: 20)
    static let fullMask = HiddenAlphaMask(alpha: [UInt8](repeating: 200, count: 400), width: 20, height: 20)

    static func layout(flipTarget: Bool = false) -> HiddenRoundLayout {
        let objs = (0..<3).map { HiddenObject(id: "o\($0)", name: "O\($0)", sizeClass: .small, png: "", pixelWidth: 20, pixelHeight: 20) }
        let spots = [
            HiddenSpot(id: "a", x: 100, y: 100, maxSize: 40, sizeClasses: [.small], surface: "", occlusion: nil),
            HiddenSpot(id: "b", x: 200, y: 100, maxSize: 40, sizeClasses: [.small], surface: "", occlusion: nil),
            HiddenSpot(id: "c", x: 100, y: 130, maxSize: 40, sizeClasses: [.small], surface: "", occlusion: nil),
        ]
        // 40 × 40 on screen: o0 at (80, 60)…(120, 100), o1 at (180, 60)…, decoy o2 at (80, 90)…(120, 130) over o0's foot
        let t0 = HiddenPlacement(object: objs[0], spot: spots[0], role: .target, longSide: 40, flipped: flipTarget, tint: 0.2)
        let t1 = HiddenPlacement(object: objs[1], spot: spots[1], role: .target, longSide: 40, flipped: false, tint: 0.2)
        let d = HiddenPlacement(object: objs[2], spot: spots[2], role: .decoy, longSide: 40, flipped: false, tint: 0.2)
        return HiddenRoundLayout(scene: .attic, round: 1, variant: 0, seed: 1, targets: [t0, t1], decoys: [d],
                                 placedOrder: [t0, t1, d])
    }

    @Test func alphaDecides() {
        let tester = HiddenHitTester(layout: Self.layout(), masks: ["o0": Self.halfMask, "o1": Self.halfMask, "o2": Self.fullMask])
        #expect(tester.hit(at: HiddenPoint(x: 85, y: 70), slop: 0) == .target("o0"))      // opaque left half
        #expect(tester.hit(at: HiddenPoint(x: 115, y: 70), slop: 0) == .nothing)          // transparent right half
        #expect(tester.hit(at: HiddenPoint(x: 115, y: 70), slop: 18) == .target("o0"))    // forgiving radius
        #expect(tester.hit(at: HiddenPoint(x: 115, y: 70), slop: 10) == .nothing)
        #expect(tester.hit(at: HiddenPoint(x: 85, y: 95), slop: 30) == .decoy("o2"))      // decoy drawn on top
        #expect(tester.hit(at: HiddenPoint(x: 150, y: 70), slop: 40) == .target("o1"))    // nearest target (o1 at 180)
        #expect(tester.hit(at: HiddenPoint(x: 85, y: 70), slop: 0, found: ["o0"]) == .nothing)
        #expect(tester.hit(at: HiddenPoint(x: 300, y: 300), slop: 48) == .nothing)
    }

    @Test func flippedObjects() {
        let tester = HiddenHitTester(layout: Self.layout(flipTarget: true), masks: ["o0": Self.halfMask, "o1": Self.halfMask, "o2": Self.fullMask])
        #expect(tester.hit(at: HiddenPoint(x: 85, y: 70), slop: 0) == .nothing)
        #expect(tester.hit(at: HiddenPoint(x: 115, y: 70), slop: 0) == .target("o0"))
    }

    @Test func slopFollowsZoom() {
        #expect(HiddenTouch.slop(pointsPerBackgroundPixel: 1) == 22)
        #expect(HiddenTouch.slop(pointsPerBackgroundPixel: 4) == 6)
        #expect(HiddenTouch.slop(pointsPerBackgroundPixel: 0.25) == 48)
        #expect(Self.halfMask.columns == 10 && abs(Self.halfMask.coverage - 0.5) < 1e-9)
    }
}

// MARK: - Round state and progression

@Suite("Hidden: round state, stars, progression")
struct HiddenStateTests {
    @Test func stars() {
        #expect(HiddenStars.stars(hints: 0, wrongTaps: 0) == 3)
        #expect(HiddenStars.stars(hints: 0, wrongTaps: 3) == 3)
        #expect(HiddenStars.stars(hints: 0, wrongTaps: 4) == 2)
        #expect(HiddenStars.stars(hints: 1, wrongTaps: 0) == 2)
        #expect(HiddenStars.stars(hints: 2, wrongTaps: 10) == 2)
        #expect(HiddenStars.stars(hints: 3, wrongTaps: 0) == 1)
        #expect(HiddenStars.stars(hints: 0, wrongTaps: 11) == 1)
    }

    @Test func playARound() {
        let l = HiddenGenerator.round(scene(.attic), round: 1)
        var s = HiddenRoundState(layout: l)
        #expect(s.remaining.count == 8 && !s.isComplete)
        #expect(tapping(&s, .nothing) == .wrong(decoy: nil))
        #expect(tapping(&s, .decoy(l.decoys[0].objectID)) == .wrong(decoy: l.decoys[0].objectID))
        #expect(s.wrongTaps == 2)
        let first = l.targets[0].objectID
        #expect(tapping(&s, .target(first)) == .found(first, remaining: 7))
        #expect(tapping(&s, .target(first)) == .wrong(decoy: nil))                  // already gone from the picture
        #expect(s.wrongTaps == 3 && s.stars == 3)
        let glow = hinting(&s, 100, l)
        #expect(glow?.objectID == l.targets[1].objectID)
        if let g = glow, let p = l.placement(g.objectID) {
            let dx = g.center.x - p.center.x, dy = g.center.y - p.center.y
            #expect((dx * dx + dy * dy).squareRoot() <= g.radius * 0.35 + 1e-9)
            #expect(g == HiddenHintGlow.glow(for: p, seed: l.seed, hintNumber: 1))
        }
        #expect(hinting(&s, 110, l) == nil && s.hintCooldownRemaining(now: 110) == 20)
        #expect(s.hintsUsed == 1 && s.stars == 2)
        #expect(hinting(&s, 130, l) != nil && s.hintsUsed == 2)
        #expect(revealing(&s) == l.targets[1].objectID && s.hintsUsed == 3 && s.stars == 1)
        for t in l.targets.dropFirst(2) { _ = tapping(&s, .target(t.objectID)) }
        #expect(s.isComplete && s.remaining.isEmpty)
        #expect(tapping(&s, .nothing) == .wrong(decoy: nil) && s.wrongTaps == 3)     // after the end: not counted
        #expect(revealing(&s) == nil && hinting(&s, 999, l) == nil)
    }

    @Test func roomsOpenWithChapters() {
        func open(upTo n: Int) -> [Bool] { (1...10).map { $0 <= n } }
        #expect(!HiddenProgression.isSceneUnlocked(.attic, chapterUnlocked: open(upTo: 1)))
        #expect(HiddenProgression.isSceneUnlocked(.attic, chapterUnlocked: open(upTo: 2)))
        #expect(!HiddenProgression.isSceneUnlocked(.market, chapterUnlocked: open(upTo: 4)))
        #expect(HiddenProgression.isSceneUnlocked(.market, chapterUnlocked: open(upTo: 5)))
        #expect(!HiddenProgression.isSceneUnlocked(.hoard, chapterUnlocked: open(upTo: 7)))
        #expect(HiddenProgression.isSceneUnlocked(.hoard, chapterUnlocked: open(upTo: 8)))
        #expect(!HiddenProgression.isSceneUnlocked(.hoard, chapterUnlocked: []))
        #expect(HiddenProgression.sceneOnOpening(.market, seen: []) == "hidden.market")
        #expect(HiddenProgression.sceneOnOpening(.market, seen: ["hidden.market"]) == nil)
        #expect(HiddenSceneID(number: 3) == .hoard && HiddenSceneID(number: 4) == nil)
    }

    @Test func roundsOpenInOrder() throws {
        var p = HiddenProgress()
        #expect(HiddenProgression.isRoundUnlocked(1, in: .attic, progress: p))
        #expect(!HiddenProgression.isRoundUnlocked(2, in: .attic, progress: p))
        #expect(!HiddenProgression.isRoundUnlocked(11, in: .attic, progress: p))
        #expect(recording(&p, .attic, 1, 2))
        #expect(HiddenProgression.isRoundUnlocked(2, in: .attic, progress: p))
        #expect(!HiddenProgression.isRoundUnlocked(2, in: .market, progress: p))
        #expect(!recording(&p, .attic, 1, 1))                // not a new best
        #expect(recording(&p, .attic, 1, 3))
        #expect(p.bestStars(.attic, round: 1) == 3 && p.finishedPlays(.attic, round: 1) == 3)
        #expect(p.stars(.attic) == 3 && p.roundsFinished(.attic) == 1 && p.nextRound(.attic) == 2)
        #expect(!recording(&p, .attic, 0, 3))
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(HiddenProgress.self, from: data) == p)
    }
}
