# Rot Riot - project notes for Claude

Original 2D top-down twin-stick zombie arena shooter. Godot 4 (developed on
4.7.2, also verified on 4.5.1), GDScript only, GL Compatibility renderer.
Target: PC (Windows + Mac) on Steam first, mobile later.

The owner is a beginner who does not write code: Claude writes everything,
the owner plays the result and gives feedback. Explain things in plain words.

The hero is called **Cliff** (`Config.HERO_NAME`). The owner sends reference
pictures from other games and artists for the LAYOUT or the GENERAL LOOK he
wants (an upgrade page, an equipment screen with the character
in the middle, a tactical-looking hero). Follow the structure and the mood;
never copy the art, names, icons or exact look (rule 1).

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
tools/cooptest.sh 3                                        # co-op test: 3 copies of the game play together (2 = two copies)
tools/nattest.sh 3                                         # the same through PRETEND HOME ROUTERS (Linux, root; see "Getting through routers")
godot --headless --export-release "Windows Desktop" build/windows/RotRiot.exe
godot --headless --export-release "macOS" build/mac/RotRiot.zip
```

Other dev flags (all after `--`, see `scripts/dev/dev_tools.gd`): `--play`,
`--god`, `--wave=N`, `--weapon=ID`, `--dual`, `--keep-weapon`, `--no-crates`,
`--cycle`, `--level=N`, `--coins=N`, `--map=N` (with `--best=W` best wave cleared there and
`--start=W` starting wave), `--screen=maps|character|skills|armory|pets|settings|pause|gameover|victory`,
`--forge` (with `--screen=character`: open the forge), `--armory-weapon=ID`,
`--gear=N` (start with N random pieces, some worn), `--drop-gear` (drop a piece of every tier in a run),
`--drop-crates` (drop four weapon crates, two of them damaged), `--pets=N` (own the first N pets;
needs `--level=18` or more),
`--at=X,Y` (start the run at that spot of the map; the middle is 3000,2000), `--no-fog` (whole map
uncovered), `--show-chests` (a closed chest beside the player and an opened one),
`--horde=KIND:N,KIND:N` (put zombies around the player: shambler, runner, brute, boss, gobber,
chucker, gasbag, lunger - e.g. `--horde=gobber:3,gasbag:2`),
`--coop=host [--players=N]` / `--coop=join[:ADDRESS]` (co-op between copies on this computer: run
them WITHOUT `--fixed-fps`, end them with `--seconds=N`, name them with `--name=X`; `join:` takes
a game code or an address; `--stun=IP:PORT,IP:PORT` makes the copies find each other the internet
way through those address finders; `--letin-file=PATH` = reply codes the host "types in", one per
line), `--cooptest`, `--screen=coop --coop-view=host|full|reply` (the co-op screen in a pretend state),
`--shot=PATH --shot-frame=N` (screenshot; needs a real display, e.g. `xvfb-run`),
`--dump-sfx=DIR` (writes every generated sound as .wav),
`--gallery=PREFIX[,PREFIX] --gallery-scale=N` (shows generated sprites enlarged, e.g.
`--gallery=icon_` or `--gallery=boss_0,player`; combine with `--shot` to review art).

Definition of done for any change: `--autotest` and `--inputtest` pass,
`tools/cooptest.sh 2` and `tools/cooptest.sh 3` pass (anything that touches
the run, zombies, pickups or the HUD can break co-op; after touching
`net.gd` or `stun.gd` also `tools/nattest.sh 3`, `2 noletin`, `2 open` and
`2 strict`), and
the `-d` run prints zero `WARNING` / `SCRIPT ERROR` lines. **Drawing code
does not run headless**: after touching anything that draws (a screen, the
HUD, a sprite name) also open it once with a real renderer
(`xvfb-run -a godot --rendering-driver opengl3 ... -- --screen=NAME --shot=...`)
and check for `SCRIPT ERROR` - a missing sprite name only shows up there. Run the autotest a
few times: it plays a real fight, so a check that counts frames or relies on
what the bot happens to do will fail now and then. In test code, wait with
`_until(condition)` (hit stop can delay game updates by several frames) and
set up the state a check needs directly instead of hoping the bot creates it.

## File map

```
project.godot            settings + autoloads (Config, SaveData, GameInput, Art, Sfx, Net)
export_presets.cfg       "Windows Desktop" (single .exe) and "macOS" (universal .zip)
scenes/main.tscn         one node with scripts/main.gd - everything else is built in code
scripts/config.gd        ALL balance + feel numbers, plus the wave/shop formulas
scripts/main.gd          app state machine: MENU / PLAYING / PAUSED / GAME_OVER, screen stack
scripts/autoload/
  game_input.gd          all input, key bindings, device detection, virtual sticks (touch/bot)
  save_data.gd           coins, character level + skill points + learned tree nodes, weapon levels + weapon
                         trees, gear (bag, worn, seen), pets, map progress, bests, settings -> user://save.json
  art.gd                 placeholder sprites generated from SVG shapes at startup; the hero's
                         pictures (front view + top-down) are rebuilt from the gear he wears
  sfx.gd                 sounds synthesised at startup (worker thread) + pooled playback
  net.gd                 online co-op: hosting, joining (game codes, reply codes, getting through home
                         routers), who is in the game (slots), delivering messages
scripts/net/stun.gd      asks a public "address finder" how this computer looks from the internet
scripts/game/
  game.gd                one run: owns the world, runs the simulation loop, hit stop, slow-mo, score
  player.gd              movement, aim, firing (bullets / grenade / melee), drawing
  player_stats.gd        THE stat pipeline: level + bought skill ranks + gear + pet + special powers + weapon upgrades/perks
                         -> the numbers the game uses
  pet.gd                 the companion in a run: heel, bite, fetch, guard (numbers arrive via PlayerStats)
  enemy.gd               one zombie = data + Sprite2D (no logic)
  enemy_manager.gd       ALL zombie logic in one loop: spatial grid, separation, attacks, boss AI, the
                         zombies with an attack of their own (_tick_special), Gasbag bursts, damage, queries
  enemy_shots.gd         what zombies spit and throw: spit globs and lobbed rubble (data + one draw node)
  wave_director.gd       waves, packs (rising in a ring around the screen), enemy mix, boss waves,
                         map multipliers, end of the map
  projectiles.gd         bullets + grenades (plain data, swept hits, explosions)
  pickups.gd             coins, weapon crates (breakable), medkits, gear drops, treasure chests
  fx.gd                  particles, casings, corpses, muzzle flash, rings, floating text
  decals.gd              ground + permanent blood/bodies/casings (never-cleared SubViewports, one per
                         "chunk" of the map, made when first needed)
  arena.gd               the big map: bounds, obstacles (in lookup buckets), tree ring, collision
                         helpers, "a free spot near the player", "a spawn spot out of sight"
  fog.gd                 fog of war: which squares of the map have been seen this run, the misty
                         overlay (a small shader), the picture the minimap draws
  coop.gd                the co-op part of a run: what the computers tell each other (events,
                         player states, zombie snapshots), picking up fallen players, the shared ending
  mate.gd                another player as shown on this computer (a figure that glides to where they are)
  game_camera.gd         follow, aim lead, trauma shake, recoil kick
  hud.gd                 in-game overlay drawn in _draw (bars, weapon panel, minimap, arrows)
  draw_layer.gd          blank canvas whose _draw is forwarded to a manager
scripts/ui/              ui_kit.gd (theme + helpers), menu_background, main_menu, map_screen (Play),
                         coop_screen (PLAY WITH FRIENDS: host a game / join with a code),
                         character_screen (the hero, his gear, inventory and forge),
                         skill_screen (the plain list of stat upgrades),
                         armory_screen (plain weapon upgrade pages), pet_screen,
                         settings_screen, pause_menu, game_over_screen (also the victory screen)
scripts/dev/dev_tools.gd bot, autotest, input test, benchmark, screenshots (only with CLI args)
assets/sprites/, assets/sfx/   empty; drop-in overrides for generated art and sounds
tools/cooptest.sh        runs the co-op test with 2 or 3 copies of the game on one computer
tools/nattest.sh         the co-op test over a pretend internet: every copy in its own "home" behind
                         its own router (network namespaces + iptables; nattest_stun.py = its address finders)
Update Rot Riot.command  double-click updater for the owner's Mac (downloads main from GitHub,
                         replaces the project folder; the save file lives elsewhere)
```

## Design

**Loop:** main menu -> PLAY opens the map screen (choose map + starting wave)
-> run -> death or map cleared -> results (coins banked) -> spend points in
the Skills page and on weapon upgrades (Armory), wear and forge gear
(Character), choose a pet (Pets) -> next run. The main menu is PLAY on top,
then two columns: CHARACTER, SKILLS, ARMORY, PETS, SETTINGS, QUIT, with
Cliff standing beside them in whatever he is wearing.
Quitting a run from pause also banks its coins.

**Co-op** (owner: "a multiplayer option so I can play with T. All gold will
be shared, enemies will be stronger"; then "up to 3 players"). Online, each
player on their own computer (the owner did not answer whether same-screen
was wanted; T has their own copy, so online was built). Main menu ->
PLAY WITH FRIENDS, in three steps: (1) one player presses HOST A GAME and
sends the others the **game code** shown in big letters (12 signs, like
K7QM-X2PD-9AB4); (2) the others type it in and press JOIN; (3) if a router
stands in the way - usually - the joiner's screen shows a **reply code**
after 3 seconds, which the joiner sends to the host, who types it into the
same box and presses LET IN. See "Getting through routers" below for why.
While hosting, the code box stays usable (the owner's first try: he had
pressed HOST and then could not type his friend's code): a reply code lets
that friend in, a friend's game code stops hosting and joins them. A plain
address (192.168.0.12) still works as a code for players in the same house.
The host chooses map and wave and starts; everybody's game starts the same
run. Everybody must have the same version (checked on joining). Rules, all
in the CO-OP section of config.gd:
- **All gold is shared** (owner's rule): one count, kept by the host; a coin
  picked up by anyone counts for everybody, and at the end every player
  banks the whole amount. Score, combo, kills and XP from kills are shared
  too; a weapon's own XP goes to whoever made the kill.
- **Gear is shared as well** (Claude's choice, to match): a piece any player
  picks up, and the piece in a chest anybody opens, goes into every bag.
- **Zombies are stronger** (owner's rule), by the number of players (1/2/3):
  health x1 / 1.6 / 2.2, damage x1 / 1.15 / 1.3, wave size x1 / 1.3 / 1.6.
  If somebody leaves, the next wave is sized for whoever is left.
- Each player plays their **own character**: own level, skills, gear (shown
  on their figure), weapons, pet. Other players are drawn with a coloured
  ring and their name (slot colours `COOP_COLORS`), and appear on the HUD
  (name + health bar), the minimap and as an arrow at the screen edge.
- **Falling**: out of health with others still up, a player lies down
  instead of dying; zombies leave them alone. Another player standing
  beside them for 3 s picks them up (40% health, 2 s of safety); a cleared
  wave does the same. The run is lost when everybody is down.
- **Pausing** pauses everybody. No auto-pause on losing focus in co-op. No
  slow motion in co-op. Only the host starts, restarts or chooses runs.
- After a run everybody is back on the co-op screen, still connected. A
  player who quits a run early keeps their share; the rest play on. If the
  HOST quits or drops, the run ends for everybody (the world was theirs).
  A player who joins while a run is on waits for the next one.

**Maps** (`Config.MAPS`, five of them): every map has 100 waves
(`WAVES_PER_MAP`). Clearing wave 100 ends the run as a victory, pays a bonus
and unlocks the next map, where zombies have much more health and damage
(health x1 / 4 / 12 / 35 / 100) and XP and coins are worth more. Every boss
beaten (every 5th wave, `CHECKPOINT_EVERY`) unlocks the next starting wave
on that map, so a map is finished over several sessions; a checkpoint run
starts with a weapon crate beside the player. All five maps use the same
big clearing for now, with a colour wash per map (`ground` / `trees`); the
real themed scenery is roadmap step 5 (a map may already set its own
`"size"`). The owner calls maps "levels"; the UI
says MAP so it is not confused with the character LEVEL.

**The map** (THE MAP section of config.gd): one big clearing of 6000x4000
ringed by trees (the screen shows about 1070x600 of it), with about 60 random
rocks/stumps. The player starts in the middle. Camera zoom 1.2, may look
110 px past the edge.
- *Zombies hunt the player wherever they are.* A pack claws out of the
  ground (`rising`) in a ring around the middle of the screen, just out of
  sight: `Game.spawn_min` = screen centre-to-corner + aim lead +
  `SPAWN_RING_MARGIN`, measured from `GameCamera.center_for(player)` because
  near the map's edge the player is not in the middle of the screen. Later
  waves split a pack over several directions. A zombie left further behind
  than `Game.leash_dist` is taken off the field without a reward and the
  director owes one more (`on_enemy_lost`); a boss left behind
  (`Game.boss_leash`) digs through the ground and bursts out near the player
  - there is no running away on a big map.
- *Fog of war* (`fog.gd`): the map starts under mist and clears for the rest
  of the run wherever the player has been (`FOG_CLEAR_RADIUS` 380 px, soft
  edge to 520; the screen is 533 px to each side, so unexplored land shows
  as mist at the sides of the screen). A weapon crate or piece of gear
  landing in fog clears a small hole around itself; crates prefer uncovered
  ground. The fog resets every run.
- *Minimap* (bottom right, drawn by the HUD): the whole map, fog included;
  zombies as red dots under the fog; over it the chests already seen (gold),
  opened chests (dim), weapon crates, gear, the boss, the screen's outline
  and the player's arrow. Above it: chests opened / total and "% explored".
- *Treasure chests* (`CHEST_*`): 4 are hidden each run, at least 1100 px
  from the start and spread out. A chest shows (and gets a minimap mark, and
  an edge arrow when off-screen) once the fog over it clears; walking into
  it opens it: a piece of gear straight into the bag (kept even if you die)
  and 12-24 coins flying out. Chest gear: any piece zombies or brutes drop
  on that map (**rings and amulets stay boss-only**), tier by
  `CHEST_TIER_WEIGHTS` (70% COMMON / 25% STURDY / 5% FINE), plus the map's
  `gear_up` chance of one tier more, plus 1% per wave of the run (max 50%)
  of one tier more - rolled when opened, so chests are worth more deep into
  a run. The results screen shows chests opened and map explored.
- *Weapon crates* land 260-620 px from the player.

**Player:** instant movement (no acceleration), 100 HP, 0.55 s of safety after
a hit plus a shove that pushes the crowd back. Zombies body-block the player.

**Weapons** (`Config.WEAPONS`, nine of them). Crate weapons last about 20 s
then revert to the pistol. Crates drop on a timer (max 2 on the field) and
bosses drop one. A crate shows the weapon's side-view picture large across it
and its name underneath in the rarity colour (owner: the old small logo was
too hard to read, and he did not want the coloured circles around crates -
no glow, no rings). Off-screen crates get an arrow with the weapon picture.
**Crates are breakable** (owner's request): the player's bullets, flames and
blasts damage them (`CRATE_HP`; a bullet stops in the wood) and a destroyed
crate takes its weapon with it. A hit counts the weapon's plain damage, not
the player's upgraded damage; blasts count double. Cracks and a small bar
show the damage.
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
  0.22, times the weapon's own spawn-rate upgrade. The colour of the name
  under the crate shows its tier. The launcher must stay rarer than the machine gun (owner's request).
- *Dual wielding:* picking up a crate of the weapon already held gives one in
  each hand if the weapon has `"dual": true` (pistol, SMG, shotgun, machine
  gun): about 1.8x fire rate, more spread and recoil. A pistol crate always
  gives dual pistols for 25 s. Crates that would dual show "x2".
- *Reloading:* every gun has a magazine (`mag`) and reloads when empty or on
  R / gamepad X (`GameInput.reload_pressed`). `reload_kind: "mag"` swaps the
  whole magazine and blocks firing; `"shell"` (shotgun) loads one round at a
  time and firing interrupts it. The launcher holds one round, so every shot
  is followed by a reload. Melee weapons have `mag: 0`. Reload speed scales
  with the dexterity passive and the weapon's own RELOAD SPEED track. The HUD shows "R = reload" beside the
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
  `--bench=150 --no-crates --weapon=ID [--dual]` (kills in 15 s; the numbers below were taken before rage was removed, with the bot not using it).
  Last measured (with reloading): pistol 32, dual pistols 37, SMG 67,
  shotgun 93, rifle 106, machine gun 124, dual machine gun 199, launcher
  ~500, flamethrower ~620; sledgehammer ~350 and chainsaw ~380 do not
  reload. Melee and flame numbers are flattered by the test (the bot cannot
  die); real play punishes short range.

**Enemies** (`Config.ENEMIES`): Shambler (basic), Runner (fast, zig-zags),
Brute (tank, resists knockback and stagger), boss "The Gorger" every 5th wave
(charge with a telegraphed wind-up, dazed afterwards; summons shamblers out of
the ground; +60% HP each time it returns), and four kinds with an attack of
their own (owner: "more enemies including some that shoot from range"):
- **Gobber** (ranged): stops about 400 px away, swells for 0.6 s, spits a
  slow glob (330 px/s, 11 damage) that rocks and weapon crates stop. Any hit
  while it swells makes it swallow the spit and start over.
- **Chucker** (ranged, tough): heaves a lump of rubble onto the spot where
  the player stands; it lands 1.15 s later and hits everything within 78 px
  (20 damage). A red ring on the ground shows where and fills as it falls.
  Hits do not stop it. Drops from the brute gear pool.
- **Gasbag**: walks up, swells for 0.65 s and bursts (125 px; 20 damage to
  the player). It bursts however it dies, and the blast hurts zombies too
  (70 x the wave's health multiplier - the kills are the player's) and sets
  off other Gasbags a moment later. Shoot it in a crowd, not next to you.
- **Lunger**: thin and quick; crouches 0.45 s, then leaps ~290 px in a
  straight line at where the player was (16 damage) and lies dazed for
  0.75 s. Shooting it out of the air drops it.
*Rules for these* (keep them for any new kind): every special attack has a
**warning** first (the zombie stops, swells and flushes with its
`warn_color`); shooters only attack when the player can see them (**on
screen and on ground the fog has cleared from**, otherwise they walk
closer); enemy projectiles **damage weapon crates** like the player's do
(owner's earlier wish). The first time a kind is seen it is introduced
once per save with a banner near the bottom of the screen ("NEW: GOBBER" +
the `"tip"` from config, `Hud.show_tip`, `SaveData.enemies_seen`) and a ring
around it. In code they share the boss's states (chase / wind-up / attack /
recover) and are stepped by `EnemyManager._tick_special`; `"ai"` in config
says which behaviour a kind has. Names must stay original (checked: no
"Spitter", "Boomer", "Bloater", "Hunter" and the like).
*Wounded look:* below 30% health (`WOUNDED_AT`) a zombie switches to its
`<sprite>_hurt` texture (gashes, bare ribs, a lost eye), limps, walks a
little slower and leaves a trail of blood drops; its corpse keeps the wounds.
The player gets a bloodied, bandaged sprite and drips blood below 30% too.
Every new enemy or character needs a `_hurt` variant.

**Waves** (`Config.wave_*` helpers), same curve on every map and stretched
over 100 waves: count = 22 + 9(w-1), capped at 500 per wave and 240 alive.
Zombies arrive in packs (out of the ground around the screen, see "The map")
so they form hordes; pack size and rate grow with the wave, and every 5 waves
the packs come from one more direction at once (up to 4) so hordes surround
the player; who is in a wave comes from `Config.ENEMY_MIX` (Runners from
wave 2, Brutes and Gobbers from 3, Lungers from 4, Gasbags from 6, Chuckers
from 8; each kind's share grows per wave to its maximum; at least 20% of
every wave stays Shamblers); per wave +6% HP,
+1% damage, +0.5% speed, +1% XP per kill, all multiplied by the map. Boss HP
= 1700 x wave growth x map x (+25% per earlier boss). Clearing a wave pays
a coin and XP bonus. The slope is deliberately gentle so that every bit of
character growth buys another wave or two (owner: "incremental feel"). The
bot reaches wave 6-9 as a new character and ~11 at level 15-30.

**Score / combo:** each kill within 2.5 s of the last raises the combo, which
multiplies score (up to x3). Taking damage resets it.

**No rage.** The game used to have a rage meter (kills filled it; Space
gave a blast and 8 s of x3 damage). The owner had it **removed completely**
(after v0.7): no meter, no key, no sounds, nothing in config. Do not bring it
back. Space, the right mouse button, LB and LT are free. The FERAL keystone,
which used to speed the pet up during rage, now does so while the player is
badly hurt (below 30% health). SECOND WIND kept its blast
(`SECOND_WIND_BURST_*`).

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
- *Skills* (Skills screen, `skill_screen.gd`; SKILLS section of config.gd).
  **A plain list, no tree.** History: the owner first asked for an
  "intimidating tree", found the 289-node web "super messy and complex", got
  a three-family tree, and then had it removed altogether: "remove the skill
  tree completely and add a simple interface for essential upgrades like
  life, defense, movement speed, critical etc... similar to the new weapon
  upgrade interface". So the page looks like an Armory page: one row per
  stat - icon, name, ten pips, "rank N", what it gives now and next - with a
  **"+1" button** that spends skill points. Nine stats in three labelled
  groups (`Config.SKILL_GROUPS`): **VITALITY** (HEALTH, DEFENSE, EVASION),
  **STRENGTH** (DAMAGE, ATTACK SPEED, CRITICAL), **INSTINCT** (MOVE SPEED,
  LUCK, PET BOND). Those are display names; the ids in code and save files
  are still `vitality`, `defense`, `evasion`, `strength`, `dexterity`,
  `critical`, `agility`, `luck`, `bond` - never rename ids.
  A rank costs 1 point, plus 1 for every 5 ranks of that stat already bought
  (`SKILL_RANK_COST_STEP`); ranks have no upper limit (endless progression).
  PET BOND needs character level 18. **Special powers** (`Config.KEYSTONES`,
  one per stat: SECOND WIND, EXECUTIONER...) are not bought: a stat's power
  is yours once 15 ranks of it are bought (`KEYSTONE_RANK`); each row names
  its power and a strip at the bottom explains the row under the pointer.
  There are no nodes, no deeds, no sealed things. Do not make this page more
  complicated without the owner asking.
  More skill points can be bought with coins (price x1.15 each time); a paid
  reset returns all spent points. Stat ranks = ranks bought here + gear
  (`SaveData.passive_rank`; `SaveData.skill_rank` is the bought part);
  `SaveData.bonus_ranks` is a hook for tests. Points spent in the old skill
  tree (saves of v0.2 - v0.8) are handed back on load, once.
- *Weapon levels and upgrades* (Armory): each weapon earns XP from kills
  made with it (kills carry a `source` weapon id through
  `EnemyManager.damage`). Each weapon level gives a point for that weapon
  only. The owner did not like weapon trees ("simpler, more straightforward,
  cleaner, no tree"), so the Armory is one plain page per weapon: a row per
  upgrade (power, shooting speed, stability = spread + recoil, reload speed,
  spawn rate = crate share, duration) with pips, what it gives now and next,
  and a "+1" button - ranks are unlimited, one more point per rank every 5
  ranks (`WEAPON_RANK_COST_STEP`) - and three **perk** cards per weapon
  (`Config.WEAPON_PERKS`, open at weapon level 5 / 12 / 20, cost 2 / 4 / 6)
  that change the weapon's own numbers (bigger magazine, piercing, more
  pellets, wider swing, bigger blast...). Perks are applied by
  `PlayerStats.weapon_def(id)`, which the player uses instead of
  `Config.WEAPONS[id]`. Which upgrades a weapon has is decided by `"needs"`
  in `Config.WEAPON_TRACKS` (`Config.weapon_tracks(id)`): the pistol has no
  crate upgrades, melee weapons have no stability or reload, the launcher
  has no shooting speed (its rate of fire is its reload). A weapon's points
  can be taken back for coins.
- *Gear* (Character screen; everything in the GEAR section of config.gd):
  nine slots (helmet, amulet, chest, gloves, two rings, belt, pants, boots)
  and 32 pieces, four per kind. A piece gives ranks of one or two passive
  stats (`SaveData.gear_rank`, added to `passive_rank` on top of the tree).
  **Drops** are deliberately rare (owner: "should not be overload"): about
  0.4% per shambler, 4% per brute, times the map's `gear` multiplier and half
  of the LUCK bonus; the bot finds 0-4 pieces per run as a new character.
  **Rings and amulets drop only from bosses** (a boss always drops one), some
  pieces only from brutes, and one piece per kind only from map 2 onwards.
  Later maps also sometimes drop a piece one tier up (`gear_up`). A drop is a
  pillar of light in the tier's colour with a HUD arrow; picking it up puts it
  straight in the bag (kept even if you die). **Treasure chests** on the map
  are the other source (see "The map"): up to 4 pieces per run for exploring.
  **Five tiers** (colours): COMMON, STURDY, FINE, SUPERIOR, LEGENDARY, with
  stat multipliers 1 / 2 / 3 / 5 / 8. **Forging**: two identical pieces of the
  same tier make one of the next tier with the owner's odds - 100% / 90% /
  40% / 10%. A failed attempt always uses up one of the two; for SUPERIOR
  and LEGENDARY there is also a 35% / 50% chance (`break`) that the other is
  destroyed too. A piece is stored as "item:tier" (`Config.gear_key`) with a
  count; worn pieces are not counted in the bag. Never rename item ids.
  The **Character screen** is laid out the way the owner asked (no tree
  here): Cliff stands in the middle, five slots on his left and four on his
  right, his stats under him; the inventory is on the right; a strip along
  the bottom describes whatever is pointed at. Click a piece in the
  inventory to wear it, click a slot to take it off. **FORGE** in the
  inventory opens the forge menu: pick a pair, see "piece + piece = result"
  with the chance, press FORGE (anything that can fail asks twice).
- *Cliff's look*: `Config.HERO_LOOK` (short dark hair, black shirt, brown
  harness straps, dark cargo trousers with knee pads, boots, a pistol) plus
  the `"look"` of every piece he wears (`"style"` + two colours in
  `Config.GEAR_ITEMS`). `Art.refresh_hero()` rebuilds the front view
  (`hero_front`, Character screen and main menu) and the top-down game sprite
  (`player`, `player_hurt`, `player_flash`) whenever `SaveData.gear_changed`
  fires - the owner wants the top-down Cliff to match his current gear. From
  above only helmet, chest, gloves and belt pouches can be seen. A new piece
  of gear needs a `"look"`; a new style needs drawing code in both
  `_hero_top_svg` and `_hero_front_svg`. A PNG `assets/sprites/player.png`
  or `hero_front.png` still replaces the generated picture.
- *Pets* (Pets screen; PETS section of config.gd). The feature opens at
  character level 18 (`PET_UNLOCK_LEVEL`): the first pet, SCRAPS the stray
  dog, joins by itself (mid-run if that is where the level is reached). Five
  pets, one per rarity: Scraps (common), Soot the alley cat (uncommon,
  level 25 + 1,500 coins), Brutus the bulldog (rare, level 35 + 6,000),
  Ash the wolf (epic, clear map 1 + 20,000), Cinder the hellhound
  (legendary, clear map 2 + 60,000; its bites ignite). One comes along at a
  time (`SaveData.pet_active`). **Owner's rules:** a pet adds to the
  character's damage, at most its rarity's cap - 3 / 6 / 9 / 12 / **15%**
  for legendary (`PET_RARITIES`, "lower rarity = less damage") - and pet
  damage and perks have **their own upgrade**: PET BOND (id `bond`), a row
  of the Skills page (needs level 18; it was a branch of the skill tree
  while there was one). With no BOND a pet gives 30% of its cap, at 30 BOND
  ranks all of it (`Config.pet_damage_bonus`); never more. BOND also makes
  the pet's own bite stronger without limit. Ranks 1 / 5 / 10 / 13 of it
  teach the tricks fetch, maul, guardian and frenzy (`PET_TRICKS`,
  `PET_TRICK_RANKS`); its special power at rank 15 is FERAL. In a run the
  pet (`scripts/game/pet.gd`) walks at heel, bites zombies that come within
  `PET_GUARD_RANGE` of the player (bite = `PET_BITE_DAMAGE` x rarity x BOND x
  the character's damage bonuses) and cannot be hurt (zombies ignore it), so
  pets need no `_hurt` sprite. Pet pictures are generated from the colours in
  `Config.PETS[...]["look"]`.
- Save format version 2 (new fields are simply added with defaults). Version 1
  saves keep records and settings but coins and the old upgrades are wiped
  once (agreed with the owner). Points spent in upgrade screens that have
  since been redesigned (the old stat list, the first skill tree, the weapon
  trees) are handed back on load.

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
- **Co-op: who decides what.** Each computer runs its OWN player for real
  (movement, shooting, health, reloading), so your character always reacts
  instantly. The HOST runs the world (zombies, waves, pickups, gold). On a
  joiner's computer `Game.is_client` is true: the wave director does not
  run, `EnemyManager.tick_remote` moves COPIES of the host's zombies
  (`remote`), and `Pickups.remote` only shows what the host says exists.
  What travels (`net.gd` delivers, `coop.gd` decides):
  - *player states* 30 times a second each way (position, aim, weapon,
    health, down, who they are picking up); the host passes each joiner's
    state on to the other joiner;
  - *snapshots* 15 times a second from the host: the run's numbers (wave,
    score, coins, kills...) and every living zombie in 10 bytes (number,
    kind, position, facing, flags, health), cut into pieces of 120 zombies
    so each fits one packet; a zombie missing from a complete snapshot is
    gone; copies glide between snapshots;
  - *events* that must arrive (reliable): kills, hits on players, pickups
    appearing and going, chests, spit and rubble, wave starts, the ending.
  A joiner's bullets are real on the joiner's own screen: they hit the
  copies, and `EnemyManager.damage` on a joiner shows the hit and sends it
  to the host (`C_HITS`), who applies it (`apply_mate_hit`) - so what you
  see is what you hit. Zombie attacks on a joiner are decided by the host
  and sent as `E_HURT`; the joiner's own computer applies defense, evasion
  and safety time. Spit and rubble fly on every computer and each one only
  checks its own player. **The host's map is sent as it is**: when a run
  starts the host sends the finished list of rocks (`Arena.rocks()`) and the
  chest spots; a joiner never works the map out for itself. (Until v0.9.0
  both built the rocks from a shared number - a Mac and a PC do not always
  round numbers the same way, so they could have ended up with different
  maps.) Rule: never rely on two computers computing the same thing; send
  the result. Mac and Windows copies speak the same messages and can play
  together. Other players' shots are shown as look-alikes
  (`Shot.cosmetic`). Players are numbered by **slot** (0 = host, 1 and 2 =
  joiners); joiners only talk to the host. Zombies chase the nearest player
  who is up; packs rise out of sight of every player. Never make a joiner
  decide anything about the world, and never trust message contents
  (`Coop.SIZES`, `Net._clean_info`).
- **Getting through routers** (v0.10.0, after the owner's first co-op
  evening failed: his router refused UPnP, and a friend had been sent a
  same-house address). A home router lets nothing in that was not spoken to
  first, so nobody can simply connect to the host. The game uses UDP hole
  punching, all in `net.gd`:
  - `Stun` asks two public address finders (STUN servers, `NET_STUN_SERVERS`:
    Google and Cloudflare) "what address and door did my packet come from?"
    - through the very UDP port the game uses next (ask first, close, then
    open ENet on the same port). Two different answers = a "strict" router
    (`Net.strict`), which cannot be reached; the screen says so.
  - The host's answer, packed by `make_code`, is the game code. A joiner
    asks the same for itself, then tries to connect in rounds of 3 s from
    that same local port (`_begin_round`; ENet knocks at 0, 0.5, 1.5 s).
  - Not through after the first round: the joiner shows its own address as
    a reply code. The host's `let_in` then sends 1-byte packets to it for
    20 s with `ENetConnection.socket_send` - they only have to leave
    through the host's router; after that both routers let the other side
    in, and the joiner's next knock connects.
  - While hosting, a packet to the address finder every 10 s keeps the
    router's door from closing. UPnP is still tried as well; where it works
    joiners get in at the first knock.
  - Codes: 6 bytes (address + port) + a check byte + a mark (game / reply)
    = 12 signs of a 32-sign alphabet without I, L, O, U; a typing mistake
    is noticed at once.
  `tools/nattest.sh` proves this on one Linux machine: each copy of the game
  sits in its own network namespace behind its own NAT router (port-
  restricted, like home routers). Modes: normal (2 or 3 players), `noletin`
  (the joiner must NOT get in - shows the routers really block), `open`
  (door forwarded: no reply code needed), `strict` (must be noticed).
  **There is no server of ours and no meeting-point service**: the players
  pass the two codes by hand. Automating step 3 would need an outside
  service to pass the joiner's address to the host (a public message relay
  such as ntfy.sh was considered and NOT built: it means sending players'
  addresses through somebody else's service and accepting its terms - the
  owner has not been asked). The real answer for the Steam release is Steam's
  own networking (invites, no codes, no routers).
- **One simulation loop.** `Game._process` computes `dt` once and ticks
  player -> director -> enemies -> projectiles -> pickups -> fx. Hit stop sets
  `dt = 0` for a few hundredths of a second (rate-limited by
  `HITSTOP_MIN_INTERVAL`, `force` bypasses it); slow motion scales `dt`.
  Camera and HUD always use real time.
- **Persistent gore is free.** `decals.gd` paints the ground once into
  SubViewports that are never cleared, then stamps blood, bodies and casings
  onto them (a viewport is set to UPDATE_ONCE for the frames that have
  stamps). Tens of thousands of decals cost the same as none. The map is too
  big for one picture, so it is cut into chunks (7x5 of about 900x860 px); a
  chunk is only made when the screen comes within `DECAL_CHUNK_AHEAD` of it
  (one per frame at most) or something is stamped on it. Whatever can lie
  across the line between two chunks (the big soft ground patches, the edge
  shadows) is derived from the run's seed and painted in the same order by
  both, so there is no visible seam. Worst case, with the whole map
  explored, the chunks hold about 108 MB of video memory
  (`DECAL_RESOLUTION` 0.5 would quarter that).
- **Obstacles in buckets.** `arena.gd` sorts the ~60 rocks into 256 px
  squares; `resolve()` and `segment_hit()` (every bullet, every frame) only
  look at the rocks listed in the squares they touch.
- **Fog is one tiny picture**: one pixel per 50 px square of the map, alpha =
  how thick the fog still is, stretched over the map with linear filtering
  (soft edges) by a small canvas shader that adds drifting wisps. The HUD
  draws the same picture as the minimap's fog. The shader is the only one in
  the game; like all drawing it only runs with a real renderer.
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
| 150     | 1.5    | 2.1    |
| 250     | 2.7    | 3.9    |
| 400     | 5.6    | 8.4    |

(Measured on the big map with all eight kinds of zombie in the horde. The
400 case got slower with Gasbags in it: their chain bursts kill twice as
many zombies per second.)

60 fps allows 16.6 ms per frame. With a real renderer 250 zombies plus
effects were ~330 draw calls (minimap and fog included). Not yet measured on the owner's hardware.

## Not verified yet (needs a human)

- How it actually feels to play - all feel values are first guesses.
- The balance of the 100-wave maps, the skill prices, the special powers, the
  perks, gear drop rates and gear stats, pet prices and pet strength: all
  first guesses, only checked with the bot and the tests.
- Co-op over the real internet. The first real attempt (v0.9.0, three homes)
  failed to connect at all; v0.10.0 connects by hole punching instead. That
  is tested with two and three copies on ONE computer, each behind a
  pretend router (`tools/nattest.sh`), and the address finder is checked
  against the standard's own example and against coturn - but NOT against
  real routers, the real Google/Cloudflare address finders, Windows/Mac
  firewalls asking for permission, or networks that block UDP. Also unknown:
  how it feels with real delay between homes, whether a slow connection
  copes (the host sends up to ~40 KB a second per joiner in the biggest
  fights). Co-op difficulty numbers are first guesses.
- The new enemies: whether their warnings are long enough to react to,
  whether ranged zombies are fair or annoying, how often each should appear
  (first guesses; the bot gets about as far as before, wave 5-11 as a new
  character). Their sounds are unheard.
- The big map on real hardware: whether making a new piece of ground causes
  a hitch when walking into new territory, how much video memory a fully
  explored map takes (about 108 MB by calculation), how the fog looks in
  motion (only still screenshots were checked), whether the minimap is big
  enough to read. Chest count and chest loot are first guesses.
- The Skills page and the Character screen with a real mouse / trackpad /
  gamepad (only simulated input was tested).
- How Cliff looks to a human eye: he is simple shapes in the general style
  the owner asked for, to be replaced by real art one day.
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
  sounds (drop "ting", pickup, forge success / fail / break) and the chest
  opening are unheard too.
- A physical gamepad (only simulated gamepad events were tested).
- The exported Windows .exe and macOS .app on real Windows / macOS machines
  (exports succeed and the exported game data passes the autotest on Linux).

## Owner feedback so far (after the first playtest, Nov 2026)

- Loved: the gore, corpses/blood/casings staying on the ground, the shooting.
- Rage shook the screen too much -> toned down; later the owner had rage
  removed from the game altogether ("remove the rage option completely").
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
  (Superseded by the third playtest, see below: he wants clean screens.)
- "Each weapon sound should be different and satisfying" -> v3 gun sounds
  (done, awaiting feedback).
- Gear (the owner's design: slots like an action-RPG character sheet, rare
  drops, boss-only pieces, merging two identical pieces of the same colour,
  five tiers with 100/90/40/10% odds and a chance to destroy at tiers 4-5)
  -> built (awaiting feedback).
- Third playtest (v0.4): weapon logo on crates too small, no coloured
  circles around crates, crates should be breakable by bullets and blasts
  (done). "I really don't like the tree look in the weapon upgrade screen":
  plain list now (done). The skill tree "looks super messy and complex":
  rebuilt as three families with multi-level nodes (done). The character
  screen should be an equipment page with the hero in the middle and a forge
  menu in the inventory, no tree (done). The hero is Cliff, with a tactical
  look, and the top-down sprite must match his gear (done). LESSON: this
  owner wants clean, readable, modern screens - not big intimidating webs,
  even though he asked for "intimidating" once. Show less, bigger.
- Pets (the owner's design: unlock at level 18; several pets of different
  rarity; each adds to the character's damage with a cap by rarity, legendary
  at most 15%; pet damage and perks in their own skill tree branch) -> built
  (awaiting feedback). How pets are obtained (levels / map clears + coins)
  was Claude's choice - ask the owner if they would rather find them as drops.
- Fourth playtest (v0.5): "the game is much better and understandable".
  Asked for the skill families to be called VITALITY, STRENGTH and INSTINCT
  (done; the stats that shared those names are shown as HEALTH and DAMAGE),
  and to continue -> the big map with fog of war, minimap and treasure
  chests (built, awaiting feedback). First guesses to ask about: the size of
  the map, four chests per run, how thick and how wide the fog is.
- After v0.7: "Remove the [three-family] skill tree completely and add a
  simple interface for essential upgrades like life, defense, movement
  speed, critical etc... similar to the new weapon upgrade interface" -> the
  Skills page is a plain list now (built, awaiting feedback). The powers
  that used to sit at the ends of the tree's branches are kept, as
  milestones at rank 15 of each stat (Claude's choice - if the owner finds
  even that too much, drop the `power` column). SECOND LESSON, same as the
  first: plain lists with a "+1" button are what this owner likes.
- While v0.6 was being built: "next add more enemies including some that
  shoot from range. put working on the new maps last." -> Gobber, Chucker,
  Gasbag, Lunger (built, awaiting feedback); themed maps moved to the end of
  the roadmap.
- "Add a multiplayer option so I can play with T. All gold will be shared,
  enemies will be stronger", then "coop should work with up to 3 players"
  -> online co-op for up to three (built, awaiting feedback). Asked whether
  they would sit at one computer or each at their own: no answer, so online
  only; same-screen co-op is not built. T needs the same version of the
  game: send T new builds after every update (Claude cannot publish GitHub
  releases from a session; builds are handed to the owner as files).
- First co-op evening (v0.9.0, the owner on a Mac, Tatoni and Kosta on PCs,
  three homes): nobody could connect. The owner's router refused to open
  the door, and once he had pressed HOST he "couldn't even write in the text
  field"; Kosta pasted Tatoni's code and it "didn't work" (probably a
  same-house address, which COPY CODE handed out when the router refused).
  -> v0.10.0: hole punching with game code + reply code, the code box stays
  usable while hosting, COPY CODE only ever copies a code that works from
  outside (built, awaiting their second try). If it fails again: ask what
  each screen said; then consider Steam networking or a relay.
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
2b. **100-wave maps, skill tree, weapon upgrades. DONE (awaiting the owner's
   playtest).** See "Maps" and "Progression" above.
3. **Gear. DONE (awaiting the owner's playtest).** See "Gear" under
   Progression. Ideas if the owner wants more:
   more pieces per kind, set bonuses, a way to sell or break down spare gear.
3b. **Pets. DONE (awaiting the owner's playtest).** See "Pets" under
   Progression. Ideas if the owner wants more: more pets per rarity, pets as
   rare boss drops, a pet that flies and fetches from far away.
4. **Big map. DONE (awaiting the owner's playtest).** A 6000x4000 map, fog of
   war, a minimap, four treasure chests per run that give gear; zombies rise
   around the player wherever they are. See "The map" above. Ideas if the
   owner wants more: an even bigger map or different sizes per map, a full
   map on a key, chests guarded by a pack, a key or boss needed for a
   special chest, landmarks to find.
5. **More enemy types, including some that shoot from range. DONE (awaiting
   the owner's playtest).** Gobber, Chucker, Gasbag, Lunger - see "Enemies"
   above. More can be added the same way (ideas: a shielded zombie that must
   be flanked, a screamer that speeds up the horde, a second boss).
6. **Five themed maps** - LAST, by the owner's order - each telling a story
   through its scenery: forest campsite, abandoned farm, graveyard,
   crashed-convoy highway, quarantine lab. (Map select, unlock order and
   difficulty already exist; this step is the scenery.)

Design rule from the owner: progression must feel incremental and endless.

## Later / ideas

- Mobile: on-screen sticks calling `GameInput.set_virtual_input()`; lower
  `DECAL_RESOLUTION`; pack zombie sprites into one atlas to cut draw calls.
- Steam: Steamworks (GodotSteam), achievements, cloud save, custom user data
  folder, real icon, macOS signing + notarisation, store assets.
- Content: more enemy types and bosses, arenas, weapon variety, music, real
  art and sound, damage numbers, daily challenge, leaderboards.
