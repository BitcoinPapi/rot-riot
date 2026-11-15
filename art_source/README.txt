The big pictures the game's painted sprites were made from. Godot ignores this
folder (.gdignore); nothing here is shipped with the game.

To turn one into a sprite: tools/make_sprite.py (read its top).

  runner.webp   the Runner. Made by the owner with ChatGPT's image generator
                (November 2026). Became assets/sprites/runner_0 / runner_1
                (+ _hurt) with:
                  tools/make_sprite.py art_source/runner.webp runner_0      --length 60 --center 790,605
                  tools/make_sprite.py art_source/runner.webp runner_0_hurt --length 60 --center 790,605 --wounds
                  tools/make_sprite.py art_source/runner.webp runner_1      --length 60 --center 790,605 --hue 28
                  tools/make_sprite.py art_source/runner.webp runner_1_hurt --length 60 --center 790,605 --hue 28 --wounds
