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
        version=3,
        objectives={
            surface="Follow the dry wash into Redwash Basin.",
            complete="Survey the basin cairns, then return to Stop 5.",
        },
        spawns={town={x=836,y=868},basinReturn={x=1395,y=211}},
        clearings={
            {x=836,y=868,rx=41.6,ry=44.2},
            {x=890,y=528,rx=45.5,ry=35.1},
            {x=1318,y=495,rx=45.5,ry=26},
            {x=1410,y=187,rx=39,ry=28.6},
        },
        -- Additive ground regions outlined by the user in the map review.
        walkRegions={
            {id="entrance-west",points={
                {x=803,y=796},{x=790,y=805},{x=776,y=822},{x=766,y=840},
                {x=761,y=858},{x=766,y=877},{x=780,y=894},{x=796,y=905},
                {x=808,y=894},{x=810,y=868},{x=808,y=840},{x=810,y=815},
            },nodes={{x=780,y=861},{x=798,y=828}}},
            {id="entrance-east",points={
                {x=885,y=805},{x=907,y=810},{x=922,y=829},{x=931,y=852},
                {x=930,y=870},{x=918,y=891},{x=900,y=912},{x=883,y=917},
                {x=874,y=905},{x=869,y=878},{x=865,y=851},{x=867,y=822},
            },nodes={{x=894,y=860},{x=888,y=896},{x=890,y=826}}},
            {id="entrance-left-pocket",points={
                {x=733,y=692},{x=756,y=681},{x=779,y=676},{x=796,y=681},
                {x=805,y=700},{x=810,y=722},{x=804,y=737},{x=787,y=742},
                {x=762,y=736},{x=739,y=733},{x=727,y=718},{x=731,y=703},
            },nodes={{x=763,y=710},{x=793,y=711}}},
            {id="entrance-right-shoulder",points={
                {x=833,y=596},{x=846,y=580},{x=856,y=580},{x=869,y=593},
                {x=883,y=614},{x=901,y=640},{x=925,y=667},{x=948,y=694},
                {x=967,y=721},{x=980,y=746},{x=979,y=755},{x=956,y=766},
                {x=935,y=765},{x=907,y=752},{x=881,y=735},{x=875,y=712},
                {x=860,y=683},{x=849,y=659},{x=835,y=632},{x=829,y=610},
            },nodes={{x=851,y=610},{x=866,y=648},{x=883,y=682},{x=911,y=724},{x=951,y=744}}},
            {id="tree-pocket",points={
                {x=688,y=548},{x=716,y=548},{x=745,y=559},{x=763,y=573},
                {x=773,y=596},{x=775,y=614},{x=760,y=628},{x=739,y=629},
                {x=720,y=610},{x=704,y=596},{x=682,y=582},{x=678,y=564},
            },nodes={{x=710,y=568},{x=723,y=586},{x=748,y=605}}},
            {id="supply-camp-floor",points={
                {x=1145,y=433},{x=1164,y=420},{x=1198,y=417},{x=1238,y=423},
                {x=1270,y=434},{x=1307,y=449},{x=1325,y=468},{x=1333,y=485},
                {x=1312,y=493},{x=1280,y=499},{x=1245,y=505},{x=1208,y=500},
                {x=1177,y=492},{x=1157,y=483},{x=1147,y=463},
            },nodes={{x=1175,y=455},{x=1238,y=459},{x=1297,y=478}}},
            {id="supply-camp-ledge",points={
                {x=1250,y=544},{x=1290,y=529},{x=1336,y=513},{x=1373,y=492},
                {x=1402,y=479},{x=1427,y=474},{x=1444,y=480},{x=1452,y=491},
                {x=1451,y=509},{x=1432,y=525},{x=1392,y=540},{x=1351,y=552},
                {x=1309,y=562},{x=1270,y=564},{x=1250,y=555},
            },nodes={{x=1281,y=548},{x=1360,y=530},{x=1418,y=500}}},
            {id="central-rock-pocket",points={
                {x=1008,y=412},{x=1023,y=420},{x=1041,y=435},{x=1070,y=454},
                {x=1080,y=463},{x=1062,y=471},{x=1041,y=475},{x=1024,y=466},
                {x=1009,y=452},{x=1002,y=438},{x=1003,y=422},
            },nodes={{x=1020,y=437},{x=1043,y=448},{x=1047,y=463}}},
            {id="ruined-wall-shoulder",points={
                {x=724,y=299},{x=746,y=292},{x=777,y=296},{x=805,y=314},
                {x=834,y=339},{x=868,y=359},{x=906,y=382},{x=930,y=400},
                {x=940,y=418},{x=931,y=439},{x=911,y=459},{x=906,y=434},
                {x=883,y=414},{x=854,y=398},{x=819,y=380},{x=788,y=356},
                {x=761,y=332},{x=740,y=315},
            },nodes={{x=760,y=310},{x=796,y=335},{x=838,y=366},{x=880,y=394},{x=918,y=420}}},
            {id="upper-east-ledge",points={
                {x=1265,y=304},{x=1295,y=299},{x=1328,y=284},{x=1366,y=265},
                {x=1401,y=245},{x=1431,y=232},{x=1450,y=234},{x=1465,y=247},
                {x=1468,y=262},{x=1455,y=281},{x=1422,y=305},{x=1386,y=326},
                {x=1351,y=344},{x=1312,y=351},{x=1278,y=344},{x=1260,y=331},
                {x=1257,y=315},
            },nodes={{x=1291,y=324},{x=1340,y=312},{x=1370,y=295},{x=1438,y=258}}},
            {id="waystation-shelter",points={
                {x=1204,y=183},{x=1221,y=166},{x=1250,y=154},{x=1275,y=151},
                {x=1291,y=159},{x=1299,y=177},{x=1292,y=190},{x=1276,y=207},
                {x=1268,y=225},{x=1290,y=225},{x=1285,y=236},{x=1241,y=235},
                {x=1218,y=221},{x=1204,y=206},
            },nodes={{x=1250,y=177},{x=1250,y=195},{x=1245,y=222}}},
            {id="upper-ridge-spur",points={
                {x=883,y=127},{x=906,y=109},{x=936,y=96},{x=975,y=85},
                {x=1007,y=84},{x=1027,y=90},{x=1033,y=100},{x=1030,y=112},
                {x=1013,y=130},{x=1005,y=145},{x=1018,y=160},{x=1046,y=179},
                {x=1073,y=193},{x=1115,y=214},{x=1159,y=235},{x=1164,y=243},
                {x=1149,y=254},{x=1126,y=265},{x=1103,y=273},{x=1087,y=260},
                {x=1061,y=240},{x=1026,y=224},{x=987,y=204},{x=954,y=181},
                {x=926,y=161},{x=901,y=148},{x=885,y=141},
            },nodes={{x=1118,y=245},{x=1065,y=216},{x=1015,y=205},{x=978,y=174},{x=937,y=140},{x=954,y=123},{x=1005,y=103}}},
            {id="western-arch-ground",points={
                {x=452,y=291},{x=465,y=263},{x=492,y=241},{x=531,y=220},
                {x=577,y=201},{x=630,y=179},{x=656,y=177},{x=677,y=188},
                {x=699,y=222},{x=712,y=257},{x=712,y=278},{x=699,y=309},
                {x=681,y=336},{x=657,y=363},{x=624,y=386},{x=590,y=405},
                {x=554,y=425},{x=525,y=432},{x=500,y=420},{x=481,y=387},
                {x=467,y=355},{x=459,y=326},
            },nodes={{x=490,y=303},{x=510,y=374},{x=555,y=400},{x=575,y=345},{x=602,y=214},{x=646,y=206},{x=676,y=251}}},
        },
        corridors={
            -- Native-pixel traces of the painted trail, including the entrance
            -- below the wooden gate and the bend around the central rock face.
            {x1=836,y1=916,x2=836,y2=868,r=41.6},
            {x1=836,y1=868,x2=836,y2=840,r=39},
            {x1=836,y1=840,x2=836,y2=770,r=37.7},
            {x1=836,y1=770,x2=830,y2=710,r=41.6},
            {x1=830,y1=710,x2=810,y2=657,r=39},
            {x1=810,y1=657,x2=782,y2=612,r=39},
            {x1=782,y1=612,x2=810,y2=565,r=40.3},
            {x1=810,y1=565,x2=890,y2=528,r=41.6},
            {x1=890,y1=528,x2=955,y2=478,r=39},
            {x1=955,y1=478,x2=968,y2=425,r=40.3},
            {x1=968,y1=425,x2=984,y2=385,r=39},
            {x1=984,y1=385,x2=1041,y2=352,r=37.7},
            {x1=1041,y1=352,x2=1075,y2=312,r=23.4},
            {x1=1075,y1=312,x2=1110,y2=310,r=23.4},
            {x1=1110,y1=310,x2=1120,y2=277,r=23.4},
            {x1=1120,y1=277,x2=1150,y2=263,r=24.7},
            {x1=1150,y1=263,x2=1190,y2=268,r=24.7},
            {x1=1190,y1=268,x2=1220,y2=277,r=29.9},
            {x1=1220,y1=277,x2=1310,y2=253,r=39},
            {x1=1310,y1=253,x2=1395,y2=211,r=36.4},
            {x1=1395,y1=211,x2=1410,y2=187,r=35.1},
            -- Approach the camp from the ground below its tent and supplies.
            {x1=955,y1=478,x2=1055,y2=497,r=35.1},
            {x1=1055,y1=497,x2=1165,y2=526,r=35.1},
            {x1=1165,y1=526,x2=1255,y2=519,r=31.2},
            {x1=1255,y1=519,x2=1318,y2=495,r=29.9},
            -- The western trail loops around the ruined wall, not through it.
            {x1=810,y1=565,x2=746,y2=543,r=28.6},
            {x1=746,y1=543,x2=676,y2=519,r=27.3},
            {x1=676,y1=519,x2=610,y2=490,r=27.3},
            {x1=610,y1=490,x2=558,y2=451,r=27.3},
            {x1=558,y1=451,x2=543,y2=415,r=26},
            {x1=543,y1=415,x2=568,y2=380,r=26},
            {x1=568,y1=380,x2=604,y2=358,r=26},
            {x1=604,y1=358,x2=646,y2=344,r=26},
            {x1=646,y1=344,x2=635,y2=317,r=23.4},
            {x1=635,y1=317,x2=621,y2=286,r=23.4},
            {x1=621,y1=286,x2=637,y2=257,r=23.4},
            {x1=637,y1=257,x2=693,y2=247,r=24.7},
            {x1=693,y1=247,x2=751,y2=270,r=24.7},
            {x1=751,y1=270,x2=803,y2=305,r=24.7},
            {x1=803,y1=305,x2=861,y2=337,r=26},
            {x1=861,y1=337,x2=921,y2=361,r=26},
            {x1=921,y1=361,x2=984,y2=385,r=28.6},
        },
        interactions={
            {id="return-stop-5",kind="returnStop",x=836,y=868,radius=72,label="RETURN TO STOP 5"},
            {id="surface-cache",kind="chest",chestId="surface-cache",x=1318,y=495,radius=62,label="SEARCH SUPPLY CACHE",
                contents={"food-ration","water-bottle","field-bandage-roll"}},
            {id="basin-entrance",kind="enterArea",target=Areas.BADLANDS_BASIN_ID,spawn="surface",x=1410,y=187,radius=66,
                label="ENTER REDWASH BASIN",mapLabel="BASIN"},
        },
        mobs={
            {id="surface-dust-beetle",file="dust-beetle.png",name="Dust Beetle",x=890,y=528,maxHp=13,tier="easy",packId="badlands-roamers",
                patrol={{x=810,y=565},{x=890,y=528},{x=955,y=478}}},
            {id="surface-cactus-rat",file="cactus-rat.png",name="Cactus Rat",x=1120,y=277,maxHp=14,tier="easy",
                patrol={{x=1085,y=315},{x=1120,y=277},{x=1220,y=277}}},
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
        version=2,
        objectives={
            explore="Survey the three cairns from the marked viewpoints. Use the dry bank when the wash floods.",
            complete="The basin route is surveyed. Return to Stop 5 when ready.",
        },
        completionRequiredMarkers={"north-cairn","wash-cairn","arch-cairn"},
        completionMessage="All three cairns are marked. The basin route is mapped.",
        environment={
            kind="flashFlood",cycle=34,warningAt=10,floodAt=14,floodEnds=22,recedesAt=25,
            floodZone={radius=27,safeBanks={{x=897,y=578},{x=1092,y=717}},
                points={{x=977,y=604},{x=996,y=623},{x=986,y=641},{x=981,y=661}}},
        },
        spawns={surface={x=1174,y=867}},
        clearings={},
        -- Additive ground regions outlined by the user in the map review.
        walkRegions={
            {id="southern-wash-floor",points={
                {x=697,y=741},{x=727,y=738},{x=780,y=760},{x=852,y=748},
                {x=910,y=735},{x=969,y=730},{x=1032,y=742},{x=1074,y=762},
                {x=1114,y=778},{x=1151,y=801},{x=1177,y=830},{x=1214,y=865},
                {x=1208,y=888},{x=1184,y=911},{x=1150,y=929},{x=1099,y=934},
                {x=1040,y=932},{x=976,y=926},{x=923,y=912},{x=879,y=893},
                {x=841,y=874},{x=815,y=845},{x=786,y=815},{x=758,y=790},
                {x=725,y=765},{x=701,y=751},
            },nodes={{x=1010,y=840},{x=1148,y=883},{x=1090,y=818},{x=936,y=842},{x=853,y=803},{x=762,y=765}}},
            {id="southeast-channel",points={
                {x=1288,y=714},{x=1305,y=712},{x=1332,y=723},{x=1361,y=740},
                {x=1389,y=758},{x=1412,y=776},{x=1419,y=791},{x=1405,y=808},
                {x=1375,y=818},{x=1341,y=818},{x=1318,y=825},{x=1301,y=839},
                {x=1291,y=871},{x=1277,y=872},{x=1250,y=861},{x=1239,y=854},
                {x=1231,y=842},{x=1244,y=828},{x=1270,y=813},{x=1295,y=799},
                {x=1318,y=778},{x=1321,y=770},{x=1309,y=753},{x=1291,y=737},
                {x=1287,y=717},
            },nodes={{x=1355,y=775},{x=1369,y=800},{x=1325,y=811},{x=1272,y=846},{x=1306,y=730}}},
            {id="eastern-wash-island",points={
                {x=1029,y=544},{x=1056,y=534},{x=1080,y=537},{x=1121,y=558},
                {x=1158,y=580},{x=1194,y=604},{x=1227,y=624},{x=1244,y=646},
                {x=1251,y=669},{x=1263,y=706},{x=1273,y=745},{x=1275,y=771},
                {x=1264,y=779},{x=1241,y=778},{x=1215,y=769},{x=1195,y=750},
                {x=1168,y=731},{x=1137,y=709},{x=1115,y=684},{x=1081,y=661},
                {x=1059,y=636},{x=1045,y=610},{x=1034,y=579},{x=1020,y=554},
            },nodes={{x=1060,y=565},{x=1101,y=621},{x=1160,y=640},{x=1210,y=710},{x=1246,y=751}}},
            {id="eastern-pillar-bank",points={
                {x=1240,y=404},{x=1248,y=387},{x=1262,y=369},{x=1279,y=372},
                {x=1290,y=388},{x=1299,y=409},{x=1320,y=430},{x=1344,y=450},
                {x=1370,y=468},{x=1390,y=487},{x=1393,y=499},{x=1385,y=519},
                {x=1372,y=549},{x=1361,y=583},{x=1344,y=604},{x=1320,y=627},
                {x=1296,y=646},{x=1275,y=661},{x=1249,y=665},{x=1237,y=657},
                {x=1242,y=640},{x=1253,y=619},{x=1265,y=600},{x=1280,y=569},
                {x=1293,y=539},{x=1305,y=527},{x=1326,y=518},{x=1346,y=509},
                {x=1355,y=501},{x=1347,y=490},{x=1328,y=477},{x=1302,y=465},
                {x=1285,y=449},{x=1265,y=427},{x=1248,y=417},
            },nodes={{x=1265,y=394},{x=1270,y=412},{x=1302,y=439},{x=1340,y=466},{x=1371,y=493},{x=1355,y=551},{x=1320,y=603},{x=1265,y=644}}},
            {id="pillar-western-channel",points={
                {x=1134,y=402},{x=1110,y=400},{x=1095,y=405},{x=1080,y=425},
                {x=1070,y=449},{x=1066,y=475},{x=1061,y=489},{x=1053,y=494},
                {x=1056,y=499},{x=1060,y=514},{x=1087,y=526},{x=1125,y=539},
                {x=1169,y=553},{x=1215,y=575},{x=1253,y=578},{x=1274,y=570},
                {x=1287,y=554},{x=1289,y=542},{x=1278,y=534},{x=1253,y=529},
                {x=1227,y=528},{x=1185,y=518},{x=1156,y=503},{x=1134,y=484},
                {x=1131,y=470},{x=1135,y=450},{x=1142,y=431},{x=1145,y=409},
            },nodes={{x=1118,y=419},{x=1095,y=442},{x=1095,y=497},{x=1163,y=528},{x=1238,y=552}}},
            {id="upper-wash-island",points={
                {x=819,y=490},{x=833,y=477},{x=862,y=464},{x=898,y=454},
                {x=938,y=447},{x=976,y=442},{x=1006,y=440},{x=1020,y=455},
                {x=1026,y=474},{x=1027,y=520},{x=1022,y=540},{x=1007,y=549},
                {x=984,y=557},{x=958,y=554},{x=932,y=549},{x=904,y=541},
                {x=884,y=533},{x=855,y=522},{x=832,y=514},{x=818,y=502},
            },nodes={{x=915,y=495},{x=978,y=503},{x=1004,y=469},{x=852,y=494}}},
            {id="middle-wash-pocket",points={
                {x=839,y=591},{x=859,y=590},{x=893,y=599},{x=929,y=609},
                {x=951,y=621},{x=964,y=639},{x=968,y=654},{x=956,y=667},
                {x=941,y=676},{x=919,y=675},{x=896,y=665},{x=879,y=651},
                {x=859,y=632},{x=842,y=614},{x=831,y=600},
            },nodes={{x=907,y=625},{x=936,y=650},{x=865,y=613}}},
            {id="fossil-bank",points={
                {x=519,y=672},{x=533,y=653},{x=568,y=635},{x=609,y=620},
                {x=651,y=610},{x=698,y=612},{x=742,y=623},{x=791,y=638},
                {x=829,y=651},{x=851,y=666},{x=858,y=691},{x=852,y=713},
                {x=833,y=723},{x=809,y=724},{x=767,y=715},{x=728,y=706},
                {x=677,y=698},{x=637,y=697},{x=602,y=703},{x=574,y=714},
                {x=550,y=703},{x=528,y=691},{x=517,y=681},
            },nodes={{x=690,y=658},{x=595,y=665},{x=553,y=681},{x=777,y=676},{x=832,y=696}}},
            {id="western-bank-floor",points={
                {x=220,y=731},{x=276,y=717},{x=341,y=706},{x=403,y=698},
                {x=464,y=692},{x=520,y=693},{x=552,y=701},{x=574,y=712},
                {x=578,y=730},{x=566,y=745},{x=543,y=755},{x=505,y=765},
                {x=449,y=766},{x=399,y=761},{x=348,y=764},{x=294,y=773},
                {x=259,y=773},{x=234,y=762},{x=221,y=750},
            },nodes={{x=394,y=728},{x=275,y=742},{x=506,y=729},{x=552,y=727}}},
            {id="western-cairn-spur",points={
                {x=15,y=596},{x=36,y=584},{x=62,y=589},{x=95,y=604},
                {x=136,y=629},{x=173,y=655},{x=203,y=690},{x=220,y=719},
                {x=233,y=747},{x=232,y=768},{x=210,y=779},{x=176,y=782},
                {x=136,y=777},{x=107,y=774},{x=105,y=744},{x=107,y=714},
                {x=79,y=698},{x=52,y=681},{x=31,y=655},{x=19,y=630},
                {x=12,y=613},
            },nodes={{x=100,y=657},{x=48,y=622},{x=151,y=699},{x=161,y=750},{x=205,y=755}}},
            {id="north-viewpoint-bank",points={
                {x=547,y=493},{x=542,y=474},{x=561,y=462},{x=596,y=453},
                {x=640,y=452},{x=682,y=451},{x=689,y=463},{x=694,y=488},
                {x=719,y=516},{x=741,y=534},{x=751,y=555},{x=771,y=580},
                {x=782,y=599},{x=779,y=612},{x=756,y=618},{x=728,y=616},
                {x=691,y=604},{x=653,y=592},{x=620,y=576},{x=587,y=561},
                {x=564,y=543},{x=554,y=521},
            },nodes={{x=640,y=553},{x=589,y=512},{x=662,y=493},{x=721,y=564},{x=750,y=597}}},
            {id="north-west-pocket",points={
                {x=480,y=517},{x=494,y=500},{x=517,y=488},{x=541,y=482},
                {x=553,y=492},{x=562,y=514},{x=559,y=531},{x=541,y=541},
                {x=514,y=542},{x=489,y=540},{x=482,y=531},
            },nodes={{x=518,y=513},{x=545,y=513}}},
        },
        corridors={
            -- Trace the channel and low banks in native background pixels.
            -- The painted high terraces have sheer edges, so survey viewpoints
            -- remain on the connected basin floor instead of crossing cliffs.
            {x1=1130,y1=900,x2=1174,y2=867,r=31.2},
            {x1=1174,y1=867,x2=1210,y2=835,r=31.2},
            {x1=1210,y1=835,x2=1220,y2=807,r=31.2},
            {x1=1220,y1=807,x2=1186,y2=780,r=31.2},
            {x1=1186,y1=780,x2=1148,y2=758,r=31.2},
            {x1=1148,y1=758,x2=1120,y2=737,r=31.2},
            {x1=1120,y1=737,x2=1092,y2=717,r=31.2},
            {x1=1092,y1=717,x2=1047,y2=701,r=31.2},
            {x1=1047,y1=701,x2=1009,y2=683,r=31.2},
            {x1=1009,y1=683,x2=981,y2=661,r=31.2},
            {x1=981,y1=661,x2=986,y2=641,r=31.2},
            {x1=986,y1=641,x2=996,y2=623,r=31.2},
            {x1=996,y1=623,x2=977,y2=604,r=31.2},
            {x1=977,y1=604,x2=939,y2=590,r=31.2},
            {x1=939,y1=590,x2=897,y2=578,r=31.2},
            {x1=897,y1=578,x2=846,y2=568,r=31.2},
            {x1=846,y1=568,x2=790,y2=555,r=31.2},
            {x1=790,y1=555,x2=732,y2=542,r=31.2},
            {x1=732,y1=542,x2=679,y2=528,r=31.2},
            {x1=679,y1=528,x2=632,y2=516,r=31.2},
            {x1=632,y1=516,x2=603,y2=500,r=31.2},
            {x1=603,y1=500,x2=650,y2=487,r=31.2},
            {x1=650,y1=487,x2=710,y2=474,r=31.2},
            {x1=710,y1=474,x2=770,y2=461,r=31.2},
            {x1=770,y1=461,x2=835,y2=450,r=31.2},
            {x1=835,y1=450,x2=900,y2=438,r=31.2},
            {x1=900,y1=438,x2=960,y2=425,r=31.2},
            {x1=960,y1=425,x2=1008,y2=409,r=31.2},
            {x1=1008,y1=409,x2=1040,y2=392,r=31.2},
            {x1=1040,y1=392,x2=1072,y2=382,r=31.2},
            {x1=1072,y1=382,x2=1124,y2=375,r=31.2},
            {x1=1124,y1=375,x2=1168,y2=364,r=31.2},
            {x1=1168,y1=364,x2=1190,y2=344,r=31.2},
            {x1=1190,y1=344,x2=1175,y2=326,r=31.2},
            {x1=1175,y1=326,x2=1173,y2=317,r=31.2},
            {x1=1173,y1=317,x2=1201,y2=304,r=31.2},
            {x1=1201,y1=304,x2=1225,y2=295,r=31.2},
            {x1=897,y1=578,x2=945,y2=566,r=26},
            {x1=945,y1=566,x2=990,y2=570,r=26},
            {x1=990,y1=570,x2=1035,y2=600,r=26},
            {x1=1035,y1=600,x2=1060,y2=620,r=26},
            {x1=1060,y1=620,x2=1044,y2=648,r=26},
            {x1=1044,y1=648,x2=1054,y2=675,r=26},
            {x1=1054,y1=675,x2=1100,y2=710,r=26},
            {x1=1100,y1=710,x2=1120,y2=737,r=26},
            {x1=1040,y1=392,x2=1065,y2=412,r=29.9},
            {x1=1065,y1=412,x2=1040,y2=434,r=29.9},
            {x1=1040,y1=434,x2=1068,y2=452,r=29.9},
            {x1=1068,y1=452,x2=1068,y2=470,r=29.9},
            {x1=1068,y1=470,x2=1036,y2=489,r=29.9},
            {x1=1036,y1=489,x2=1009,y2=500,r=29.9},
            {x1=1009,y1=500,x2=1012,y2=518,r=29.9},
            {x1=1012,y1=518,x2=1050,y2=539,r=29.9},
            {x1=1050,y1=539,x2=1140,y2=565,r=29.9},
            {x1=1140,y1=565,x2=1218,y2=584,r=29.9},
            {x1=1218,y1=584,x2=1276,y2=610,r=29.9},
            {x1=1276,y1=610,x2=1270,y2=639,r=29.9},
            {x1=1270,y1=639,x2=1240,y2=666,r=29.9},
            {x1=1240,y1=666,x2=1215,y2=694,r=29.9},
            {x1=1215,y1=694,x2=1237,y2=720,r=29.9},
            {x1=1237,y1=720,x2=1284,y2=750,r=29.9},
            {x1=1284,y1=750,x2=1320,y2=775,r=29.9},
            {x1=1320,y1=775,x2=1270,y2=791,r=29.9},
            {x1=1270,y1=791,x2=1220,y2=807,r=29.9},
            {x1=981,y1=661,x2=940,y2=688,r=27.3},
            {x1=940,y1=688,x2=905,y2=713,r=27.3},
            {x1=905,y1=713,x2=865,y2=732,r=27.3},
            {x1=865,y1=732,x2=815,y2=739,r=27.3},
            {x1=815,y1=739,x2=760,y2=736,r=27.3},
            {x1=760,y1=736,x2=720,y2=720,r=27.3},
            {x1=720,y1=720,x2=690,y2=707,r=27.3},
            {x1=690,y1=707,x2=650,y2=703,r=27.3},
            {x1=650,y1=703,x2=615,y2=730,r=27.3},
            {x1=615,y1=730,x2=615,y2=758,r=27.3},
            {x1=615,y1=758,x2=560,y2=770,r=27.3},
            {x1=560,y1=770,x2=500,y2=773,r=27.3},
            {x1=500,y1=773,x2=440,y2=779,r=27.3},
            {x1=440,y1=779,x2=370,y2=783,r=27.3},
            {x1=370,y1=783,x2=295,y2=787,r=27.3},
            {x1=295,y1=787,x2=220,y2=780,r=27.3},
            {x1=220,y1=780,x2=183,y2=786,r=27.3},
            {x1=183,y1=786,x2=146,y2=790,r=27.3},
            {x1=146,y1=790,x2=110,y2=813,r=27.3},
            {x1=110,y1=813,x2=60,y2=848,r=27.3},
            {x1=650,y1=703,x2=615,y2=700,r=26},
            {x1=615,y1=700,x2=590,y2=713,r=26},
            {x1=1009,y1=683,x2=1009,y2=711,r=26},
            {x1=1009,y1=711,x2=965,y2=723,r=26},
            {x1=965,y1=723,x2=905,y2=713,r=26},
            {x1=1276,y1=610,x2=1301,y2=586,r=27.3},
            {x1=1301,y1=586,x2=1310,y2=561,r=27.3},
            {x1=650,y1=487,x2=617,y2=481,r=28.6},
        },
        interactions={
            {id="return-approach",kind="enterArea",target=Areas.BADLANDS_SURFACE_ID,spawn="basinReturn",x=1174,y=867,radius=72,
                label="RETURN TO RED MESA",mapLabel="APPROACH"},
            {id="western-stash",kind="chest",chestId="western-stash",x=500,y=773,radius=58,label="SEARCH BANK STASH",mapLabel="STASH",
                contents={"water-bottle","field-bandage-roll"}},
            {id="fossil-cache",kind="chest",chestId="fossil-cache",x=590,y=713,radius=58,label="SEARCH FOSSIL CACHE",mapLabel="CACHE",
                contents={"food-ration","small-oil-canister"}},
            {id="north-cairn",kind="survey",markerId="north-cairn",x=617,y=481,radius=54,label="SURVEY NORTH CAIRN",mapLabel="VIEWPOINT"},
            {id="wash-cairn",kind="survey",markerId="wash-cairn",x=146,y=790,radius=58,label="SURVEY WASH CAIRN",mapLabel="VIEWPOINT"},
            {id="arch-cairn",kind="survey",markerId="arch-cairn",x=1310,y=561,radius=56,label="SURVEY ARCH CAIRN",mapLabel="VIEWPOINT"},
            {id="basin-exit",kind="enterArea",target=Areas.BADLANDS_SURFACE_ID,spawn="basinReturn",x=1225,y=295,radius=68,
                label="RETURN TO RED MESA",mapLabel="EXIT"},
        },
        mobs={
            {id="basin-dust-beetle",file="dust-beetle.png",name="Dust Beetle",x=760,y=736,maxHp=15,tier="easy",packId="redwash-scavengers",
                patrol={{x=650,y=703},{x=760,y=736},{x=865,y=732}}},
            {id="basin-cactus-rat",file="cactus-rat.png",name="Cactus Rat",x=710,y=474,maxHp=16,tier="easy",
                patrol={{x=650,y=487},{x=770,y=461},{x=900,y=438}}},
            {id="basin-scorpion",file="wasteland-scorpion.png",name="Wasteland Scorpion",x=1218,y=584,maxHp=19,tier="easy",
                patrol={{x=1140,y=565},{x=1276,y=610},{x=1215,y=694}}},
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
local gateRegions={}
-- Pixel-level navigation queries should not rescan ungated terrain on every
-- foot sample. Only the waystation's progression regions can block a mask.
for areaId,area in pairs(definitions) do
    local regions={clearings={},corridors={}}
    for _,clearing in ipairs(area.clearings or {}) do
        if clearing.gate then regions.clearings[#regions.clearings+1]=clearing end
    end
    for _,corridor in ipairs(area.corridors or {}) do
        if corridor.gate then regions.corridors[#regions.corridors+1]=corridor end
    end
    if #regions.clearings>0 or #regions.corridors>0 then gateRegions[areaId]=regions end
end

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
    if data.players then
        assert(require("game.coop_entities").ensure(data))
        assert(require("game.item_instances").ensure(data))
    end
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

function Areas.environment(data,areaId,readOnly)
    local area=definitions[areaId]
    if not area or not area.environment then return nil end
    local state=readOnly and data.expeditions and data.expeditions[areaId] or (not readOnly and Areas.state(data,areaId))
    if not state then return nil end
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

function Areas.isInFlood(data,areaId,x,y,readOnly)
    local area=definitions[areaId]
    local state=area and (readOnly and data.expeditions and data.expeditions[areaId] or not readOnly and Areas.state(data,areaId))
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

local function insideWalkRegion(region,x,y)
    local points=region.points or {}
    if #points<3 then return false end
    local inside=false
    local previous=points[#points]
    local ax,ay=previous.x or previous[1],previous.y or previous[2]
    for _,point in ipairs(points) do
        local bx,by=point.x or point[1],point.y or point[2]
        -- Include the polygon outline, including horizontal edges and vertices.
        if pointSegmentDistance(x,y,ax,ay,bx,by)<=.0001 then return true end
        if (ay>y)~=(by>y) and x<(bx-ax)*(y-ay)/(by-ay)+ax then inside=not inside end
        ax,ay=bx,by
    end
    return inside
end

local function authoredWalkable(area,state,x,y)
    for _,clearing in ipairs(area.clearings or {}) do
        if gateOpen(state,clearing.gate) and insideClearing(clearing,x,y) then return true end
    end
    for _,corridor in ipairs(area.corridors or {}) do
        if gateOpen(state,corridor.gate) and insideCorridor(corridor,x,y) then return true end
    end
    for _,region in ipairs(area.walkRegions or {}) do
        if insideWalkRegion(region,x,y) then return true end
    end
    return false
end

local function gateBlocked(area,state,x,y)
    -- Masks own the ground; only progression locks still use authored regions.
    -- Shared endpoints must remain accessible from the open side of a gate.
    local regions=gateRegions[area.id]
    if not regions then return false end
    for _,clearing in ipairs(regions.clearings) do
        if clearing.gate and not gateOpen(state,clearing.gate) and insideClearing(clearing,x,y) then
            return not authoredWalkable(area,state,x,y)
        end
    end
    for _,corridor in ipairs(regions.corridors) do
        if corridor.gate and not gateOpen(state,corridor.gate) and insideCorridor(corridor,x,y) then
            return not authoredWalkable(area,state,x,y)
        end
    end
    return false
end

function Areas.isWalkable(data,areaId,x,y,readOnly)
    local area=definitions[areaId]
    if not area or x<24 or y<24 or x>area.width-24 or y>area.height-24 then return false end
    local state
    if readOnly then state=data.expeditions and data.expeditions[areaId]
    else state=Areas.state(data,areaId); Areas.updateGates(data,areaId) end
    if not state then return false end
    if state.environmentPhase=='flooded' and insideFloodZone(area.environment and area.environment.floodZone,x,y) then return false end
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

function Areas.move(data,areaId,oldX,oldY,newX,newY,readOnly)
    -- Substeps prevent sprinting or a long frame from hopping over a river.
    local steps=math.max(1,math.ceil(distance(oldX,oldY,newX,newY)/6))
    local dx,dy=(newX-oldX)/steps,(newY-oldY)/steps
    local x,y=oldX,oldY
    for _=1,steps do
        if Areas.isWalkable(data,areaId,x+dx,y+dy,readOnly) then x,y=x+dx,y+dy
        elseif Areas.isWalkable(data,areaId,x+dx,y,readOnly) then x=x+dx
        elseif Areas.isWalkable(data,areaId,x,y+dy,readOnly) then y=y+dy end
    end
    return x,y
end

function Areas.canReach(data,areaId,x1,y1,x2,y2,readOnly)
    -- Check each native mask pixel, including edges encountered when walking
    -- slowly. Frame-sized samples can approve a shortcut through a tight bend
    -- that the player's next, shorter movement step correctly rejects.
    local steps=math.max(1,math.ceil(distance(x1,y1,x2,y2)))
    for i=0,steps do
        local t=i/steps
        if not Areas.isWalkable(data,areaId,x1+(x2-x1)*t,y1+(y2-y1)*t,readOnly) then return false end
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
    for _,region in ipairs(area.walkRegions or {}) do
        for _,point in ipairs(region.nodes or {}) do add(point.x or point[1],point.y or point[2]) end
    end
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

function Areas.interaction(data,scene,player,readOnly)
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
    local state=readOnly and data.expeditions and data.expeditions[area.id] or not readOnly and Areas.state(data,area.id)
    if not state then return nil end
    for _,definition in ipairs(area.interactions or {}) do
        local d=distance(player.x,player.y,definition.x,definition.y)
        if d<=definition.radius and Areas.canReach(data,area.id,player.x,player.y,definition.x,definition.y,readOnly)
            and (not bestDistance or d<bestDistance) then best,bestDistance=definition,d end
    end
    for _,mob in ipairs(area.mobs or {}) do
        local saved=state.mobs[mob.id]
        if mob.boss and saved and not saved.dead and (not mob.requires or state.gates[mob.requires])
            and distance(player.x,player.y,saved.x,saved.y)<=180
            and Areas.canReach(data,area.id,player.x,player.y,saved.x,saved.y,readOnly) then
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
