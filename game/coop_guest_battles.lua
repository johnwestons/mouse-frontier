-- The shared battlefield is inspected locally; owned actions go to the host.
local UI=require('game.battle_ui')
local Rules=require('game.battle_rules')
local Grid=require('game.battle_grid')
local Actors=require('game.battle_actors')
local Weapons=require('game.battle_weapon_ownership')
local Commands=require('game.coop_battles')
local Style=require('game.ui_layout')
local Focus=require('game.ui_focus')
local WorldView=require('game.world_view')
local Animation=require('game.battle_controller')
local Accessibility=require('game.accessibility')
local Native=require('game.battle_native_ui')
local Panel={}; Panel.__index=Panel
function Panel.new(view,c)
    local self=setmetatable({view=view,c=c,runtime=view.runtime,ui=view.ui},Panel)
    self.worldView=WorldView.new({apply=function() view.camera:apply(480,250) end,
        toWorld=function(x,y) return view.camera:toWorld(x,y,480,250) end,
        toScreen=function(x,y) return (x-480)*view.camera.zoom+480+view.camera.panX,(y-250)*view.camera.zoom+250+view.camera.panY end})
    return self
end
function Panel:available() return self.runtime.saveData and self.runtime.saveData.tacticalBattle~=nil end
function Panel:canAct(unit)
    local b=self.runtime.battle
    return self.view.ready and self.view.focused and not self.view.controller.menuOpen and not self.pending
        and self.view.controller.network and not self.view.controller.network.pendingCommand
        and b and not b.finished and unit and unit.hp>0 and Actors.id(unit)=='companion'
end
function Panel:chooseWeapon(selector)
    local b=self.runtime.battle; local unit=b and Rules.activeUnit(b)
    local s=self.runtime.saveData and self.runtime.saveData.tacticalBattle
    if not s or not self:canAct(unit) then return false end
    local info=Weapons.resolve(self.runtime.saveData,unit,selector,self.c.catalog)
    if not info then return false end
    -- Selecting a target is a local preview, just like choosing a move cell.
    -- The one attack request still quotes the exact equipped item and turn.
    self.weapon={key=info.key,name=info.name,unitId=unit.id,turn=s.revision,encounterId=s.encounterId,
        epoch=self.view.epoch,network=self.view.controller.network}
    self.epoch=self.view.epoch; self.turn=s.revision; self.mode='target'
    self.notice='Choose an enemy within '..Rules.weaponRange(self.c.catalog,info.name)..' terrain space(s).'
    return true
end
function Panel:targetWeapon()
    local w=self.weapon; if not w then return end
    local s=self.runtime.saveData and self.runtime.saveData.tacticalBattle
    local b=self.runtime.battle; local unit=b and Rules.activeUnit(b)
    local valid=s and not b.finished and s.encounterId==w.encounterId and s.revision==w.turn
        and unit and unit.id==w.unitId and unit.hp>0 and self.view.epoch==w.epoch
        and self.view.controller.network==w.network and self.view.focused and not self.view.controller.menuOpen
    local info=valid and Weapons.resolve(self.runtime.saveData,unit,w.key,self.c.catalog)
    if info and info.name==w.name then return w end
    self.weapon=nil
    if self.mode=='target' then self.mode=nil; self.notice=nil end
end
function Panel:submit(name,extra)
    local s=self.runtime.saveData.tacticalBattle; local b=self.runtime.battle
    if not s or not self:canAct(Rules.activeUnit(b)) then return false end
    local args={encounterId=s.encounterId,turnRevision=s.revision,unitId=b.units[b.active].id}
    for key,value in pairs(extra or {}) do args[key]=value end
    local pending={name=name,args=args,epoch=self.view.epoch,encounterId=s.encounterId,
        network=self.view.controller.network,startedAt=self.elapsed or 0}
    local id,reason=self:send(pending)
    if not id then self.notice='Action unavailable. Wait for the battlefield to update.'; return false,reason end
    self.pending=pending; self.mode=nil; self.weapon=nil; self.notice='Action sent. Waiting for the host...'; return true
end
function Panel:send(pending)
    local expected={}; for _,scope in ipairs(Commands.scopes(self.runtime.saveData)) do expected[scope]=self.runtime.saveData.coop.revisions[scope] or 0 end
    local id,reason=pending.network:submitCommand(pending.name,pending.args,pending.epoch,expected)
    if id then pending.id=id; pending.retryAt=nil; pending.sourceRevision=self.runtime.saveData.coop.revision end
    return id,reason
end
-- These timers only animate the private presentation copy. HP, board positions,
-- RNG, turn advancement and inventory still come exclusively from the host.
function Panel:animate(dt,s)
    local b=self.runtime.battle; local previous=self.visual
    if not b or not s then self.visual=nil; return end
    if previous and previous.battle~=b and previous.epoch==self.view.epoch
        and previous.encounterId==s.encounterId and previous.turn==s.revision then
        local old=previous.battle
        for _,key in ipairs({'attackTimer','enemyDelay','hitFlash'}) do b[key]=math.min(b[key] or 0,old[key] or 0) end
        if not old.intro then b.intro=nil elseif b.intro then b.intro=math.max(b.intro,old.intro) end
        local function motion(current,prior)
            if not prior then return nil end
            if current and current.fromQ==prior.fromQ and current.fromR==prior.fromR
                and current.toQ==prior.toQ and current.toR==prior.toR then current.t=math.max(current.t,prior.t) end
            return current
        end
        b.projectile=motion(b.projectile,old.projectile)
        for i,u in ipairs(b.units) do
            local prior=old.units[i]
            if prior and u.id==prior.id then
                for _,key in ipairs({'actionTimer','hitTimer','damageNumberTimer'}) do u[key]=math.min(u[key] or 0,prior[key] or 0) end
                u.moveAnim=motion(u.moveAnim,prior.moveAnim)
            end
        end
    end
    Animation.animate({battle=b},math.min(.25,dt or 0)*Accessibility.motionSpeed(self.runtime.saveData))
    self.visual={battle=b,epoch=self.view.epoch,encounterId=s.encounterId,turn=s.revision}
end
function Panel:update(dt)
    self.elapsed=(self.elapsed or 0)+(dt or 0)
    local s=self.runtime.saveData and self.runtime.saveData.tacticalBattle
    if not s then Native.release(self.ui)end
    self:targetWeapon()
    self:animate(dt,s)
    local p=self.pending
    if p and (not s or p.encounterId~=s.encounterId or p.epoch~=self.view.epoch or p.network~=self.view.controller.network) then
        self.pending=nil; self.notice=nil; self.mode=nil; self.selected=nil
    end
    if not s or self.epoch~=self.view.epoch then self.mode=nil; self.selected=nil; self.epoch=self.view.epoch end
    if s and self.turn~=s.revision then self.mode=nil; self.turn=s.revision end
    local p=self.pending; local reply=self.view.controller.network and self.view.controller.network.lastCommandResult
    if p and p.retryAt then
        local active=Rules.activeUnit(self.runtime.battle)
        if not s or s.revision~=p.args.turnRevision or not active or active.id~=p.args.unitId
            or self.runtime.battle.finished or not self.view.focused or self.view.controller.menuOpen
            or self.elapsed-p.startedAt>5 then
            self.pending=nil; self.notice='Action canceled. Review the current turn.'; return
        end
        if self.elapsed>=p.retryAt and self.view.ready and not p.network.pendingCommand
            and (not p.needsUpdate or self.runtime.saveData.coop.revision>p.sourceRevision) then
            self:send(p)
        end
        return
    end
    if not p or not reply or reply.requestId~=p.id then return end
    if reply.savePending or reply.reason=='save_pending' or reply.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
    if reply.ok and (reply.durable~=true or self.runtime.saveData.coop.revision<reply.revision) then return end
    if not reply.ok and (reply.reason=='battle_busy' or reply.reason=='stale_revision') then
        p.id=nil; p.retryAt=self.elapsed+.15; p.needsUpdate=reply.reason=='stale_revision'
        self.notice='Action queued. Waiting for the battlefield...'; return
    end
    self.pending=nil; self.lastOutcome=reply
    self.notice=not reply.ok and 'The turn changed or this action is unavailable. Review the battlefield.' or nil
end
function Panel:context()
    local content=self.c.content; local r=self.view.renderer
    local b={}; for key,value in pairs(self.runtime.battle) do b[key]=value end
    local weapon=self:targetWeapon()
    b.phase=self.mode or b.phase; b.selected=self.selected or b.selected; b.logScroll=self.logScroll or 0
    if weapon then b.chosenWeapon=weapon.name; b.chosenItemId=weapon.key end
    local ctx={W=960,H=720,battle=b,battleGrid=Grid,scenery=content.scenery,colors=self.c.colors,mobileEnabled=self.view.mobile.enabled,
        statusText=self.notice or(b.finished and'The host will continue when ready.'or b.pendingActorId=='companion'and'You will enter at the next turn.'
            or Actors.id(Rules.activeUnit(b))=='companion'and'Your turn. Choose an action.'or'Waiting for the active player.'),
        animationClock=self.runtime.animationClock,characterAnimations=self.c.characterAnimations and self.c.characterAnimations() or {},
        saveData=self.runtime.saveData,inventoryOpen=false,ui=self.ui,playerProgression=require('game.player_progression'),
        drawLandscape=r.drawLandscape,drawGround=r.drawGround,drawAnimatedCharacter=r.drawAnimatedCharacter,
        button=function(...) return Style.transformRect(self.view.inventory:button(...)) end,
        screenToGame=function(x,y) return require('game.viewport').toGame(x,y,960,720) end,
        pointerPosition=function() return love.mouse.getPosition() end,
        canAct=function(unit) return self:canAct(unit) end,hostControls=false,worldView=self.worldView,
        setInventoryOpen=function() self.view.inventory:toggle() end,resetInventoryDrag=function() self.view.inventory:cancelDrag() end,
        handleInventoryClick=function() end,
        setMoveMode=function() self.mode='move'; self.weapon=nil; self.notice=nil end,setBattlePrompt=function() end,
        battleAttack=function(weapon) self:chooseWeapon(weapon) end,
        resolveBattleAttack=function(_,target,weapon,id) self:submit('battle.attack',{weapon=id or weapon,targetId=target.id}) end,
        battleMoveTo=function(q,row)
            if (self.mode or self.runtime.battle.phase)~='target' then self:submit('battle.move',{q=q,r=row}) end
        end,
        battleHeal=function() self:submit('battle.heal') end,battleGuard=function() self:submit('battle.guard') end,
        battleSearch=function(id)self:submit('battle.search',{cacheId=id})end,
        advanceBattleTurn=function() self:submit('battle.endTurn') end,
        useBattleAbility=function(kind) self:submit('battle.ability',{kind=kind}) end,
        useBattlePotion=function(name) self:submit('battle.item',{name=name}) end}
    local images=self.view.scene and self.view.scene.battleImages or {}
    for _,key in ipairs({'characterImages','npcImages','mobImages','characterWalkImages','npcWalkImages','mobAttackImages',
        'mobIdleImages','mobHitImages','mobDeathImages','mobWalkImages','mobRangedImages'}) do ctx[key]=images[key] or content[key]or{}end
    return ctx
end
function Panel:draw()
    local ctx=self:context(); UI.draw(ctx); self.runtime.battle.options=ctx.battle.options
    if self.ui.keyboardFocusVisible then Focus.draw(Focus.current(self.ui,self:targets(),'guest-battle')) end
    local b=self.runtime.battle; local active=Rules.activeUnit(b)
    local text=self.notice or (b.finished and 'The host will continue when ready.'
        or b.pendingActorId=='companion' and 'You will enter at the next turn.'
        or Actors.id(active)=='companion' and 'Your turn. Choose an action.' or 'Waiting for the active player.')
    if not b.field then love.graphics.setColor(1,.9,.7,1);love.graphics.printf(text,110,690,740,'center')end
end
function Panel:pointer(x,y,right)
    local ctx=self:context(); UI.handleMouse(ctx,x,y,right)
    self.selected=ctx.battle.selected; self.logScroll=ctx.battle.logScroll; return true
end
function Panel:targets()
    local targets={}; local function add(id,rect,action)
        if rect and rect.enabled~=false then targets[#targets+1]={id=id,rect=rect,action=action} end
    end
    for i,rect in ipairs(self.ui.battleWeapons or {}) do add('weapon'..i,rect,function() self:pointer(rect.x+rect.w/2,rect.y+rect.h/2) end) end
    for _,key in ipairs({'battleMove','battleHeal','battleGuard','battleSearch','battleAbility','battleEnd','battleInventory'}) do
        local rect=self.ui[key]; add(key,rect,function() self:pointer(rect.x+rect.w/2,rect.y+rect.h/2) end)
    end
    for i,control in ipairs(self.ui.battleCameraButtons or{})do
        local rect=control.rect;add('camera'..i,rect,function()self:pointer(rect.x+rect.w/2,rect.y+rect.h/2)end)
    end
    for index,entry in ipairs(self.ui.battlePotionButtons or {}) do
        local rect=entry[1]
        add('potion'..index,rect,function() self:pointer(rect.x+rect.w/2,rect.y+rect.h/2) end)
    end
    local b=self.runtime.battle; local active=Rules.activeUnit(b)
    self:targetWeapon()
    if self:canAct(active) then
        local cells={}
        if (self.mode or b.phase)=='move' then for _,cell in pairs(Rules.reachable(b,active,Grid.moveBudget(b,active))) do cells[#cells+1]=cell end
        elseif (self.mode or b.phase)=='target' then for _,u in ipairs(b.units) do if u.team=='enemy' and u.hp>0 and require('game.battle_fog').unitVisible(b,u)then cells[#cells+1]=u end end end
        table.sort(cells,function(a,b) return a.q==b.q and a.r<b.r or a.q<b.q end)
        for _,cell in ipairs(cells) do
            local x,y
            if b.field then x,y=Native.project(self:context(),cell.q,cell.r)
            else x,y=Grid.boardToScreen(1,cell.q,cell.r);x,y=self.worldView.toScreen(x,y)end
            x,y=x or -1000,y or -1000
            local rect=Style.transformRectFor('battle',{x=0,y=0,w=960,h=720},{x=x-20,y=y-12,w=40,h=24})
            add('cell'..cell.q..':'..cell.r,rect,function() self:pointer(rect.x+20,rect.y+12) end)
        end
    end
    return targets
end
function Panel:keypressed(key)
    if self.runtime.battle and self.runtime.battle.field and Native.key(self.ui,self.runtime.battle,key,love.keyboard and love.keyboard.isDown('lalt','ralt'))then return true end
    if key=='i' then self.view.inventory:toggle(); return true end
    if key=='escape' or key=='acback' then self.view.controller:open(); return true end
    if key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then
        return Focus.move(self.ui,self:targets(),'guest-battle',key,love.keyboard.isDown('lshift','rshift'))
    end
    if key=='return' then local target=Focus.current(self.ui,self:targets(),'guest-battle'); if target then target.action() end; return true end
    local b=self.runtime.battle; if not self:canAct(Rules.activeUnit(b)) then return true end
    local index=tonumber(key)
    if index and b.options and b.options[index] then self:chooseWeapon(b.options[index])
    elseif key=='m' and not b.moveUsed then self.mode='move'; self.weapon=nil; self.notice=nil
    elseif key=='g' then self:submit('battle.guard')
    elseif key=='h' then self:submit('battle.heal')
    elseif key=='f'then
        local cache=require('game.battle_search').nearby(self.runtime.saveData,b,Rules.activeUnit(b))
        if cache then self:submit('battle.search',{cacheId=cache.id})end
    elseif key=='space' then self:submit('battle.endTurn') end
    return true
end
return Panel
