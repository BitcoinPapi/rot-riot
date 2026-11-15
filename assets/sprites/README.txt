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

In use now (all from pictures the owner made with ChatGPT; see art_source/):
  player, hero_front (JanJan in a run and in the menus)
  runner_0, runner_1   brute_0   chucker_0   gasbag_0   gobber_0   lunger_0
  fighter_0 (the Gang Fighter)   boss_0, boss_1, boss_2 (the bosses of maps 1-3)
  ...each with its _hurt picture.
