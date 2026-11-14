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
`--god`, `--wave=N`, `--weapon=ID`, `--cycle`, `--screen=shop|settings|pause|gameover`,
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
  save_data.gd           coins, upgrades, best scores, settings -> user://save.json
  art.gd                 placeholder sprites generated from SVG shapes at startup
  sfx.gd                 sounds synthesised at startup (worker thread) + pooled playback
scripts/game/
  game.gd                one run: owns the world, runs the simulation loop, hit stop, slow-mo, rage, score
  player.gd              movement, aim, firing (bullets / grenade / melee), drawing
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
scripts/ui/              ui_kit.gd (theme + helpers), menu_background, main_menu, shop_screen,
                         settings_screen, pause_menu, game_over_screen
scripts/dev/dev_tools.gd bot, autotest, input test, benchmark, screenshots (only with CLI args)
assets/sprites/, assets/sfx/   empty; drop-in overrides for generated art and sounds
```

## Design

**Loop:** main menu -> run -> death -> game over (coins banked) -> upgrade
shop -> next run. Quitting a run from pause also banks its coins.

**Arena:** a 2400x1500 clearing ringed by trees, with 9 random rocks/stumps.
Zombies spawn outside the clearing under the tree canopy (never in view) and
walk in. Camera zoom 1.2, may look 110 px past the edge.

**Player:** instant movement (no acceleration), 100 HP, 0.55 s of safety after
a hit plus a shove that pushes the crowd back. Zombies body-block the player.

**Weapons** (`Config.WEAPONS`): pistol (starter, unlimited), shotgun (9
pellets, piercing, big recoil), machine gun (fast, wide spread, rattle),
launcher (grenade, 135 px blast, biggest shake + hit stop), sledgehammer
(melee arc, huge knockback, hit stop per swing that connects, faster
movement). Crate weapons last 18-20 s then revert to the pistol. Crates drop
on a timer (max 2 on the field) and show the weapon on the lid; off-screen
crates get an arrow on the HUD. Bosses drop a crate.

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

**Shop:** damage, fire rate, move speed, max health; 5 levels each; prices
and effects in `Config.UPGRADES`; saved immediately.

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
  and upgrades far too cheap -> first difficulty/economy pass done: bigger
  and faster waves from several sides, tougher zombies, upgrade prices x3.
  The test bot now dies on waves 5-7. Expect more tuning.

## Roadmap (owner's requests, in the agreed build order)

Build one stage at a time; the owner plays each before the next starts.

1. **Progression core.** New save format. Character level (XP from kills)
   that raises base stats. One stat pipeline everything feeds into: max
   health, strength (damage), move speed, defense, evasion, fire rate, ...
   Coin upgrades become incremental with no real ceiling ("you can always get
   stronger"), with a much slower economy. Per-weapon upgrade tracks: power,
   spawn rate (how often its crate appears), stability (spread/recoil),
   shooting speed, duration.
2. **Weapons.** More weapons. Crate rarity tiers (the launcher must be rarer
   than the machine gun). Dual wielding two of the same gun.
3. **Gear.** Character screen in the style of an action-RPG paper doll:
   helmet, chest, gloves, boots, pants, belt, two rings, amulet. Items drop
   rarely from zombies (never a flood); some pieces only from bosses. Merge
   two identical items of the same colour to get the next tier. Five tiers
   (five colours). Attempts for tier 4 and tier 5 can destroy the item;
   tier 5 succeeds 10% of the time.
4. **Big-map engine.** Much bigger maps (a large "farming map"), fog of war
   that clears as the player explores, a minimap, treasure chests to find
   each round that give gear. Needs: spawning around the player instead of
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
