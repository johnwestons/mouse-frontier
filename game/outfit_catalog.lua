-- Outfit improvements are small panels fitted to the character's existing
-- clothes. Material bundles are ordinary inventory items; bench tools are reused.
local Definitions = {materials={}, recipes={}, recipesById={}, upgrades={}}

Definitions.materials = {
    ["thread-spool"]={label="Thread Spool",rarity="common",icon="thread",color={.79,.64,.39},unlockTier=1,basePrice=2,
        description="A measured length of sewing thread. Consumed one spool at a time at the outfit bench."},
    ["fabric-scraps"]={label="Fabric Scraps",rarity="common",icon="fabric",color={.60,.65,.49},unlockTier=1,basePrice=2,
        description="Clean woven cloth offcuts, bundled for patching, backing, and soft fabric carriers."},
    ["canvas-bundle"]={label="Canvas Bundle",rarity="uncommon",icon="canvas",color={.64,.53,.33},unlockTier=2,basePrice=4,
        description="Tough woven canvas for reinforcement panels and pockets that hold an underlayer."},
    ["wool-batting"]={label="Wool Batting",rarity="common",icon="wool",color={.88,.82,.67},unlockTier=1,basePrice=3,
        description="Clean carded wool. Quilt it between cloth layers to hold the filling in place."},
    ["leather-pieces"]={label="Leather Pieces",rarity="uncommon",icon="leather",color={.52,.30,.17},unlockTier=2,basePrice=5,
        description="Supple leather offcuts. Mark and pierce stitch holes with an awl before sewing."},
    ["metal-sheet"]={label="Thin Metal Sheet",rarity="rare",icon="metal",color={.56,.62,.64},unlockTier=3,basePrice=7,
        description="Thin salvaged sheet that hand snips can cut. File every edge smooth before enclosing it in cloth."},
    ["waxed-thread"]={label="Waxed Thread",rarity="uncommon",icon="thread",color={.70,.52,.29},unlockTier=2,basePrice=4,
        description="Waxed sewing thread for durable canvas and leather seams. A bench needle passes through prepared holes."},
}

Definitions.qualityOrder={"usable","fine","masterwork"}
Definitions.qualityLabels={usable="Usable",fine="Fine",masterwork="Masterwork"}
Definitions.benchTools={"Chalk", "Scissors", "Pins", "Needles", "Awl", "Hand snips", "File", "Punch", "Mallet"}

local function p(x,y,side) return {x=x,y=y,side=side} end
local corners={p(.23,.23),p(.77,.23),p(.77,.77),p(.23,.77)}
local outline={p(.23,.23),p(.50,.23),p(.77,.23),p(.77,.50),p(.77,.77),p(.50,.77),p(.23,.77),p(.23,.50)}
local seam={p(.29,.29),p(.50,.29),p(.71,.29),p(.71,.50),p(.71,.71),p(.50,.71),p(.29,.71),p(.29,.50)}
local quilting={p(.29,.34),p(.43,.34),p(.57,.34),p(.71,.34),p(.71,.50),p(.57,.50),p(.43,.50),p(.29,.50),p(.29,.66),p(.43,.66),p(.57,.66),p(.71,.66)}
local function saddlePoints(holes)
    local points={}
    for _,hole in ipairs(holes or seam) do
        points[#points+1]=p(hole.x,hole.y,"front")
        points[#points+1]=p(hole.x,hole.y,"back")
    end
    return points
end
local function step(operation,label,instruction,points,tool,material)
    if operation=="cut" then
        local closed={}
        for index,point in ipairs(points) do closed[index]=point end
        closed[#closed+1]=p(points[1].x,points[1].y)
        points=closed
    end
    return {kind="point",operation=operation,label=label,instruction=instruction,points=points,
        tool=tool,material=material or "fabric",tolerance=.072}
end
local function tension(material)
    return {kind="tension",operation="tension",label="Set seam tension",tool="Thread",
        instruction=material=="wool" and "Set the thread snugly while keeping the wool lofty. Over-tight thread crushes the filling."
            or "Draw the stitches snug. Loose loops catch; too much pull puckers the seam.",
        material=material,targetRange=material=="wool" and {min=.34,max=.54} or {min=.46,max=.68}}
end
local function secure(material,holes)
    holes=holes or seam
    local returnHoles={}
    -- The needle is already at the final hole: backstitch through the three
    -- preceding holes, in reverse order, rather than repeating the current one.
    for index=#holes-1,#holes-3,-1 do
        returnHoles[#returnHoles+1]=p(holes[index].x,holes[index].y)
    end
    local leather=material=="leather"
    return step("secure","Secure the thread ends",leather
        and "Backstitch through the previous three prepared holes with both needles, then trim the tails."
        or "Work back through the previous three stitch holes, knot the thread, and trim the tails.",
        leather and saddlePoints(returnHoles) or returnHoles,leather and "Two needles" or "Needle",material)
end
local function clothSteps(label,material,quilt)
    local steps={
        step("mark","Mark the panel","Mark the panel corners with chalk, allowing a margin outside the seam for the turned edge.",corners,"Chalk",material),
        step("cut","Cut along the marks","Follow the numbered outline with scissors. Keep the seam allowance outside the stitching line.",outline,"Scissors",material),
        step("pin",quilt and "Layer and pin" or "Turn and pin the edges",quilt
            and "Lay backing flat, spread the filling evenly, then place the top fabric over it. Pin through all layers."
            or "Turn the raw edge under. Pin the reinforcement onto its fabric backing so it lies flat.",corners,"Pins",material),
        step(quilt and "quilt" or "stitch",quilt and "Quilt the layers" or "Backstitch the edge",quilt
            and "Follow the numbered rows with small running stitches to keep the filling from shifting."
            or "Follow the seam around the patch. Each marked segment represents a short backstitch worked into the previous stitch.",quilt and quilting or seam,"Needle",material),
        tension(material),
    }
    if quilt then steps[#steps+1]=step("bind","Bind the raw edges","Fold a cloth strip over the raw edges and stitch the binding in place through the fabric layers.",seam,"Needle",material) end
    steps[#steps+1]=secure(material)
    return steps
end
local function leatherSteps(padded)
    return {
        step("mark","Mark the leather","Chalk the panel outline and an inset seam, leaving enough leather outside the holes to resist tearing.",corners,"Chalk","leather"),
        step("cut","Cut the leather panel","Follow the marked outline with the bench shears. Keep each corner gently rounded.",outline,"Scissors","leather"),
        step("pin",padded and "Align the padded backing" or "Align the reinforcement",padded
            and "Smooth the wool between the cloth and leather. Clip the edges together; keep the filling clear of the seam."
            or "Align the leather with its canvas backing and clip the edges together before making stitch holes.",corners,"Clips","leather"),
        step("punch","Pierce the seam holes","Use the awl at each marked hole while the layers are aligned. The needle will follow these prepared holes.",seam,"Awl","leather"),
        step("stitch","Saddle stitch the seam","Pass the front needle, then the back needle, through the same prepared hole. Avoid piercing the other thread.",saddlePoints(),"Two needles","leather"),
        tension("leather"),
        secure("leather"),
    }
end
local function gussetSteps()
    local diamondPins={p(.50,.29),p(.69,.50),p(.50,.71),p(.31,.50)}
    local diamondSeam={p(.50,.29),p(.595,.395),p(.69,.50),p(.595,.605),
        p(.50,.71),p(.405,.605),p(.31,.50),p(.405,.395)}
    -- Finishing stitches lie between the inset seam and the cut edge, where
    -- the raw seam allowance is folded under after the gusset is attached.
    local diamondFinish={p(.50,.25),p(.6125,.375),p(.725,.50),p(.6125,.625),
        p(.50,.75),p(.3875,.625),p(.275,.50),p(.3875,.375)}
    local steps={
        step("mark","Mark a movement gusset","Mark a diamond shaped panel and its seam allowance. Its bias runs across the direction that needs more movement.",
            {p(.50,.20),p(.77,.50),p(.50,.80),p(.23,.50)},"Chalk","fabric"),
        step("cut","Cut the inset panel","Cut a flexible cloth diamond, keeping the marked seam allowance intact.",
            {p(.50,.20),p(.635,.35),p(.77,.50),p(.635,.65),p(.50,.80),p(.365,.65),p(.23,.50),p(.365,.35)},"Scissors","fabric"),
        step("pin","Align the seam opening","Pin the diamond between the opened seam edges. Match opposite seam points and keep the allowance outside the seam.",diamondPins,"Pins","fabric"),
        step("stitch","Backstitch the inset","Work small backstitches around the inset diamond. Keep the seam flat so the added panel can open as the character moves.",diamondSeam,"Needle","fabric"),
        tension("fabric"),
        step("bind","Finish the seam allowance","Turn the diamond's raw edges under and stitch the folded allowance down to prevent fraying against the wearer.",diamondFinish,"Needle","fabric"),
        secure("fabric",diamondFinish),
    }
    for _,stage in ipairs(steps) do stage.shape="diamond" end
    return steps
end
local function metalSteps()
    local metalHoles={p(.35,.35),p(.50,.35),p(.65,.35),p(.65,.50),p(.65,.65),p(.50,.65),p(.35,.65),p(.35,.50)}
    return {
        step("mark","Mark small metal segments","Mark a set of small overlapping segments on thin salvaged sheet. Leave space for rounded corners and fastening holes.",corners,"Chalk","metal"),
        step("cut","Snip the sheet to shape","Follow the outline with hand snips to separate the thin segments. This is sheet work, not forging thick armor plate.",outline,"Hand snips","metal"),
        step("deburr","File every edge smooth","Work around all cut edges and round the corners with a file so the metal cannot saw through its fabric carrier.",outline,"File","metal"),
        step("punch","Punch fastening holes","Use the punch and mallet over the bench block to make holes near the segment edges.",metalHoles,"Punch and mallet","metal"),
        step("deburr","Smooth the holes","Remove the raised burr around every punched hole before thread touches the metal.",metalHoles,"File","metal"),
        step("pin","Lay out the padded carrier","Place wool on the fabric backing, then arrange the smooth segments with small overlaps. Keep the inner face padded.",corners,"Pins","canvas"),
        step("stitch","Lash segments to the carrier","Pass waxed thread through the prepared metal holes and the carrier fabric. Each hole needs both passes to secure its segment.",saddlePoints(metalHoles),"Needle","metal"),
        step("bind","Close the fabric cover","Fold canvas over the metal and turn in its edges. Sew only through the fabric margin outside the segments.",seam,"Needle","canvas"),
        tension("canvas"),
        secure("canvas"),
    }
end

local function cost(id,count) return {id=id,count=count or 1} end
local recipes={
    {id="cloth-repair-patch",label="Cloth Repair Patch",tier=1,slot="clothing",icon="patch",color={.63,.68,.49},
        description="A turned cloth patch spreads strain across worn fabric in the current outfit.",bonuses={armor=1},
        materials={cost("thread-spool"),cost("fabric-scraps")},stages=clothSteps("patch","fabric",false)},
    {id="quilted-wool-lining",label="Quilted Wool Lining",tier=1,slot="clothing",icon="lining",color={.85,.76,.57},
        description="A light quilted lining holds wool in place inside the current outfit, adding a soft cushion.",bonuses={armor=1},
        materials={cost("thread-spool"),cost("fabric-scraps"),cost("wool-batting")},stages=clothSteps("lining","wool",true)},
    {id="padded-cloth-insert",label="Padded Cloth Insert",tier=1,slot="armor",icon="padding",color={.59,.64,.59},
        description="Several cloth layers form a flexible cushion fitted beneath the outfit.",bonuses={armor=1},
        materials={cost("thread-spool"),cost("fabric-scraps",2)},stages=clothSteps("padding","fabric",true)},
    {id="canvas-reinforcement",label="Canvas Reinforcement",tier=2,slot="clothing",icon="patch",color={.61,.52,.34},
        description="Double canvas panels reinforce wear points while allowing the original outfit to move.",bonuses={armor=2},
        materials={cost("thread-spool"),cost("canvas-bundle",2),cost("fabric-scraps")},stages=clothSteps("canvas","canvas",false)},
    {id="mobility-gusset",label="Mobility Gusset",tier=2,slot="clothing",icon="gusset",color={.56,.62,.44},
        description="Flexible inset panels open tight seams, giving the original outfit more room to move.",bonuses={move=1},
        materials={cost("thread-spool"),cost("fabric-scraps",2)},stages=gussetSteps()},
    {id="leather-padding-insert",label="Leather Padding Insert",tier=2,slot="armor",icon="padding",color={.49,.31,.19},
        description="A supple leather face and soft backing spread small impacts beneath the existing clothing.",bonuses={armor=2},
        materials={cost("waxed-thread"),cost("leather-pieces"),cost("fabric-scraps"),cost("wool-batting")},stages=leatherSteps(true)},
    {id="leather-reinforcement",label="Leather Reinforcement",tier=3,slot="clothing",icon="patch",color={.40,.26,.17},
        description="Leather panels saddle stitched to a canvas backing strengthen vulnerable sections of the outfit.",bonuses={armor=3},
        materials={cost("waxed-thread"),cost("leather-pieces",2),cost("canvas-bundle")},stages=leatherSteps(false)},
    {id="quilted-weather-lining",label="Quilted Weather Lining",tier=3,slot="clothing",icon="lining",color={.55,.57,.44},
        description="Quilted wool panels flex between narrow channels, adding cushioning while preserving freedom of movement.",bonuses={armor=2,move=1},
        materials={cost("waxed-thread"),cost("canvas-bundle"),cost("fabric-scraps"),cost("wool-batting",2)},stages=clothSteps("lining","wool",true)},
    {id="segmented-metal-insert",label="Segmented Metal Insert",tier=3,slot="armor",icon="metal",color={.48,.56,.59},
        description="Small smooth metal segments secured to a padded carrier protect beneath the outfit; their added weight restricts movement.",bonuses={armor=3,move=-1},
        materials={cost("waxed-thread"),cost("metal-sheet",2),cost("canvas-bundle"),cost("fabric-scraps"),cost("wool-batting")},stages=metalSteps()},
}

for _,recipe in ipairs(recipes) do
    recipe.outputIds={}
    recipe.totalActions=0
    for _,stage in ipairs(recipe.stages) do recipe.totalActions=recipe.totalActions+(stage.kind=="tension" and 1 or #stage.points) end
    for gradeIndex,quality in ipairs(Definitions.qualityOrder) do
        local id=recipe.id..(quality=="usable" and "" or "-"..quality)
        local bonuses={}
        for stat,value in pairs(recipe.bonuses) do bonuses[stat]=value end
        -- Workmanship changes the finished seams, not the substance of a recipe.
        if quality=="masterwork" then bonuses.armor=(bonuses.armor or 0)+1 end
        local prefix=quality=="usable" and "" or Definitions.qualityLabels[quality].." "
        recipe.outputIds[quality]=id
        Definitions.upgrades[id]={id=id,label=prefix..recipe.label,slot=recipe.slot,bonuses=bonuses,
            description=recipe.description,rarity=({"common","uncommon","rare"})[recipe.tier],
            icon=recipe.icon,color=recipe.color,tier=recipe.tier,quality=quality,recipeId=recipe.id,
            basePrice=recipe.tier*8+gradeIndex*3}
    end
    Definitions.recipes[#Definitions.recipes+1]=recipe
    Definitions.recipesById[recipe.id]=recipe
end

return Definitions
