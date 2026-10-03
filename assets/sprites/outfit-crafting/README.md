# Authored sewing workbench sprites

All illustration assets were created with the built-in image generation tool. Runtime rendering uses these PNGs; it does not construct tools, fabrics, upgrade icons, UI panels or stitch illustrations from geometric drawing primitives.

## Active artwork

| File | Use |
| --- | --- |
| `bench-background-v1.png` | Complete sewing desk, pattern book, cutting mat and supply clipboard |
| `bench-controls-v1.png` | 20 paper, button, marker, stitch, meter, quality and navigation sprites; 4 columns by 5 rows |
| `supplies-tools-v1.png` | 7 materials and 13 tools/accessories; 4 columns by 5 rows, 280px square cells, final 2px margin unused |
| `upgrades-v1.png` | 9 distinct finished upgrades; 3 columns by 3 rows, 418px square cells |
| `soft-workpieces-v2.png` | 12 cloth, canvas and wool construction states; 4 columns by 3 rows |
| `hard-workpieces-v3.png` | 12 leather, metal and gusset construction states; 4 columns by 3 rows |
| `metal-file-v1.png` | Accurate toothed file, replaces the file cell in the tools atlas |
| `metal-punch-mallet-v1.png` | Straight steel punch, mallet and backing block, replaces the punch cell in the tools atlas |

Older workpiece versions are art drafts; the game loads only the selected versions above. Quality uses separate bronze, silver and gold thimble sprites, combined with the nine recipe icons to represent all 27 upgrade grades.

The same item sprites appear in the bench, inventory, merchant lists and dropped-item display. Character clothing sprites and animations remain unchanged.

## Atlas rendering

`game/outfit_sprite_art.lua` owns asset mappings. It measures visible alpha bounds once when a sheet is loaded and creates texture quads; source pixels and alpha are preserved. Paper and button frames use nine-slice drawing of authored corners and edges. Workpiece quads fit inside the existing normalized action surface, preserving crafting input coordinates. Stitch and chalk graphics are authored sprites repeated along the guide. Text and numbers remain live UI text.

## Exact prompts and provenance

- [Desk and controls prompts](desk-controls-prompts.md)
- [Materials, tools, upgrades and corrected tool prompts](supplies-upgrades-prompts.md)
- [Workpiece generation and revision prompts](workpiece-prompts.md)
- [Workpiece crop reference](workpiece-bounds.json)

No API/CLI image generation or programmatically painted replacement art was used.
