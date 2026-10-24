local Renderer=require('game.battle_renderer3d')
local Field=require('game.battle_field')
local Grid=require('game.battle_grid')
local Rules=require('game.battle_rules')
local Actors=require('game.battle_actors')
local Weapons=require('game.battle_weapon_ownership')
local Catalog=require('game.catalog')
local Motion=require('game.battle_motion')
local Character=require('game.character_animation')
local Mob=require('game.mob_combat_animation')
local Typography=require('game.typography')
local Accessibility=require('game.accessibility')
local Util=require('game.util')
local Viewport=require('game.viewport')
local Fog=require('game.battle_fog')
local Graphics=require('game.battle_graphics')
local Presentation=require('game.battle_presentation')
local Search=require('game.battle_search')
local Native={}
local function release(o)if o and o.release then o:release()end end
local function text(value,x,y,w,h,scale,align)
    return Typography.drawText(love.graphics,value,x,y,w,h,{scale=scale or .75,minScale=scale or .75,align=align or 'left',valign='center'})
end
local function identity(b)return b.encounter and b.encounter.entityId or b.terrainSeed or b.field.seed end
local function focusUnit(b)
    local u=Rules.selectedUnit(b)
    if u and Fog.unitVisible(b,u)then return u end
    for _,ally in ipairs(b.units)do if ally.team=='ally'and ally.hp>0 then return ally end end
    return b.units[1]
end
local function layout(ctx)
    local width,height=love.graphics.getDimensions();local ox,oy,sx=Viewport.transform(ctx.W,ctx.H)
    local x=-ox/sx;local w=width/sx
    local fontScale=Accessibility.textScale(ctx.saveData)
    local dock=(w>=1350 and 100 or ctx.mobileEnabled and 156 or 132)*fontScale
    local header=(ctx.mobileEnabled and 96 or 56)*fontScale
    return {x=x,w=w,header=header,dock=dock,map={x=x,y=header,w=w,h=ctx.H-header-dock},bottom=ctx.H-dock,fontScale=fontScale}
end
function Native.camera(ui,battle)
    return battle and battle.field and ui.nativeBattle and ui.nativeBattle.renderer.camera or nil
end
function Native.release(ui)
    local state=ui.nativeBattle;if not state then return end
    state.renderer:release();release(state.rangeMesh);release(state.exitMesh);release(state.gridMesh)
    ui.nativeBattle=nil
end
function Native.state(ctx)
    local b,ui=ctx.battle,ctx.ui;local state=ui.nativeBattle
    if not state or state.identity~=identity(b)then
        Native.release(ui)
        state={identity=identity(b),renderer=Renderer.new({quality=ctx.mobileEnabled and 'low'or'high'}),motion={},labels={},grid=false}
        ui.nativeBattle=state
        local u=focusUnit(b)
        state.renderer.camera:focus(u.q,u.r,Field.cellHeight(b.field,u.q,u.r));state.renderer.camera:setZoom(1.05)
    end
    state.layout=layout(ctx);state.renderer.camera:configure(state.layout.map)
    state.renderer.resolution=ctx.mobileEnabled and .75 or 1
    state.renderer.renderDistance=Graphics.distance(ctx.saveData,ctx.mobileEnabled)
    state.highContrast=Accessibility.enabled(ctx.saveData,'highContrast')
    state.renderer:setBattle(b)
    return state
end
function Native.busy(b)
    if b.intro or (b.attackTimer or 0)>0 or (b.enemyDelay or 0)>0 or b.projectile then return true end
    for _,u in ipairs(b.units)do if u.moveAnim or (u.actionTimer or 0)>0 or (u.hitTimer or 0)>0 then return true end end
    return false
end
local function edge(lines,q,r,color)
    local x,z=q,r-1
    for _,p in ipairs({{x+.06,z+.06,x+.94,z+.06},{x+.94,z+.06,x+.94,z+.94},{x+.94,z+.94,x+.06,z+.94},{x+.06,z+.94,x+.06,z+.06}})do
        p.color=color;lines[#lines+1]=p
    end
end
local function overlays(ctx,state)
    local b,r=ctx.battle,state.renderer;local active=Rules.activeUnit(b)
    local parts={b.active,b.phase,tostring(b.moveUsed),tostring(b.finished),tostring(state.highContrast)}
    for _,u in ipairs(b.units)do parts[#parts+1]=u.id..':'..u.q..':'..u.r..':'..u.hp..':'..u.move end
    local key=table.concat(parts,'|')
    if state.rangeKey~=key then
        release(state.rangeMesh);local lines={}
        if active and active.team=='ally' and active.hp>0 and not b.finished then
            if not b.moveUsed and b.phase=='move'then
                for _,p in pairs(Grid.reachable(b,active,Grid.moveBudget(b,active)))do
                    if not Rules.unitAt(b,p.q,p.r)then edge(lines,p.q,p.r,state.highContrast and{1,1,.7,1}or{.94,.76,.24,.68})end
                end
            elseif b.phase=='target'then
                for _,u in ipairs(b.units)do
                    if u.team=='enemy' and u.hp>0 and Fog.unitVisible(b,u)and Rules.distance(active,u)<=Rules.weaponRange(Catalog,b.chosenWeapon or'scratch')and Rules.lineOfSight(b,active,u)then edge(lines,u.q,u.r,{1,.25,.16,.9})end
                end
            end
            edge(lines,active.q,active.r,{1,.92,.55,1})
        end
        state.rangeMesh=r:surfaceMesh(lines);state.rangeKey=key
    end
    if state.geometryKey~=r.geometryKey then
        release(state.exitMesh);release(state.gridMesh);state.gridMesh=nil
        local lines={};for row=1,b.field.rows do edge(lines,b.field.exitColumn,row,{.35,.90,.69,.9})end
        state.exitMesh=r:surfaceMesh(lines);state.geometryKey=r.geometryKey
    end
    if state.grid and not state.gridMesh then
        local lines={};for q=0,b.field.columns-1 do for row=1,b.field.rows do edge(lines,q,row,{.83,.84,.68,.24})end end
        state.gridMesh=r:surfaceMesh(lines)
    end
    r:drawOverlay(state.grid and state.gridMesh);r:drawOverlay(state.exitMesh);r:drawOverlay(state.rangeMesh)
end
local function drawActors(ctx,state)
    local b,r=ctx.battle,state.renderer;state.labels={};state.unitHits={}
    local yaw=r.camera.yaw*math.pi/180
    for i,u in ipairs(b.units)do
        if Fog.unitVisible(b,u)then
        local q,row,dq,dr,distance,moving=Motion.sample(b.field,u)
        if not u.intentQ and u.team=='enemy'and not moving then dq=-1 end
        local vx,vz=dq*math.cos(yaw)-dr*math.sin(yaw),dq*math.sin(yaw)+dr*math.cos(yaw)
        local facing=vx<0 and -1 or 1;local action=u.hp<=0 and 'unconscious'or(u.hitTimer or 0)>0 and'hit'or(u.actionTimer or 0)>0 and(u.action or'idle')or moving and'walk'or'idle'
        local phase=action=='hit'and math.max(0,.58-u.hitTimer)or(u.actionTimer or 0)>0 and math.max(0,(u.team=='enemy'and .68 or .45)-u.actionTimer)or ctx.animationClock+i*.13
        state.motion[u.id]=state.motion[u.id]or{};local motion=state.motion[u.id]
        motion.intentX,motion.intentY,motion.animationDistance,motion.moving=vx,vz,distance*Motion.PIXELS_PER_UNIT,moving
        local set=ctx.characterAnimations and ctx.characterAnimations[u.file]
        local profile=set and set.motionProfile
        motion.locomotionMode=moving and set and set.runDirectional and'run'or'walk'
        motion.posePhase=profile and motion.animationDistance/((motion.locomotionMode=='run'and profile.runPixelsPerFrame)or profile.pixelsPerFrame)or nil
        local sample
        if u.team=='ally'then sample=Character.sample(ctx.characterAnimations,u.file,action,76,96,facing,phase,ctx.animationClock,motion)
        else sample=Mob.sample(ctx,u,76,u.boss and 132 or 96,facing,ctx.animationClock)end
        if not sample then
            local im=u.team=='enemy'and ctx.mobImages[u.file]or(ctx.characterImages[u.file]or ctx.npcImages[u.file])
            if moving then im=(u.team=='enemy'and ctx.mobWalkImages[u.file]or(ctx.characterWalkImages[u.file]or ctx.npcWalkImages[u.file]))or im end
            if im then
                local w,h=im:getDimensions();local scale=math.min(76/w,96/h)
                sample={image=im,width=w,height=h,originY=h,offsetY=0,mirror=facing,scale=scale}
            end
        end
        local x,z=q+.5,row-.5;local y=Field.heightAt(b.field,x,z)
        if sample then
            local factor=1.9/96;local h=sample.height*sample.scale*factor
            local offset=-(sample.offsetY+(sample.height-sample.originY)*sample.scale)*factor
            local _,up=r.camera:basis()
            r:drawSprite(sample.image,sample.quad,x+up[1]*offset,y+up[2]*offset,z+up[3]*offset,
                sample.width*sample.scale*factor*sample.mirror,h)
            if u.hp>0 then
                local sx,sy,depth=r.camera:project(x,y,z);local pixelScale=r.camera.pixelsPerUnit*r.camera.zoom
                local width=sample.width*sample.scale*factor*pixelScale
                state.unitHits[#state.unitHits+1]={unit=u,depth=depth,x=sx-width*.4+state.layout.map.x,
                    y=sy-(h+offset)*pixelScale+state.layout.map.y,w=width*.8,h=h*pixelScale}
            end
        end
        state.labels[#state.labels+1]={unit=u,x=x,y=y,z=z}
        end
    end
end
local function minimap(ctx,state)
    local l=state.layout;local rect={x=l.x+l.w-184,y=l.header+14,w=168,h=98};ctx.ui.battleMinimap=rect
    love.graphics.setColor(.045,.05,.035,.88);love.graphics.rectangle('fill',rect.x-5,rect.y-5,rect.w+10,rect.h+10,5,5)
    love.graphics.setColor(.35,.41,.27,1)
    if state.renderer.fogImage then
        love.graphics.draw(state.renderer.fogImage,rect.x,rect.y,0,rect.w/ctx.battle.field.columns,rect.h/ctx.battle.field.rows)
    else love.graphics.rectangle('fill',rect.x,rect.y,rect.w,rect.h)end
    local field=ctx.battle.field
    for _,cache in ipairs(Search.list(ctx.battle))do if Fog.explored(ctx.battle,cache.q,cache.r)then
        local taken=Search.receipt(ctx.saveData,ctx.battle,cache.id)
        love.graphics.setColor(taken and .36 or .95,taken and .38 or .77,taken and .36 or .29,1)
        love.graphics.rectangle('fill',rect.x+(cache.q+.5)/field.columns*rect.w-2,rect.y+(cache.r-.5)/field.rows*rect.h-2,4,4)
    end end
    love.graphics.setColor(.29,.81,.60,1);love.graphics.rectangle('fill',rect.x+rect.w-5,rect.y,5,rect.h)
    for _,u in ipairs(ctx.battle.units)do if u.hp>0 and Fog.unitVisible(ctx.battle,u)then
        love.graphics.setColor(u.team=='enemy'and .90 or .95,u.team=='enemy'and .29 or .82,u.team=='enemy'and .19 or .38,1)
        love.graphics.circle('fill',rect.x+(u.q+.5)/field.columns*rect.w,rect.y+(u.r-.5)/field.rows*rect.h,Actors.id(u)and 3 or 2)
    end end
    local c=state.renderer.camera
    love.graphics.setColor(.93,.91,.73,1);love.graphics.circle('line',rect.x+math.max(0,math.min(1,c.targetX/field.columns))*rect.w,rect.y+math.max(0,math.min(1,c.targetZ/field.rows))*rect.h,6)
end
function Native.draw(ctx)
    local state=Native.state(ctx);local b,ui=ctx.battle,ctx.ui;local l=state.layout;local c=state.renderer.camera
    state.renderer:render(b,l.map,function()overlays(ctx,state);drawActors(ctx,state);Presentation.drawProjectile(ctx,state.renderer)end)
    love.graphics.push('all');love.graphics.setScissor()
    local active,selected=Rules.activeUnit(b),Rules.selectedUnit(b)
    if selected and not Fog.unitVisible(b,selected)then selected=active and active.team=='ally'and active or nil end
    local scale=(ctx.mobileEnabled and .80 or .72)*Accessibility.textScale(ctx.saveData)
    for _,p in ipairs(state.labels)do
        local u=p.unit;local x,y=c:project(p.x,p.y,p.z)
        if x>l.map.x+25 and x<l.map.x+l.map.w-25 and y>l.map.y+28 and y<l.map.y+l.map.h-12 then
            if u.hp>0 then
                local bar=state.highContrast and 10 or 6
                love.graphics.setColor(.025,.025,.02,.95);love.graphics.rectangle('fill',x-23,y+5,46,bar)
                love.graphics.setColor(u.team=='enemy'and ctx.colors.red or ctx.colors.green);love.graphics.rectangle('fill',x-23,y+5,46*u.hp/u.maxHP,bar)
                if state.highContrast then love.graphics.setColor(1,1,1,1);love.graphics.rectangle('line',x-23,y+5,46,bar)end
                local statuses=Presentation.statuses(u)
                local label=(u==active and'ACTIVE  'or'')..table.concat(statuses,' / ')
                if label~=''then
                    love.graphics.setColor(0,0,0,.9);love.graphics.rectangle('fill',x-100,y+bar+7,200,22*l.fontScale)
                    love.graphics.setColor(ctx.colors.brass);text(label,x-98,y+bar+7,196,22*l.fontScale,.58*l.fontScale,'center')
                end
                if u==selected then
                    love.graphics.setColor(1,.92,.5,1);love.graphics.setLineWidth(2)
                    love.graphics.circle('line',x,y-3,12);love.graphics.line(x-17,y-3,x-8,y-3,x+8,y-3,x+17,y-3)
                end
            end
            if (u.damageNumberTimer or 0)>0 then love.graphics.setColor(ctx.colors.red);text('-'..u.damageNumber,x-30,y-65,60,24,.9,'center')end
        end
    end
    minimap(ctx,state)
    state.cacheHits={}
    for _,cache in ipairs(Search.list(b))do if Fog.visible(b,cache.q,cache.r)then
        local x,y=c:project(cache.q+.5,Field.cellHeight(b.field,cache.q,cache.r)+.65,cache.r-.5)
        local taken=Search.receipt(ctx.saveData,b,cache.id)
        local rect={x=x-67,y=y-25,w=134,h=28*l.fontScale}
        if rect.x>=l.map.x and rect.x+rect.w<=l.map.x+l.map.w and rect.y>l.header+116*l.fontScale and rect.y+rect.h<l.bottom then
            love.graphics.setColor(.04,.035,.02,.9);love.graphics.rectangle('fill',rect.x,rect.y,rect.w,rect.h,3,3)
            love.graphics.setColor(taken and {.57,.59,.54,1}or ctx.colors.brass)
            text(taken and'SEARCHED'or'RUIN CACHE',rect.x+4,rect.y,rect.w-8,rect.h,.64*l.fontScale,'center')
            state.cacheHits[#state.cacheHits+1]={rect=rect,id=cache.id,taken=taken}
        end
    end end
    if ctx.statusText then
        local x,y=l.x+l.w-232,l.header+128
        love.graphics.setColor(0,0,0,.90);love.graphics.rectangle('fill',x,y,220,66*l.fontScale,4,4)
        love.graphics.setColor(ctx.colors.cream);text(ctx.statusText,x+9,y+5,202,56*l.fontScale,.68*l.fontScale)
    end
    if(state.renderer.stats.pendingChunks or 0)>0 then
        love.graphics.setColor(1,.92,.70,1);text('Loading terrain…',l.x+14,l.bottom-27,240,24,.68*l.fontScale)
    end
    love.graphics.setColor(.065,.05,.035,.98);love.graphics.rectangle('fill',l.x,0,l.w,l.header);love.graphics.rectangle('fill',l.x,l.bottom,l.w,l.dock)
    local headerInset=ctx.mobileEnabled and 150 or 14
    love.graphics.setColor(ctx.colors.brass);text('TACTICAL CROSSING  /  ROUND '..b.round,l.x+headerInset,4*l.fontScale,l.w-headerInset-14,22*l.fontScale,.88*l.fontScale)
    love.graphics.setColor(ctx.colors.cream);text('OBJECTIVE  /  '..b.objective,l.x+headerInset,27*l.fontScale,l.w-headerInset-14,24*l.fontScale,scale)
    ui.battleCameraButtons={}
    local controls={{'FOCUS','focus'},{'MAP','overview'},{'<','left'},{'>','right'},{'TILT+','tiltUp'},{'TILT-','tiltDown'},{'GRID','grid'},{'INFO','info'},{'LOG','log'}}
    local bx=l.x+12
    for _,item in ipairs(controls)do
        local w=(item[1]=='<'or item[1]=='>')and 38 or 65
        local rect=ctx.button(item[1],bx,l.header+14,w,ctx.mobileEnabled and 44 or 34,true,.64)
        ui.battleCameraButtons[#ui.battleCameraButtons+1]={rect=rect,action=item[2]};bx=bx+w+5
    end
    ui.battleWeapons={};ui.battlePotionButtons={};ui.battleOptions={}
    for _,key in ipairs({'battleHeal','battleGuard','battleSearch','battleAbility','battleEnd','battleRetreat','battleContinue','battleMove','battleInventory','battleLogUp','battleLogDown'})do ui[key]=nil end
    if selected then
        love.graphics.setColor(ctx.colors.brass);text(selected.name..'  HP '..selected.hp..'/'..selected.maxHP,l.x+14,l.bottom+3,230,32,scale)
    end
    love.graphics.setColor(ctx.colors.cream);text(b.message or '',l.x+250,l.bottom+3,l.w-264,32,scale)
    local canAct=active and active.team=='ally'and active.hp>0 and(not ctx.canAct or ctx.canAct(active))
    local enabled=canAct and not Native.busy(b)
    local cache=canAct and not b.finished and Search.nearby(ctx.saveData,b,active)
    if cache then
        local rect=ctx.button(ctx.mobileEnabled and'SEARCH RUIN'or'SEARCH RUIN [F]',l.x+14,l.header+65*l.fontScale,230*l.fontScale,44*l.fontScale,enabled,.78)
        ui.battleSearch=rect;ui.battleOptions[#ui.battleOptions+1]={rect=rect,action='search',enabled=enabled,cacheId=cache.id}
        love.graphics.setColor(ctx.colors.cream);text('Uses turn action',rect.x+rect.w+8,rect.y,170*l.fontScale,rect.h,.67*l.fontScale)
    end
    local buttons={}
    local function add(key,label,action,ok,name)buttons[#buttons+1]={key=key,label=label,action=action,enabled=ok~=false,name=name}end
    if b.finished then
        if ctx.hostControls~=false then add('battleContinue',b.finished=='win'and'CONTINUE'or'RETURN TO TRAIN',b.finished=='win'and'continue_win'or'continue_loss')end
    elseif canAct then
        local options=Weapons.options(ctx.saveData,active,Catalog);b.options=options
        for i,selector in ipairs(options)do
            local info=Weapons.resolve(ctx.saveData,active,selector,Catalog);local name=info and info.name or'scratch'
            local label=(Catalog.weaponStats[name]and Catalog.weaponStats[name].name or Util.titleFromFile(name)):gsub('^Frontier%s+','')
            add('weapon'..i,i..' '..label,'weapon'..i,enabled)
        end
        add('battleMove',b.moveUsed and'MOVE USED'or(Grid.moveBudget(b,active)>active.move and'MARCH'or'MOVE'),'move',enabled and not b.moveUsed)
        add('battleHeal','HEAL','heal',enabled);add('battleGuard','GUARD','guard',enabled)
        add('battleAbility','ABILITY','ability',enabled and not b.abilitiesUsed[active.id]);add('battleInventory','BACKPACK','inventory',true)
        add('battleEnd','END TURN','end',enabled)
        if ctx.hostControls~=false then add('battleRetreat','RETREAT','retreat',true)end
        local data=Actors.data(ctx.saveData,active);local count=0
        for slot=1,data.inventoryCapacity or 6 do
            local name=data.inventory[slot];local effect=name and Catalog.itemEffects[name]
            if effect and effect.potion and count<2 then count=count+1;add('potion'..count,string.upper(effect.shortName or effect.potion),'potion',enabled,name)end
        end
    elseif ctx.hostControls~=false and not b.finished then add('battleRetreat','RETREAT','retreat',true)end
    local columns=l.w>=1350 and math.max(1,#buttons)or 6
    local w=(l.w-28-(columns-1)*6)/columns;local h=(ctx.mobileEnabled and 48 or 39)*l.fontScale
    for i,item in ipairs(buttons)do
        local rect=ctx.button(item.label,l.x+14+((i-1)%columns)*(w+6),l.bottom+39*l.fontScale+math.floor((i-1)/columns)*(h+5),w,h,item.enabled,ctx.mobileEnabled and .80 or .72)
        ui.battleOptions[#ui.battleOptions+1]={rect=rect,action=item.action,enabled=item.enabled,name=item.name}
        if item.key:match('^weapon')then ui.battleWeapons[#ui.battleWeapons+1]=rect
        elseif item.action=='potion'then ui.battlePotionButtons[#ui.battlePotionButtons+1]={rect,name=item.name}
        else ui[item.key]=rect end
    end
    Presentation.drawPanel(ctx,state,selected)
    if ctx.inventoryOpen then
        love.graphics.setColor(0,0,0,.65);love.graphics.rectangle('fill',l.x,0,l.w,ctx.H);ui.drawInventory()
        ui.battleInventoryClose=ctx.button('CLOSE BACKPACK',300,20,250,48,true,.8)
    else ui.battleInventoryClose=nil end
    love.graphics.pop()
end
function Native.project(ctx,q,r)
    local state=ctx.ui.nativeBattle;if not state then return nil end
    return state.renderer.camera:project(q+.5,Field.cellHeight(ctx.battle.field,q,r),r-.5)
end
function Native.cameraAction(ui,b,action)
    local state=ui.nativeBattle;if not state then return end;local c=state.renderer.camera
    if action=='overview'then c:frame(b.field.columns,b.field.rows)
    elseif action=='focus'then local u=focusUnit(b);c:focus(u.q,u.r,Field.cellHeight(b.field,u.q,u.r));c:setZoom(1.05)
    elseif action=='left'then c:orbit(-15,0)elseif action=='right'then c:orbit(15,0)
    elseif action=='tiltUp'then c:orbit(0,5)elseif action=='tiltDown'then c:orbit(0,-5)
    elseif action=='grid'then state.grid=not state.grid end
    if action=='info'or action=='log'then state.panel=state.panel==action and nil or action;state.panelScroll=nil
    elseif action=='panelClose'then state.panel=nil
    elseif action=='panelUp'then state.panelScroll=math.max(0,(state.panelScroll or 0)-(state.panelPage or 80))
    elseif action=='panelDown'then state.panelScroll=math.min(state.panelMaxScroll or 0,(state.panelScroll or 0)+(state.panelPage or 80))end
end
function Native.key(ui,b,key,alt)
    local c=Native.camera(ui,b);if not c then return false end
    if alt then
        if key=='left'then c:pan(70,0)elseif key=='right'then c:pan(-70,0)elseif key=='up'then c:pan(0,70)elseif key=='down'then c:pan(0,-70)else return false end
    elseif key=='q'then c:orbit(-15,0)elseif key=='e'then c:orbit(15,0)
    elseif key=='['then c:orbit(0,-5)elseif key==']'then c:orbit(0,5)
    elseif key=='o'then Native.cameraAction(ui,b,'overview')elseif key=='home'or key=='0'or key=='kp0'then Native.cameraAction(ui,b,'focus')
    elseif key=='+'or key=='='or key=='kp+'then c:setZoom(c.zoom*1.13)
    elseif key=='-'or key=='kp-'then c:setZoom(c.zoom/1.13)else return false end
    return true
end
function Native.beginDrag(ui,b,x,y,button,shift)
    local c=Native.camera(ui,b);if not c or not c:contains(x,y)or Util.pointIn(x,y,ui.battleMinimap)then return false end
    if button~=2 and button~=3 and not(button==1 and shift)then return false end
    ui.nativeBattle.drag={x=x,y=y,startX=x,startY=y,mode=button==2 and'orbit'or'pan',button=button,moved=false};return true
end
function Native.drag(ui,x,y)
    local state=ui.nativeBattle;local d=state and state.drag;if not d then return false end
    local dx,dy=x-d.x,y-d.y;d.x,d.y=x,y;d.moved=d.moved or math.abs(x-d.startX)+math.abs(y-d.startY)>4
    if d.mode=='orbit'then state.renderer.camera:orbit(-dx*.45,dy*.25)else state.renderer.camera:pan(dx,dy)end
    return true
end
function Native.endDrag(ui)
    local state=ui.nativeBattle;local d=state and state.drag;if not d then return nil end
    state.drag=nil;return d
end
function Native.handleMouse(ctx,x,y,right)
    local b,ui=ctx.battle,ctx.ui;local state=ui.nativeBattle;if not state then return 'handled'end
    if ctx.inventoryOpen then
        if Util.pointIn(x,y,ui.battleInventoryClose)or x<545 or x>935 or y<35 or y>695 then ctx.setInventoryOpen(false);ctx.resetInventoryDrag()
        elseif not right then ctx.handleInventoryClick(x,y)end
        return 'handled'
    end
    for _,control in ipairs(ui.battleCameraButtons or{})do if Util.pointIn(x,y,control.rect)then Native.cameraAction(ui,b,control.action);return'handled'end end
    if Util.pointIn(x,y,state.panelRect)then return'handled'end
    if Util.pointIn(x,y,ui.battleMinimap)then
        local rect=ui.battleMinimap;local c=state.renderer.camera
        c.targetX=(x-rect.x)/rect.w*b.field.columns;c.targetZ=(y-rect.y)/rect.h*b.field.rows
        c.targetY=Field.heightAt(b.field,c.targetX,c.targetZ)+.7;return'handled'
    end
    for _,item in ipairs(ui.battleOptions or{})do if item.enabled and Util.pointIn(x,y,item.rect)then
        local action=item.action
        if action=='retreat'then return ctx.hostControls~=false and not b.finished and'retreat'or'handled'end
        if action=='continue_win'or action=='continue_loss'then return ctx.hostControls~=false and b.finished and(b.finished=='win'and'continue_win'or'continue_loss')or'handled'end
        local active=Rules.activeUnit(b)
        if b.finished or Native.busy(b)or not active or active.team~='ally'or active.hp<=0 or ctx.canAct and not ctx.canAct(active)then return'handled'end
        if action=='inventory'then ctx.setInventoryOpen(true);ctx.resetInventoryDrag()
        elseif action:match('^weapon')then ctx.battleAttack(b.options[tonumber(action:match('%d+'))])
        elseif action=='move'then if ctx.setMoveMode then ctx.setMoveMode()else b.phase='move'end
        elseif action=='heal'then ctx.battleHeal()elseif action=='guard'then ctx.battleGuard()
        elseif action=='search'then ctx.battleSearch(item.cacheId)
        elseif action=='ability'then ctx.useBattleAbility(Catalog.characterAbility(Rules.activeUnit(b).file).kind)
        elseif action=='end'then ctx.advanceBattleTurn()elseif action=='potion'then ctx.useBattlePotion(item.name)end
        return'handled'
    end end
    for _,hit in ipairs(state.cacheHits or{})do if Util.pointIn(x,y,hit.rect)then
        local active=Rules.activeUnit(b)
        if not right and not b.finished and not Native.busy(b)and active and(not ctx.canAct or ctx.canAct(active))then
            if Search.available(ctx.saveData,b,active,hit.id)then ctx.battleSearch(hit.id)
            else ctx.setBattlePrompt(hit.taken and'This ruin has already been searched.'or'Move onto or next to this cache, then search. Uses turn action.')end
        end
        return'handled'
    end end
    local q,r=state.renderer:pick(x,y)
    local clicked= q and Rules.unitAt(b,q,r)or nil
    if clicked and not Fog.unitVisible(b,clicked)then clicked=nil end
    local depth=math.huge
    local terrainTarget=b.phase=='target'and clicked and clicked.team=='enemy'
    if(right or b.phase~='move')and not terrainTarget then
        for _,hit in ipairs(state.unitHits or{})do if hit.depth<depth and(right or b.phase~='target'or hit.unit.team=='enemy')and Fog.unitVisible(b,hit.unit)and Util.pointIn(x,y,hit)then
            for _,u in ipairs(b.units)do if u.id==hit.unit.id and Fog.unitVisible(b,u)then clicked=u;q,r=u.q,u.r;depth=hit.depth;break end end
        end end
    end
    if not q then return'handled'end
    if right then if clicked then b.selected=clicked.id;state.panel='info';state.panelScroll=0 end;return'handled'end
    local active=Rules.activeUnit(b)
    if b.finished or Native.busy(b)or not active or active.team~='ally'or active.hp<=0 or ctx.canAct and not ctx.canAct(active)then
        if clicked then b.selected=clicked.id end;return'handled'
    end
    if clicked and b.phase=='target'and clicked.team=='enemy'then ctx.resolveBattleAttack(active,clicked,b.chosenWeapon or'scratch',b.chosenItemId)
    elseif clicked then b.selected=clicked.id
    elseif b.phase~='target'then ctx.battleMoveTo(q,r)end
    return'handled'
end
return Native
