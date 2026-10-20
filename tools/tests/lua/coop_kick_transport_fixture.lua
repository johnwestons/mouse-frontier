-- Actual transport_enet adapter over the impairment lab, without native ENet.
-- The native peer model distinguishes disconnect's queue reset from the
-- reliable queue drain of disconnect_later. Production never loads this file.
local Transport=require('game.net.transport_enet')
local Fixture={}
function Fixture.install(lab,raw)
    local native={queue={},log={},closed=false}
    local function discard(peer)
        local keep={};for _,packet in ipairs(native.queue)do if packet.peer~=peer then keep[#keep+1]=packet end end
        native.queue=keep
        keep={};for _,frame in ipairs(lab.scheduled)do
            if not(frame.event.peer==peer and frame.transport~=raw and frame.event.type=='receive')then keep[#keep+1]=frame end
        end;lab.scheduled=keep
    end
    local function prepare(peer)
        if peer.nativeId then return end
        local link=assert(lab.linksByPeer[peer])
        peer.nativeId=link.index*100000+link.generation
        function peer:connect_id()return self.nativeId end
        function peer:index()return link.index end
        function peer:state()return link.active and 'connected' or 'disconnected' end
        function peer:send(bytes,channel,flags)
            if native.failSend then return false end
            native.queue[#native.queue+1]={peer=self,bytes=bytes,channel=channel,reliable=flags=='reliable'}
            return true
        end
        function peer:disconnect(code)
            native.log[#native.log+1]={method='disconnect',peer=self,code=code}
            discard(self);return raw:disconnect(self,code,false)
        end
        function peer:disconnect_now(code)
            native.log[#native.log+1]={method='disconnect_now',peer=self,code=code}
            discard(self);return raw:disconnect(self,code,true)
        end
        function peer:disconnect_later(code)
            native.log[#native.log+1]={method='disconnect_later',peer=self,code=code}
            local queued=false;for _,packet in ipairs(native.queue)do if packet.peer==self then queued=true end end
            if not queued then return self:disconnect(code)end
            self.departureCode=code;return true
        end
    end
    function native:flush()
        self.log[#self.log+1]={method='flush'}
        local queue=self.queue;self.queue={}
        for _,packet in ipairs(queue)do raw:send(packet.peer,packet.bytes,packet.channel,packet.reliable)end
    end
    function native:service()
        self:flush()
        local events=assert(raw:service(1));local event=events[1]
        if not event then return nil end
        prepare(event.peer)
        if event.type=='disconnect'then event.peer.nativeId=0 end
        return {type=event.type,peer=event.peer,channel=event.channel,
            data=event.type=='receive' and (event.data or event.payload) or event.code}
    end
    function native:destroy()self.closed=true;return raw:close(0,true)end
    local adapter=assert(Transport.createHost({enet={host_create=function()return native end},peerCapacity=2}))
    return adapter,native
end
return Fixture
