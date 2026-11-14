# Rot Riot - project notes for Claude

Original 2D top-down twin-stick zombie arena shooter. Godot 4 (developed on
4.7.2, also verified on 4.5.1), GDScript only, GL Compatibility renderer.
Target: PC (Windows + Mac) on Steam first, mobile later.

The owner is a beginner who does not write code: Claude writes everything,
the owner plays the result and gives feedback. Explain things in plain words.

## Rules (from the owner - always follow)

1. **Everything is original.** No names, characters, art or sounds from any
   existing game. The genre is the inspiration, nothing else. "Rot Riot" is a
   working title (no Steam game with that exact name was found in Nov 2026;
   re-check before release).
2. **Build in stages.** After each stage run the project headless from the
   command line and fix every error before moving on.
3. **One config file.** Every balance number (speeds, health, prices, wave
   sizes) and every feel value (shake, hit stop, knockback, recoil, slow
   motion) lives in `scripts/config.gd`. Never hard-code such a number
   elsewhere - add a constant to config.gd and read it.
4. **Input in one place.** The game never reads keyboard/mouse/gamepad
   directly. Everything goes through `scripts/autoload/game_input.gd`, so
   touch controls can be added later via `GameInput.set_virtual_input()`
   without touching gameplay code.
5. **Game feel is the top priority.** White hit flash, knockback, stagger, hit
   stop on kills, per-weapon screen shake, muzzle flash, shell casings,
   persistent blood and bodies, instant movement, mild aim assist. Each weapon
   must feel distinct (fire rate, spread, recoil, knockback, shake, sound).
6. **Performance:** 150+ enemies on screen at 60 fps (see Benchmark below).
7. **Git:** commit after each stage. Never commit `.godot/` or `build/`.
8. Placeholder art is made from simple shapes; sound effects are basic.

## Commands

Godot must be on PATH as `godot` (any 4.5+ build). Run from the project folder.

```bash
godot --headless --import                                  # first time / after adding files
godot --headless --fixed-fps 60 --quit-after 200           # boots to the menu, must print no errors
godot --headless -d --fixed-fps 60 -- --autotest           # full playthrough test, prints PASS/FAIL (-d also shows GDScript warnings)
godot --headless -d --fixed-fps 60 -- --inputtest          # fake keyboard/mouse/gamepad events through GameInput
godot --headless --fixed-fps 60 -- --bench=250             # hold 250 zombies, report simulation ms per frame
godot --headless --fixed-fps 60 -- --bot --frames=6000     # bot plays 100 s, prints a SUMMARY line
godot --headless --export-release "Windows Desktop" build/windows/RotRiot.exe
godot --headless --export-release "macOS" build/mac/RotRiot.zip
```

Other dev flags (all after `--`, see `scripts/dev/dev_tools.gd`): `--play`,
`--god`, `--wave=N`, `--weapon=ID`, `--dual`, `--keep-weapon`, `--no-crates`, `--no-rage`,
`--cycle`, `--level=N`, `--coins=N`, `--map=N` (with `--best=W` best wave cleared there and
`--start=W` starting wave), `--screen=maps|character|armory|gear|settings|pause|gameover|victory`,
`--armory-weapon=ID`, `--tree-node=ID --tree-zoom=N` (skill tree / gear screen: highlight a node, zoom;
0 = whole tree), `--gear=N` (start with N random pieces), `--drop-gear` (drop a piece of every tier in a run),
`--shot=PATH --shot-frame=N` (screenshot; needs a real display, e.g. `xvfb-run`),
`--dump-sfx=DIR` (writes every generated sound as .wav),
`--gallery=PREFIX[,PREFIX] --gallery-scale=N` (shows generated sprites enlarged, e.g.
`--gallery=icon_` or `--gallery=boss_0,player`; combine with `--shot` to review art).

Definition of done for any change: `--autotest` and `--inputtest` pass, and
the `-d` run prints zero `WARNING` / `SCRIPT ERROR` lines. Run the autotest a
few times: it plays a real fight, so a check that counts frames or relies on
what the bot happens to do will fail now and then. In test code, wait with
`_until(condition)` (hit stop can delay game updates by several frames) and
set up the state a check needs directly instead of hoping the bot creates it.

## File map

```
project.godot            settings + autoloads (Config, SaveData, GameInput, Art, Sfx)
export_presets.cfg       "Windows Desktop" (single .exe) and "macOS" (universal .zip)
scenes/main.tscn         one node with scripts/main.gd - everything else is built in code
scripts/config.gd        ALL balance + feel numbers, plus the wave/shop formulas
scripts/main.gd          app state machine: MENU / PLAYING / PAUSED / GAME_OVER, screen stack
scripts/autoload/
  game_input.gd          all input, key bindings, device detection, virtual sticks (touch/bot)
  save_data.gd           coins, character level + skill points + learned tree nodes, weapon levels + weapon
                         trees, gear (bag, worn, seen), map progress, bests, settings -> user://save.json
  art.gd                 placeholder sprites generated from SVG shapes at startup
  sfx.gd                 sounds synthesised at startup (worker thread) + pooled playback
scripts/game/
  game.gd                one run: owns the world, runs the simulation loop, hit stop, slow-mo, rage, score
  player.gd              movement, aim, firing (bullets / grenade / melee), drawing
  player_stats.gd        THE stat pipeline: level + skill tree + gear + keystones + weapon trees/perks
                         -> the numbers the game uses
  skill_tree.gd          builds the character's skill tree (257 nodes) from Config; describes nodes only
  weapon_tree.gd         builds each weapon's upgrade tree (63-93 nodes) from Config
  gear_tree.gd           layout of the Gear screen: 9 body slots + every piece x 5 tiers (177 nodes)
  enemy.gd               one zombie = data + Sprite2D (no logic)
  enemy_manager.gd       ALL zombie logic in one loop: spatial grid, separation, attacks, boss AI, damage, queries
  wave_director.gd       waves, packs, enemy mix, boss waves, map multipliers, end of the map
  projectiles.gd         bullets + grenades (plain data, swept hits, explosions)
  pickups.gd             coins, weapon crates, medkits, gear drops
  fx.gd                  particles, casings, corpses, muzzle flash, rings, floating text
  decals.gd              ground + permanent blood/bodies/casings (never-cleared SubViewport)
  arena.gd               bounds, obstacles, tree ring, collision helpers
  game_camera.gd         follow, aim lead, trauma shake, recoil kick
  hud.gd                 in-game overlay drawn in _draw
  draw_layer.gd          blank canvas whose _draw is forwarded to a manager
scripts/ui/              ui_kit.gd (theme + helpers), menu_background, main_menu, map_screen (Play),
                         tree_view (pannable/zoomable node web used by both trees),
                         character_screen (skill tree), armory_screen (weapon trees), gear_screen,
                         settings_screen, pause_menu, game_over_screen (also the victory screen)
scripts/dev/dev_tools.gd bot, autotest, input test, benchmark, screenshots (only with CLI args)
assets/sprites/, assets/sfx/   empty; drop-in overrides for generated art and sounds
Update Rot Riot.command  double-click updater for the owner's Mac (downloads main from GitHub,
                         replaces the project folder; the save file lives elsewhere)
```

## Design

**Loop:** main menu -> PLAY opens the map screen (choose map + starting wave)
-> run -> death or map cleared -> results (coins banked) -> spend points in
the skill tree (Character) and the weapon trees (Armory), wear and forge
gear (Gear) -> next run.
Quitting a run from pause also banks its coins.

**Maps** (`Config.MAPS`, five of them): every map has 100 waves
(`WAVES_PER_MAP`). Clearing wave 100 ends the run as a victory, pays a bonus
and unlocks the next map, where zombies have much more health and damage
(health x1 / 4 / 12 / 35 / 100) and XP and coins are worth more. Every boss
beaten (every 5th wave, `CHECKPOINT_EVERY`) unlocks the next starting wave
on that map, so a map is finished over several sessions; a checkpoint run
starts with a weapon crate beside the player. All five maps use the same
clearing for now, with a colour wash per map (`ground` / `trees`); the real
themed scenery is roadmap step 5. The owner calls maps "levels"; the UI
says MAP so it is not confused with the character LEVEL.

**Arena:** a 2400x1500 clearing ringed by trees, with 9 random rocks/stumps.
Zombies spawn outside the clearing under the tree canopy (never in view) and
walk in. Camera zoom 1.2, may look 110 px past the edge.

**Player:** instant movement (no acceleration), 100 HP, 0.55 s of safety after
a hit plus a shove that pushes the crowd back. Zombies body-block the player.

**Weapons** (`Config.WEAPONS`, nine of them). Crate weapons last about 20 s
then revert to the pistol. Crates drop on a timer (max 2 on the field), show
the weapon on the lid, and off-screen crates get an arrow on the HUD. Bosses
drop a crate.
- *Common:* pistol (starter, unlimited), SMG (very fast, weak, faster
  movement), shotgun (9 pellets, piercing, big recoil).
- *Uncommon:* machine gun (fast, wide spread, rattle), rifle (slow, 85 damage,
  goes through 6 zombies), sledgehammer (melee arc, huge knockback, hit stop
  per swing that connects).
- *Rare:* launcher (grenade, 135 px blast, biggest shake + hit stop),
  flamethrower (`kind: "flame"`: slowing, growing puffs that pass through
  everything and set zombies burning; burning zombies take damage over time,
  glow orange and leave charred bodies), chainsaw (melee held out in front,
  bites 13 times a second, extra blood).
- *Rarity* (`Config.CRATE_RARITIES`): weights common 1.0 / uncommon 0.5 / rare
  0.22, times the weapon's own spawn-rate upgrade. The crate's glow shows its
  tier. The launcher must stay rarer than the machine gun (owner's request).
- *Dual wielding:* picking up a crate of the weapon already held gives one in
  each hand if the weapon has `"dual": true` (pistol, SMG, shotgun, machine
  gun): about 1.8x fire rate, more spread and recoil. A pistol crate always
  gives dual pistols for 25 s. Crates that would dual show "x2".
- *Reloading:* every gun has a magazine (`mag`) and reloads when empty or on
  R / gamepad X (`GameInput.reload_pressed`). `reload_kind: "mag"` swaps the
  whole magazine and blocks firing; `"shell"` (shotgun) loads one round at a
  time and firing interrupts it. The launcher holds one round, so every shot
  is followed by a reload. Melee weapons have `mag: 0`. Reload speed scales
  with the dexterity passive, the weapon's own RELOAD SPEED track and rage;
  activating rage refills the magazine. The HUD shows "R = reload" beside the
  ammo count whenever the magazine is not full (the owner asked for a way to
  reload early when it is quiet). Each reload plays three shared
  clicks (`mag_out`, `mag_in`, `rack`; shotgun `shell_in`; flamethrower
  `hiss`) at the weapon's `reload_pitch`, tips the gun in the player's hands,
  and drops an empty magazine / box / clip / shell case / fuel can that stays
  on the ground like casings. HUD: ammo count in the weapon panel and under
  the crosshair (red when low), a ring around the crosshair while reloading.
- *Gun art:* each weapon has a detailed side-view picture (`icon_<id>`,
  220x80, in `art.gd`) used on the HUD and in the Armory, plus a small
  top-down sprite (`gun_<id>`) held by the player and shown on crates.
- Weapon strength is compared with
  `--bench=150 --no-crates --no-rage --weapon=ID [--dual]` (kills in 15 s).
  Last measured (with reloading): pistol 32, dual pistols 37, SMG 67,
  shotgun 93, rifle 106, machine gun 124, dual machine gun 199, launcher
  ~500, flamethrower ~620; sledgehammer ~350 and chainsaw ~380 do not
  reload. Melee and flame numbers are flattered by the test (the bot cannot
  die); real play punishes short range.

**Enemies** (`Config.ENEMIES`): Shambler (basic), Runner (fast, zig-zags),
Brute (tank, resists knockback and stagger), boss "The Gorger" every 5th wave
(charge with a telegraphed wind-up, dazed afterwards; summons shamblers out of
the ground; +60% HP each time it returns).
*Wounded look:* below 30% health (`WOUNDED_AT`) a zombie switches to its
`<sprite>_hurt` texture (gashes, bare ribs, a lost eye), limps, walks a
little slower and leaves a trail of blood drops; its corpse keeps the wounds.
The player gets a bloodied, bandaged sprite and drips blood below 30% too.
Every new enemy or character needs a `_hurt` variant.

**Waves** (`Config.wave_*` helpers), same curve on every map and stretched
over 100 waves: count = 22 + 9(w-1), capped at 500 per wave and 240 alive.
Zombies arrive in packs from the tree line so they form hordes; pack size and
rate grow with the wave, and every 5 waves the packs come from one more
direction at once (up to 4) so hordes surround the player; per wave +6% HP,
+1% damage, +0.5% speed, +1% XP per kill, all multiplied by the map. Boss HP
= 1700 x wave growth x map x (+25% per earlier boss). Clearing a wave pays
a coin and XP bonus. The slope is deliberately gentle so that every bit of
character growth buys another wave or two (owner: "incremental feel"). The
bot reaches wave 6-9 as a new character and ~11 at level 15-30.

**Score / combo:** each kill within 2.5 s of the last raises the combo, which
multiplies score (up to x3). Taking damage resets it.

**Rage:** fills from kills (not while active). Activate with Space / RMB / LB /
LT / X: a blast throws the horde back, then for 8 s damage x3, fire rate
x1.5, speed x1.25, damage taken x0.2. `RAGE_AUTO_ACTIVATE` exists in config.

**Progression** (all permanent; numbers in the PROGRESSION section of
config.gd; stored by `save_data.gd`; turned into game numbers only in
`player_stats.gd`):
- *Character level*: XP from kills and cleared waves (shown as the bar along
  the bottom of the HUD). Each level: +3 max health, +1% damage, +1 skill
  point. Levelling mid-run applies at once and heals 25%. **Hard cap: level
  100** (`LEVEL_CAP`), which the owner wants to take months: XP needed per
  level = 80 * level^2, about 26 million XP in total (a new character earns
  roughly 2-4 thousand XP per run; later waves and later maps pay several
  times that - which is why the exponent went from 1.8 to 2.0 when maps
  were added). Re-check this pacing whenever XP sources change.
- *Skill tree* (Character screen; built by `skill_tree.gd` from the SKILL
  TREE section of config.gd): a web of 257 nodes around the survivor. Eight
  branches, one per passive stat (vitality, strength, dexterity = fire rate,
  agility = move speed, defense, evasion, critical, luck = coin drops). Per
  branch: four rings of small nodes (+1 rank) ending in a big node (+3), a
  side twig per ring ending in a **sealed** node (opens after a deed such as
  "clear wave 12" or "kill 3000 zombies", `TREE_SEAL_DEEDS`), arcs of nodes
  that link neighbouring branches, and at the tip a **keystone** (a special
  power, `Config.KEYSTONES`: second wind, executioner, adrenaline, breakaway,
  thick skin, ghost, deadeye, scavenger) and an **endless** node (repeatable,
  rising price - this keeps progression endless). A node can be learned when
  it touches a learned node, the character level is high enough for its ring
  (1 / 5 / 12 / 22) and its deed is done. Rings cost 1 / 2 / 3 / 4 points per
  small node. "linear" stats grow forever; "curve" stats approach a maximum.
  More skill points can be bought with coins (price x1.15 each time); a paid
  reset returns all spent points. Stat ranks = the sum of learned nodes
  (`SaveData.passive_rank`), plus `SaveData.bonus_ranks` (hook for gear).
- *Weapon levels and weapon trees* (Armory; built by `weapon_tree.gd` from
  the WEAPON TREES section): each weapon earns XP from kills made with it
  (kills carry a `source` weapon id through `EnemyManager.damage`). Each
  weapon level gives a point for that weapon only, spent in that weapon's
  own tree: one branch per upgrade track (power, shooting speed, stability =
  spread + recoil, reload speed, spawn rate = crate share, duration), three
  tiers per branch that need weapon level 1 / 6 / 14, arcs between the
  branches, an endless node at each tip (weapon level 20) and **three perks
  per weapon** (`Config.WEAPON_PERKS`) that change the weapon's own numbers
  (bigger magazine, piercing, more pellets, wider swing, bigger blast...).
  Perks are applied by `PlayerStats.weapon_def(id)`, which the player uses
  instead of `Config.WEAPONS[id]`. Which tracks a weapon has is decided by
  `"needs"` in `Config.WEAPON_TRACKS` (`Config.weapon_tracks(id)`): the
  pistol has no crate tracks, melee weapons have no stability or reload, the
  launcher has no shooting speed (its rate of fire is its reload). A weapon's
  tree can be reset for coins.
- *Gear* (Gear screen; everything in the GEAR section of config.gd): nine
  slots (helmet, amulet, chest, gloves, two rings, belt, pants, boots) and
  32 pieces, four per kind. A piece gives ranks of one or two passive stats
  (`SaveData.gear_rank`, added to `passive_rank` on top of the skill tree).
  **Drops** are deliberately rare (owner: "should not be overload"): about
  0.4% per shambler, 4% per brute, times the map's `gear` multiplier and half
  of the LUCK bonus; the bot finds 0-4 pieces per run as a new character.
  **Rings and amulets drop only from bosses** (a boss always drops one), some
  pieces only from brutes, and one piece per kind only from map 2 onwards.
  Later maps also sometimes drop a piece one tier up (`gear_up`). A drop is a
  pillar of light in the tier's colour with a HUD arrow; picking it up puts it
  straight in the bag (kept even if you die).
  **Five tiers** (colours): COMMON, STURDY, FINE, SUPERIOR, LEGENDARY, with
  stat multipliers 1 / 2 / 3 / 5 / 8. **Forging**: two identical pieces of the
  same tier make one of the next tier with the owner's odds - 100% / 90% /
  40% / 10%. A failed attempt always uses up one of the two; for SUPERIOR
  and LEGENDARY there is also a 35% / 50% chance (`break`) that the other is
  destroyed too. A piece is stored as "item:tier" (`Config.gear_key`) with a
  count; worn pieces are not counted in the bag. Never rename item ids.
  The **Gear screen** follows the owner's wish for an "intimidating tree":
  the nine slots are laid out like a body in the middle (the paper doll) and
  around it every piece has a row of five tier nodes (177 nodes). Owned =
  lit, never found = padlock, glowing = two of the tier below are in the bag
  and can be forged. Click a piece to wear it, a worn slot to take it off, a
  glowing node to forge (anything that can fail asks twice).
- All three screens are shown by `scripts/ui/tree_view.gd` (drag / scroll / pinch,
  arrow keys or stick to walk the nodes, Enter / A to learn, gamepad Y or Tab
  to reach the buttons beside it). Tree node ids are stored in the save:
  never rename them. If a saved tree no longer fits the layout (unknown or
  disconnected nodes) all its points are handed back on load, as were the
  points spent in the old flat stat list and old weapon ranks.
- Weapon levels have no cap (only the character level is capped).
- Save format version 2 (new fields are simply added with defaults). Version 1
  saves keep records and settings but coins and the old upgrades are wiped
  once (agreed with the owner).

**Settings:** master volume, SFX volume, screen shake strength, fullscreen
(also F11). The game auto-pauses when the window loses focus.

## How the important systems work

- **No physics engine.** Player, zombies, bullets are circles and segments
  handled with plain maths. `enemy_manager.gd` sorts zombies into a 64 px grid
  each frame (linked lists in PackedInt32Arrays); each zombie only checks the
  3x3 cells around it. Dead zombies are flagged and compacted at the start of
  the next tick, so grid indices stay valid for bullet/explosion queries all
  frame. Bosses are too big for the grid and live in `bigs`, checked directly.
- **Crowding:** zombies touching more than `ENEMY_CROWD_FREE` neighbours slow
  down, so hordes surround the player instead of stacking into a blob.
- **One simulation loop.** `Game._process` computes `dt` once and ticks
  player -> director -> enemies -> projectiles -> pickups -> fx. Hit stop sets
  `dt = 0` for a few hundredths of a second (rate-limited by
  `HITSTOP_MIN_INTERVAL`, `force` bypasses it); slow motion scales `dt`.
  Camera and HUD always use real time.
- **Persistent gore is free.** `decals.gd` paints the ground once into a
  SubViewport that is never cleared, then stamps blood, bodies and casings
  onto it (viewport set to UPDATE_ONCE for the frames that have stamps).
  Tens of thousands of decals cost the same as none.
- **Rendering cost.** Zombies are Sprite2Ds sharing a few textures (batched by
  the renderer); everything else high-count is drawn as textured rects/lines
  from a handful of nodes. Avoid `draw_circle` / polygons for anything
  numerous - they are not batched.
- **Art:** `art.gd` rasterises small SVG strings at 2x. A PNG with the same
  name in `assets/sprites/` replaces a sprite (hit-flash versions are derived
  automatically). **Sound:** `sfx.gd` recipes; a file with the same name in
  `assets/sfx/` (.wav/.ogg/.mp3) replaces a sound.
- **Menus** are Controls built in code, themed by `UiKit.make_theme()`.
  `Main` keeps a stack of screen names; every screen may define `opened()`
  and `closed()`. Buttons grab focus on hover so mouse and gamepad share one
  highlight. Godot's built-in `ui_accept`/`ui_cancel` have no gamepad
  buttons, so `game_input.gd` adds A and B.

## Benchmark (headless, simulation only, this dev machine)

| zombies | avg ms | p95 ms |
|--------:|-------:|-------:|
| 150     | 1.1    | 1.7    |
| 250     | 2.4    | 3.7    |
| 400     | 4.7    | 7.3    |

60 fps allows 16.6 ms per frame. With a real renderer 250 zombies plus
effects were ~280 draw calls. Not yet measured on the owner's hardware.

## Not verified yet (needs a human)

- How it actually feels to play - all feel values are first guesses.
- The balance of the 100-wave maps, the tree prices, the keystones, the
  perks, gear drop rates and gear stats: all first guesses, only checked with
  the bot and the tests.
- The tree screens with a real mouse / trackpad / gamepad (only simulated
  input was tested).
- How the synthesised sounds sound; Claude can only check them numerically
  (length, loudness, brightness, how tonal they are), never listen. Owner
  feedback on v1: guns "sounded like lasers" (cause: fast high-to-low pitch
  sweeps). v2 guns are noise crack + body + low thump + echo tail with no
  sweeps above ~200 Hz, and the owner says they sound much better. Never add
  gliding tones above ~200 Hz to a gun sound. v3 (owner: "each weapon sound
  should be different and satisfying") gives every gun its own pitch range
  with `Synth.band` (noise ringing around a fixed pitch): SMG ~3 kHz, pistol
  ~1.5 kHz, rifle ~1 kHz with the longest echo, machine gun ~700 Hz with a
  bolt clank, shotgun ~330 Hz, launcher ~260 Hz. Measured, not heard. The
  owner may buy sound assets later: drop them in `assets/sfx/`. The gear
  sounds (drop "ting", pickup, forge success / fail / break) are unheard too.
- A physical gamepad (only simulated gamepad events were tested).
- The exported Windows .exe and macOS .app on real Windows / macOS machines
  (exports succeed and the exported game data passes the autotest on Linux).

## Owner feedback so far (after the first playtest, Nov 2026)

- Loved: the gore, corpses/blood/casings staying on the ground, the shooting.
- Rage shook the screen too much -> `RAGE_SHAKE_MULT` (done).
- Guns sounded like lasers -> rebuilt. Owner: "the guns sound much better".
- Far too easy (reached wave 15 on the first run and had to die on purpose)
  and upgrades far too cheap -> difficulty/economy pass: bigger and faster
  waves from several sides, tougher zombies. The owner then reported "it is
  harder, I reach about 5-6", which is about right for a new character.
- Wants a hard character level cap of 100 that takes months (done).
- Wants every gun to "look and feel amazing": reload animation and sound per
  gun, detailed gun art (done, awaiting feedback); keep raising this bar.
- Wants enemies and characters to look damaged under 30% health, with the
  player still looking tough (done, awaiting feedback).
- "I always die around level 5" (= wave 5, the first boss) and "each level
  should have 100 waves to complete and unlock the next level, much more
  difficult to complete and farm" -> maps with 100 waves, checkpoints, a
  gentler wave slope (done, awaiting feedback).
- "The upgrade screens need to look like an intimidating tree with lots of
  upgrades and upgrades that need to be unlocked" -> skill tree and weapon
  trees (done, awaiting feedback). The gear screen (roadmap 3) must follow
  the same style.
- "Each weapon sound should be different and satisfying" -> v3 gun sounds
  (done, awaiting feedback).
- Gear (the owner's design: slots like an action-RPG character sheet, rare
  drops, boss-only pieces, merging two identical pieces of the same colour,
  five tiers with 100/90/40/10% odds and a chance to destroy at tiers 4-5)
  -> built (awaiting feedback).
- The owner's Mac: browser downloads do not work there, so updates go through
  Terminal (curl) or the double-click updater. Always give the full update
  command and say plainly that Return must be pressed.

## Roadmap (owner's requests, in the agreed build order)

Build one stage at a time; the owner plays each before the next starts.

1. **Progression core. DONE (awaiting the owner's playtest).** See
   "Progression" above. Owner's decisions: coins are permanent; weapon
   upgrades are permanent and earned by using the weapon.
2. **Weapons. DONE (awaiting the owner's playtest).** Four new weapons (SMG,
   rifle, flamethrower, chainsaw), three crate rarity tiers, dual wielding.
   See "Weapons" above. More weapons can be added the same way later.
2b. **100-wave maps, skill tree, weapon trees. DONE (awaiting the owner's
   playtest).** See "Maps" and "Progression" above.
3. **Gear. DONE (awaiting the owner's playtest).** See "Gear" under
   Progression. Still open from the owner's wishes: treasure chests that give
   gear (comes with the big map, step 4). Ideas if the owner wants more:
   more pieces per kind, set bonuses, a way to sell or break down spare gear.
4. **Big-map engine.** Much bigger maps (a large "farming map"), fog of war
   that clears as the player explores, a minimap, treasure chests to find
   each round that give gear. Waves stay: zombies hunt the player wherever
   they are; exploring for chests happens during and between waves. Needs: spawning around the player instead of
   at the map edge, and the decal layer split into chunks (one never-cleared
   viewport cannot cover a huge map).
5. **Five themed maps**, each telling a story through its scenery: forest
   campsite, abandoned farm, graveyard, crashed-convoy highway, quarantine
   lab. (Map select, unlock order and difficulty already exist; this step
   is the scenery.)
6. **Many more enemy types** (ongoing).

Design rule from the owner: progression must feel incremental and endless.

## Later / ideas

- Mobile: on-screen sticks calling `GameInput.set_virtual_input()`; lower
  `DECAL_RESOLUTION`; pack zombie sprites into one atlas to cut draw calls.
- Steam: Steamworks (GodotSteam), achievements, cloud save, custom user data
  folder, real icon, macOS signing + notarisation, store assets.
- Content: more enemy types and bosses, arenas, weapon variety, music, real
  art and sound, damage numbers, daily challenge, leaderboards.
