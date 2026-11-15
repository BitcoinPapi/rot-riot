The big pictures the game's painted sprites were made from. Godot ignores this
folder (.gdignore); nothing here is shipped with the game.

All of them were made by the owner with ChatGPT's image generator (November
2026) from descriptions written for this game: seen from straight above,
facing right, see-through background.

To turn one into a sprite: tools/make_sprite.py (read its top). The sizes and
centres below were found by looking at the result in the game
(--horde=fighter:3,brute:2,... and --map=N --horde=boss:1).

  picture               sprite        length  centre     more
  runner.webp           runner_0        60    790,605
                        runner_1        60    790,605    --hue 28   (a second look: a yellow hood)
  brute.webp            brute_0         92    620,635
  chucker.webp          chucker_0       80    545,690
  fighter.webp          fighter_0       84    500,600    (the Gang Fighter)
                        shambler_0..3   70    500,600    the SHAMBLER has no picture of its own: it is the
                                                         Gang Fighter with the machete rubbed out and a
                                                         washed-out headcloth in another colour:
                          --main-only --erase "798,768 840,772 1245,655 1254,700 1245,800 1040,845 840,860 798,850; 650,836 698,836 700,892 650,892"
                          shambler_0: --hue 170 --dull 0.6          shambler_1: --hue 45 --dull 0.55 --mirror
                          shambler_2: --hue 250 --dull 0.5          shambler_3: --hue 100 --dull 0.55 --mirror
  gasbag.webp           gasbag_0        70    580,630    --main-only
  gobber.webp           gobber_0        64    560,650    --main-only   (drops the flying spit)
  lunger.webp           lunger_0        74    480,640
  boss_kok_batay.webp   boss_0         168    500,590    (map 1's boss)
  boss_machwe_fe.webp   boss_1         168    500,560    (map 2's boss)
  boss_papa_zo.webp     boss_2         168    480,580    (map 3's boss)

  janjan_aiming.webp    player          64    528,629    --turn 30    (the hero with ONE gun: both arms stretched
                                                         out, hands empty - the game draws the gun in
                                                         them. He aims up and to the right in the
                                                         picture; turned, his two hands lie on one line
                                                         straight ahead. Config: THE HERO'S HANDS -
                                                         right hand 18.7 ahead and 5.7 to his right of
                                                         the sprite's middle, left hand 12.8 further out)
  janjan_no_guns.webp   player_twin     62    600,500    --turn -90   (the hero with a gun in EACH hand: fists
                                                         apart; he was drawn walking DOWN the picture.
                                                         His left fist 16.4 ahead / 18.0 to his left, his
                                                         right fist 10.4 ahead / 16.5 to his right)
  janjan.webp           hero_front      --portrait 380   (the hero in the menus, with his guns)

Each also has NAME_hurt, made with the same line plus --wounds (blood painted
on), because no wounded pictures were sent. A kind's other looks (brute_1,
gobber_1...) use the first look's picture; so do the bosses of maps 4 and 5
until their pictures arrive. Nothing in the game is drawn as shapes any more;
when a picture of the Shambler arrives, make shambler_0 from it and delete
shambler_1..3 (and their _hurt files), or make four looks of it the same way.

ANIMATIONS (v0.15). The owner sent sheets of frames for the Gobber and for the hero:
for each, walk (12 frames), idle (8), attack (12), hit (6), death (12), in cells of
512 px, four to a row (the hit sheets three). Every frame is the character's one
picture, slightly moved. Kept here as <who>_<movement>_<N>f.webp (saved at quality 95
from the PNGs he sent, which were used for cutting).

  sheet                    strip in assets/sprites     the line of the still sprite, plus
  gobber_walk_12f.webp     gobber_0_walk    --sheet 4x3   --match art_source/gobber.webp --length 64 --center 560,650 --main-only
  gobber_idle_8f.webp      gobber_0_idle    --sheet 4x2   (the same)
  gobber_attack_12f.webp   gobber_0_attack  --sheet 4x3
  gobber_hit_6f.webp       gobber_0_hit     --sheet 3x2
  gobber_death_12f.webp    gobber_0_death   --sheet 4x3
  janjan_walk_12f.webp     player_twin_walk    --sheet 4x3   --match art_source/janjan_no_guns.webp --length 62 --center 600,500 --turn -90 --sheet-turn -90
  janjan_idle_8f.webp      player_twin_idle    --sheet 4x2   (the same; his sheets show him facing LEFT, his
  janjan_attack_12f.webp   player_twin_attack  --sheet 4x3    picture has him walking down: hence --sheet-turn)
  janjan_hit_6f.webp       player_twin_hit     --sheet 3x2
  janjan_death_12f.webp    player_twin_death   --sheet 4x3

The hero's ONE-GUN pose (janjan_aiming.webp) has no sheets from the owner: the five he sent
with it could not be used (another pose, a hazy cut-out, figures sliced by the grid). Its
frames are MADE from the picture by tools/make_moves.py (walk, idle, hit, death; no attack -
the gun in his hands kicks instead), then cut like any others:
  tools/make_moves.py art_source/janjan_aiming.webp OUT --pivot 528,629 --aim -30 --feet "555,865 375,1015" --still-from 250 --step 60 --name janjan_aim
  tools/make_sprite.py OUT/janjan_aim_walk_12f.png player_walk --sheet 4x3 --match art_source/janjan_aiming.webp --length 64 --center 528,629 --turn 30
  (idle 4x2, hit 3x2, death 4x3 the same; each again with --wounds as player_..._hurt)

Each strip also exists as NAME_hurt (the same line plus --wounds). For example:
  tools/make_sprite.py art_source/gobber_walk_12f.webp gobber_0_walk      --sheet 4x3 --match art_source/gobber.webp --length 64 --center 560,650 --main-only
  tools/make_sprite.py art_source/gobber_walk_12f.webp gobber_0_walk_hurt --sheet 4x3 --match art_source/gobber.webp --length 64 --center 560,650 --main-only --wounds
A new character's sheets: the same, with the line of its still sprite. Sheets must show
the picture the still sprite was cut from (the script finds it inside the first frame).

GEAR ICONS. gear_icons/icon_<type>.webp: the eight symbols for the kinds of gear (helmet,
amulet, chest, gloves, ring, belt, pants, boots), made by the owner with ChatGPT as plain
white shapes; the game tints them. Each was cut to its edges and fitted into 96x96 px as
assets/sprites/gear_<type>.png (5 px of room around it) - they replace the small symbols
drawn in art.gd on the inventory tiles, the Character screen's slots, the gear cases on the
ground and the arrows that point to gear. A picture per PIECE (32 of them, named by item
id) is still to come from him.

For example (a still sprite):
  tools/make_sprite.py art_source/brute.webp brute_0      --length 92 --center 620,635
  tools/make_sprite.py art_source/brute.webp brute_0_hurt --length 92 --center 620,635 --wounds
