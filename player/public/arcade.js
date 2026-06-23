'use strict';

// OpenObject Retro Arcade: the hidden self-playing "attract mode" demo (an easter egg).
//
// HOMAGE NOTICE: this is a trivial, NON-PLAYABLE feature of OpenObject (a self-playing demo, no
// controls), built as an homage to an era, created with stylistic inspiration that was commonplace
// in 1980s arcade gaming. It is not affiliated with, and reproduces no assets, names, or trademarks
// of, any specific game or company; every sprite, font, the logo, and all code here are original.
//
// A self-contained vanilla <canvas> homage to the classic fixed-shooter arcade demo: an insectoid
// swarm that streams in along swooping curved paths, holds formation, and peels off to dive-bomb a
// self-playing fighter, all over a rainbow starfield under an "OpenObject" marquee. A PARODY/HOMAGE,
// not a copy: the sprites, palette, and logo are our own, drawn in code, no ROM, no emulator, no
// external assets, no network. It reads as the genre without reproducing anyone's artwork.
//
// Aspect: the playfield is a SQUARE logical field (FIELD units), centred and scaled to the stage's
// shorter side. Square display → fills edge to edge; wide screen → the square centres and the side
// margins carry the same starfield (no bars, no cropped action). Re-flows live on resize.
//
// display.js owns the lifecycle: RetroArcade.start(canvas) when the demo takes the stage, .stop() on
// Return to Art. The loop only runs in between. Always silent (no audio), like all OpenObject art.
//
// Built so far: pixel-art sprites, curved fly-in entrances, formation sway, dive-bomb runs, endless
// waves. Next: the capture beam + dual fighter, and bonus stages.

window.RetroArcade = (function () {
  const FIELD = 256;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const rand = (a, b) => a + Math.random() * (b - a);
  const TAU = Math.PI * 2;

  // Parallax rainbow starfield: [count, speed (fraction of height/sec), size px].
  const STAR_LAYERS = [[44, 0.03, 1], [30, 0.06, 1.4], [18, 0.11, 2]];
  const STAR_COLORS = ['#ff5d73', '#ffd24d', '#59f0ff', '#7cff8a', '#c08aff', '#ffffff', '#ff9d3c'];

  const C = { bg: '#04050c', bullet: '#9ff0ff', ebullet: '#ff5d73', hudRed: '#ff3b30', hudWhite: '#eaf2ff',
    marquee1: '#ffe27a', marquee2: '#ff9d3c' };

  // Enemy explosion, developer flip: 'ring' (the original expanding circle) | 'dust' (pixel-dust burst).
  const BLAST = 'dust';
  const BLAST_PAL = ['#ffffff', '#ffffff', '#ffffff', '#fff3a8', '#ffe27a', '#ffd24d', '#ff9d3c', '#ff5d73', '#9ff0ff'];

  // ── Pixel-art sprites (our own). Each cell is one "sprite pixel"; '.' / ' ' = transparent. ──
  const SPRITES = {
    boss: { pal: { T: '#2fe0c4', t: '#16a890', Y: '#ffd83d', W: '#eaf2ff', K: '#05121a' }, rows: [
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
      "...K.....K..." ] },
    escort: { pal: { R: '#ff3b30', r: '#b51a0e', W: '#eaf2ff', B: '#3aa0ff', K: '#05121a' }, rows: [
      ".....r.r.....",
      ".....RRR.....",
      "...RRRRRRR...",
      "..RRWWWWWRR..",
      ".RRRWKBKWRRR.",
      ".RRRRRRRRRRR.",
      "RRRRRRRRRRRRR",
      "RRR.RRRRR.RRR",
      ".RR..RRR..RR.",
      "..R...R...R.." ] },
    grunt: { pal: { B: '#2b6bff', b: '#143a9e', Y: '#ffd83d', W: '#eaf2ff', K: '#05121a' }, rows: [
      ".....b.b.....",
      ".....BBB.....",
      "...BBBBBBB...",
      "..BBBBBBBBB..",
      ".BBBYYYYYBBB.",
      "WBBBYYYYYBBBW",
      "WBBBBYWYBBBBW",
      ".BBBBBBBBBBB.",
      "..Bbb...bbB..",
      "...K.....K..." ] },
    ship: { pal: { W: '#f2f6ff', R: '#ff3b30', B: '#3aa0ff' }, rows: [
      ".....W.....",
      ".....W.....",
      "....WWW....",
      "....WRW....",
      "...WWRWW...",
      "..WWWRWWW..",
      ".WWBWRWBWW.",
      "WWW.WRW.WWW",
      "RW...B...WR" ] },
  };

  // Formation: rows of slots near the top; bosses up top, red crabs, then blue bees (like the genre).
  const COLS = 8, ROWS = 5, SLOT_W = 21, SLOT_H = 15, GRID_TOP = 70;
  const GRID_X0 = FIELD / 2 - ((COLS - 1) * SLOT_W) / 2;
  const slot = (c, r) => ({ x: GRID_X0 + c * SLOT_W, y: GRID_TOP + r * SLOT_H });
  const kindForRow = (r) => (r === 0 ? 'boss' : r <= 2 ? 'escort' : 'grunt');

  let canvas, ctx, raf = null, running = false, last = 0, t = 0;
  let W = 0, H = 0, dpr = 1, box = { x: 0, y: 0, size: 1 }, resizePending = true, stars = [];

  let enemies = [], bullets = [], eBullets = [], blasts = [], dust = [], spawnQueue = [];
  let ship, score, hi = 20000, wave, formPhase, formOffset, spawnTimer, diveTimer, clearT, lastFire = 0;

  const bz = (p, q, r, s, u) => { const k = 1 - u;
    return { x: k*k*k*p.x + 3*k*k*u*q.x + 3*k*u*u*r.x + u*u*u*s.x, y: k*k*k*p.y + 3*k*k*u*q.y + 3*k*u*u*r.y + u*u*u*s.y }; };
  const bzd = (p, q, r, s, u) => { const k = 1 - u;
    return { x: 3*k*k*(q.x-p.x) + 6*k*u*(r.x-q.x) + 3*u*u*(s.x-r.x), y: 3*k*k*(q.y-p.y) + 6*k*u*(r.y-q.y) + 3*u*u*(s.y-r.y) }; };

  // Entry paths: streaming swoops from the bottom corners and the top, ending at the formation slot.
  function entryPath(group, T) {
    switch (group % 4) {
      // cases 0/1 swoop up from the bottom CORNERS, so their path crosses the fighter's row out at the
      // left/right edges (a centred fighter is already clear); the AI also dodges imminent crossings.
      case 0: return [{ x: FIELD * 0.14, y: FIELD + 20 }, { x: FIELD * 0.04, y: FIELD * 0.55 }, { x: FIELD * 0.3, y: 12 }, T];
      case 1: return [{ x: FIELD * 0.86, y: FIELD + 20 }, { x: FIELD * 0.96, y: FIELD * 0.55 }, { x: FIELD * 0.7, y: 12 }, T];
      case 2: return [{ x: -26, y: -8 }, { x: FIELD * 0.42, y: FIELD * 0.5 }, { x: FIELD * 0.82, y: FIELD * 0.42 }, T];
      default: return [{ x: FIELD + 26, y: -8 }, { x: FIELD * 0.58, y: FIELD * 0.5 }, { x: FIELD * 0.18, y: FIELD * 0.42 }, T];
    }
  }

  function spawnWave() {
    wave++;
    enemies = []; bullets = []; eBullets = []; spawnQueue = [];
    let i = 0;
    for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) {
      const T = slot(c, r), grp = Math.floor(i / 8), path = entryPath(grp, T);
      spawnQueue.push({ at: i * 0.1, e: { kind: kindForRow(r), state: 'enter', t: 0, speed: rand(0.5, 0.62),
        path, slot: T, x: path[0].x, y: path[0].y, heading: 0, fireCd: rand(1, 4) } });
      i++;
    }
    spawnTimer = 0; diveTimer = 2.2; clearT = 1;
  }

  function resetGame() { ship = { x: FIELD / 2, tx: FIELD / 2, fireCd: 0 }; score = 0; wave = 0; t = 0; formPhase = 0; formOffset = 0; lastFire = -2; blasts = []; dust = []; spawnWave(); }

  function startDive(e) {
    const side = e.x < FIELD / 2 ? 1 : -1;
    e.dive = [
      { x: e.x, y: e.y },
      { x: e.x + side * 46, y: FIELD * 0.42 },
      { x: clamp(ship.x - side * 24, 14, FIELD - 14), y: FIELD * 0.82 },
      { x: e.slot.x + formOffset, y: e.slot.y },
    ];
    e.state = 'dive'; e.t = 0; e.speed = rand(0.4, 0.52); e.fireCd = rand(0.2, 0.5);
  }

  function fireEnemyBullet(e) {
    // Aim at the fighter but with a little spread, so shots aren't laser-homing (the fighter dodges
    // the rest). sp kept modest so the dodge always has time to clear the lane.
    const ang = Math.atan2(FIELD - 26 - e.y, ship.x - e.x) + rand(-0.2, 0.2), sp = 86;
    eBullets.push({ x: e.x, y: e.y, vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp });
  }

  // Enemy explosion: 'ring' pushes one expanding circle; 'dust' sprays short-lived pixel specks + a flash.
  function spawnBlast(x, y) {
    if (BLAST !== 'dust') { blasts.push({ x, y, age: 0 }); return; }
    for (let i = 0; i < 16; i++) {
      const a = Math.random() * TAU, sp = rand(10, 69), small = Math.random() < 0.68, life = small ? rand(0.3, 0.6) : rand(0.45, 0.8);
      dust.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life, max: life, size: small ? rand(0.4, 1.1) : rand(1.2, 1.8), color: BLAST_PAL[(Math.random() * BLAST_PAL.length) | 0] });
    }
    for (let i = 0; i < 3; i++) dust.push({ x, y, vx: rand(-6, 6), vy: rand(-6, 6), life: 0.1, max: 0.1, size: 3.4, color: '#ffffff' }); // flash
  }

  // Where an entrant/diver's curved path crosses the fighter's row (SHIP_Y), or null if it never does
  // (e.g. a diver that pulls up above the fighter). The fighter avoids this x so it's never body-checked.
  function crossingX(e) {
    const path = e.state === 'enter' ? e.path : e.dive;
    if (!path) return null;
    const SY = FIELD - 26;
    let prev = bz(path[0], path[1], path[2], path[3], e.t);
    for (let s = e.t + 0.04; s <= 1.001; s += 0.04) {
      const p = bz(path[0], path[1], path[2], path[3], Math.min(s, 1));
      if ((prev.y - SY) * (p.y - SY) <= 0) return prev.x + (p.x - prev.x) * ((SY - prev.y) / ((p.y - prev.y) || 1));
      prev = p;
    }
    return null;
  }

  function update(dt) {
    t += dt; formPhase += dt; formOffset = Math.sin(formPhase * 0.7) * 7;

    spawnTimer += dt;
    while (spawnQueue.length && spawnQueue[0].at <= spawnTimer) enemies.push(spawnQueue.shift().e);

    diveTimer -= dt;
    if (diveTimer <= 0) {
      const formed = enemies.filter((e) => e.state === 'form');
      if (formed.length) {
        startDive(formed[(Math.random() * formed.length) | 0]);
        if (formed.length > 12 && Math.random() < 0.5) startDive(formed[(Math.random() * formed.length) | 0]);
      }
      diveTimer = rand(0.6, 1.5);
    }

    for (const e of enemies) {
      if (e.state === 'enter') {
        e.t += e.speed * dt;
        if (e.t >= 1) { e.state = 'form'; e.x = e.slot.x + formOffset; e.y = e.slot.y; e.heading = 0; }
        else { const p = bz(...e.path, e.t), d = bzd(...e.path, e.t); e.x = p.x; e.y = p.y; e.heading = Math.atan2(d.y, d.x) + Math.PI / 2; }
      } else if (e.state === 'form') {
        e.x = e.slot.x + formOffset; e.y = e.slot.y; e.heading = 0;
      } else if (e.state === 'dive') {
        e.t += e.speed * dt;
        if (e.t >= 1) { e.state = 'form'; e.heading = 0; }
        else {
          const p = bz(...e.dive, e.t), d = bzd(...e.dive, e.t);
          e.x = p.x; e.y = p.y; e.heading = Math.atan2(d.y, d.x) + Math.PI / 2;
          // Fire only EARLY in the dive while still high (shots start far away, so dodgeable) AND at
          // most one shot every ~1.4s across the whole swarm, with a single shot in the air the
          // fighter's safest-spot move always clears it, so nothing ever lands (never-die).
          e.fireCd -= dt;
          if (e.fireCd <= 0 && e.t < 0.3 && e.y < FIELD * 0.5 && t - lastFire > 1.4) { e.fireCd = rand(1.5, 2.5); lastFire = t; fireEnemyBullet(e); }
        }
      }
    }

    // Self-playing fighter. Staying alive is the top priority: this is a never-die demo, so a shot
    // must never land. Each incoming shot's predicted crossing x is a "danger"; while any exist the
    // fighter moves to the x furthest from every danger (a real gap always exists at this fire rate),
    // pre-positioning instead of reacting late. Otherwise it chases a diver to pick off, or pans.
    const SHIP_Y = FIELD - 26;
    const dangers = [];
    for (const b of eBullets) {
      if (b.vy <= 0) continue;
      const dy = SHIP_Y - b.y;
      if (dy > 0) dangers.push(b.x + b.vx * (dy / b.vy));
    }
    // Moving attack pieces are dangers too, but only the IMMINENT ones (currently near the fighter's
    // row, about to cross it). Predict where each one's path crosses the row and dodge that. Reacting
    // to every far-off crossing over-constrains the fighter and ironically causes hits, so gate on
    // nearness; with the bottom swoops crossing out at the edges, the centred fighter stays clear.
    for (const e of enemies) if ((e.state === 'dive' || e.state === 'enter') && e.y > SHIP_Y - 8 && e.y < SHIP_Y + 42) { const ex = crossingX(e); if (ex != null) dangers.push(ex); }
    let target;
    if (dangers.length) {
      let bestX = ship.x, bestScore = -Infinity;
      for (let cand = FIELD * 0.1; cand <= FIELD * 0.9; cand += 5) {
        let minD = Infinity;
        for (const d of dangers) { const gap = Math.abs(cand - d); if (gap < minD) minD = gap; }
        const score = minD - Math.abs(cand - ship.x) * 0.12; // safest spot, mild stay-put bias
        if (score > bestScore) { bestScore = score; bestX = cand; }
      }
      target = bestX;
    } else {
      const divers = enemies.filter((e) => e.state === 'dive' && e.y > FIELD * 0.35).sort((a, b) => b.y - a.y);
      if (divers.length) target = divers[0].x;
      else { const formed = enemies.filter((e) => e.state === 'form'); target = formed.length ? formed[Math.floor(t * 0.6) % formed.length].x : FIELD / 2; }
    }
    ship.tx = clamp(target, FIELD * 0.08, FIELD * 0.92);
    const sd = ship.tx - ship.x, step = 168 * dt;
    ship.x += Math.abs(sd) < step ? sd : Math.sign(sd) * step;
    ship.fireCd -= dt; if (ship.fireCd <= 0) { ship.fireCd = rand(0.16, 0.26); bullets.push({ x: ship.x, y: FIELD - 32 }); }

    for (const b of bullets) b.y -= 270 * dt;
    for (const b of eBullets) { b.x += b.vx * dt; b.y += b.vy * dt; }

    for (const b of bullets) {
      for (const e of enemies) {
        if (e._dead) continue;
        const rr = e.kind === 'boss' ? 8 : 6.5;
        if (Math.abs(b.x - e.x) < rr && Math.abs(b.y - e.y) < rr) {
          e._dead = true; b._dead = true; spawnBlast(e.x, e.y);
          score += e.kind === 'boss' ? 150 : e.kind === 'escort' ? 80 : 50; break;
        }
      }
    }
    enemies = enemies.filter((e) => !e._dead);
    bullets = bullets.filter((b) => !b._dead && b.y > -6);
    eBullets = eBullets.filter((b) => b.y < FIELD + 6 && b.y > -6 && b.x > -6 && b.x < FIELD + 6);
    for (const x of blasts) x.age += dt; blasts = blasts.filter((x) => x.age < 0.38);
    for (const p of dust) { p.x += p.vx * dt; p.y += p.vy * dt; const k = 1 - 6 * dt; p.vx *= k; p.vy *= k; p.vy += 18 * dt; p.life -= dt; }
    dust = dust.filter((p) => p.life > 0);
    if (score > hi) hi = score;

    if (enemies.length === 0 && spawnQueue.length === 0) { clearT -= dt; if (clearT <= 0) spawnWave(); } else clearT = 1;

    for (const s of stars) { s.y += s.speed * dt; if (s.y > 1) s.y -= 1; }
  }

  // ── draw ──
  const fx = (x) => box.x + (x / FIELD) * box.size;
  const fy = (y) => box.y + (y / FIELD) * box.size;
  const fs = (v) => (v / FIELD) * box.size;

  function drawStarfield() {
    for (const s of stars) {
      ctx.globalAlpha = s.tw ? 0.5 + 0.5 * Math.sin(t * 3 + s.ph) : 1;
      ctx.fillStyle = s.color;
      ctx.fillRect(Math.round(s.x * W), Math.round(s.y * H), s.size, s.size);
    }
    ctx.globalAlpha = 1;
  }

  function blitSprite(cx, cy, sp, cellF, rot) {
    const cell = fs(cellF), rows = sp.rows, pal = sp.pal, h = rows.length;
    ctx.save();
    ctx.translate(fx(cx), fy(cy));
    if (rot) ctx.rotate(rot);
    for (let y = 0; y < h; y++) {
      const row = rows[y], w = row.length;
      for (let x = 0; x < w; x++) {
        const col = pal[row[x]];
        if (!col) continue;
        ctx.fillStyle = col;
        ctx.fillRect(Math.round((x - w / 2) * cell), Math.round((y - h / 2) * cell), Math.ceil(cell), Math.ceil(cell));
      }
    }
    ctx.restore();
  }

  function drawEnemy(e) {
    const rot = e.state === 'enter' || e.state === 'dive' ? e.heading : 0;
    blitSprite(e.x, e.y, SPRITES[e.kind], e.kind === 'boss' ? 1.15 : 1, rot);
  }

  // ── Marquee + HUD text: a 5×7 BITMAP FONT drawn as hard pixel blocks (fillRect), so the logo and
  // scores are crisp pixels with edge fidelity, exactly like the sprites, NOT a blurry downscale. ──
  const COLOR_SCHEMES = [
    { name: 'Emerald', outer: '#d11a1a', mid: '#ffd21a', fillTop: '#86e85f', fillBot: '#1f8f2e', comet: '#aef0ff' },
    { name: 'Sunburst', outer: '#7a1500', mid: '#ffe14a', fillTop: '#ffd24a', fillBot: '#ff6a1f', comet: '#aef0ff' },
    { name: 'Nebula', outer: '#3a0a6e', mid: '#5ff0ff', fillTop: '#ff8af0', fillBot: '#a826ff', comet: '#fff27a' },
    { name: 'Ice', outer: '#0a2a6e', mid: '#eaf6ff', fillTop: '#9fe6ff', fillBot: '#1f6fff', comet: '#ffd24a' },
  ];
  const scheme = 0; // marquee colour scheme (dev flip): 0 Emerald, 1 Sunburst, 2 Nebula, 3 Ice

  const FONT = {
    ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
    '(': ['..#..', '.#...', '.#...', '.#...', '.#...', '.#...', '..#..'],
    ')': ['..#..', '...#.', '...#.', '...#.', '...#.', '...#.', '..#..'],
    '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
    '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
    '2': ['.###.', '#...#', '....#', '..##.', '.#...', '#....', '#####'],
    '3': ['.###.', '#...#', '....#', '..##.', '....#', '#...#', '.###.'],
    '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
    '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
    '6': ['.###.', '#....', '#....', '####.', '#...#', '#...#', '.###.'],
    '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
    '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
    '9': ['.###.', '#...#', '#...#', '.####', '....#', '....#', '.###.'],
    B: ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
    C: ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
    E: ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
    G: ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.###.'],
    H: ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    I: ['.###.', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
    J: ['..###', '...#.', '...#.', '...#.', '#..#.', '#..#.', '.##..'],
    N: ['#...#', '##..#', '##..#', '#.#.#', '#..##', '#..##', '#...#'],
    O: ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    P: ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
    R: ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
    S: ['.###.', '#...#', '#....', '.###.', '....#', '#...#', '.###.'],
    T: ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
    U: ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  };

  // Draw a string as hard pixel blocks (crisp). x,y in field coords (y = top); px = block size in
  // field units; align left|center|right.
  function drawText(str, x, y, px, color, align) {
    const CW = 5, CH = 7, ADV = 6, wpx = str.length * ADV - 1, blk = Math.ceil(fs(px));
    let left = align === 'center' ? x - (wpx * px) / 2 : align === 'right' ? x - wpx * px : x;
    ctx.fillStyle = color;
    for (let i = 0; i < str.length; i++) {
      const g = FONT[str[i]];
      if (!g) continue;
      const gx = left + i * ADV * px;
      for (let r = 0; r < CH; r++) for (let c = 0; c < CW; c++)
        if (g[r][c] === '#') ctx.fillRect(Math.round(fx(gx + c * px)), Math.round(fy(y + r * px)), blk, blk);
    }
  }

  // The "OPENOBJECT" marquee: our own bitmap word in the 5×7 font with a chunky 4-way outline. Crisp
  // pixels (hard fillRect blocks, like the sprites), centred just below the HIGH SCORE line.
  function drawLogo() {
    const sc = COLOR_SCHEMES[scheme], cx = FIELD / 2, yTop = 32, px = 2.6, word = 'OPENOBJECT';
    for (const [ox, oy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) drawText(word, cx + ox * px, yTop + oy * px, px, sc.outer, 'center');
    drawText(word, cx, yTop, px, sc.fillTop, 'center');
  }

  function drawHud() {
    drawText('1UP', 10, 6, 0.9, C.hudRed, 'left');
    drawText(String(score).padStart(6, '0'), 10, 14, 0.9, C.hudWhite, 'left');
    drawText('HIGH SCORE', FIELD / 2, 6, 0.9, C.hudRed, 'center');
    drawText(String(hi).padStart(6, '0'), FIELD / 2, 14, 0.9, C.hudWhite, 'center');
    for (let i = 0; i < 3; i++) blitSprite(14 + i * 13, FIELD - 10, SPRITES.ship, 0.62, 0); // lives
    drawText('(C) 2026 OPENOBJECT', FIELD / 2, FIELD - 11, 0.58, '#7f8aa6', 'center');
  }

  function draw() {
    if (window.innerWidth !== W || window.innerHeight !== H) measure(); // self-heal a stale/late size
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = C.bg; ctx.fillRect(0, 0, W, H);
    drawStarfield();
    drawLogo();
    ctx.fillStyle = C.bullet;
    for (const b of bullets) ctx.fillRect(fx(b.x) - fs(0.8), fy(b.y) - fs(3), fs(1.6), fs(5));
    ctx.fillStyle = C.ebullet;
    for (const b of eBullets) ctx.fillRect(fx(b.x) - fs(1), fy(b.y) - fs(1), fs(2), fs(2));
    for (const e of enemies) drawEnemy(e);
    for (const b of blasts) {
      ctx.strokeStyle = '#ffd24d'; ctx.globalAlpha = 1 - b.age / 0.38; ctx.lineWidth = Math.max(1, fs(1));
      ctx.beginPath(); ctx.arc(fx(b.x), fy(b.y), fs(2 + b.age * 20), 0, TAU); ctx.stroke(); ctx.globalAlpha = 1;
    }
    for (const p of dust) {
      ctx.globalAlpha = Math.max(0, p.life / p.max); ctx.fillStyle = p.color;
      const s = Math.ceil(fs(p.size)); ctx.fillRect(Math.round(fx(p.x)), Math.round(fy(p.y)), s, s);
    }
    ctx.globalAlpha = 1;
    blitSprite(ship.x, FIELD - 26, SPRITES.ship, 1.15, 0);
    drawHud();
  }

  function frame(now) {
    if (!running) return;
    if (resizePending) measure();
    const dt = Math.min(0.05, (now - last) / 1000 || 0);
    last = now;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    update(dt); draw();
    raf = requestAnimationFrame(frame);
  }

  function measure() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    // The stage canvas always fills the viewport (absolute inset:0 inside a fixed full-screen stage),
    // so read the viewport directly. getBoundingClientRect can return a half-laid-out size the instant
    // the canvas is unhidden (display.js flips `hidden` then calls start() the same tick).
    W = window.innerWidth || canvas.getBoundingClientRect().width || 1;
    H = window.innerHeight || canvas.getBoundingClientRect().height || 1;
    canvas.width = Math.max(1, Math.round(W * dpr)); canvas.height = Math.max(1, Math.round(H * dpr));
    const size = Math.min(W, H);
    box = { x: (W - size) / 2, y: (H - size) / 2, size };
    resizePending = false;
  }

  function seedStars() {
    stars = STAR_LAYERS.flatMap(([count, speed, size]) =>
      Array.from({ length: count }, () => ({ x: Math.random(), y: Math.random(), speed, size,
        color: STAR_COLORS[(Math.random() * STAR_COLORS.length) | 0], tw: Math.random() < 0.5, ph: rand(0, TAU) })));
  }

  function onResize() { resizePending = true; }

  function start(cv) {
    canvas = cv || document.getElementById('arcade');
    if (!canvas) return;
    ctx = canvas.getContext('2d');
    running = true;
    measure(); seedStars(); resetGame();
    last = performance.now();
    window.addEventListener('resize', onResize);
    raf = requestAnimationFrame(frame);
  }

  function stop() {
    running = false;
    if (raf) cancelAnimationFrame(raf);
    raf = null;
    window.removeEventListener('resize', onResize);
    if (ctx) { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, canvas.width, canvas.height); }
  }

  return { start, stop };
})();
