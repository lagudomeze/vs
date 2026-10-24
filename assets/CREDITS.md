# Asset credits

## Heroes and generated props

assets/models/*.obj and the brazier / mote / rune circle props are
procedurally authored for VX by tools/characters.py and
tools/bake_assets.py. They belong to this project.

Skeleton, wraith, golem, abyss guard and the elite skeleton /
elite wraith variants share the same procedural humanoid rig as
the heroes. The threat ring, dungeon floor/wall tiles, stairs,
chest and traps are generated flat-colour props.

## Kenney 3D kit

The dungeon/arena props are derived from free Kenney 3D packs
(CC0 1.0 Universal, public domain):

- https://kenney.nl/assets/mini-dungeon
- https://kenney.nl/assets/mini-arena

Models used: banner, barrel, bricks, chair, chest, coin, column, column_damaged, gate, pot, potion, rocks, statue, table, tree, trophy, wall, wall_gate, weapon_rack, weapon_spear, weapon_sword.

Kenney's license text:

~~~
	

	Mini Dungeon (2.0)

	Created/distributed by Kenney (www.kenney.nl)
	Creation date: 29-07-2026 10:35
	
			------------------------------

	License: (Creative Commons Zero, CC0)
	http://creativecommons.org/publicdomain/zero/1.0/

	You can use this content for personal, educational, and commercial purposes.

	Support by crediting 'Kenney' or 'www.kenney.nl' (this is not a requirement)

			------------------------------

	• Website : www.kenney.nl
	• Donate  : www.kenney.nl/donate

	• Patreon : patreon.com/kenney
	
	Follow on social media for updates:

	• Twitter:	 twitter.com/KenneyNL
	• BlueSky:	 kenney.bsky.social
	• Instagram: instagram.com/kenney_nl
~~~

## UI font

The Chinese HUD uses a subset of **Ark Pixel Font 12px** by TakWolf
(https://github.com/TakWolf/ark-pixel-font), licensed under the
SIL Open Font License 1.1. The license text is in assets/fonts/OFL.txt.
Only glyph bitmaps for characters used by the game are embedded;
the source BDF is not required at runtime.

## Kenney UI icons

The HUD 12x12 1-bit icons are derived from free Kenney packs
(CC0 1.0 Universal, public domain):

- https://kenney.nl/assets/board-game-icons
- https://kenney.nl/assets/game-icons

Sources are in assets/icons/board and assets/icons/game; license
texts are in assets/icons/License-board.txt and License-game.txt.
The generated atlas is src/engine/icons.zig, built by
tools/gen_icons.py.
