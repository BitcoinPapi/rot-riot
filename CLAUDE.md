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
`--cycle`, `--level=N`, `--coins=N`, `--screen=character|armory|settings|pause|gameover`,
`--shot=PATH --shot-frame=N` (screenshot; needs a real display, e.g. `xvfb-run`),
`--dump-sfx=DIR` (writes every generated sound as .wav).

Definition of done for any change: `--autotest` and `--inputtest` pass, and
the `-d` run prints zero `WARNING` / `SCRIPT ERROR` lines.

## File map

```
project.godot            settings + autoloads (Config, SaveData, GameInput, Art, Sfx)
export_presets.cfg       "Windows Desktop" (single .exe) and "macOS" (universal .zip)
scenes/main.tscn         one node with scripts/main.gd - everything else is built in code
scripts/config.gd        ALL balance + feel numbers, plus the wave/shop formulas
scripts/main.gd          app state machine: MENU / PLAYING / PAUSED / GAME_OVER, screen stack
scripts/autoload/
  game_input.gd          all input, key bindings, device detection, virtual sticks (touch/bot)
  save_data.gd           coins, character level + skill points, weapon levels, bests, settings -> user://save.json
  art.gd                 placeholder sprites generated from SVG shapes at startup
  sfx.gd                 sounds synthesised at startup (worker thread) + pooled playback
scripts/game/
  game.gd                one run: owns the world, runs the simulation loop, hit stop, slow-mo, rage, score
  player.gd              movement, aim, firing (bullets / grenade / melee), drawing
  player_stats.gd        THE stat pipeline: level + passives (+ gear later) -> the numbers the game uses
  enemy.gd               one zombie = data + Sprite2D (no logic)
  enemy_manager.gd       ALL zombie logic in one loop: spatial grid, separation, attacks, boss AI, damage, queries
  wave_director.gd       waves, packs, enemy mix, boss waves
  projectiles.gd         bullets + grenades (plain data, swept hits, explosions)
  pickups.gd             coins, weapon crates, medkits
  fx.gd                  particles, casings, corpses, muzzle flash, rings, floating text
  decals.gd              ground + permanent blood/bodies/casings (never-cleared SubViewport)
  arena.gd               bounds, obstacles, tree ring, collision helpers
  game_camera.gd         follow, aim lead, trauma shake, recoil kick
  hud.gd                 in-game overlay drawn in _draw
  draw_layer.gd          blank canvas whose _draw is forwarded to a manager
scripts/ui/              ui_kit.gd (theme + helpers), menu_background, main_menu, character_screen,
                         armory_screen, settings_screen, pause_menu, game_over_screen
scripts/dev/dev_tools.gd bot, autotest, input test, benchmark, screenshots (only with CLI args)
assets/sprites/, assets/sfx/   empty; drop-in overrides for generated art and sounds
```

## Design

**Loop:** main menu -> run -> death -> game over (coins banked) -> spend
points on the Character and Armory screens -> next run. Quitting a run from
pause also banks its coins.

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
- Weapon strength is compared with
  `--bench=150 --no-crates --no-rage --weapon=ID [--dual]` (kills in 15 s).
  Last measured: pistol 35, SMG 69, shotgun 100, rifle 121, machine gun 136,
  dual machine gun 264, chainsaw ~380, sledgehammer ~350, launcher ~510,
  flamethrower ~600. Melee and flame numbers are flattered by the test (the
  bot cannot die); real play punishes short range.

**Enemies** (`Config.ENEMIES`): Shambler (basic), Runner (fast, zig-zags),
Brute (tank, resists knockback and stagger), boss "The Gorger" every 5th wave
(charge with a telegraphed wind-up, dazed afterwards; summons shamblers out of
the ground; +60% HP each time it returns).

**Waves** (`Config.wave_*` helpers): count = 22 + 13(w-1) + 1.5(w-1)^2, capped
at 500 per wave and 240 alive. Zombies arrive in packs from the tree line so
they form hordes; pack size and rate grow with the wave, and every 3 waves the
packs come from one more direction at once (up to 4) so hordes surround the
player; +8% HP and +2% speed per wave. Clearing a wave pays a coin bonus.

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
  level = 80 * level^1.8, about 11.2 million XP in total (a new character
  earns roughly 1,500 XP in a 4-minute run; stronger characters earn several
  times that). Re-check this pacing whenever XP sources change.
- *Skill points* go into 8 passive stats on the Character screen: vitality,
  strength, dexterity (fire rate), agility (move speed), defense (less damage
  taken), evasion (dodge chance), critical (double-damage shots), luck (coin
  drops). "linear" stats grow forever; "curve" stats approach a maximum. Every
  10 ranks of a stat the next ranks cost one more point. More skill points
  can be bought with coins (price x1.15 each time); a paid reset returns all
  spent points.
- *Weapon levels*: each weapon earns XP from kills made with it (kills carry a
  `source` weapon id through `EnemyManager.damage`). Each weapon level gives a
  point for that weapon only, spent in the Armory on power, shooting speed,
  stability (spread + recoil), spawn rate (crate share) and duration. The
  pistol has no crate-only tracks.
- Weapon levels have no cap (only the character level is capped).
- Save format version 2. Version 1 saves keep records and settings but coins
  and the old upgrades are wiped once (agreed with the owner).

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
- How the synthesised sounds sound; Claude can only check them numerically
  (length, loudness, brightness, how tonal they are), never listen. Owner
  feedback on v1: guns "sounded like lasers" (cause: fast high-to-low pitch
  sweeps). v2 guns are noise crack + body + low thump + echo tail with no
  sweeps above ~200 Hz; not yet heard by the owner. Never add gliding tones
  above ~200 Hz to a gun sound.
- A physical gamepad (only simulated gamepad events were tested).
- The exported Windows .exe and macOS .app on real Windows / macOS machines
  (exports succeed and the exported game data passes the autotest on Linux).

## Owner feedback so far (after the first playtest, Nov 2026)

- Loved: the gore, corpses/blood/casings staying on the ground, the shooting.
- Rage shook the screen too much -> `RAGE_SHAKE_MULT` (done).
- Guns sounded like lasers -> rebuilt (done, awaiting feedback).
- Far too easy (reached wave 15 on the first run and had to die on purpose)
  and upgrades far too cheap -> difficulty/economy pass: bigger and faster
  waves from several sides, tougher zombies. The owner then reported "it is
  harder, I reach about 5-6", which is about right for a new character.
- Wants a hard character level cap of 100 that takes months (done).

## Roadmap (owner's requests, in the agreed build order)

Build one stage at a time; the owner plays each before the next starts.

1. **Progression core. DONE (awaiting the owner's playtest).** See
   "Progression" above. Owner's decisions: coins are permanent; weapon
   upgrades are permanent and earned by using the weapon.
2. **Weapons. DONE (awaiting the owner's playtest).** Four new weapons (SMG,
   rifle, flamethrower, chainsaw), three crate rarity tiers, dual wielding.
   See "Weapons" above. More weapons can be added the same way later.
3. **Gear.** Character screen in the style of an action-RPG paper doll:
   helmet, chest, gloves, boots, pants, belt, two rings, amulet. Items drop
   rarely from zombies (never a flood); some pieces only from bosses. Merge
   two identical items of the same colour to get the next tier. Five tiers
   (five colours). Success chance set by the owner: tier 2 100%, tier 3 90%,
   tier 4 40%, tier 5 10%. A failed tier 4 or 5 attempt always uses up one of
   the two items and has a chance to destroy the other as well. Gear bonuses
   plug into `player_stats.gd`.
4. **Big-map engine.** Much bigger maps (a large "farming map"), fog of war
   that clears as the player explores, a minimap, treasure chests to find
   each round that give gear. Waves stay: zombies hunt the player wherever
   they are; exploring for chests happens during and between waves. Needs: spawning around the player instead of
   at the map edge, and the decal layer split into chunks (one never-cleared
   viewport cannot cover a huge map).
5. **Five themed maps**, each telling a story through its scenery: forest
   campsite, abandoned farm, graveyard, crashed-convoy highway, quarantine
   lab. Map select + unlock order.
6. **Many more enemy types** (ongoing).

Design rule from the owner: progression must feel incremental and endless.

## Later / ideas

- Mobile: on-screen sticks calling `GameInput.set_virtual_input()`; lower
  `DECAL_RESOLUTION`; pack zombie sprites into one atlas to cut draw calls.
- Steam: Steamworks (GodotSteam), achievements, cloud save, custom user data
  folder, real icon, macOS signing + notarisation, store assets.
- Content: more enemy types and bosses, arenas, weapon variety, music, real
  art and sound, damage numbers, daily challenge, leaderboards.
