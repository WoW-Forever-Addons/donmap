# Changes

## 1.3.2

- **Fixed on WoW Forever:** typing a /run line in the chat no longer shows "DonMap has been blocked from an action only available to the Blizzard UI".
- **Tooltips** of wide rows open at the mouse pointer.

## 1.3.1

- **Pins above quest marks:** an addon can put its world map pins above Questdon's quest pins. Guildon uses it, so a guild member under a "!" can be hovered and clicked again.

## 1.3.0

- **Square and shaped minimaps:** EllesmereUI's square or 4:3 cut minimap and the mixed shapes of other minimap addons (for example SexyMap) are recognised, so points, routes and pins show in the corners too.
- **Options in the Don family window:** DonMap's options sit in the shared options window of the Don addons (`/donmap options`).
- **Window size:** all Don windows share one scale, 80 % by default, set from 60 to 110 % under General > Window in the options window. Saved window sizes are reset once, places stay.
- **Addon list:** the addon has its own logo in the game's addon list.
- **Update note:** new files, so restart the game after updating (a /reload is not enough).

## 1.2.0

- **First full release.** DonMap is the map layer of the Don addons, for WoW Forever and WoW Classic Era in one download. **Questdon**, **Leveldon** and **Guildon: Map & Members** need it; the CurseForge app installs it with them. If you install by hand, put the `DonMap` folder next to them in `Interface\AddOns`.
- **Pins in one place:** the pins of Questdon and Guildon on the world map and the minimap, and the inn, auction house, flight master and bank symbols. Pins close together become one, and they stay below Questie and GatherMate.
- **Arrow and compass:** the direction arrow (with the way back to your corpse) and the compass, pointed by Questdon, Leveldon and Guildon (right-click a guild member). Without Questdon DonMap has its own options page (`/donmap options`); `/donmap arrow` shows or hides the arrow.
- **One pointer for Leveldon:** with Leveldon and without Questdon only one pointer shows the way, not two.
- **Light:** pins are only drawn again when something changed; running with 50 points on the minimap makes almost no memory garbage.
- **Commands:** `/donmap` lists the addons that draw through DonMap, `/donmap <name>` switches one off and on, `/donmap diag` for bug reports.
- **For addon authors:** `DonMapAPI` version 5 (pins, minimap points, world map provider, arrow, compass mode).
