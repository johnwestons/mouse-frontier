# Sewing desk sprite art

## Controls atlas

Use case: stylized-concept
Asset type: production transparent UI SPRITE ATLAS for detailed pixel-art frontier sewing game, exactly 4 columns by 5 rows of equal square cells. Canvas1024x1280 or same4:5 aspect. True transparent background, even invisible grid, no drawn gridlines. Each sprite fully contained within its own cell with at least12% transparent padding from every cell boundary. No overlap. NO text NO letters NO numbers anywhere.
Style: rich handcrafted 2D pixel art with crisp pixel clusters and dark clean outlines, worn walnut, warm brass, ivory parchment, olive cloth, muted russet and iron. Orthographic frontal UI surfaces, no perspective. Match a mature rustic train workshop game. NOT smooth vector graphics or plain geometric schematic icons.
Cell order left to right then top to bottom:
ROW1: (1) square blank aged ivory paper sheet with subtle curled corners; (2) square blank parchment recipe card thin brown stitched leather edge; (3) same blank parchment card with warm brass selection trim; (4) square dark walnut button plaque with thin brass border and blank dark center.
ROW2: (1) square dark walnut button plaque bright gold edge selected state; (2) square dark walnut button plaque dull gray iron edge disabled state; (3) small ivory hollow chalk-ring marker transparent inside; (4) amber brass circular ring marker with dark inner face to support a number added by code.
ROW3: (1) olive-green circular completion stamp with cream checkmark only; (2) slender vertical silver needle-shaped meter pointer with brass head; (3) short horizontal ivory tailor-chalk dash with grainy ends; (4) one thick horizontal golden thread stitch with tiny dark needle holes at both ends.
ROW4: (1) wide horizontal empty tension-gauge housing in wood and brass, dark interior, no ticks; (2) wide horizontal olive green woven-cloth meter fill strip; (3) small bronze thimble quality medal on russet ribbon; (4) small silver thimble quality medal on olive ribbon.
ROW5: (1) small gold thimble quality medal on olive ribbon; (2) small left-pointing brass chevron arrow; (3) small right-pointing brass chevron arrow; (4) small brass X close icon.
Important: panel/blank card sprites should use most of each cell while retaining transparent12%margin; meter and line sprites are horizontal and narrow. All backgrounds between icons must be genuinely alpha transparent. No background shadows crossing cells, no labels, no UI mockup, no screenshots. This sheet will be sliced into individual game sprites.

Generated with the built-in image generation tool. Runtime code renders authored PNG sprites and live text.

## Desk background

Use case: stylized-concept
Asset type: production 2D pixel-art GAME UI BACKGROUND texture, 4:3 landscape 1536x1152, for a 960x720 game sewing workbench.
Primary request: draw a beautiful authored sprite background for Mouse Frontier, a cozy rugged frontier train sewing workshop. Orthographic top-down close view of a worn walnut plank sewing desk. Rich detailed hand-placed pixel clusters, dark clean pixel outlines, restrained warm amber light, muted olive cloth, russet leather, aged ivory paper, brass and iron accents. Match mature detailed 2D game sprites, not vector art, not photorealistic.
Composition EXACT relative zones, practical blank writable surfaces:
Top 2%-12%: long dark wooden nameplate almost full width, with brass corner screws and thin brass inset trim; leave interior blank for live text. At top right inside header leave a clear dark place for a close button.
Left x2%-27% y14%-90%: tall open pattern book, aged light cream parchment pages and dark brown leather binding, large EMPTY readable interior with small worn corners, no printed patterns, no rows or pictures; a few paper tabs along its outside edge.
Center x29%-71% y16%-68%: large unobstructed dark olive cutting mat on the wooden desk, lying flat top-down, very subtle woven texture, minimal low contrast grid. EMPTY center for separate workpiece sprites; no hoop, no workpieces or tools covering it.
Right x73%-98% y14%-90%: tall aged ivory supply ledger mounted on a wooden clipboard, brass clip at top, large EMPTY interior for text and item sprites. No marks or lines in writing surface.
Center bottom x29%-71% y70%-90%: separate empty ivory instruction card with worn corners resting on dark desk, suitable for short live text and controls.
Bottom x2%-98% y92%-99%: dark wooden instruction strip, blank and unobstructed.
Tiny decorative sewing-related details only in OUTER margins and between surfaces: a few brass buttons at bottom corner, folded cloth sliver, thread tail, screw heads; do not clutter the blank UI areas. Entire frame filled, opaque.
Constraints: NO text, NO lettering, NO numbers, NO icons, NO pretend screenshots. No characters/hands/body parts. No large tools. All panels straight and aligned, not perspective skew, consistent pixel density. No code-like flat rectangles: use beautiful physical paper/leather/wood textures but keep all interiors calm for legibility. This is one fully painted background asset, UI content added separately.
