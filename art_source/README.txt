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
until their pictures arrive. Still shapes, no picture yet: the Shambler.

For example:
  tools/make_sprite.py art_source/brute.webp brute_0      --length 92 --center 620,635
  tools/make_sprite.py art_source/brute.webp brute_0_hurt --length 92 --center 620,635 --wounds
