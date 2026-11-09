import SwiftUI

// OpenObject Retro Arcade, the tvOS half (HANDOFF §20): a NATIVE SWIFT PORT of player/public/arcade.js,
// because tvOS has no WebKit for the web-view reuse the iPhone and iPad use. This file mirrors arcade.js
// SECTION BY SECTION with the same names, constants, sprites, font, and update logic, so the two stay
// easy to diff by eye. ANY CHANGE TO arcade.js MUST BE MIRRORED HERE (and vice versa); both headers say so.
//
// HOMAGE NOTICE (same as arcade.js): a trivial, NON-PLAYABLE self-playing demo built as an homage to an
// era, with stylistic inspiration that was commonplace in 1980s arcade gaming. Not affiliated with, and
// reproducing no assets, names, or trademarks of, any specific game or company; every sprite, the font,
// the logo, and all code here are original.
//
// Rendering: SwiftUI Canvas inside a TimelineView (ArcadeView.swift). The game is pure rectangle
// drawing, so GraphicsContext is a near 1:1 stand-in for canvas 2D; the one liberty taken is batching
// same-color rects into one Path per fill (a sprite is a handful of fills instead of ~90), purely a
// draw-call optimization, the geometry is identical. The playfield is the same SQUARE logical field
// (FIELD units) centered on the screen's shorter side; a 16:9 TV gets the starfield wings.
final class ArcadeGame {
    private let FIELD = 256.0
    private func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { v < a ? a : (v > b ? b : v) }
    private func rand(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }
    private let TAU = Double.pi * 2

    // Parallax rainbow starfield: (count, speed as fraction of height/sec, size pt).
    private static let STAR_LAYERS: [(count: Int, speed: Double, size: Double)] = [(44, 0.03, 1), (30, 0.06, 1.4), (18, 0.11, 2)]
    private static let STAR_COLORS: [Color] = [hex(0xff5d73), hex(0xffd24d), hex(0x59f0ff), hex(0x7cff8a), hex(0xc08aff), hex(0xffffff), hex(0xff9d3c)]

    private enum C {
        static let bg = hex(0x04050c), bullet = hex(0x9ff0ff), ebullet = hex(0xff5d73)
        static let hudRed = hex(0xff3b30), hudWhite = hex(0xeaf2ff)
    }

    // Enemy explosion, developer flip (as in arcade.js): true = 'dust' pixel burst, false = 'ring'.
    private static let BLAST_DUST = true
    private static let BLAST_PAL: [Color] = [hex(0xffffff), hex(0xffffff), hex(0xffffff), hex(0xfff3a8), hex(0xffe27a), hex(0xffd24d), hex(0xff9d3c), hex(0xff5d73), hex(0x9ff0ff)]

    // ── Pixel-art sprites (our own), the exact grids from arcade.js. '.' / ' ' = transparent. ──
    private static let boss = makeSprite(
        pal: ["T": hex(0x2fe0c4), "t": hex(0x16a890), "Y": hex(0xffd83d), "W": hex(0xeaf2ff), "K": hex(0x05121a)],
        rows: [
            "......K......",
            "..K...t...K..",
            "..K..ttt..K..",
            "...tTTTTTt...",
            "..tTTTTTTTt..",
            ".tTTTYYYTTTt.",
            "WTTTYYYYYTTTW",
            "WTTYYYWYYYTTW",
            "WtTTYYYYYTTtW",
            ".tTTtTTTtTTt.",
            "..tt..t..tt..",
            "...K.....K..." ])
    private static let escort = makeSprite(
        pal: ["R": hex(0xff3b30), "r": hex(0xb51a0e), "W": hex(0xeaf2ff), "B": hex(0x3aa0ff), "K": hex(0x05121a)],
        rows: [
            ".....r.r.....",
            ".....RRR.....",
            "...RRRRRRR...",
            "..RRWWWWWRR..",
            ".RRRWKBKWRRR.",
            ".RRRRRRRRRRR.",
            "RRRRRRRRRRRRR",
            "RRR.RRRRR.RRR",
            ".RR..RRR..RR.",
            "..R...R...R.." ])
    private static let grunt = makeSprite(
        pal: ["B": hex(0x2b6bff), "b": hex(0x143a9e), "Y": hex(0xffd83d), "W": hex(0xeaf2ff), "K": hex(0x05121a)],
        rows: [
            ".....b.b.....",
            ".....BBB.....",
            "...BBBBBBB...",
            "..BBBBBBBBB..",
            ".BBBYYYYYBBB.",
            "WBBBYYYYYBBBW",
            "WBBBBYWYBBBBW",
            ".BBBBBBBBBBB.",
            "..Bbb...bbB..",
            "...K.....K..." ])
    private static let shipSprite = makeSprite(
        pal: ["W": hex(0xf2f6ff), "R": hex(0xff3b30), "B": hex(0x3aa0ff)],
        rows: [
            ".....W.....",
            ".....W.....",
            "....WWW....",
            "....WRW....",
            "...WWRWW...",
            "..WWWRWWW..",
            ".WWBWRWBWW.",
            "WWW.WRW.WWW",
            "RW...B...WR" ])

    // Formation: rows of slots near the top; bosses up top, red crabs, then blue bees (like the genre).
    private let COLS = 8, ROWS = 5
    private let SLOT_W = 21.0, SLOT_H = 15.0, GRID_TOP = 70.0
    private var GRID_X0: Double { FIELD / 2 - (Double(COLS - 1) * SLOT_W) / 2 }
    private func slot(_ c: Int, _ r: Int) -> CGPoint { CGPoint(x: GRID_X0 + Double(c) * SLOT_W, y: GRID_TOP + Double(r) * SLOT_H) }
    private func kindForRow(_ r: Int) -> Kind { r == 0 ? .boss : (r <= 2 ? .escort : .grunt) }

    enum Kind { case boss, escort, grunt }
    private enum EState { case enter, form, dive }
    private struct Enemy {
        var kind: Kind
        var state: EState
        var t: Double
        var speed: Double
        var path: [CGPoint]
        var dive: [CGPoint]?
        var slot: CGPoint
        var x: Double, y: Double
        var heading: Double
        var fireCd: Double
        var dead = false
    }
    private struct Bullet { var x: Double, y: Double; var dead = false }
    private struct EBullet { var x: Double, y: Double, vx: Double, vy: Double }
    private struct Blast { var x: Double, y: Double, age: Double }
    private struct Dust { var x: Double, y: Double, vx: Double, vy: Double, life: Double, max: Double, size: Double; var color: Color }
    private struct Star { var x: Double, y: Double, speed: Double, size: Double; var color: Color; var tw: Bool; var ph: Double }
    private struct Ship { var x: Double, tx: Double, fireCd: Double }

    private var last: Double?
    private var t = 0.0
    private var W = 0.0, H = 0.0
    private var box = (x: 0.0, y: 0.0, size: 1.0)
    private var stars: [Star] = []

    private var enemies: [Enemy] = [], bullets: [Bullet] = [], eBullets: [EBullet] = []
    private var blasts: [Blast] = [], dust: [Dust] = []
    private var spawnQueue: [(at: Double, e: Enemy)] = []
    private var ship = Ship(x: 128, tx: 128, fireCd: 0)
    private var score = 0, hi = 20000, wave = 0
    private var formPhase = 0.0, formOffset = 0.0, spawnTimer = 0.0, diveTimer = 0.0, clearT = 0.0, lastFire = 0.0

    init() {
        seedStars()
        resetGame()
    }

    private func bz(_ p: [CGPoint], _ u: Double) -> CGPoint {
        let k = 1 - u
        return CGPoint(x: k*k*k*p[0].x + 3*k*k*u*p[1].x + 3*k*u*u*p[2].x + u*u*u*p[3].x,
                       y: k*k*k*p[0].y + 3*k*k*u*p[1].y + 3*k*u*u*p[2].y + u*u*u*p[3].y)
    }
    private func bzd(_ p: [CGPoint], _ u: Double) -> CGPoint {
        let k = 1 - u
        return CGPoint(x: 3*k*k*(p[1].x-p[0].x) + 6*k*u*(p[2].x-p[1].x) + 3*u*u*(p[3].x-p[2].x),
                       y: 3*k*k*(p[1].y-p[0].y) + 6*k*u*(p[2].y-p[1].y) + 3*u*u*(p[3].y-p[2].y))
    }

    // Entry paths: streaming swoops from the bottom corners and the top, ending at the formation slot.
    private func entryPath(_ group: Int, _ T: CGPoint) -> [CGPoint] {
        switch group % 4 {
        // cases 0/1 swoop up from the bottom CORNERS, so their path crosses the fighter's row out at the
        // left/right edges (a centred fighter is already clear); the AI also dodges imminent crossings.
        case 0: return [CGPoint(x: FIELD * 0.14, y: FIELD + 20), CGPoint(x: FIELD * 0.04, y: FIELD * 0.55), CGPoint(x: FIELD * 0.3, y: 12), T]
        case 1: return [CGPoint(x: FIELD * 0.86, y: FIELD + 20), CGPoint(x: FIELD * 0.96, y: FIELD * 0.55), CGPoint(x: FIELD * 0.7, y: 12), T]
        case 2: return [CGPoint(x: -26, y: -8), CGPoint(x: FIELD * 0.42, y: FIELD * 0.5), CGPoint(x: FIELD * 0.82, y: FIELD * 0.42), T]
        default: return [CGPoint(x: FIELD + 26, y: -8), CGPoint(x: FIELD * 0.58, y: FIELD * 0.5), CGPoint(x: FIELD * 0.18, y: FIELD * 0.42), T]
        }
    }

    private func spawnWave() {
        wave += 1
        enemies = []; bullets = []; eBullets = []; spawnQueue = []
        var i = 0
        for r in 0..<ROWS { for c in 0..<COLS {
            let T = slot(c, r), grp = i / 8, path = entryPath(grp, T)
            spawnQueue.append((at: Double(i) * 0.1, e: Enemy(kind: kindForRow(r), state: .enter, t: 0, speed: rand(0.5, 0.62),
                                                             path: path, dive: nil, slot: T, x: path[0].x, y: path[0].y, heading: 0, fireCd: rand(1, 4))))
            i += 1
        } }
        spawnTimer = 0; diveTimer = 2.2; clearT = 1
    }

    private func resetGame() {
        ship = Ship(x: FIELD / 2, tx: FIELD / 2, fireCd: 0)
        score = 0; wave = 0; t = 0; formPhase = 0; formOffset = 0; lastFire = -2; blasts = []; dust = []
        spawnWave()
    }

    private func startDive(_ i: Int) {
        let e = enemies[i]
        let side: Double = e.x < FIELD / 2 ? 1 : -1
        enemies[i].dive = [
            CGPoint(x: e.x, y: e.y),
            CGPoint(x: e.x + side * 46, y: FIELD * 0.42),
            CGPoint(x: clamp(ship.x - side * 24, 14, FIELD - 14), y: FIELD * 0.82),
            CGPoint(x: e.slot.x + formOffset, y: e.slot.y),
        ]
        enemies[i].state = .dive; enemies[i].t = 0; enemies[i].speed = rand(0.4, 0.52); enemies[i].fireCd = rand(0.2, 0.5)
    }

    private func fireEnemyBullet(_ e: Enemy) {
        // Aim at the fighter but with a little spread, so shots aren't laser-homing (the fighter dodges
        // the rest). sp kept modest so the dodge always has time to clear the lane.
        let ang = atan2(FIELD - 26 - e.y, ship.x - e.x) + rand(-0.2, 0.2), sp = 86.0
        eBullets.append(EBullet(x: e.x, y: e.y, vx: cos(ang) * sp, vy: sin(ang) * sp))
    }

    // Enemy explosion: 'ring' pushes one expanding circle; 'dust' sprays short-lived pixel specks + a flash.
    private func spawnBlast(_ x: Double, _ y: Double) {
        if !Self.BLAST_DUST { blasts.append(Blast(x: x, y: y, age: 0)); return }
        for _ in 0..<16 {
            let a = Double.random(in: 0..<TAU), sp = rand(10, 69), small = Double.random(in: 0..<1) < 0.68
            let life = small ? rand(0.3, 0.6) : rand(0.45, 0.8)
            dust.append(Dust(x: x, y: y, vx: cos(a) * sp, vy: sin(a) * sp, life: life, max: life,
                             size: small ? rand(0.4, 1.1) : rand(1.2, 1.8), color: Self.BLAST_PAL.randomElement()!))
        }
        for _ in 0..<3 { dust.append(Dust(x: x, y: y, vx: rand(-6, 6), vy: rand(-6, 6), life: 0.1, max: 0.1, size: 3.4, color: Self.hex(0xffffff))) } // flash
    }

    // Where an entrant/diver's curved path crosses the fighter's row (SHIP_Y), or nil if it never does
    // (e.g. a diver that pulls up above the fighter). The fighter avoids this x so it's never body-checked.
    private func crossingX(_ e: Enemy) -> Double? {
        guard let path = e.state == .enter ? e.path : e.dive else { return nil }
        let SY = FIELD - 26
        var prev = bz(path, e.t)
        var s = e.t + 0.04
        while s <= 1.001 {
            let p = bz(path, min(s, 1))
            if (prev.y - SY) * (p.y - SY) <= 0 {
                return prev.x + (p.x - prev.x) * ((SY - prev.y) / ((p.y - prev.y) != 0 ? (p.y - prev.y) : 1))
            }
            prev = p
            s += 0.04
        }
        return nil
    }

    private func update(_ dt: Double) {
        t += dt; formPhase += dt; formOffset = sin(formPhase * 0.7) * 7

        spawnTimer += dt
        while let first = spawnQueue.first, first.at <= spawnTimer { enemies.append(first.e); spawnQueue.removeFirst() }

        diveTimer -= dt
        if diveTimer <= 0 {
            let formed = enemies.indices.filter { enemies[$0].state == .form }
            if !formed.isEmpty {
                startDive(formed.randomElement()!)
                if formed.count > 12 && Double.random(in: 0..<1) < 0.5 { startDive(formed.randomElement()!) }
            }
            diveTimer = rand(0.6, 1.5)
        }

        for i in enemies.indices {
            switch enemies[i].state {
            case .enter:
                enemies[i].t += enemies[i].speed * dt
                if enemies[i].t >= 1 {
                    enemies[i].state = .form; enemies[i].x = enemies[i].slot.x + formOffset; enemies[i].y = enemies[i].slot.y; enemies[i].heading = 0
                } else {
                    let p = bz(enemies[i].path, enemies[i].t), d = bzd(enemies[i].path, enemies[i].t)
                    enemies[i].x = p.x; enemies[i].y = p.y; enemies[i].heading = atan2(d.y, d.x) + .pi / 2
                }
            case .form:
                enemies[i].x = enemies[i].slot.x + formOffset; enemies[i].y = enemies[i].slot.y; enemies[i].heading = 0
            case .dive:
                enemies[i].t += enemies[i].speed * dt
                if enemies[i].t >= 1 {
                    enemies[i].state = .form; enemies[i].heading = 0
                } else {
                    let dive = enemies[i].dive!
                    let p = bz(dive, enemies[i].t), d = bzd(dive, enemies[i].t)
                    enemies[i].x = p.x; enemies[i].y = p.y; enemies[i].heading = atan2(d.y, d.x) + .pi / 2
                    // Fire only EARLY in the dive while still high (shots start far away, so dodgeable) AND at
                    // most one shot every ~1.4s across the whole swarm, with a single shot in the air the
                    // fighter's safest-spot move always clears it, so nothing ever lands (never-die).
                    enemies[i].fireCd -= dt
                    if enemies[i].fireCd <= 0 && enemies[i].t < 0.3 && enemies[i].y < FIELD * 0.5 && t - lastFire > 1.4 {
                        enemies[i].fireCd = rand(1.5, 2.5); lastFire = t; fireEnemyBullet(enemies[i])
                    }
                }
            }
        }

        // Self-playing fighter. Staying alive is the top priority: this is a never-die demo, so a shot
        // must never land. Each incoming shot's predicted crossing x is a "danger"; while any exist the
        // fighter moves to the x furthest from every danger (a real gap always exists at this fire rate),
        // pre-positioning instead of reacting late. Otherwise it chases a diver to pick off, or pans.
        let SHIP_Y = FIELD - 26
        var dangers: [Double] = []
        for b in eBullets {
            if b.vy <= 0 { continue }
            let dy = SHIP_Y - b.y
            if dy > 0 { dangers.append(b.x + b.vx * (dy / b.vy)) }
        }
        // Moving attack pieces are dangers too, but only the IMMINENT ones (currently near the fighter's
        // row, about to cross it). Predict where each one's path crosses the row and dodge that. Reacting
        // to every far-off crossing over-constrains the fighter and ironically causes hits, so gate on
        // nearness; with the bottom swoops crossing out at the edges, the centred fighter stays clear.
        for e in enemies where (e.state == .dive || e.state == .enter) && e.y > SHIP_Y - 8 && e.y < SHIP_Y + 42 {
            if let ex = crossingX(e) { dangers.append(ex) }
        }
        var target: Double
        if !dangers.isEmpty {
            var bestX = ship.x, bestScore = -Double.infinity
            var cand = FIELD * 0.1
            while cand <= FIELD * 0.9 {
                var minD = Double.infinity
                for d in dangers { let gap = abs(cand - d); if gap < minD { minD = gap } }
                let score = minD - abs(cand - ship.x) * 0.12 // safest spot, mild stay-put bias
                if score > bestScore { bestScore = score; bestX = cand }
                cand += 5
            }
            target = bestX
        } else {
            let divers = enemies.filter { $0.state == .dive && $0.y > FIELD * 0.35 }.sorted { $0.y > $1.y }
            if let first = divers.first { target = first.x }
            else {
                let formed = enemies.filter { $0.state == .form }
                target = formed.isEmpty ? FIELD / 2 : formed[Int(t * 0.6) % formed.count].x
            }
        }
        // A bullet already level with the fighter is a "blocker": never slide THROUGH one to reach a far
        // target, hold on the side the fighter is already on. (The dangers above pre-position for shots
        // still overhead; this closes the lone graze where the safest-x sat across a level shot.)
        for b in eBullets where b.vy > 0 && b.y > SHIP_Y - 12 && b.y < SHIP_Y + 10 {
            if ship.x <= b.x { target = min(target, b.x - 7) }
            else { target = max(target, b.x + 7) }
        }
        ship.tx = clamp(target, FIELD * 0.08, FIELD * 0.92)
        let sd = ship.tx - ship.x, step = 168 * dt
        ship.x += abs(sd) < step ? sd : (sd < 0 ? -step : step)
        ship.fireCd -= dt
        if ship.fireCd <= 0 { ship.fireCd = rand(0.16, 0.26); bullets.append(Bullet(x: ship.x, y: FIELD - 32)) }

        for i in bullets.indices { bullets[i].y -= 270 * dt }
        for i in eBullets.indices { eBullets[i].x += eBullets[i].vx * dt; eBullets[i].y += eBullets[i].vy * dt }

        for bi in bullets.indices {
            for ei in enemies.indices where !enemies[ei].dead {
                let rr: Double = enemies[ei].kind == .boss ? 8 : 6.5
                if abs(bullets[bi].x - enemies[ei].x) < rr && abs(bullets[bi].y - enemies[ei].y) < rr {
                    enemies[ei].dead = true; bullets[bi].dead = true
                    spawnBlast(enemies[ei].x, enemies[ei].y)
                    score += enemies[ei].kind == .boss ? 150 : (enemies[ei].kind == .escort ? 80 : 50)
                    break
                }
            }
        }
        enemies.removeAll { $0.dead }
        bullets.removeAll { $0.dead || $0.y <= -6 }
        eBullets.removeAll { !($0.y < FIELD + 6 && $0.y > -6 && $0.x > -6 && $0.x < FIELD + 6) }
        for i in blasts.indices { blasts[i].age += dt }
        blasts.removeAll { $0.age >= 0.38 }
        for i in dust.indices {
            dust[i].x += dust[i].vx * dt; dust[i].y += dust[i].vy * dt
            let k = 1 - 6 * dt
            dust[i].vx *= k; dust[i].vy *= k; dust[i].vy += 18 * dt; dust[i].life -= dt
        }
        dust.removeAll { $0.life <= 0 }
        if score > hi { hi = score }

        if enemies.isEmpty && spawnQueue.isEmpty { clearT -= dt; if clearT <= 0 { spawnWave() } } else { clearT = 1 }

        for i in stars.indices { stars[i].y += stars[i].speed * dt; if stars[i].y > 1 { stars[i].y -= 1 } }
    }

    // ── draw ──
    private func fx(_ x: Double) -> Double { box.x + (x / FIELD) * box.size }
    private func fy(_ y: Double) -> Double { box.y + (y / FIELD) * box.size }
    private func fs(_ v: Double) -> Double { (v / FIELD) * box.size }

    private func drawStarfield(_ ctx: inout GraphicsContext) {
        for s in stars {
            ctx.opacity = s.tw ? 0.5 + 0.5 * sin(t * 3 + s.ph) : 1
            ctx.fill(Path(CGRect(x: (s.x * W).rounded(), y: (s.y * H).rounded(), width: s.size, height: s.size)), with: .color(s.color))
        }
        ctx.opacity = 1
    }

    private struct Sprite { let groups: [(color: Color, cells: [(ox: Double, oy: Double)])] }
    private static func makeSprite(pal: [Character: Color], rows: [String]) -> Sprite {
        let h = rows.count
        var order: [Character] = []
        var byChar: [Character: [(Double, Double)]] = [:]
        for (y, row) in rows.enumerated() {
            let chars = Array(row), w = chars.count
            for (x, ch) in chars.enumerated() where pal[ch] != nil {
                if byChar[ch] == nil { order.append(ch) }
                byChar[ch, default: []].append((Double(x) - Double(w) / 2, Double(y) - Double(h) / 2))
            }
        }
        return Sprite(groups: order.map { (pal[$0]!, byChar[$0]!) })
    }

    private func blitSprite(_ cx: Double, _ cy: Double, _ sp: Sprite, _ cellF: Double, _ rot: Double, _ ctx: GraphicsContext) {
        let cell = fs(cellF)
        var c = ctx
        c.translateBy(x: fx(cx), y: fy(cy))
        if rot != 0 { c.rotate(by: .radians(rot)) }
        let sz = cell.rounded(.up)
        for group in sp.groups {
            var path = Path()
            for cellPos in group.cells {
                path.addRect(CGRect(x: (cellPos.ox * cell).rounded(), y: (cellPos.oy * cell).rounded(), width: sz, height: sz))
            }
            c.fill(path, with: .color(group.color))
        }
    }

    private func drawEnemy(_ e: Enemy, _ ctx: GraphicsContext) {
        let rot = e.state == .enter || e.state == .dive ? e.heading : 0
        let sp = e.kind == .boss ? Self.boss : (e.kind == .escort ? Self.escort : Self.grunt)
        blitSprite(e.x, e.y, sp, e.kind == .boss ? 1.15 : 1, rot, ctx)
    }

    // ── Marquee + HUD text: a 5×7 BITMAP FONT drawn as hard pixel blocks, so the logo and scores are
    // crisp pixels with edge fidelity, exactly like the sprites, NOT a blurry downscale. ──
    private struct ColorScheme { let outer: Color, fillTop: Color }
    private static let COLOR_SCHEMES: [ColorScheme] = [
        ColorScheme(outer: hex(0xd11a1a), fillTop: hex(0x86e85f)),   // Emerald
        ColorScheme(outer: hex(0x7a1500), fillTop: hex(0xffd24a)),   // Sunburst
        ColorScheme(outer: hex(0x3a0a6e), fillTop: hex(0xff8af0)),   // Nebula
        ColorScheme(outer: hex(0x0a2a6e), fillTop: hex(0x9fe6ff)),   // Ice
    ]
    private static let scheme = 0 // marquee colour scheme (dev flip): 0 Emerald, 1 Sunburst, 2 Nebula, 3 Ice

    private static let FONT: [Character: [String]] = [
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        "(": ["..#..", ".#...", ".#...", ".#...", ".#...", ".#...", "..#.."],
        ")": ["..#..", "...#.", "...#.", "...#.", "...#.", "...#.", "..#.."],
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "..##.", ".#...", "#....", "#####"],
        "3": [".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
        "N": ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".###.", "#...#", "#....", ".###.", "....#", "#...#", ".###."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    ]
    private static let glyphCells: [Character: [(c: Int, r: Int)]] = FONT.mapValues { rows in
        var cells: [(c: Int, r: Int)] = []
        for (r, row) in rows.enumerated() {
            for (c, ch) in Array(row).enumerated() where ch == "#" { cells.append((c, r)) }
        }
        return cells
    }

    private enum Align { case left, center, right }

    // Draw a string as hard pixel blocks (crisp). x,y in field coords (y = top); px = block size in
    // field units; align left|center|right.
    private func drawText(_ str: String, _ x: Double, _ y: Double, _ px: Double, _ color: Color, _ align: Align, _ ctx: inout GraphicsContext) {
        let ADV = 6.0, wpx = Double(str.count) * ADV - 1, blk = fs(px).rounded(.up)
        let left = align == .center ? x - (wpx * px) / 2 : (align == .right ? x - wpx * px : x)
        var path = Path()
        for (i, ch) in str.enumerated() {
            guard let cells = Self.glyphCells[ch] else { continue }
            let gx = left + Double(i) * ADV * px
            for cell in cells {
                path.addRect(CGRect(x: fx(gx + Double(cell.c) * px).rounded(), y: fy(y + Double(cell.r) * px).rounded(), width: blk, height: blk))
            }
        }
        ctx.fill(path, with: .color(color))
    }

    // The "OPENOBJECT" marquee: our own bitmap word in the 5×7 font with a chunky 4-way outline. Crisp
    // pixels (hard blocks, like the sprites), centred just below the HIGH SCORE line.
    private func drawLogo(_ ctx: inout GraphicsContext) {
        let sc = Self.COLOR_SCHEMES[Self.scheme], cx = FIELD / 2, yTop = 32.0, px = 2.6, word = "OPENOBJECT"
        for (ox, oy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
            drawText(word, cx + ox * px, yTop + oy * px, px, sc.outer, .center, &ctx)
        }
        drawText(word, cx, yTop, px, sc.fillTop, .center, &ctx)
    }

    private func drawHud(_ ctx: inout GraphicsContext) {
        drawText("1UP", 10, 6, 0.9, C.hudRed, .left, &ctx)
        drawText(String(format: "%06d", score), 10, 14, 0.9, C.hudWhite, .left, &ctx)
        drawText("HIGH SCORE", FIELD / 2, 6, 0.9, C.hudRed, .center, &ctx)
        drawText(String(format: "%06d", hi), FIELD / 2, 14, 0.9, C.hudWhite, .center, &ctx)
        for i in 0..<3 { blitSprite(14 + Double(i) * 13, FIELD - 10, Self.shipSprite, 0.62, 0, ctx) } // lives
        drawText("(C) 2026 OPENOBJECT", FIELD / 2, FIELD - 11, 0.58, Self.hex(0x7f8aa6), .center, &ctx)
    }

    private func draw(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)), with: .color(C.bg))
        drawStarfield(&ctx)
        drawLogo(&ctx)
        var bPath = Path()
        for b in bullets { bPath.addRect(CGRect(x: fx(b.x) - fs(0.8), y: fy(b.y) - fs(3), width: fs(1.6), height: fs(5))) }
        ctx.fill(bPath, with: .color(C.bullet))
        var ePath = Path()
        for b in eBullets { ePath.addRect(CGRect(x: fx(b.x) - fs(1), y: fy(b.y) - fs(1), width: fs(2), height: fs(2))) }
        ctx.fill(ePath, with: .color(C.ebullet))
        for e in enemies { drawEnemy(e, ctx) }
        for b in blasts {
            ctx.opacity = 1 - b.age / 0.38
            let r = fs(2 + b.age * 20)
            ctx.stroke(Path(ellipseIn: CGRect(x: fx(b.x) - r, y: fy(b.y) - r, width: r * 2, height: r * 2)),
                       with: .color(Self.hex(0xffd24d)), lineWidth: max(1, fs(1)))
            ctx.opacity = 1
        }
        for p in dust {
            ctx.opacity = max(0, p.life / p.max)
            let s = fs(p.size).rounded(.up)
            ctx.fill(Path(CGRect(x: fx(p.x).rounded(), y: fy(p.y).rounded(), width: s, height: s)), with: .color(p.color))
        }
        ctx.opacity = 1
        blitSprite(ship.x, FIELD - 26, Self.shipSprite, 1.15, 0, ctx)
        drawHud(&ctx)
    }

    /// One frame: advance the simulation by the real elapsed time (capped at 0.05 s, so a hitch or a
    /// 120 Hz display never breaks the physics) and draw into the Canvas. `now` is any monotonic-enough
    /// clock in seconds; the TimelineView's date drives it.
    func frame(now: Double, context: inout GraphicsContext, size: CGSize) {
        W = size.width; H = size.height
        let s = min(W, H)
        box = (x: (W - s) / 2, y: (H - s) / 2, size: s)
        let dt = min(0.05, max(0, now - (last ?? now)))
        last = now
        update(dt)
        draw(&context)
    }

    private func seedStars() {
        stars = Self.STAR_LAYERS.flatMap { layer in
            (0..<layer.count).map { _ in
                Star(x: Double.random(in: 0..<1), y: Double.random(in: 0..<1), speed: layer.speed, size: layer.size,
                     color: Self.STAR_COLORS.randomElement()!, tw: Double.random(in: 0..<1) < 0.5, ph: Double.random(in: 0..<TAU))
            }
        }
    }

    private static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255, opacity: 1)
    }
}
