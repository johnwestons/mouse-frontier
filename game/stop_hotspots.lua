-- Authored scenery details, measured on 640x480 previews of the stop paintings.
-- Harvests use ordinary saved containers; inspections have no campaign state.
local Home=require('game.home_stop')
local Beacon=require('game.interaction_beacon')
local Hotspots={radius=75}
local green={deep={.16,.30,.08},base={.65,.95,.30},highlight={.90,1,.70},outline={.04,.08,.02}}
local definitions={}
local function inspect(stop,id,x,y,title,text,radius)
    definitions[stop]=definitions[stop] or {}
    local list=definitions[stop]
    list[#list+1]={id=id,kind='stopInspect',x=x*1.5,y=y*1.5,title=title,description=text,label='INSPECT '..title,
        radius=radius or 75,hoverRadius=40,beaconRadius=12}
end
local function garden(stop,x,y,label,fruit)
    local list=definitions[stop]
    list[#list+1]={id='harvest',kind='harvest',x=x*1.5,y=y*1.5,title=label or 'GARDEN',
        label='HARVEST '..(label or 'GARDEN'),crop=fruit or 'carrot',count=3,radius=75,hoverRadius=40,beaconRadius=12,beaconPalette=green}
end

inspect(1,'well',275,350,'STONE WELL','A stone-lined well. The raised rim keeps loose soil out of the water below.')
garden(1,365,325)
inspect(2,'windmill',455,153,'WIND PUMP','The wind turns the blades to lift water into the settlement\'s tank.',120)
garden(2,450,360)
inspect(3,'waterwheel',360,160,'WATERWHEEL','Water pushes the wooden paddles, turning a shaft that carries power into the mill.')
garden(3,230,250)
inspect(4,'firepit',360,357,'COURTYARD FIRE PIT','A ring of stones contains the ashes of a small fire. The open courtyard leaves room for its smoke to rise.')
garden(4,300,190)
inspect(5,'observatory',285,170,'OBSERVATORY','The split dome gives a telescope a clear view of the sky while sheltering it from dust.')
inspect(6,'wheel',105,280,'MILL WHEEL','The current turns this wheel beneath the houses. Its paddles are darkened by constant spray.')
garden(6,325,355)
inspect(7,'irrigation',430,350,'IRRIGATION POOL','Narrow channels carry water from this pool toward the planted beds, keeping the oasis green.')
garden(7,290,300)
inspect(8,'rails',310,390,'OLD RAILWAY','Moss grows between the sleepers. Nature has long since reclaimed this stretch of railway.')
garden(8,275,250)
inspect(9,'glasshouse',170,155,'OVERGROWN GLASSHOUSE','Vines climb the old frame and press against the glass. Nature has long since reclaimed this greenhouse.')
garden(9,390,280)
inspect(10,'bridge',145,173,'ROPE BRIDGE','Planks and rope link the cliff paths. Salt and wind have worn the exposed wood pale.')
inspect(11,'bus',125,330,'OLD BUS','This old bus has become part of the settlement. Its wheels sit deep in the ground beside the path.')
garden(11,400,390)
inspect(12,'aqueduct',200,185,'AQUEDUCT WHEEL','A raised channel guides water downhill to the wheel. Gravity does the work of a pump.')
garden(12,240,285)
inspect(13,'mine',250,165,'MINE ENTRANCE','Rails disappear into the rock. Timber supports brace the entrance where the hillside has been cut away.')
inspect(14,'lighthouse',455,170,'LIGHTHOUSE','A beacon above the harbor marks the rocky coast for boats approaching after dark.',120)
inspect(15,'cistern',450,380,'WATER CISTERN','This broad tank stores water close to the railway and the planted beds.')
garden(15,300,280)
inspect(16,'fallen-tree',500,175,'FALLEN TREE','An enormous fallen trunk shelters the settlement. Moss and roots are slowly softening its outline.',110)
inspect(17,'solar',170,173,'SOLAR ARRAY','The panels face the open sky. The dry ground offers little shade, but plenty of dust to brush away.',120)
inspect(18,'windmill',160,220,'GRAIN WINDMILL','A windmill used for crushing grain')
garden(18,565,305,'GREENHOUSE')
inspect(19,'boat',90,300,'MOORED BOAT','A small boat rests beside the platforms, ready to carry supplies where the walkways end.')
garden(19,260,405,'ROOFTOP GARDEN')
inspect(20,'logs',185,280,'STACKED FIREWOOD','Logs are stacked clear of the snow. Air between the pieces helps the wood dry before burning.')
inspect(21,'lighthouse',435,200,'LIGHTHOUSE','The tower rises above the sea mist. Its high position gives the light a longer reach across the water.')
garden(21,550,330,'GREENHOUSE')
inspect(22,'pump',250,320,'WATER PUMP','A hand-operated pump draws water beside the channels. Damp stone traces the route of every spill.')
inspect(23,'fountain',315,365,'OLD FOUNTAIN','Plants grow between the stones of the basin. Nature has long since reclaimed this fountain.')
inspect(24,'timber',285,220,'TIMBER STACK','Freshly cut ends show the growth rings of the trees. The logs wait beside the mill for sawing.')
inspect(25,'pipes',420,375,'STEAM PIPES','Heavy pipes run between the buildings. Their bends allow the metal room to expand when heated.')
garden(25,535,345,'GREENHOUSE')
inspect(26,'aircraft',340,230,'AIRCRAFT HULL','The old fuselage now shelters a home. Rounded metal ribs still reveal what this building used to be.')
garden(26,550,260,'GREENHOUSE')
inspect(27,'turntable',290,340,'RAIL TURNTABLE','A rotating section of track lets a locomotive change direction without a wide loop of railway.')
garden(27,560,335,'GREENHOUSE')
inspect(28,'wheel',380,220,'BARN WATERWHEEL','Water from the hillside turns the wheel beside the barn, putting the stream to work.')
garden(28,410,285,'ORCHARD','red-apple')
inspect(29,'carousel',300,365,'OLD CAROUSEL','The ride stands still among the houses. Weather has faded the bright paint beneath its canopy.')
garden(29,480,282,'GREENHOUSE')
inspect(30,'tank',120,210,'WATER TOWER','A raised tank feeds the beds below. The height supplies pressure without a motor at each outlet.',120)
garden(30,330,330)
inspect(31,'sluice',510,365,'SLUICE GATE','The gate controls how much water leaves the reservoir. The narrow channel guides the powerful outflow.')
garden(31,230,390,'GREENHOUSE')
inspect(32,'quarry',405,285,'OPEN QUARRY','Terraces cut into the earth follow the layers of stone. Each ledge gives workers access to another face.')
inspect(33,'wheel',90,390,'WATERWHEEL','The wheel turns at the edge of the marsh. Its broad paddles catch the slow-moving water.')
garden(33,225,320)
inspect(34,'panels',410,360,'SOLAR PANELS','Rows of panels share the clearing with the radio dishes, gathering power beneath the open sky.')
inspect(35,'stream',350,315,'FOREST STREAM','Water slips between the platforms and roots, carrying fallen needles down the slope.')
garden(35,485,235,'GREENHOUSE')
inspect(36,'bus',160,385,'CONVERTED BUS','An old bus now serves as a shelter. Added steps and roof fittings have made it part of the village.')
garden(36,545,195,'GREENHOUSE')
inspect(37,'ferry',100,285,'RUSTING FERRY','Rust follows the old hull\'s seams. The vessel rests against the shore below the mountain houses.')
garden(37,570,310,'GREENHOUSE')
inspect(38,'press',110,315,'FRUIT PRESS','A screw presses the wooden plate down into the barrel, squeezing juice from the fruit inside.')
garden(38,310,420)
inspect(39,'bell',350,235,'BELL TOWER','The open tower lets the sound of a bell carry across the terraces and down the mountain.')
garden(39,450,365,'GREENHOUSE')
inspect(40,'bus',320,210,'WORKSHOP BUS','The old vehicle sits among tools and warm workshop lights, with its traveling days behind it.')
garden(40,545,210,'GREENHOUSE')
inspect(41,'fountain',315,275,'COURTYARD FOUNTAIN','A stone basin anchors the courtyard. Fallen autumn leaves collect along its sheltered edges.')
garden(41,175,350)
inspect(42,'car',580,400,'ABANDONED CAR','This old car hasn\'t moved in some time...',150)
garden(42,145,320)
inspect(43,'firewood',315,410,'WINTER FIREWOOD','A stack of split logs waits beside the path. Keeping it close saves a long walk through the snow.')
inspect(44,'brook',365,410,'GARDEN BROOK','The brook passes below the gardens. Stones break the current into small pools and ripples.')
garden(44,260,330)
inspect(45,'cart',475,420,'MINE CART','A small rail cart carries heavy loads on steel wheels. Its short wheelbase suits the tight bends of a mine.')
inspect(46,'mine',395,180,'ROCK CUTTING','A dark opening has been cut into the cliff. Timber and stone meet where the path reaches the rock face.')
garden(46,390,360)
inspect(47,'boat',220,405,'MARSH BOAT','A shallow hull can cross water too thin for a larger vessel. Reeds brush against its sides.')
garden(47,300,245,'RAISED GARDEN')
inspect(48,'boat',250,310,'BEACHED ROWBOAT','The boat rests above the waterline, its wooden hull exposed for drying and repairs.')
garden(48,70,250)
inspect(49,'cart',125,375,'ORE CART','Dust coats the cart beside the track. Its sturdy sides keep loose rock contained on the journey out of the mine.')
inspect(50,'channel',220,280,'GARDEN CHANNEL','A narrow watercourse links the planted terraces. Small changes in height carry water from bed to bed.')
garden(50,285,400)

function Hotspots.definitions(location)
    -- The campaign has 50 stops; do not wrap unknown artwork onto unrelated scenes.
    return definitions[tonumber(location)] or {}
end
function Hotspots.find(data,id)
    if not data or data.scene~='stop' or Home.isHome(data) then return nil end
    for _,spot in ipairs(Hotspots.definitions(data.location)) do if spot.id==id then return spot end end
end
function Hotspots.inReach(spot,player)
    return spot and player and (spot.x-player.x)^2+(spot.y-player.y)^2<(spot.radius or Hotspots.radius)^2
end
function Hotspots.nearest(data,player)
    if not data or data.scene~='stop' or Home.isHome(data) then return nil end
    local best,distance
    for _,spot in ipairs(Hotspots.definitions(data.location)) do
        if spot.kind=='stopInspect' and Hotspots.inReach(spot,player) then
            local d=(spot.x-player.x)^2+(spot.y-player.y)^2
            if not distance or d<distance then best,distance=spot,d end
        end
    end
    return best
end
function Hotspots.ensure(data)
    if Home.isHome(data) then return end
    data.droppedItems=data.droppedItems or {}
    local added=false
    for _,spot in ipairs(Hotspots.definitions(data.location)) do if spot.kind=='harvest' then
        local fixture
        for _,item in ipairs(data.droppedItems) do
            if item.scene=='stop' and item.location==data.location and item.stopHotspotId==spot.id then fixture=item;break end
        end
        if not fixture then
            fixture={storage={},scene='stop',location=data.location,stopHotspotId=spot.id}
            for slot=1,spot.count do fixture.storage[slot]=spot.crop end
            data.droppedItems[#data.droppedItems+1]=fixture;added=true
        end
        fixture.name='garden-harvest';fixture.permanent=true;fixture.x=spot.x;fixture.y=spot.y
        fixture.storageLabel=spot.title;fixture.storage=fixture.storage or {}
    end end
    if added then assert(require('game.coop_entities').ensure(data)) end
end
function Hotspots.draw(data,clock,player,selected)
    if not data or data.scene~='stop' or Home.isHome(data) then return end
    local options={player=player,saveData=data}
    for _,spot in ipairs(Hotspots.definitions(data.location)) do
        if not selected or selected.x~=spot.x or selected.y~=spot.y then
            Beacon.drawUnderlay(spot,clock,options)
            Beacon.drawOverlay(spot,clock,options)
        end
    end
end
return Hotspots
