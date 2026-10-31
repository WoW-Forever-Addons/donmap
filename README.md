# DonMap

The map layer of the Don addons for WoW Forever and WoW Classic Era, as an addon of its own.
Guildon and Questdon need it (Leveldon through Questdon); CurseForge installs it together with them.

What it does: other addons hand over points, DonMap draws them as pins on the world map and as points on the minimap.
Points close together become one pin, the pins sit on whole pixels and below the marks of Questie and GatherMate,
the minimap points turn with a rotating minimap and follow its zoom and shape. The direction arrow (with its way back to
your corpse) and the compass for windows are DonMap's too: Questdon, Leveldon and Guildon point it. DonMap shows nothing
by itself.

- WoW Forever: `DonMap_Camelot.toc`. WoW Classic Era: `DonMap_Vanilla.toc`. Same files.
- `/donmap`: the addons that draw through DonMap and their pins; `/donmap <name>` switches one off and on again;
  `/donmap diag` shows the frame levels of other addons' pins.
- `/donmap arrow` shows or hides the arrow, `/donmap options` opens its settings (with Questdon they are in Questdon's options).
- Saved variables: `DonMapDB` (which sources you switched off, the arrow's settings without Questdon).

For addon authors: `DonMapAPI` (version 4: the arrow since 2, sticky minimap sources since 3, world map pins through the map's data provider and hiding the game's quest markers since 4), see `API.lua`.

```lua
local src = DonMapAPI.Register("myaddon", { title = "My addon", size = 16, group = 10 })
src:SetPoints({ { mapID = 1429, x = 0.42, y = 0.65, label = "Here", color = { 1, 0.8, 0 } } })
```

Code: MIT License (LICENSE.txt). Parts of the geometry come from Questdon and Guildon by the same author.
