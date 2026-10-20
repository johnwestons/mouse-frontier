local GuiArt=require('game.gui_art')
-- Neutral connection controls; no authored character speech is created here.
local Viewport=require('game.viewport')
local Util=require('game.util')
local Panel={}; Panel.__index=Panel
local messages={load_journey_to_host='Continue a journey before hosting.',join_from_title='Return to the title screen to join a friend.',
    invalid_port='Enter a port from 1 to 65535.',save_not_ready='The host save needs to finish. Retry the save, then try again.',
    incompatible_build='Both players need the same game build.',host_declined='The host declined this request.',
    session_full='This journey already has a guest or a pending request.',credential_not_saved='The reconnect credential could not be saved on this device.',
    host_timeout='The host stopped responding.',peer_timeout='The companion stopped responding.',join_timeout='The connection timed out.',
    host_disconnected='The host disconnected.',host_closed='The host ended Local Play.',
    host_kicked='The host disconnected your companion. Joining again requires host approval.',
    management_busy='Finish the pending companion change before continuing.',
    management_expired='This companion request expired. Select the companion again.',
    companion_connected='Disconnect the companion before changing their traveler.',
    replacement_unavailable='Change travelers while stopped on the train, outside encounters and activities.',
    pending_admission='Approve or decline the pending connection first.',
    character_unchanged='Choose a different traveler.',
    invalid_guest_profile='Enter a name and select a traveler.',credential_lookup_failed='Saved connection information could not be read.',
    hosting_entry_unavailable='Choose a saved journey from the title screen.',hosting_entry_pending='Cancel hosting before joining a friend.'}
local function inside(rect,x,y) return rect and x>=rect.x and y>=rect.y and x<=rect.x+rect.w and y<=rect.y+rect.h end
local function trimBytes(value,limit)
    local count=math.max(0,math.min(#value,limit))
    while count>0 do local nextByte=value:byte(count+1); if not nextByte or nextByte<128 or nextByte>=192 then break end; count=count-1 end
    return value:sub(1,count)
end
function Panel.new(controller,context) return setmetatable({controller=controller,context=context,controls={},selected=1},Panel) end
function Panel:stopTextInput()
    self.field=nil; self.selectAll=nil
    self.controller.manualEntry=self.manualSelected==true
    if love.keyboard and love.keyboard.setTextInput then love.keyboard.setTextInput(false) end
end
function Panel:activate(control)
    if not control or control.enabled==false then return end
    if control.field then
        if control.field=='address' then self.manualSelected=true end
        self.field=control.field; self.selectAll=true
        self.controller.manualEntry=true
        if love.keyboard and love.keyboard.setTextInput then love.keyboard.setTextInput(true) end
    else self:stopTextInput(); control.action() end
end
function Panel:click(x,y)
    x,y=self.context.screenToGame(x,y)
    for index,control in ipairs(self.controls) do
        if inside(control,x,y) then self.selected=index; self:activate(control); return true end
    end
    self:stopTextInput(); return true
end
function Panel:textinput(text)
    local field=self.field; if not field then return true end
    text=text:gsub('[%z\1-\31\127]','')
    if field=='port' then text=text:gsub('[^0-9]','') end
    local previous=self.selectAll and '' or self.controller[field]
    self.controller[field]=trimBytes(previous..text,field=='name' and 32 or field=='port' and 5 or 160)
    self.selectAll=false; return true
end
function Panel:key(key)
    if key=='escape' or key=='acback' or key=='f8' then
        self:stopTextInput()
        if self.controller.managementStatus and self.controller:managementStatus() then self.controller:cancelCompanionManagement()
        else self.controller:closeMenu() end
        return true
    end
    if self.field then
        if key=='backspace' then
            local value=self.controller[self.field]
            self.controller[self.field]=self.selectAll and '' or trimBytes(value,#value-1); self.selectAll=false
        elseif key=='delete' then self.controller[self.field]=''; self.selectAll=false
        elseif key=='return' or key=='kpenter' then self:stopTextInput(); return true
        elseif key=='a' and love.keyboard and love.keyboard.isDown('lctrl','rctrl') then self.selectAll=true
        elseif key~='tab' then return true end
    end
    if key=='tab' or key=='down' or key=='up' then
        self:stopTextInput()
        local direction=key=='up' and -1 or 1
        for _=1,#self.controls do
            self.selected=(self.selected-1+direction)%#self.controls+1
            if self.controls[self.selected].enabled~=false then break end
        end
    elseif key=='return' or key=='kpenter' or key=='space' then self:activate(self.controls[self.selected]) end
    return true
end
function Panel:draw()
    local g=love.graphics; local c=self.controller
    self.font=self.font or g.newFont(20); self.smallFont=self.smallFont or g.newFont(16); self.titleFont=self.titleFont or g.newFont(30)
    self.controls={}; self.context.ui.localPlayControls={}
    g.push('all'); g.origin(); g.clear(.055,.045,.035,1)
    local ox,oy,sx,sy=Viewport.transform(960,720); g.translate(ox,oy); g.scale(sx,sy); g.setFont(self.font)
    local function text(value,x,y,w,color)
        g.setColor(unpack(color or {.94,.88,.73,1})); g.printf(tostring(value),x,y,w or 830,'left')
    end
    local function control(id,label,x,y,w,action,enabled,field,height,active)
        local h=height or 52
        local rect={x=x,y=y,w=w,h=h,action=action,enabled=enabled,field=field}
        self.controls[#self.controls+1]=rect; self.context.ui.localPlayControls[id]=rect
        local focused=self.selected==#self.controls or self.field==field and field~=nil
        GuiArt.frame(x,y,w,h,{selected=focused or active,disabled=enabled==false})
        text(label,x+14,y+(h-24)/2,w-28,enabled==false and {.55,.52,.46,1} or nil)
    end
    local function button(id,label,x,y,w,action,enabled,height,active) control(id,label,x,y,w,action,enabled,nil,height,active) end
    local function small(value,x,y,w,color) g.setFont(self.smallFont); text(value,x,y,w,color); g.setFont(self.font) end
    local function adapters(y)
        local interfaces=c.localInterfaces and c:localInterfaces() or {}
        local usb,other
        for _,entry in ipairs(interfaces) do
            local value=tostring(entry.address or '')
            if entry.prefixLength then value=value..'/'..tostring(entry.prefixLength) end
            if entry.isUsb and not usb then usb=value elseif not entry.isUsb and not other then other=value end
        end
        small('USB ETHERNET: '..(usb or 'not detected')..'     WI-FI / ETHERNET: '..(other or 'not detected'),54,y,852,{.7,.65,.54,1})
    end
    g.setFont(self.titleFont); text('LOCAL PLAY',54,35,850); g.setFont(self.font)
    text('One host and one friend on the same local network',54,83,850,{.7,.65,.54,1})
    if c.hostingIntent=='failed' then
        text('The journey is loaded. Hosting has not started.',54,145,852)
        text('Retry hosting before the journey resumes, or continue solo.',54,195,852,{.7,.65,.54,1})
        adapters(254)
        small('Hosting port',54,305,852)
        control('port',c.port,54,330,300,nil,true,'port',48)
        button('retryHosting','Retry hosting',54,475,300,function() c:retryHostingEntry() end)
        button('cancelHosting','Continue solo',380,475,300,function() c:cancelHostingEntry() end)
    elseif c.phase=='idle' then
        for index,mode in ipairs({{'auto','AUTO'},{'wifi','WI-FI'},{'usb','USB TETHER'}}) do
            local modeId=mode[1]
            button('connection_'..modeId,mode[2],54+(index-1)*169,115,158,function()
                self.manualSelected=false; self.discoveryPage=1; self:stopTextInput(); c:setConnectionMode(modeId)
            end,true,42,c.connectionMode==modeId and not self.manualSelected)
        end
        button('manual','MANUAL IP',561,115,177,function()
            self.manualSelected=true; self:activate(self.context.ui.localPlayControls.address)
        end,true,42,self.manualSelected)
        button('refresh','REFRESH',750,115,156,function() self.discoveryPage=1; c:refreshDiscovery() end,true,42)
        adapters(171)
        small('Host address (IPv4 or computer name; optional :port)',54,203)
        control('address',c.address~='' and c.address or 'Enter the host address',54,224,852,nil,true,'address',42)
        small('Your name',54,275,580); small('Hosting port',710,275,180)
        control('name',c.name,54,296,626,nil,true,'name',42)
        local savedHosting=c.canHostSavedJourney and c:canHostSavedJourney() or false
        control('port',c.port,710,296,196,nil,c:canHost() or savedHosting,'port',42)
        small('Companion traveler — reconnect uses the companion saved by the host',54,350,852)
        button('previous','<',54,375,62,function() c:cycleCharacter(-1) end,true,42)
        text(c:character() and Util.titleFromFile(c:character()) or 'Loading travelers...',140,384,640)
        button('next','>',844,375,62,function() c:cycleCharacter(1) end,true,42)
        button('autoJoin','AUTO-CONNECT ONE FOUND JOURNEY: '..(c.autoJoin and 'ON' or 'OFF'),54,432,852,function()
            c:setAutoJoin(not c.autoJoin)
        end,true,40,c.autoJoin)
        local reconnect=c.reconnectStatus and c:reconnectStatus()
        if reconnect and reconnect.active then
            small('Reconnect attempt '..tostring(reconnect.attempt)..' of '..tostring(reconnect.maxAttempts)
                ..(reconnect.state=='connecting' and ': contacting the host...' or ': retrying in '..math.ceil(reconnect.nextIn or 0)..' seconds...'),54,490,852)
            button('cancelReconnect','Cancel reconnect',54,532,300,function() c:cancelReconnect() end)
        else
            local hosts=c.discoveredHosts and c:discoveredHosts() or {}
            local pages=math.max(1,math.ceil(#hosts/2))
            self.discoveryPage=math.max(1,math.min(self.discoveryPage or 1,pages))
            small('FOUND JOURNEYS'..(#hosts>2 and (' — '..#hosts..' found') or ''),54,487,620)
            if pages>1 then
                button('discoveryPrevious','<',694,482,52,function() self.discoveryPage=self.discoveryPage-1 end,self.discoveryPage>1,28)
                small(self.discoveryPage..' / '..pages,758,489,86)
                button('discoveryNext','>',854,482,52,function() self.discoveryPage=self.discoveryPage+1 end,self.discoveryPage<pages,28)
            end
            if #hosts==0 then small(c.discoveryStatus and c:discoveryStatus() or 'Searching local adapters...',54,522,852,{.7,.65,.54,1}) end
            local first=(self.discoveryPage-1)*2+1
            for index=1,math.min(2,#hosts-first+1) do
                local host=hosts[first+index-1]; local row=index
                button('discovered_'..row,host.name..'   '..host.address..':'..host.port,54,510+(index-1)*48,852,function()
                    c:joinDiscovered(host)
                end,self.context.runtime.state=='slots' and not c.hostingIntent,42)
            end
        end
        button('host',savedHosting and 'Host saved journey' or 'Start hosting',54,630,225,function()
            if savedHosting then c:hostSavedJourney() else c:host() end
        end,c:canHost() or savedHosting)
        button('join','Join friend',301,630,225,function() c:join() end,self.context.runtime.state=='slots' and not c.hostingIntent)
        button('close',c.hostingIntent and 'Cancel hosting' or 'Back',730,630,176,function() c:closeMenu() end)
        if c.hostingIntent=='selecting' then small('Choose a saved slot to start hosting. Cancel hosting to join a friend.',54,605,852) end
    elseif c.phase=='hosting' then
        local pending=c:pending(); local link=c.network and c.network.link
        text('Hosting this journey on port '..c.port,54,140)
        text('Give your friend this computer\'s local IPv4 address and port.',54,177,852,{.7,.65,.54,1})
        adapters(218)
        if pending then
            text(pending.name..' wants to join.',54,259)
            local existing=c.campaign.players.companion
            text(existing and 'Approve reconnect to the saved companion. Their items and progress stay with this journey.'
                or 'Approve a new companion for this journey.',54,302,852)
            text('Traveler: '..Util.titleFromFile(existing and existing.character or pending.character),54,390)
            button('approve',existing and 'Approve reconnect' or 'Approve companion',54,475,300,function() c:approve() end)
            button('decline','Decline',380,475,176,function() c:decline() end)
        else
            text(link and (link.admitted and (link.name..' is connected.') or 'Connecting companion...') or 'Waiting for a friend to join.',54,259)
            local management=c.managementStatus and c:managementStatus()
            if management and management.phase=='saving' then
                text('Saving the companion change...',54,315)
                small('Retry the host save to finish. The connection changes after saving succeeds.',54,365,852)
            elseif management and management.kind=='kick' then
                text('Disconnect this companion?',54,315)
                small('Their items and progress stay in this journey. Joining again requires your approval.',54,365,852)
                button('confirmDisconnect','Disconnect companion',54,455,340,function() c:disconnectCompanion() end)
                button('cancelManagement','Cancel',420,455,180,function() c:cancelCompanionManagement() end)
            elseif management and management.kind=='replace' then
                small('Choose the saved companion traveler',54,310,852)
                button('previousReplacement','<',54,345,62,function() c:cycleReplacementCharacter(-1) end)
                text(c:replacementCharacter() and Util.titleFromFile(c:replacementCharacter()) or 'Loading travelers...',140,355,640)
                button('nextReplacement','>',844,345,62,function() c:cycleReplacementCharacter(1) end)
                small('Items and progress stay. The new trait applies without healing. Joining requires new approval.',54,410,852)
                button('confirmReplacement','Confirm traveler change',54,475,350,function() c:replaceCompanion() end,
                    c:replacementCharacter()~=c.campaign.players.companion.character)
                button('cancelManagement','Cancel',430,475,180,function() c:cancelCompanionManagement() end)
            elseif c.campaign.players.companion and c.canManageCompanion then
                text('Saved traveler: '..Util.titleFromFile(c.campaign.players.companion.character),54,310,852)
                local canKick=c:canManageCompanion('kick');local canReplace,replaceReason=c:canManageCompanion('replace')
                button('disconnectCompanion','Disconnect companion',54,370,350,function() c:selectCompanionDisconnect() end,canKick)
                button('changeCompanion','Change saved traveler',430,370,350,function() c:selectCompanionReplacement() end,canReplace)
                small(c.managementNotice or (not canReplace and messages[replaceReason]) or 'Changing travelers keeps companion equipment and progress.',54,450,852)
            end
        end
        button('stop','End Local Play',54,630,240,function() c:stop(); c.menuOpen=false end)
        button('close','Back to journey',664,630,242,function() c:closeMenu() end)
    else
        if c.replica and c.replica.data then
            local data=c.replica.data
            text('Connected to the host journey: stop '..data.location..' / '..data.scene,54,138)
            for index,id in ipairs({'host','companion'}) do
                local actor=data.players[id]; local x=54+(index-1)*450
                g.setColor(.15,.12,.085,1); g.rectangle('fill',x,200,402,230,10,10)
                text(id=='host' and 'HOST' or 'YOU',x+18,218,360)
                text(Util.titleFromFile(actor.character),x+18,263,360)
                text('Health '..actor.health..' / '..actor.maxHealth,x+18,310,360)
                text('Level '..actor.stats.level,x+18,353,360)
            end
            text('The host owns story decisions and scene progression.',54,467)
            if c.previewOnly then text('Connection preview: gameplay controls are not available yet.',54,505,852,{.85,.7,.39,1}) end
        else
            local status=c.network and c.network.status
            local label=status=='approval' and 'Waiting for the host to approve your companion.'
                or (status=='snapshot' or status=='acknowledging') and 'Receiving the host journey...' or 'Connecting to the host...'
            text(label,54,250)
            local reconnect=c.reconnectStatus and c:reconnectStatus()
            if reconnect and reconnect.active then
                small('Reconnect attempt '..tostring(reconnect.attempt)..' of '..tostring(reconnect.maxAttempts),54,305,852)
            end
        end
        button('leave',c.phase=='connected' and 'Leave session' or 'Cancel connection',54,630,240,function() c:stop(); c.menuOpen=false end)
        if c.clientView and c.clientView.ready then
            if c.clientView.settings then
                button('settings','Device settings',315,630,320,function() c.clientView.settings:open() end)
            end
            button('close','Back to journey',664,630,242,function() c:closeMenu() end)
        end
    end
    if c.error then small(messages[c.error] or ('Local Play could not continue: '..tostring(c.error)),54,c.phase=='idle' and 605 or 560,852,{1,.55,.4,1}) end
    self.selected=math.max(1,math.min(self.selected,#self.controls))
    g.pop()
end
return Panel
