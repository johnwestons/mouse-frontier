-- Sight-tip coordinates measured in each authored ADS atlas cell.
-- Frame order: ready, flash, recoil, settle. Keep these separate from the
-- static sights PNG anchors: those images have different framing.
-- The .380 pocket pistol recoil cell obscures its sight; use its bore line.
-- Flash-obscured tips retain the barrel centerline at the visible sight height.
local measured={
    ["compact-carbine"]={{260,199},{244,199},{258,173},{253,178}},
    ["compact-scrap-pistol"]={{271,161},{236,157},{271,64},{235,129}},
    ["frontier-12g-pump-shotgun"]={{290,100},{218,118},{291,41},{218,81}},
    ["frontier-22-lever-rifle"]={{257,108},{226,141},{258,97},{228,100}},
    ["frontier-22-pocket-pistol"]={{271,181},{231,179},{274,118},{231,164}},
    ["frontier-22-target-pistol"]={{271,225},{237,222},{271,167},{239,167}},
    ["frontier-32-pocket-pistol"]={{258,157},{248,158},{258,127},{256,164}},
    ["frontier-380-pocket-pistol"]={{268,202},{256,206},{270,98},{256,187}},
    ["frontier-380-revolver"]={{271,173},{240,173},{272,74},{240,141}},
    ["frontier-45-1911"]={{271,202},{233,198},{272,154},{235,186}},
    ["frontier-556-carbine"]={{275,145},{234,153},{274,92},{236,100}},
    ["frontier-762-carbine"]={{278,199},{229,204},{278,108},{228,129}},
    ["frontier-9mm-glock"]={{274,106},{240,106},{273,54},{243,103}},
    ["frontier-9mm-service-pistol"]={{257,118},{249,121},{258,104},{251,133}},
    ["frontier-9mm-smg"]={{257,137},{256,154},{258,100},{257,137}},
    ["frontier-ak-compact"]={{258,123},{254,135},{257,79},{254,120}},
    ["frontier-compact-9mm"]={{261,139},{248,140},{260,82},{248,125}},
    ["frontier-compact-9mm-pistol"]={{262,200},{246,200},{264,153},{248,198}},
    ["frontier-lever-carbine"]={{272,213},{240,212},{271,180},{240,180}},
    ["frontier-lever-rifle"]={{277,185},{212,187},{278,171},{213,175}},
    ["frontier-long-22-target-pistol"]={{256,122},{255,127},{264,85},{256,120}},
    ["frontier-long-barrel-revolver"]={{271,191},{240,193},{269,188},{243,188}},
    ["frontier-pearl-pocket-pistol"]={{278,214},{231,219},{279,174},{234,180}},
    ["frontier-silver-22-revolver"]={{274,85},{236,91},{274,41},{237,71}},
    ["frontier-silver-compact-pistol"]={{285,165},{224,168},{285,133},{222,154}},
    ["frontier-single-shot-hunter"]={{257,148},{256,158},{257,83},{254,116}},
    ["frontier-sr22-pistol"]={{257,153},{241,157},{258,81},{244,142}},
    ["heavy-frontier-pistol"]={{256,209},{243,211},{257,198},{246,198}},
    ["improvised-556-rifle"]={{259,156},{247,163},{259,142},{254,142}},
    ["improvised-service-rifle"]={{282,184},{210,188},{284,109},{211,148}},
    ["long-barrel-22-pistol"]={{258,194},{248,196},{258,124},{248,161}},
    ["machine-pistol"]={{267,249},{225,249},{266,185},{227,185}},
    ["patched-22-survival-rifle"]={{274,150},{244,153},{274,158},{245,156}},
    ["rugged-submachine-gun"]={{274,144},{227,151},{274,118},{229,129}},
    ["sawed-off-shotgun"]={{326,202},{312,204},{324,172},{315,177},width=627,height=627},
    ["scrap-pistol"]={{259,131},{257,148},{259,63},{256,127}},
    ["vintage-bolt-action-rifle"]={{262,150},{237,158},{269,86},{237,120}},
    ["weathered-lever-rifle"]={{281,162},{231,177},{281,144},{232,143}},
    ["wood-stock-survival-carbine"]={{273,221},{242,231},{273,188},{243,188}},
}

local anchors={}
for weapon,frames in pairs(measured) do
    local width,height=frames.width or 512,frames.height or 768
    anchors[weapon]={}
    for frame=1,4 do
        local point=frames[frame]
        anchors[weapon][frame]={x=point[1]/width,y=point[2]/height,calibrated=true}
    end
end
return anchors
