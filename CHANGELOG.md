# Changes

## 1.2.0

- **First full release.** DonMap is the map layer of the Don addons, for WoW Forever and WoW Classic Era in one download. **Questdon**, **Leveldon** and **Guildon: Map & Members** need it; the CurseForge app installs it with them. If you install by hand, put the `DonMap` folder next to them in `Interface\AddOns`.
- **Pins in one place:** the pins of Questdon and Guildon on the world map and the minimap, and the inn, auction house, flight master and bank symbols. Pins close together become one, and they stay below Questie and GatherMate.
- **Arrow and compass:** the direction arrow (with the way back to your corpse) and the compass, pointed by Questdon, Leveldon and Guildon (right-click a guild member). Without Questdon DonMap has its own options page (`/donmap options`); `/donmap arrow` shows or hides the arrow.
- **One pointer for Leveldon:** with Leveldon and without Questdon only one pointer shows the way, not two.
- **Light:** pins are only drawn again when something changed; running with 50 points on the minimap makes almost no memory garbage.
- **Commands:** `/donmap` lists the addons that draw through DonMap, `/donmap <name>` switches one off and on, `/donmap diag` for bug reports.
- **For addon authors:** `DonMapAPI` version 5 (pins, minimap points, world map provider, arrow, compass mode).
