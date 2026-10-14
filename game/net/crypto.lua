-- Connection credentials never use the gameplay RNG, time, or display names.
-- Windows contract: https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptgenrandom
local Crypto={}
local function hex(bytes) return (bytes:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
function Crypto.isHex(value,length) return type(value)=='string' and #value==length and value:match('^[0-9a-f]+$')~=nil end
function Crypto.hash(value)
    if type(value)~='string' or not (love and love.data and love.data.hash) then return nil,'hash_unavailable' end
    local ok,digest=pcall(love.data.hash,'sha256',value)
    if not ok or type(digest)~='string' or #digest~=32 then return nil,'hash_unavailable' end
    return hex(digest)
end
function Crypto.randomBytes(count)
    if type(count)~='number' or count~=math.floor(count) or count<16 or count>64 then return nil,'invalid_entropy_size' end
    local ffiOk,ffi=pcall(require,'ffi')
    if ffiOk and ffi.os=='Windows' then
        local ok,bytes=pcall(function()
            ffi.cdef[[long __stdcall BCryptGenRandom(void *, unsigned char *, unsigned long, unsigned long);]]
            local library=ffi.load('bcrypt.dll')
            local buffer=ffi.new('unsigned char[?]',count)
            if library.BCryptGenRandom(nil,buffer,count,2)~=0 then return nil end
            return ffi.string(buffer,count)
        end)
        if ok and type(bytes)=='string' and #bytes==count then return bytes end
        return nil,'entropy_unavailable'
    end
    -- Unix/Android use the OS entropy device. Failure disables admission;
    -- there is deliberately no fallback to a pseudorandom game seed.
    local ok,bytes=pcall(function()
        local file=io.open('/dev/urandom','rb')
        if not file then return nil end
        local readOk,result=pcall(file.read,file,count)
        file:close()
        return readOk and result or nil
    end)
    if ok and type(bytes)=='string' and #bytes==count then return bytes end
    return nil,'entropy_unavailable'
end
function Crypto.token(bytes)
    local value,reason=Crypto.randomBytes(bytes or 32)
    return value and hex(value) or nil,reason
end
function Crypto.equal(a,b)
    if type(a)~='string' or type(b)~='string' or #a~=#b then return false end
    local difference=0
    for index=1,#a do if a:byte(index)~=b:byte(index) then difference=difference+1 end end
    return difference==0
end
return Crypto
