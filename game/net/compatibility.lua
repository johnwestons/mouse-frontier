-- Exact gameplay-code/content identity (including authored dialogue/catalogs).
-- Art/package capability validation is separate: platform image optimizations
-- must not make otherwise compatible desktop/mobile logic look different.
local Crypto=require('game.net.crypto')
local Schema=require('game.save_schema')
local P=require('game.net.protocol')
local Compatibility={MAX_FILES=2048,MAX_FILE_BYTES=4*1024*1024,MAX_TOTAL_BYTES=32*1024*1024}
local function call(fn,...)
    local ok,value=pcall(fn,...); return ok and value or nil
end
function Compatibility.compute(filesystem,hash)
    filesystem=filesystem or love.filesystem; hash=hash or Crypto.hash
    local paths={}; local visited=0
    local function visit(directory,depth)
        if depth>12 then return nil,'compatibility_depth_limit' end
        local entries=call(filesystem.getDirectoryItems,directory)
        if type(entries)~='table' then return nil,'compatibility_list_failed' end
        local seen={}
        for _,name in ipairs(entries) do
            visited=visited+1
            if visited>Compatibility.MAX_FILES*2 then return nil,'compatibility_entry_limit' end
            if not P.text(name,128) or name=='.' or name=='..' or name:find('[/\\]') or seen[name] then
                return nil,'invalid_compatibility_path'
            end
            seen[name]=true
            local path=directory..'/'..name
            local info=call(filesystem.getInfo,path)
            if type(info)~='table' then return nil,'compatibility_stat_failed' end
            if info.type=='directory' then
                local ok,reason=visit(path,depth+1); if not ok then return nil,reason end
            elseif info.type=='file' and name:sub(-4)=='.lua' then
                if #paths>=Compatibility.MAX_FILES or not P.integer(info.size,0,Compatibility.MAX_FILE_BYTES) then
                    return nil,'compatibility_file_limit'
                end
                paths[#paths+1]={path=path,size=info.size}
            end
        end
        return true
    end
    local ok,reason=visit('game',1); if not ok then return nil,reason end
    if #paths==0 then return nil,'compatibility_no_code' end
    table.sort(paths,function(a,b) return a.path<b.path end)
    local parts={'mouse-frontier-code-v1',tostring(Schema.CURRENT_VERSION),tostring(P.VERSION)}
    local total=0
    for _,entry in ipairs(paths) do
        total=total+entry.size; if total>Compatibility.MAX_TOTAL_BYTES then return nil,'compatibility_size_limit' end
        local bytes=call(filesystem.read,entry.path)
        if type(bytes)~='string' or #bytes~=entry.size then return nil,'compatibility_read_failed' end
        local digest=call(hash,bytes)
        if not Crypto.isHex(digest,64) then return nil,'hash_unavailable' end
        parts[#parts+1]=#entry.path..':'..entry.path..':'..entry.size..':'..digest
    end
    local digest=call(hash,table.concat(parts,'\n'))
    if not Crypto.isHex(digest,64) then return nil,'hash_unavailable' end
    return {build=digest,schema=Schema.CURRENT_VERSION,protocol=P.VERSION,files=#paths,bytes=total}
end
return Compatibility
