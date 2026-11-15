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

  janjan_no_guns.webp   player          62    600,500    --turn -90   (the hero in a run: he was
                                                         drawn walking DOWN the picture; the game draws
                                                         the gun he holds, so this one has empty hands)
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
  janjan_walk_12f.webp     player_walk      --sheet 4x3   --match art_source/janjan_no_guns.webp --length 62 --center 600,500 --turn -90 --sheet-turn -90
  janjan_idle_8f.webp      player_idle      --sheet 4x2   (the same; his sheets show him facing LEFT, his
  janjan_attack_12f.webp   player_attack    --sheet 4x3    picture has him walking down: hence --sheet-turn)
  janjan_hit_6f.webp       player_hit       --sheet 3x2
  janjan_death_12f.webp    player_death     --sheet 4x3

Each strip also exists as NAME_hurt (the same line plus --wounds). For example:
  tools/make_sprite.py art_source/gobber_walk_12f.webp gobber_0_walk      --sheet 4x3 --match art_source/gobber.webp --length 64 --center 560,650 --main-only
  tools/make_sprite.py art_source/gobber_walk_12f.webp gobber_0_walk_hurt --sheet 4x3 --match art_source/gobber.webp --length 64 --center 560,650 --main-only --wounds
A new character's sheets: the same, with the line of its still sprite. Sheets must show
the picture the still sprite was cut from (the script finds it inside the first frame).

For example (a still sprite):
  tools/make_sprite.py art_source/brute.webp brute_0      --length 92 --center 620,635
  tools/make_sprite.py art_source/brute.webp brute_0_hurt --length 92 --center 620,635 --wounds
