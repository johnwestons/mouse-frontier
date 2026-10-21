-- Defense at local controller entry points as well as the wire dispatcher.
-- Replication installs authoritative state through its own apply path;
-- a guest button/callback must never execute the host's story controller.
local Capabilities=require("game.coop_capabilities")
local Progression={}

function Progression.allowed(runtime,command)
    local session=runtime and runtime.session
    if session and session.checkpointPending then return false,"save_pending" end
    local mode=session and session.networkMode or "offline"
    -- Personal scene commands still execute on the host. Their wire policy
    -- must not let a client call the solo controllers and mutate a replica.
    if mode=='client' then return false,'host_only' end
    local role=(mode=="offline" or mode=="host") and "host" or mode=="client" and "guest" or nil
    return Capabilities.authorize(command,role)
end

return Progression
