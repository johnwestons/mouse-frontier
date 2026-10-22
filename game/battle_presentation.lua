-- Read-only battle presentation. Uses existing authored art and rules; device
-- panels and projectile drawing never mutate the authoritative battle.
local Field=require('game.battle_field')
local Fog=require('game.battle_fog')
local Rules=require('game.battle_rules')
local Actors=require('game.battle_actors')
local Weapons=require('game.battle_weapon_ownership')
local Catalog=require('game.catalog')
local Progression=require('game.player_progression')
local Typography=require('game.typography')
local Presentation={}
function Presentation.statuses(unit)
    local result={}
    if unit.boss then result[#result+1]='BOSS'end
    for _,entry in ipairs({{'sleepRounds','SLEEP'},{'paralyzedRounds','PARALYZED'},{'bleedRounds','BLEED'},
        {'staggeredRounds','STAGGERED'},{'regenRounds','REGEN'}})do
        if(unit[entry[1]]or 0)>0 then result[#result+1]=entry[2]..' '..unit[entry[1]]end
    end
    if(unit.moveBonus or 0)<0 then result[#result+1]='SNARED'end
    if unit.guarding then result[#result+1]='GUARD'end
    return result
end
function Presentation.details(ctx,unit)
    if not unit or not Fog.unitVisible(ctx.battle,unit)then return{'Select a visible unit to inspect.'}end
    local lines={unit.name..'  /  '..(unit.team=='enemy'and'ENEMY'or'ALLY'),
        'HP '..unit.hp..' / '..unit.maxHP..'    AIM '..unit.aim..'    ARMOR '..unit.armor,
        'MOVE '..unit.move..'    HEIGHT '..string.format('%.2f',Field.cellHeight(ctx.battle.field,unit.q,unit.r))}
    local statuses=Presentation.statuses(unit);lines[#lines+1]=#statuses>0 and table.concat(statuses,'  /  ')or'NO CONDITIONS'
    local selectors=unit.team=='enemy'and{unit.weapon}or Weapons.options(ctx.saveData,unit,Catalog)
    local actor=Actors.data(ctx.saveData,unit)
    for _,selector in ipairs(selectors)do
        local info=Weapons.resolve(ctx.saveData,unit,selector,Catalog)
        if info then
            local stats=Catalog.weaponStats[info.name]or Catalog.weaponStats.scratch
            local combat=Catalog.weaponCombat[info.name]or{}
            local detail=(stats.name or info.name)..'  /  RANGE '..Rules.weaponRange(Catalog,info.name)
            if stats.min and stats.max then detail=detail..'  /  DAMAGE '..stats.min..'–'..stats.max end
            if unit.team=='ally'and info.name~='scratch'then
                detail=detail..'  /  DUR '..info.durability..'%'
                if combat.ammo then detail=detail..'  /  AMMO '..(actor.ammo[combat.ammo]or 0)end
            end
            lines[#lines+1]=detail
        end
    end
    if unit.team=='ally'then
        local ability=Catalog.characterAbility(unit.file)
        local level=Actors.id(unit)and actor.stats.level or math.max(1,math.min(12,math.ceil((ctx.saveData.location or 1)/5)))
        local profile=Progression.abilityProfile(ability.kind,level)
        lines[#lines+1]=ability.name..'  /  RANK '..profile.rank
        lines[#lines+1]=profile.description
        if ctx.battle.abilitiesUsed[unit.id]then lines[#lines+1]='ABILITY USED THIS BATTLE'end
    end
    return lines
end
function Presentation.projectile(ctx)
    local p=ctx.battle.projectile;local atlas=ctx.scenery and ctx.scenery.projectiles
    if not p or not atlas then return nil end
    local t=math.max(0,math.min(1,p.t/math.max(.001,p.duration)))
    local x,z=p.fromQ+.5+(p.toQ-p.fromQ)*t,p.fromR-.5+(p.toR-p.fromR)*t
    if not Fog.visible(ctx.battle,math.floor(x),math.floor(z)+1)then return nil end
    local a=Field.cellHeight(ctx.battle.field,p.fromQ,p.fromR)+.95
    local b=Field.cellHeight(ctx.battle.field,p.toQ,p.toR)+.95
    local arc=(p.ammo=='rocks'or p.ammo=='ball-bearings')and math.sin(t*math.pi)*.45 or 0
    local index=p.ammo=='rocks'and 1 or p.ammo=='ball-bearings'and 2 or p.ammo=='arrows'and 3 or(p.ammo=='45-cal'or p.ammo=='556')and 5 or 4
    local scale=math.min(.56/atlas.w,.36/atlas.h)
    return{image=atlas.image,quad=atlas.quads[index],x=x,y=a+(b-a)*t+arc,z=z,w=atlas.w*scale,h=atlas.h*scale,
        fromX=p.fromQ+.5,fromY=a,fromZ=p.fromR-.5,toX=p.toQ+.5,toY=b,toZ=p.toR-.5}
end
function Presentation.drawProjectile(ctx,renderer)
    local p=Presentation.projectile(ctx);if not p then return false end
    local sx,sy=renderer.camera:project(p.fromX,p.fromY,p.fromZ);local tx,ty=renderer.camera:project(p.toX,p.toY,p.toZ)
    renderer:drawSprite(p.image,p.quad,p.x,p.y,p.z,p.w,p.h,nil,{centered=true,rotation=math.atan2(ty-sy,tx-sx)})
    renderer.stats.projectiles=(renderer.stats.projectiles or 0)+1;return true
end
function Presentation.drawPanel(ctx,state,selected)
    state.panelRect=nil;if not state.panel then return end
    local g=love.graphics;local l=state.layout;local fs=l.fontScale
    local rect={x=l.x+12,y=l.header+(ctx.mobileEnabled and 70 or 59),w=math.min(380*fs,l.w-24),h=math.min(350*fs,l.map.h-83)}
    state.panelRect=rect
    local lines={};local title=state.panel=='log'and'BATTLE HISTORY'or'UNIT DETAILS'
    if state.panel=='log'then for _,entry in ipairs(ctx.battle.log or{})do lines[#lines+1]=entry end
    else lines=Presentation.details(ctx,selected)end
    if #lines==0 then lines={'No battle history yet.'}end
    g.setColor(.025,.025,.022,.97);g.rectangle('fill',rect.x,rect.y,rect.w,rect.h,5,5)
    g.setColor(.90,.77,.44,1);g.rectangle('line',rect.x,rect.y,rect.w,rect.h,5,5)
    Typography.drawText(g,title,rect.x+12,rect.y+7,rect.w-154*fs,32*fs,{scale=.75*fs,minScale=.65*fs,valign='center'})
    local buttons={{'UP','panelUp'},{'DN','panelDown'},{'X','panelClose'}}
    for i,item in ipairs(buttons)do
        local button=ctx.button(item[1],rect.x+rect.w-(158-(i-1)*49)*fs,rect.y+7,44*fs,32*fs,true,.56)
        ctx.ui.battleCameraButtons[#ctx.ui.battleCameraButtons+1]={rect=button,action=item[2]}
    end
    local scale=.75*fs;local font=g.getFont();local contentWidth=rect.w-26;local heights={};local total=0
    for i,line in ipairs(lines)do
        local _,wrapped=font:getWrap(line,contentWidth/scale)
        heights[i]=math.max(1,#wrapped)*font:getHeight()*font:getLineHeight()*scale+10*fs;total=total+heights[i]
    end
    local visible=rect.h-52*fs;state.panelMaxScroll=math.max(0,total-visible);state.panelPage=visible*.8
    if state.panel=='log'and state.panelScroll==nil then state.panelScroll=state.panelMaxScroll end
    state.panelScroll=math.max(0,math.min(state.panelMaxScroll,state.panelScroll or 0))
    local px,py=g.transformPoint(rect.x+10,rect.y+47*fs);local qx,qy=g.transformPoint(rect.x+rect.w-10,rect.y+rect.h-5)
    g.push('all');g.intersectScissor(px,py,math.max(1,qx-px),math.max(1,qy-py));g.setColor(1,.94,.80,1)
    local y=rect.y+47*fs-state.panelScroll
    for i,line in ipairs(lines)do
        if y+heights[i]>rect.y+47*fs and y<rect.y+rect.h then
            Typography.drawText(g,line,rect.x+13,y,contentWidth,heights[i],{scale=scale,minScale=scale,valign='top'})
        end
        y=y+heights[i]
    end
    g.pop()
end
return Presentation
