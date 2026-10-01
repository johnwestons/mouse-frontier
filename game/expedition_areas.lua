local Areas = {}

Areas.SCENE = "expedition"
Areas.FIRST_STOP = 5
Areas.SURFACE_ID = "stop06-outskirts"
Areas.DUNGEON_ID = "stop06-buried-waystation"
Areas.BADLANDS_SURFACE_ID = "stop05-badlands-approach"
Areas.BADLANDS_BASIN_ID = "stop05-redwash-basin"
Areas.CONTENT_VERSION = 3

local definitions = {
    [Areas.BADLANDS_SURFACE_ID] = {
        id=Areas.BADLANDS_SURFACE_ID,
        stop=5,
        kind="surface",
        name="Red Mesa Approach",
        width=1672,
        height=941,
        background="assets/sprites/expeditions/stop05/badlands-approach-background.png",
        walkMask="assets/sprites/expeditions/stop05/walkmask-badlands-approach.png",
        version=2,
        objectives={
            surface="Follow the dry wash into Redwash Basin.",
            complete="Survey the basin cairns, then return to Stop 5.",
        },
        spawns={town={x=836,y=700},basinReturn={x=1418,y=188}},
        clearings={
            {x=836,y=700,rx=56,ry=54},
            {x=920,y=565,rx=58,ry=50},
            {x=1160,y=390,rx=55,ry=48},
            {x=1264,y=397,rx=58,ry=55},
            {x=1302,y=361,rx=48,ry=46},
            {x=1460,y=150,rx=58,ry=62},
        },
        corridors={
            {x1=836,y1=748,x2=836,y2=700,r=44},
            {x1=836,y1=700,x2=849,y2=663,r=44},
            {x1=849,y1=663,x2=876,y2=614,r=44},
            {x1=876,y1=614,x2=914,y2=565,r=44},
            {x1=914,y1=565,x2=953,y2=518,r=44},
            {x1=953,y1=518,x2=1014,y2=476,r=44},
            {x1=1014,y1=476,x2=1074,y2=436,r=44},
            {x1=1074,y1=436,x2=1137,y2=399,r=44},
            {x1=1137,y1=399,x2=1200,y2=362,r=44},
            {x1=1200,y1=362,x2=1262,y2=322,r=44},
            {x1=1262,y1=322,x2=1325,y2=274,r=52},
            {x1=1325,y1=274,x2=1387,y2=220,r=44},
            {x1=1387,y1=220,x2=1450,y2=168,r=44},
            {x1=1450,y1=168,x2=1492,y2=118,r=44},
            {x1=1200,y1=362,x2=1264,y2=397,r=48},
            {x1=1264,y1=397,x2=1302,y2=361,r=52},
            {x1=1302,y1=361,x2=1325,y2=274,r=52},
            {x1=1020,y1=474,x2=1115,y2=478,r=44},
            {x1=1115,y1=478,x2=1208,y2=446,r=44},
            {x1=1208,y1=446,x2=1265,y2=397,r=44},
        },
        interactions={
            {id="return-stop-5",kind="returnStop",x=836,y=700,radius=72,label="RETURN TO STOP 5"},
            {id="surface-cache",kind="chest",chestId="surface-cache",x=1264,y=397,radius=62,label="SEARCH SUPPLY CACHE",
                contents={"food-ration","water-bottle","field-bandage-roll"}},
            {id="basin-entrance",kind="enterArea",target=Areas.BADLANDS_BASIN_ID,spawn="surface",x=1460,y=150,radius=66,
                label="ENTER REDWASH BASIN",mapLabel="BASIN"},
        },
        mobs={
            {id="surface-dust-beetle",file="dust-beetle.png",name="Dust Beetle",x=920,y=565,maxHp=13,tier="easy",packId="badlands-roamers",
                patrol={{x=876,y=614},{x=914,y=565},{x=953,y=518}}},
            {id="surface-cactus-rat",file="cactus-rat.png",name="Cactus Rat",x=1160,y=390,maxHp=14,tier="easy",
                patrol={{x=1137,y=399},{x=1200,y=362},{x=1264,y=397}}},
        },
    },
    [Areas.BADLANDS_BASIN_ID] = {
        id=Areas.BADLANDS_BASIN_ID,
        stop=5,
        kind="wilderness",
        progressType="survey",
        name="Redwash Basin",
        width=1672,
        height=941,
        background="assets/sprites/expeditions/stop05/redwash-basin-background.png",
        walkMask="assets/sprites/expeditions/stop05/walkmask-redwash-basin.png",
        version=1,
        objectives={
            explore="Mark the three cairns. Take the high ridge when the wash floods.",
            complete="The basin route is surveyed. Return to Stop 5 when ready.",
        },
        completionRequiredMarkers={"north-cairn","wash-cairn","arch-cairn"},
        completionMessage="All three cairns are marked. The basin route is mapped.",
        environment={
            kind="flashFlood",cycle=34,warningAt=10,floodAt=14,floodEnds=22,recedesAt=25,
            floodZone={radius=72,safeBanks={{x=690,y=515},{x=1015,y=510}},
                points={{x=770,y=500},{x=850,y=500},{x=935,y=506}}},
        },
        spawns={surface={x=60,y=600}},
        clearings={
            {x=60,y=600,rx=64,ry=58},
            {x=360,y=180,rx=54,ry=46},
            {x=450,y=720,rx=58,ry=50},
            {x=750,y=110,rx=62,ry=48},
            {x=900,y=500,rx=68,ry=58},
            {x=1120,y=300,rx=56,ry=48},
            {x=1580,y=320,rx=58,ry=48},
            {x=1610,y=410,rx=64,ry=56},
            {x=530,y=180,rx=55,ry=48},
            {x=620,y=515,rx=58,ry=50},
            {x=1170,y=515,rx=58,ry=50},
            {x=450,y=340,rx=52,ry=46},
        },
        corridors={
            {x1=60,y1=600,x2=170,y2=650,r=54},
            {x1=170,y1=650,x2=300,y2=630,r=54},
            {x1=300,y1=630,x2=410,y2=555,r=54},
            {x1=410,y1=555,x2=570,y2=515,r=58},
            {x1=570,y1=515,x2=770,y2=500,r=58},
            {x1=770,y1=500,x2=850,y2=500,r=58},
            {x1=850,y1=500,x2=935,y2=506,r=58},
            {x1=935,y1=506,x2=1080,y2=515,r=58},
            {x1=1080,y1=515,x2=1270,y2=470,r=58},
            {x1=1270,y1=470,x2=1450,y2=430,r=58},
            {x1=1450,y1=430,x2=1610,y2=410,r=58},
            {x1=300,y1=630,x2=280,y2=500,r=52},
            {x1=280,y1=500,x2=270,y2=370,r=52},
            {x1=270,y1=370,x2=220,y2=250,r=52},
            {x1=220,y1=250,x2=220,y2=180,r=52},
            {x1=220,y1=180,x2=380,y2=180,r=52},
            {x1=380,y1=180,x2=530,y2=180,r=52},
            {x1=530,y1=180,x2=650,y2=140,r=52},
            {x1=650,y1=140,x2=750,y2=110,r=52},
            {x1=750,y1=110,x2=900,y2=145,r=52},
            {x1=900,y1=145,x2=1030,y2=205,r=52},
            {x1=1030,y1=205,x2=1120,y2=300,r=52},
            {x1=1120,y1=300,x2=1270,y2=315,r=52},
            {x1=1270,y1=315,x2=1430,y2=345,r=52},
            {x1=1430,y1=345,x2=1580,y2=320,r=52},
            {x1=1580,y1=320,x2=1610,y2=410,r=52},
            {x1=300,y1=630,x2=345,y2=720,r=48},
            {x1=345,y1=720,x2=450,y2=720,r=48},
            {x1=280,y1=500,x2=380,y2=440,r=45},
            {x1=380,y1=440,x2=450,y2=340,r=45},
            {x1=450,y1=340,x2=500,y2=250,r=45},
            {x1=500,y1=250,x2=530,y2=180,r=45},
        },
        interactions={
            {id="return-approach",kind="enterArea",target=Areas.BADLANDS_SURFACE_ID,spawn="basinReturn",x=60,y=600,radius=72,
                label="RETURN TO RED MESA",mapLabel="APPROACH"},
            {id="western-stash",kind="chest",chestId="western-stash",x=360,y=180,radius=58,label="SEARCH RIDGE STASH",mapLabel="STASH",
                contents={"water-bottle","field-bandage-roll"}},
            {id="fossil-cache",kind="chest",chestId="fossil-cache",x=450,y=720,radius=58,label="SEARCH FOSSIL CACHE",mapLabel="CACHE",
                contents={"food-ration","small-oil-canister"}},
            {id="north-cairn",kind="survey",markerId="north-cairn",x=750,y=110,radius=54,label="MARK NORTH CAIRN",mapLabel="CAIRN"},
            {id="wash-cairn",kind="survey",markerId="wash-cairn",x=900,y=500,radius=58,label="MARK WASH CAIRN",mapLabel="CAIRN"},
            {id="arch-cairn",kind="survey",markerId="arch-cairn",x=1580,y=320,radius=56,label="MARK ARCH CAIRN",mapLabel="CAIRN"},
            {id="basin-exit",kind="enterArea",target=Areas.BADLANDS_SURFACE_ID,spawn="basinReturn",x=1610,y=410,radius=68,
                label="RETURN TO RED MESA",mapLabel="EXIT"},
        },
        mobs={
            {id="basin-dust-beetle",file="dust-beetle.png",name="Dust Beetle",x=530,y=180,maxHp=15,tier="easy",packId="redwash-scavengers",
                patrol={{x=380,y=180},{x=530,y=180},{x=650,y=140}}},
            {id="basin-cactus-rat",file="cactus-rat.png",name="Cactus Rat",x=620,y=515,maxHp=16,tier="easy",
                patrol={{x=410,y=555},{x=620,y=515},{x=770,y=500}}},
            {id="basin-scorpion",file="wasteland-scorpion.png",name="Wasteland Scorpion",x=1170,y=515,maxHp=19,tier="easy",
                patrol={{x=1080,y=515},{x=1170,y=515},{x=1270,y=470}}},
        },
    },
    [Areas.SURFACE_ID] = {
        id=Areas.SURFACE_ID,
        stop=6,
        kind="surface",
        name="Riverwood Outskirts",
        width=1672,
        height=941,
        background="assets/sprites/expeditions/stop06/outskirts-background.png",
        walkMask="assets/sprites/expeditions/stop06/walkmask-outskirts.png",
        version=2,
        objectives={
            surface="Search the cache, then enter the waystation.",
            gateClosed="Defeat both wardens to open the gate.",
            bossReady="Weaken or challenge the Buried Host.",
            complete="Search the vault and return to the surface.",
        },
        tutorialText="Strike, then move out of the red attack ring. Enemy hits begin turn-based combat with all damage carried over. Clean field victories earn the same rewards. Open AREA MAP to find the waystation.",
        completionMessage="The Buried Host is defeated. The corruption vault is open!",
        spawns={town={x=836,y=842},dungeonReturn={x=1452,y=250}},
        clearings={
            {x=720,y=140,rx=115,ry=55},
            {x=1520,y=467,rx=45,ry=28},
        },
        corridors={
            -- Footpaths traced against the painted ground; bridge decks have
            -- their own narrow corridors instead of a clearing over water.
            {x1=836,y1=878,x2=839,y2=778,r=23},
            {x1=839,y1=778,x2=801,y2=704,r=28},
            {x1=801,y1=704,x2=879,y2=639,r=28},
            {x1=879,y1=639,x2=870,y2=551,r=30},
            {x1=870,y1=551,x2=949,y2=484,r=29},
            {x1=949,y1=484,x2=945,y2=405,r=29},
            {x1=945,y1=405,x2=879,y2=329,r=30},
            {x1=879,y1=329,x2=897,y2=268,r=29},
            {x1=897,y1=268,x2=1000,y2=301,r=29},
            {x1=1000,y1=301,x2=1197,y2=303,r=30},
            {x1=1197,y1=303,x2=1340,y2=283,r=27},
            {x1=1340,y1=283,x2=1452,y2=250,r=28},
            {x1=1452,y1=250,x2=1457,y2=218,r=28},
            {x1=897,y1=268,x2=790,y2=218,r=28},
            {x1=790,y1=218,x2=724,y2=151,r=30},
            {x1=945,y1=445,x2=1038,y2=447,r=25},
            {x1=1038,y1=447,x2=1114,y2=466,r=18},
            {x1=1114,y1=466,x2=1202,y2=454,r=19},
            {x1=1202,y1=454,x2=1320,y2=479,r=25},
            {x1=1320,y1=479,x2=1467,y2=476,r=24},
            {x1=1467,y1=476,x2=1520,y2=467,r=25},
            {x1=801,y1=704,x2=703,y2=627,r=27},
            {x1=703,y1=627,x2=591,y2=589,r=30},
            {x1=591,y1=589,x2=469,y2=551,r=29},
            {x1=469,y1=551,x2=365,y2=501,r=28},
            {x1=365,y1=501,x2=355,y2=421,r=25},
            {x1=591,y1=589,x2=694,y2=529,r=26},
            {x1=694,y1=529,x2=870,y2=551,r=28},
        },
        interactions={
            {id="return-town",kind="returnStop",x=836,y=856,radius=82,label="RETURN TO STOP"},
            {id="surface-cache",kind="chest",chestId="surface-cache",x=1520,y=467,radius=64,label="SEARCH RUIN CHEST",mapLabel="CACHE",
                contents={"food-ration","water-bottle","field-bandage-roll"}},
            {id="dungeon-entrance",kind="enterArea",target=Areas.DUNGEON_ID,spawn="surface",x=1457,y=218,radius=68,label="ENTER BURIED WAYSTATION",mapLabel="WAYSTATION"},
        },
        mobs={
            {id="surface-bandit-a",file="sludge-bandit.png",name="Sludge-Taken Bandit",x=694,y=529,maxHp=18,tier="easy",packId="surface-bandits",
                patrol={{x=591,y=589},{x=703,y=627},{x=870,y=551}}},
            {id="surface-bandit-b",file="sludge-bandit.png",name="Sludge-Taken Bandit",x=1080,y=302,maxHp=18,tier="easy",packId="surface-bandits",
                patrol={{x=1000,y=301},{x=1197,y=303},{x=1340,y=283}}},
        },
    },
    [Areas.DUNGEON_ID] = {
        id=Areas.DUNGEON_ID,
        stop=6,
        kind="dungeon",
        name="Buried Waystation",
        width=1672,
        height=941,
        background="assets/sprites/expeditions/stop06/buried-waystation-background.png",
        walkMask="assets/sprites/expeditions/stop06/walkmask-buried-waystation.png",
        version=2,
        objectives={
            surface="Find the waystation cache and return to the outskirts.",
            gateClosed="Defeat both wardens to open the gate.",
            bossReady="Weaken or challenge the Buried Host.",
            complete="Search the vault and return to the surface.",
        },
        completionMessage="The Buried Host is defeated. The corruption vault is open!",
        sealedCacheMessage="The corruption vault is sealed. Defeat the guardian to open it.",
        bossInteractionLabel="CHALLENGE THE BURIED HOST",
        spawns={surface={x=135,y=405}},
        clearings={
            {x=390,y=424,rx=97,ry=38},
            {x=460,y=160,rx=48,ry=28},
            {x=826,y=220,rx=102,ry=52},
            {x=883,y=699,rx=80,ry=34},
            {x=1430,y=460,rx=150,ry=116,gate="bossGateOpen"},
            {x=1480,y=150,rx=52,ry=28,gate="bossDefeated"},
        },
        corridors={
            {x1=110,y1=405,x2=245,y2=419,r=25},
            {x1=245,y1=419,x2=405,y2=430,r=28},
            {x1=405,y1=430,x2=551,y2=410,r=29},
            {x1=551,y1=410,x2=649,y2=321,r=25},
            {x1=649,y1=321,x2=752,y2=251,r=27},
            {x1=752,y1=251,x2=850,y2=211,r=28},
            {x1=850,y1=211,x2=975,y2=177,r=27},
            {x1=405,y1=430,x2=501,y2=309,r=24},
            {x1=501,y1=309,x2=488,y2=230,r=20},
            {x1=488,y1=230,x2=460,y2=160,r=22},
            {x1=551,y1=410,x2=620,y2=538,r=26},
            {x1=620,y1=538,x2=764,y2=593,r=27},
            {x1=764,y1=593,x2=850,y2=690,r=27},
            {x1=850,y1=690,x2=968,y2=708,r=25},
            {x1=620,y1=538,x2=784,y2=479,r=27},
            {x1=784,y1=479,x2=966,y2=490,r=25},
            {x1=966,y1=490,x2=991,y2=490,r=18},
            {x1=991,y1=490,x2=1149,y2=478,r=24,gate="bossGateOpen"},
            {x1=1149,y1=478,x2=1296,y2=479,r=25,gate="bossGateOpen"},
            {x1=1296,y1=479,x2=1430,y2=460,r=29,gate="bossGateOpen"},
            {x1=1430,y1=370,x2=1455,y2=270,r=24,gate="bossDefeated"},
            {x1=1455,y1=270,x2=1460,y2=185,r=23,gate="bossDefeated"},
            {x1=1460,y1=185,x2=1480,y2=150,r=24,gate="bossDefeated"},
        },
        interactions={
            {id="return-surface",kind="enterArea",target=Areas.SURFACE_ID,spawn="dungeonReturn",x=110,y=405,radius=86,label="RETURN TO OUTSKIRTS",mapLabel="SURFACE"},
            {id="dungeon-cache",kind="chest",chestId="dungeon-cache",x=460,y=160,radius=64,label="SEARCH WAYSTATION CACHE",mapLabel="CACHE",
                contents={"healing-salve","medium-oil-canister","9mm"}},
            {id="boss-vault",kind="chest",chestId="boss-vault",x=1480,y=150,radius=64,label="OPEN CORRUPTION VAULT",mapLabel="VAULT",requires="bossDefeated",
                lockedMessage="The corruption vault is sealed. Defeat the guardian to open it.",
                contents={"frontier-curved-saber","red-potion-vial","large-oil-canister"}},
        },
        gateRequired={"dungeon-bandit-a","dungeon-bandit-b"},
        mobs={
            {id="dungeon-bandit-a",file="sludge-bandit.png",name="Sludge-Taken Bandit",x=752,y=251,maxHp=22,tier="medium",packId="waystation-bandits",gateRequired=true,
                patrol={{x=649,y=321},{x=850,y=211},{x=900,y=195}}},
            {id="dungeon-bandit-b",file="sludge-bandit.png",name="Sludge-Taken Bandit",x=883,y=699,maxHp=22,tier="medium",packId="waystation-bandits",gateRequired=true,
                patrol={{x=764,y=593},{x=850,y=690},{x=968,y=708}}},
            {id="sludge-badger-boss",file="sludge-badger-boss.png",name="The Buried Host",x=1430,y=460,maxHp=58,tier="medium",boss=true,packId="buried-host",requires="bossGateOpen",
                awareness=225,reach=112,speed=44,patrol={{x=1350,y=442},{x=1490,y=490}}},
        },
    },
}

local stopEntrances={
    [5]={id="explore-badlands",kind="enterArea",target=Areas.BADLANDS_SURFACE_ID,spawn="town",x=875,y=367,radius=86,
        label="EXPLORE BADLANDS",signLabel="BADLANDS"},
    [6]={id="explore-outskirts",kind="enterArea",target=Areas.SURFACE_ID,spawn="town",x=875,y=367,radius=86,
        label="EXPLORE OUTSKIRTS",signLabel="OUTSKIRTS"},
}
local initialized=setmetatable({},{__mode="k"})
local navigation={}
local walkMasks={}

local function finite(value,fallback)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return fallback end
    return value
end

local function copyArray(values)
    local result={}
    for i,value in ipairs(values or {}) do result[i]=value end
    return result
end

local function distance(ax,ay,bx,by)
    local dx,dy=bx-ax,by-ay
    return math.sqrt(dx*dx+dy*dy)
end

local function pointSegmentDistance(px,py,x1,y1,x2,y2)
    local dx,dy=x2-x1,y2-y1
    local lengthSquared=dx*dx+dy*dy
    if lengthSquared<=.0001 then return distance(px,py,x1,y1) end
    local t=math.max(0,math.min(1,((px-x1)*dx+(py-y1)*dy)/lengthSquared))
    return distance(px,py,x1+dx*t,y1+dy*t)
end

function Areas.definition(areaId)
    return definitions[areaId]
end

function Areas.availableAtStop(stop)
    return stopEntrances[tonumber(stop)]~=nil
end

function Areas.isArea(areaId)
    return definitions[areaId]~=nil
end

function Areas.current(data)
    return data and definitions[data.activeExpeditionArea]
end

function Areas.ensure(data)
    if type(data)~="table" then return nil end
    if initialized[data]==data.expeditions and type(data.expeditions)=="table" then return data.expeditions end
    data.expeditions=type(data.expeditions)=="table" and data.expeditions or {}
    local revisions={}
    for areaId,definition in pairs(definitions) do
        local state=data.expeditions[areaId]
        if type(state)~="table" then state={}; data.expeditions[areaId]=state end
        state.discovered=state.discovered==true
        state.completed=state.completed==true
        state.mobs=type(state.mobs)=="table" and state.mobs or {}
        state.chests=type(state.chests)=="table" and state.chests or {}
        state.markers=type(state.markers)=="table" and state.markers or {}
        state.gates=type(state.gates)=="table" and state.gates or {}
        local revised=(tonumber(state.contentVersion) or 0)<(definition.version or 1)
        if revised then revisions[areaId]=true end
        for _,mob in ipairs(definition.mobs or {}) do
            local saved=state.mobs[mob.id]
            if type(saved)~="table" then saved={}; state.mobs[mob.id]=saved end
            saved.x=revised and mob.x or finite(saved.x,mob.x)
            saved.y=revised and mob.y or finite(saved.y,mob.y)
            saved.maxHp=math.max(1,finite(saved.maxHp,mob.maxHp))
            saved.hp=math.max(0,math.min(saved.maxHp,finite(saved.hp,saved.maxHp)))
            saved.dead=saved.dead==true or saved.hp<=0
            saved.rewardResolved=saved.rewardResolved==true
            saved.file=mob.file
            saved.name=mob.name
        end
        for _,interaction in ipairs(definition.interactions or {}) do
            if interaction.kind=="chest" then
                local chest=state.chests[interaction.chestId]
                if type(chest)~="table" then chest={}; state.chests[interaction.chestId]=chest end
                chest.name=chest.name or "travel-chest"
                chest.storage=type(chest.storage)=="table" and chest.storage or copyArray(interaction.contents)
                chest.opened=chest.opened==true
                chest.permanent=true
                chest.expeditionChest=true
            end
        end
        state.contentVersion=definition.version or 1
    end
    if data.activeExpeditionArea and not definitions[data.activeExpeditionArea] then data.activeExpeditionArea=nil end
    initialized[data]=data.expeditions
    local pending=data.expeditionBattle
    local battle=type(pending)=="table" and pending.battle
    local encounter=type(battle)=="table" and battle.encounter
    local destination=type(encounter)=="table" and encounter.returnContext
    if type(destination)=="table" and revisions[destination.areaId]
        and finite(destination.x) and finite(destination.y) then
        -- A versioned map repair may remove the old ground. Only migration
        -- repairs that obsolete return point; ordinary victories remain exact.
        destination.x,destination.y=Areas.clamp(data,destination.areaId,destination.x,destination.y)
    end
    return data.expeditions
end

function Areas.state(data,areaId)
    Areas.ensure(data)
    return data and data.expeditions and data.expeditions[areaId]
end

function Areas.mobDefinition(area,mobId)
    area=type(area)=="table" and area or definitions[area]
    for _,mob in ipairs(area and area.mobs or {}) do if mob.id==mobId then return mob end end
end

function Areas.updateGates(data,areaId)
    local area=definitions[areaId]
    local state=area and Areas.state(data,areaId)
    if not state then return nil end
    if area.gateRequired then
        local open=true
        for _,mobId in ipairs(area.gateRequired) do
            local mob=state.mobs[mobId]
            if mob and not mob.dead then open=false; break end
        end
        state.gates.bossGateOpen=open
    end
    local hasBoss,allDefeated=false,true
    for _,definition in ipairs(area.mobs or {}) do
        if definition.boss then
            hasBoss=true
            if not state.mobs[definition.id].dead then allDefeated=false end
        end
    end
    state.gates.bossDefeated=hasBoss and allDefeated
    if state.gates.bossDefeated then state.completed=true end
    if area.completionRequiredMarkers then
        local marked=0
        for _,markerId in ipairs(area.completionRequiredMarkers) do
            if state.markers[markerId]==true then marked=marked+1 end
        end
        state.gates.routeSurveyed=marked>=#area.completionRequiredMarkers
        if state.gates.routeSurveyed then state.completed=true end
    end
    return state.gates
end

local function hazardPhase(area,elapsed)
    local environment=area and area.environment
    if not environment then return "dry" end
    local phase=(elapsed or 0)%environment.cycle
    if phase>=environment.floodAt and phase<environment.floodEnds then return "flooded" end
    if phase>=environment.warningAt and phase<environment.floodAt then return "warning" end
    if phase>=environment.floodEnds and phase<environment.recedesAt then return "receding" end
    return "dry"
end

function Areas.resetEnvironment(data,areaId)
    local area=definitions[areaId]
    if not area or not area.environment then return end
    local state=Areas.state(data,areaId)
    state.environmentClock=0
    state.environmentPhase="dry"
end

function Areas.updateEnvironment(data,areaId,dt)
    local area=definitions[areaId]
    if not area or not area.environment then return nil,false end
    local state=Areas.state(data,areaId)
    local previous=state.environmentPhase or hazardPhase(area,state.environmentClock)
    state.environmentClock=((tonumber(state.environmentClock) or 0)+math.max(0,tonumber(dt) or 0))%area.environment.cycle
    state.environmentPhase=hazardPhase(area,state.environmentClock)
    return state.environmentPhase,previous~=state.environmentPhase
end

function Areas.environment(data,areaId)
    local area=definitions[areaId]
    if not area or not area.environment then return nil end
    local state=Areas.state(data,areaId)
    local phase=state.environmentPhase or hazardPhase(area,state.environmentClock)
    return {kind=area.environment.kind,phase=phase,flooded=phase=="flooded",definition=area.environment}
end

local function insideFloodZone(zone,x,y)
    if not zone then return false end
    for i=1,#zone.points-1 do
        local a,b=zone.points[i],zone.points[i+1]
        if pointSegmentDistance(x,y,a.x,a.y,b.x,b.y)<=zone.radius then return true end
    end
    return false
end

function Areas.isInFlood(data,areaId,x,y)
    local area=definitions[areaId]
    local state=area and Areas.state(data,areaId)
    return state and state.environmentPhase=="flooded" and insideFloodZone(area.environment and area.environment.floodZone,x,y) or false
end

function Areas.nearestFloodBank(data,areaId,x,y)
    local area=definitions[areaId]
    local banks=area and area.environment and area.environment.floodZone and area.environment.floodZone.safeBanks
    if not banks then return nil end
    local best,bestDistance
    for _,bank in ipairs(banks) do
        if Areas.isWalkable(data,areaId,bank.x,bank.y) then
            local d=distance(x,y,bank.x,bank.y)
            if not bestDistance or d<bestDistance then best,bestDistance=bank,d end
        end
    end
    return best and best.x,best and best.y
end

local function gateOpen(state,gate)
    if not gate then return true end
    return state and state.gates and state.gates[gate]==true
end

local function walkMask(area)
    if not area.walkMask or not (love and love.image and love.image.newImageData) then return nil end
    if walkMasks[area.walkMask]==nil then
        local ok,mask=pcall(love.image.newImageData,area.walkMask)
        walkMasks[area.walkMask]=ok and mask or false
    end
    return walkMasks[area.walkMask] or nil
end

local function insideClearing(clearing,x,y)
    local rx,ry=clearing.rx or clearing.r,clearing.ry or clearing.r
    return ((x-clearing.x)/rx)^2+((y-clearing.y)/ry)^2<=1
end

local function insideCorridor(corridor,x,y)
    return pointSegmentDistance(x,y,corridor.x1,corridor.y1,corridor.x2,corridor.y2)<=corridor.r
end

local function authoredWalkable(area,state,x,y)
    for _,clearing in ipairs(area.clearings or {}) do
        if gateOpen(state,clearing.gate) and insideClearing(clearing,x,y) then return true end
    end
    for _,corridor in ipairs(area.corridors or {}) do
        if gateOpen(state,corridor.gate) and insideCorridor(corridor,x,y) then return true end
    end
    return false
end

local function gateBlocked(area,state,x,y)
    -- Masks own the ground; only progression locks still use authored regions.
    -- Shared endpoints must remain accessible from the open side of a gate.
    for _,clearing in ipairs(area.clearings or {}) do
        if clearing.gate and not gateOpen(state,clearing.gate) and insideClearing(clearing,x,y) then
            return not authoredWalkable(area,state,x,y)
        end
    end
    for _,corridor in ipairs(area.corridors or {}) do
        if corridor.gate and not gateOpen(state,corridor.gate) and insideCorridor(corridor,x,y) then
            return not authoredWalkable(area,state,x,y)
        end
    end
    return false
end

function Areas.isWalkable(data,areaId,x,y)
    local area=definitions[areaId]
    if not area or x<24 or y<24 or x>area.width-24 or y>area.height-24 then return false end
    local state=Areas.state(data,areaId)
    Areas.updateGates(data,areaId)
    if Areas.isInFlood(data,areaId,x,y) then return false end
    local mask=walkMask(area)
    if mask then
        local mw,mh=mask:getDimensions()
        local function sample(px,py)
            local ix=math.max(0,math.min(mw-1,math.floor(px/area.width*mw)))
            local iy=math.max(0,math.min(mh-1,math.floor(py/area.height*mh)))
            -- Match stop masks: white/red > .5 permits the player's feet.
            return select(1,mask:getPixel(ix,iy))>.5 and not gateBlocked(area,state,px,py)
        end
        local radius=6
        return sample(x,y) and sample(x-radius,y) and sample(x+radius,y)
            and sample(x,y-radius) and sample(x,y+radius)
    end
    -- Keep the authored geometry available to headless tools and missing assets.
    return authoredWalkable(area,state,x,y)
end

function Areas.clamp(data,areaId,x,y)
    local area=definitions[areaId]
    if not area then return x,y end
    local fallback
    for _,spawn in pairs(area.spawns or {}) do fallback=spawn; break end
    x=math.max(24,math.min(area.width-24,tonumber(x) or (fallback and fallback.x) or 100))
    y=math.max(24,math.min(area.height-24,tonumber(y) or (fallback and fallback.y) or 100))
    if Areas.isWalkable(data,areaId,x,y) then return x,y end
    for radius=8,420,8 do
        for step=0,31 do
            local angle=step/32*math.pi*2
            local nx,ny=x+math.cos(angle)*radius,y+math.sin(angle)*radius
            if Areas.isWalkable(data,areaId,nx,ny) then return nx,ny end
        end
    end
    return fallback and fallback.x or 100,fallback and fallback.y or 100
end

function Areas.move(data,areaId,oldX,oldY,newX,newY)
    -- Substeps prevent sprinting or a long frame from hopping over a river.
    local steps=math.max(1,math.ceil(distance(oldX,oldY,newX,newY)/6))
    local dx,dy=(newX-oldX)/steps,(newY-oldY)/steps
    local x,y=oldX,oldY
    for _=1,steps do
        if Areas.isWalkable(data,areaId,x+dx,y+dy) then x,y=x+dx,y+dy
        elseif Areas.isWalkable(data,areaId,x+dx,y) then x=x+dx
        elseif Areas.isWalkable(data,areaId,x,y+dy) then y=y+dy end
    end
    return x,y
end

function Areas.canReach(data,areaId,x1,y1,x2,y2)
    local steps=math.max(1,math.ceil(distance(x1,y1,x2,y2)/7))
    for i=0,steps do
        local t=i/steps
        if not Areas.isWalkable(data,areaId,x1+(x2-x1)*t,y1+(y2-y1)*t) then return false end
    end
    return true
end

function Areas.isMobActive(data,areaId,mob)
    return gateOpen(Areas.state(data,areaId),mob.requires)
end

local function navigationGraph(data,areaId)
    local area=definitions[areaId]
    if not area then return end
    local gates=Areas.updateGates(data,areaId)
    local environment=Areas.environment(data,areaId)
    local key=areaId..":"..tostring(gates.bossGateOpen)..":"..tostring(gates.bossDefeated)
        ..":"..tostring(environment and environment.flooded or false)
    if navigation[key] then return navigation[key] end
    local nodes={}
    local function add(x,y)
        if not Areas.isWalkable(data,areaId,x,y) then return end
        for _,node in ipairs(nodes) do if distance(x,y,node.x,node.y)<4 then return end end
        nodes[#nodes+1]={x=x,y=y,edges={}}
    end
    for _,corridor in ipairs(area.corridors or {}) do add(corridor.x1,corridor.y1); add(corridor.x2,corridor.y2) end
    for _,clearing in ipairs(area.clearings or {}) do add(clearing.x,clearing.y) end
    for i,node in ipairs(nodes) do
        for j=1,i-1 do
            local other=nodes[j]
            if Areas.canReach(data,areaId,node.x,node.y,other.x,other.y) then
                local length=distance(node.x,node.y,other.x,other.y)
                node.edges[j]=length; other.edges[i]=length
            end
        end
    end
    navigation[key]=nodes
    return nodes
end

-- A small visibility graph follows the authored paths around ruins and water.
-- The caller caches the next waypoint briefly while a target is moving.
function Areas.pathTarget(data,areaId,x,y,targetX,targetY)
    if Areas.canReach(data,areaId,x,y,targetX,targetY) then return targetX,targetY end
    local nodes=navigationGraph(data,areaId)
    if not nodes then return nil end
    local cost,previous,visited={},{},{}
    for i,node in ipairs(nodes) do
        if Areas.canReach(data,areaId,x,y,node.x,node.y) then cost[i]=distance(x,y,node.x,node.y) end
    end
    local best,bestCost
    for _=1,#nodes do
        local current,lowest
        for i,value in pairs(cost) do if not visited[i] and (not lowest or value<lowest) then current,lowest=i,value end end
        if not current then break end
        visited[current]=true
        local node=nodes[current]
        if Areas.canReach(data,areaId,node.x,node.y,targetX,targetY) then
            local total=lowest+distance(node.x,node.y,targetX,targetY)
            if not bestCost or total<bestCost then best,bestCost=current,total end
        end
        for i,length in pairs(node.edges) do
            local candidate=lowest+length
            if not cost[i] or candidate<cost[i] then cost[i]=candidate; previous[i]=current end
        end
    end
    if not best then return nil end
    local route={best}
    while previous[best] do best=previous[best]; table.insert(route,1,best) end
    for _,index in ipairs(route) do
        if distance(x,y,nodes[index].x,nodes[index].y)>4 then return nodes[index].x,nodes[index].y end
    end
    return targetX,targetY
end

-- Preserve the original no-argument behavior for callers that still ask for
-- the Stop 6 entrance; new stop-aware callers pass their current location.
function Areas.entrance(stop) return stopEntrances[tonumber(stop) or 6] end

function Areas.cameraOffset(data,player,viewportW,viewportH)
    local area=Areas.current(data)
    if not area or not player then return 0,0 end
    local maxX=math.max(0,area.width-(viewportW or 960))
    local maxY=math.max(0,area.height-(viewportH or 720))
    return math.max(0,math.min(maxX,player.x-(viewportW or 960)/2)),
        math.max(0,math.min(maxY,player.y-(viewportH or 720)/2))
end

function Areas.spawn(areaId,spawnId)
    local area=definitions[areaId]
    local spawn=area and area.spawns and area.spawns[spawnId]
    return spawn and spawn.x,spawn and spawn.y
end

function Areas.interaction(data,scene,player)
    if not data or not player then return nil end
    local stopEntrance=scene=="stop" and Areas.entrance(data.location)
    if scene=="stop" and stopEntrance then
        if distance(player.x,player.y,stopEntrance.x,stopEntrance.y)<=stopEntrance.radius then
            return {kind="expedition",action=stopEntrance.kind,targetArea=stopEntrance.target,spawn=stopEntrance.spawn,
                x=stopEntrance.x,y=stopEntrance.y,radius=stopEntrance.radius,hoverRadius=58,label=stopEntrance.label,id=stopEntrance.id}
        end
        return nil
    end
    if scene~=Areas.SCENE then return nil end
    local area=Areas.current(data)
    if not area then return nil end
    local best,bestDistance
    local state=Areas.state(data,area.id)
    for _,definition in ipairs(area.interactions or {}) do
        local d=distance(player.x,player.y,definition.x,definition.y)
        if d<=definition.radius and Areas.canReach(data,area.id,player.x,player.y,definition.x,definition.y)
            and (not bestDistance or d<bestDistance) then best,bestDistance=definition,d end
    end
    for _,mob in ipairs(area.mobs or {}) do
        local saved=state.mobs[mob.id]
        if mob.boss and not saved.dead and Areas.isMobActive(data,area.id,mob)
            and distance(player.x,player.y,saved.x,saved.y)<=180
            and Areas.canReach(data,area.id,player.x,player.y,saved.x,saved.y) then
            return {kind="expedition",action="challenge",mobId=mob.id,id="challenge-"..mob.id,areaId=area.id,
                x=saved.x,y=saved.y,radius=180,hoverRadius=58,
                label=area.bossInteractionLabel or ("CHALLENGE "..string.upper(mob.name or "THE GUARDIAN"))}
        end
    end
    if not best then return nil end
    return {kind="expedition",action=best.kind,targetArea=best.target,spawn=best.spawn,chestId=best.chestId,markerId=best.markerId,requires=best.requires,
        lockedMessage=best.lockedMessage,x=best.x,y=best.y,radius=best.radius,hoverRadius=58,
        label=best.label,id=best.id,areaId=area.id,mapLabel=best.mapLabel}
end

function Areas.audit()
    local errors={}
    local areaCount,firstStop=0,nil
    for areaId,area in pairs(definitions) do
        areaCount=areaCount+1
        firstStop=not firstStop and area.stop or math.min(firstStop,area.stop)
        if area.id~=areaId then errors[#errors+1]=areaId.." id mismatch" end
        if not area.background or area.width<=960 or area.height<=720 then errors[#errors+1]=areaId.." is not a large authored area" end
        local entrance=stopEntrances[area.stop]
        if area.kind=="surface" and (not entrance or entrance.target~=areaId) then
            errors[#errors+1]=areaId.." has no matching stop entrance"
        end
        local seen={}
        for _,mob in ipairs(area.mobs or {}) do
            if seen[mob.id] then errors[#errors+1]=areaId.." duplicate mob "..mob.id end
            seen[mob.id]=true
        end
        local sample={location=area.stop,activeExpeditionArea=areaId,expeditions={}}
        Areas.ensure(sample)
        for _,saved in pairs(sample.expeditions[areaId].mobs) do saved.dead=true; saved.hp=0 end
        Areas.updateGates(sample,areaId)
        for spawnId,spawn in pairs(area.spawns or {}) do
            if not Areas.isWalkable(sample,areaId,spawn.x,spawn.y) then errors[#errors+1]=areaId.." blocked spawn "..spawnId end
        end
        for _,bank in ipairs(area.environment and area.environment.floodZone and area.environment.floodZone.safeBanks or {}) do
            if not Areas.isWalkable(sample,areaId,bank.x,bank.y) then errors[#errors+1]=areaId.." blocked flood bank" end
        end
        for _,mob in ipairs(area.mobs or {}) do
            if not Areas.isWalkable(sample,areaId,mob.x,mob.y) then errors[#errors+1]=areaId.." blocked mob "..mob.id end
        end
        for _,interaction in ipairs(area.interactions or {}) do
            if not Areas.isWalkable(sample,areaId,interaction.x,interaction.y) then errors[#errors+1]=areaId.." blocked interaction "..interaction.id end
        end
    end
    return {ready=#errors==0,errors=errors,areaCount=areaCount,firstStop=firstStop,curve="expedition-area-v2"}
end

Areas.definitions=definitions
return Areas
