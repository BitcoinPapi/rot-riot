Drop PNG files here to replace the placeholder shapes.

Name the file like the sprite (see scripts/autoload/art.gd), for example:
  player.png  shambler_0.png  runner_0.png  brute_0.png  boss_0.png
  gun_pistol.png  coin.png  crate.png  medkit.png  rock.png

Draw characters facing RIGHT, at twice the size listed in art.gd
(a 56x56 sprite becomes a 112x112 PNG). White hit-flash versions are
made automatically. A zombie also needs NAME_hurt.png (its wounded look),
or it turns back into the old shapes when it is badly hurt.

The easy way: tools/make_sprite.py cuts a big picture down to a sprite,
puts it here and can paint the wounded look (the big pictures are kept in
art_source/).

A kind with several looks and one painted picture uses it for all of them
(brute_1 takes brute_0.png).

MOVEMENT. A character can also have strips of frames: NAME_walk.png, NAME_idle.png,
NAME_attack.png, NAME_hit.png, NAME_death.png - the frames side by side, each a
square as tall as the strip, the middle of the chest in the middle of each frame -
and the same again as NAME_walk_hurt.png ... for the wounded look. The game then
shows the character moving instead of as one still picture (the still picture is
still needed: menus, the hit flash and the dashboard use it). tools/make_sprite.py
cuts the strips out of the sheets the owner sends (read "ANIMATIONS" at its top).
In use: gobber_0 and player (JanJan).

In use now (all from pictures the owner made with ChatGPT; see art_source/):
  player, hero_front (JanJan in a run and in the menus)
  shambler_0 .. shambler_3 (made from the Gang Fighter's picture, without his machete)
  runner_0, runner_1   brute_0   chucker_0   gasbag_0   gobber_0   lunger_0
  fighter_0 (the Gang Fighter)   boss_0, boss_1, boss_2 (the bosses of maps 1-3)
  ...each with its _hurt picture.
