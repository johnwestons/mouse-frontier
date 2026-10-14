-- Guest radio/editor state is disposable. Only host receipts change objects.
local Access=require('game.coop_object_access')
local Entities=require('game.coop_entities')
local Style=require('game.ui_layout')
local Focus=require('game.ui_focus')
local Preferences=require('game.local_preferences')
local Util=require('game.util')
local Panel={}; Panel.__index=Panel
local properties={'x','y','scale','rotation','layer','hue','saturation'}
local failures={activity_busy='This object is being edited. Try again when it is free.',actor_busy='Finish your current activity first.',
    lease_expired='The editing session expired. Select the object again.',lease_owner='Select the object again to edit it.',
    stale_revision='The object changed. Review it and try again.',stale_scene='The host moved the party. The editor has closed.',
    object_unavailable='This object is unavailable in the current car.',radio_unavailable='Move closer to the radio.',
    permanent='This stays aboard the train.',container_not_empty='Empty this container before collecting it.',
    inventory_full='Make space in your backpack before collecting this object.',rate_limited='Please wait a moment and try again.'}
local function copy(item)
    local result={}; for k,v in pairs(item) do result[k]=v end; return result
end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function Panel.new(view,c) return setmetatable({view=view,c=c,runtime=view.runtime,ui=view.ui},Panel) end
function Panel:state() return {screen=self.runtime.state,scene=self.runtime.scene,x=self.runtime.player.x,y=self.runtime.player.y} end
function Panel:busy()
    if self.view.activityBusy and self.view:activityBusy() then return true end
    if self.runtime.peopleOpen or self.view.people and self.view.people.pending then return true end
    return self.pending or self.view.inventory.pending or self.view.trade.pending or self.view.train.pending
        or self.runtime.inventoryOpen or self.runtime.tradeOpen or self.runtime.trainUpgradeOpen
end
function Panel:nearestRadio()
    if self:busy() or self.runtime.editMode or self.ui.radioOpen or not self.view:actionsAllowed() then return nil end
    return Access.nearestRadio(self.runtime.saveData,self:state())
end
function Panel:openRadio()
    local item=self:nearestRadio(); if not item then return false end
    self.radioId=item.entityId; self.ui.radioOpen=true; self.epoch=self.view.epoch; self.car=nil
    self.notice=nil; self.ui.keyboardFocusId=nil; self.view:neutralize(); return true
end
function Panel:openEditor()
    if self:busy() or self.ui.radioOpen or not self.view:actionsAllowed() or self.runtime.scene~='train' then return false end
    self.runtime.editMode=true; self.epoch=self.view.epoch; self.car=self.runtime.saveData.activeCar
    self.notice=nil; self.ui.keyboardFocusId=nil; self.view:neutralize(); return true
end
function Panel:submit(command,args,id,cleanup)
    if self.pending or self.view.inventory.pending or self.view.trade.pending or self.view.train.pending
        or not cleanup and not self.view:actionsAllowed() then return false end
    local request,reason=self.view.controller.network:submitCommand(command,args,self.epoch,
        Access.expected(self.runtime.saveData,command,'companion',id))
    if not request then self.notice=failures[reason] or 'Action unavailable. Try again when ready.'; return false end
    self.pending={id=request,command=command,entityId=id}; self.notice='Waiting for the host...'; return true
end
function Panel:radio(station,rainEnabled)
    if not self.ui.radioOpen or not Access.radio(self.runtime.saveData,self.radioId,self:state()) then return false end
    return self:submit('radio.station',{entityId=self.radioId,station=station,rainEnabled=rainEnabled},self.radioId)
end
function Panel:items()
    local list={}
    for _,item in ipairs(self.runtime.saveData.droppedItems or {}) do
        if Access.decoration(self.runtime.saveData,item.entityId,self:state()) then list[#list+1]=item end
    end
    return list
end
function Panel:selected()
    return self.entityId and Access.decoration(self.runtime.saveData,self.entityId,self:state())
end
function Panel:draftOf(item)
    if not item then return nil end
    local draft=copy(item)
    if draft.layer==nil then for i,value in ipairs(self.runtime.saveData.droppedItems) do if value.entityId==item.entityId then draft.layer=i; break end end end
    return draft
end
function Panel:select(id)
    if not self.runtime.editMode or self.pending or not self.view:actionsAllowed()
        or not Access.decoration(self.runtime.saveData,id,self:state()) then return false end
    if self.lease then
        if self.entityId==id then return true end
        self.switchId=id; self.wantRelease=true; self.draft=nil; self.drag=nil; return true
    end
    self.entityId=id; return self:submit('decoration.acquire',{entityId=id},id)
end
function Panel:cycle(step)
    if self.pending then return false end
    local items=self:items(); if #items==0 then return false end
    local at=step<0 and 1 or 0; for i,item in ipairs(items) do if item.entityId==self.entityId then at=i; break end end
    return self:select(items[((at-1+step)%#items)+1].entityId)
end
function Panel:preview(item)
    return self.runtime.editMode and self.draft and item.entityId==self.entityId and self.draft or item
end
function Panel:change(values)
    if not self.runtime.editMode or not self.lease or self.pending or self.wantRelease or not self.view:actionsAllowed() or not self:selected() then return false end
    self.draft=self.draft or self:draftOf(self:selected())
    for key,value in pairs(values) do self.draft[key]=value end
    self.dirty=true; return true
end
function Panel:apply()
    if not self.dirty or not self.lease or self.pending or not self.runtime.editMode then return false end
    local values={}; for _,key in ipairs(properties) do
        local defaults={scale=1,rotation=0,layer=0,hue=0,saturation=1}
        values[key]=self.draft[key] or defaults[key]
    end
    return self:submit('decoration.place',{leaseId=self.lease,values=values},self.entityId)
end
function Panel:revert()
    if self.pending then return false end
    self.draft=self:draftOf(self:selected()); self.dirty=nil; self.drag=nil; return true
end
function Panel:collect()
    if not self.lease or not self.runtime.editMode then return false end
    return self:submit('decoration.collect',{leaseId=self.lease},self.entityId)
end
function Panel:suspend()
    self.runtime.editMode=false; self.ui.radioOpen=false; self.radioId=nil; self.switchId=nil
    self.drag=nil; self.touch=nil; self.draft=nil; self.dirty=nil; self.ui.keyboardFocusId=nil
    if self.lease or self.pending and self.pending.command=='decoration.acquire' then self.wantRelease=true end
end
function Panel:update()
    local invalid=self.epoch and (self.epoch~=self.view.epoch or self.car and self.car~=self.runtime.saveData.activeCar)
    if invalid then self:suspend(); self.lease=nil; self.wantRelease=nil end -- Host clears scene/car leases.
    if (self.runtime.editMode or self.ui.radioOpen) and (not self.view.focused or self.view.controller.menuOpen) then self:suspend() end
    if self.ui.radioOpen and not Access.radio(self.runtime.saveData,self.radioId,self:state()) then self.ui.radioOpen=false; self.radioId=nil end
    local result=self.view.controller.network.lastCommandResult; local pending=self.pending
    if pending and result and result.requestId==pending.id then
        if result.savePending or result.reason=='save_pending' or result.reason=='busy' then self.notice='Waiting for the host to finish saving...'; return end
        if result.ok and self.runtime.saveData.coop.revision<result.revision then self.notice='Updating shared objects...'; return end
        self.pending=nil
        if not result.ok then
            self.notice=failures[result.reason] or 'That action could not be completed. Review it and try again.'
            if pending.command=='activity.release' and result.reason~='lease_expired' and result.reason~='lease_owner' and result.reason~='stale_scene' then
                self.wantRelease=true; self.retryReleaseAt=self.view.elapsed+.6
            elseif pending.command=='decoration.acquire' or pending.command=='activity.release' or result.reason=='lease_expired'
                or result.reason=='lease_owner' or result.reason=='object_unavailable' then
                self.lease=nil; self.entityId=nil; self.draft=nil; self.dirty=nil; self.wantRelease=nil
            end
        elseif pending.command=='decoration.acquire' then
            if not invalid then
                self.lease=result.details.leaseId; self.entityId=result.details.entityId
                self.renewAt=self.view.elapsed+10; self.draft=self:draftOf(self:selected())
                self.notice='Edit locally, then Apply to share the change.'
            end
        elseif pending.command=='activity.release' or pending.command=='decoration.collect' then
            self.lease=nil; self.entityId=nil; self.draft=nil; self.dirty=nil; self.wantRelease=nil
            self.notice=pending.command=='decoration.collect' and 'Object moved to your backpack.' or nil
        elseif pending.command=='decoration.place' then
            self.renewAt=self.view.elapsed+10
            if not pending.renewal then self:revert(); self.notice='Placement saved.' end
        elseif pending.command=='radio.station' then
            Preferences.followRadio(self.runtime.saveData); self.notice='Shared radio updated.'
        end
    end
    if self.pending then return end
    if self.wantRelease and self.lease then
        if self.view.elapsed>=(self.retryReleaseAt or 0) then self:submit('activity.release',{leaseId=self.lease},self.entityId,true) end
        return
    end
    if self.switchId and not self.lease and self.runtime.editMode then
        local id=self.switchId; self.switchId=nil; self:select(id); return
    end
    if self.lease and self.runtime.editMode and not self:selected() then self:suspend() end
    if self.lease and self.runtime.editMode and self.view:actionsAllowed() and self.view.elapsed>=self.renewAt then
        if self:submit('decoration.place',{leaseId=self.lease,values={}},self.entityId) then self.pending.renewal=true end
    end
end
function Panel:localAudio(name)
    if self.c.audio and self.c.audio[name] then self.c.audio[name](self.runtime) end
end
function Panel:targets()
    local list={}
    for _,control in ipairs(self.controls or {}) do list[#list+1]=control end
    return list
end
function Panel:keypressed(key)
    if key=='escape' or key=='acback' or key=='p' or key=='o' then self:suspend()
    elseif key=='tab' or key=='up' or key=='down' or key=='left' or key=='right' then
        Focus.move(self.ui,self:targets(),'guest-objects',key,love.keyboard.isDown('lshift','rshift'))
    elseif key=='return' or key=='kpenter' or key=='space' then
        local t=Focus.current(self.ui,self:targets(),'guest-objects'); if t and t.enabled then t.action() end
    end
    return true
end
function Panel:press(x,y)
    for _,target in ipairs(self:targets()) do
        if Util.pointIn(x,y,target.rect) then
            if target.enabled then self.ui.keyboardFocusId=target.id; target.action()
                if target.slider then self.drag={slider=target.slider,rect=target.rect}; self:move(x,y) end
            end
            return true
        end
    end
    if self.runtime.editMode and not self.pending then
        local wx,wy=self.view:objectPoint(x,y); local best,layer
        for i,item in ipairs(self:items()) do
            local preview=self:preview(item)
            if math.abs(wx-preview.x-31)<=14 and math.abs(wy-preview.y-31)<=14 and (not layer or (preview.layer or i)>layer) then best,layer=item,preview.layer or i end
        end
        if best then
            if self.lease and best.entityId==self.entityId then self.drag={world=true}; self:move(x,y)
            else self:select(best.entityId) end
        end
    end
    return true
end
function Panel:move(x,y)
    if not self.drag then return true end
    if self.drag.slider then
        local value=clamp((x-self.drag.rect.x)/self.drag.rect.w,0,1)
        self:change(self.drag.slider=='hue' and {hue=value} or {saturation=value*2})
    else local wx,wy=self.view:objectPoint(x,y); self:change({x=clamp(wx,0,960),y=clamp(wy,0,720)}) end
    return true
end
function Panel:releasePointer(x,y) if self.drag then self:move(x,y); self.drag=nil end; return true end
function Panel:draw()
    local g=love.graphics; local text=function(...) self.view.trade:textBox(...) end
    local button=function(label,x,y,w,h,enabled) return Style.transformRect(self.view.inventory:button(label,x,y,w,h,enabled,.8)) end
    self.controls={}; local function add(id,label,x,y,w,h,action,enabled)
        local rect=button(label,x,y,w,h,enabled~=false)
        self.ui['object_'..id]=rect; self.controls[#self.controls+1]={id=id,rect=rect,enabled=enabled~=false,action=action}; return rect
    end
    g.setColor(0,0,0,self.ui.radioOpen and .72 or .18); g.rectangle('fill',0,0,960,720)
    if self.ui.radioOpen then Style.scope('radio',{x=145,y=110,w=670,h=510},function()
        self.view.inventory:frame(145,110,670,510,1,1); g.setColor(self.c.colors.brass); text('RADIO',175,130,610,50,1.3,'center')
        local audio=self.runtime.saveData.audio or {}; g.setColor(self.c.colors.cream)
        text(self.notice or ('Shared station: '..(audio.station or 'chill')..' / Rain '..(audio.rainEnabled~=false and 'ON' or 'OFF')),175,195,610,50,.9,'center')
        for i,station in ipairs({'8bit','chill','vibes'}) do
            add(station,station:upper(),175+(i-1)*207,263,196,60,function() self:radio(station) end,not self.pending)
        end
        add('rain',audio.rainEnabled~=false and 'RAIN OFF' or 'RAIN ON',175,335,610,54,function() self:radio(nil,audio.rainEnabled==false) end,not self.pending)
        text('Playback controls affect this device.',175,398,610,35,.8,'center')
        for i,entry in ipairs({{'previous','PREV','previousTrack'},{'pause','PLAY / PAUSE','togglePause'},{'next','NEXT','nextTrack'},{'mute','MUTE','toggleMute'}}) do
            local name=entry[3]; add(entry[1],entry[2],175+(i-1)*155,443,145,54,function() self:localAudio(name) end,true)
        end
        add('close','CLOSE RADIO',310,533,340,60,function() self:suspend() end,true)
    end) else Style.scope('guest-editor',{x=90,y=80,w=780,h=302},function()
        self.view.inventory:frame(90,80,780,302,1,1); g.setColor(self.c.colors.brass)
        text('TRAIN DECORATIONS',110,88,740,32,1,'center'); g.setColor(self.c.colors.cream)
        text(self.entityId and self:selected() and Util.titleFromFile(self:selected().name) or 'Select an object or its yellow handle.',225,131,510,40,.82,'center')
        add('previous','<',115,130,90,44,function() self:cycle(-1) end,not self.pending)
        add('next','>',755,130,90,44,function() self:cycle(1) end,not self.pending)
        local item=self.draft or self:selected(); local enabled=not self.pending and self.lease~=nil and not self.wantRelease and item~=nil
        local function change(values) return function() self:change(values()) end end
        local entries={
            {'left','LEFT',change(function() return {x=clamp(item.x-5,0,960)} end)},
            {'right','RIGHT',change(function() return {x=clamp(item.x+5,0,960)} end)},
            {'up','UP',change(function() return {y=clamp(item.y-5,0,720)} end)},
            {'down','DOWN',change(function() return {y=clamp(item.y+5,0,720)} end)},
            {'smaller','SIZE -',change(function() return {scale=clamp((item.scale or 1)-.1,.5,2.5)} end)},
            {'larger','SIZE +',change(function() return {scale=clamp((item.scale or 1)+.1,.5,2.5)} end)},
            {'rotate','ROTATE',change(function() return {rotation=((item.rotation or 0)+math.pi/4)%(math.pi*2)} end)},
            {'back','LAYER -',change(function() return {layer=clamp((item.layer or 0)-1,-100000,100000)} end)},
            {'front','LAYER +',change(function() return {layer=clamp((item.layer or 0)+1,-100000,100000)} end)},
            {'collect','PICK UP',function() self:collect() end},
            {'apply','APPLY',function() self:apply() end},
            {'revert','REVERT',function() self:revert() end},
        }
        for i,e in ipairs(entries) do add(e[1],e[2],115+((i-1)%6)*124,185+math.floor((i-1)/6)*53,114,44,e[3],enabled and (e[1]~='apply' or self.dirty==true)) end
        local function slider(id,label,x,value,maximum)
            g.setColor(self.c.colors.cream); text(label,x,295,225,23,.72)
            g.setColor(.25,.2,.14,1); g.rectangle('fill',x,331,225,10,4,4)
            g.setColor(1,.78,.1,1); g.circle('fill',x+clamp(value/maximum,0,1)*225,336,7)
            local rect=Style.transformRect({x=x,y=319,w=225,h=34})
            self.ui['object_'..id]=rect
            self.controls[#self.controls+1]={id=id,rect=rect,enabled=enabled,slider=id,action=function()
                self:change({[id]=(value+.05*maximum)%(maximum+.000001)})
            end}
        end
        slider('hue','HUE '..math.floor((item and item.hue or 0)*360),125,item and item.hue or 0,1)
        slider('saturation','SATURATION '..math.floor((item and item.saturation or 1)*100)..'%',395,item and item.saturation or 1,2)
        add('close','DONE',685,306,160,54,function() self:suspend() end,true)
        g.setColor(self.c.colors.cream); text(self.notice or (self.dirty and 'Preview only. Apply to save and share.' or 'Changes stay local until you Apply.'),115,352,730,25,.72,'center')
    end) end
    if self.ui.keyboardFocusVisible then Focus.draw(Focus.current(self.ui,self:targets(),'guest-objects')) end
end
return Panel
