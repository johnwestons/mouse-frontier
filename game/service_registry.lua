local function new(moduleManifest)
  assert(type(moduleManifest)=="table","service registry requires a module manifest")
  local snapshot={}
  for name,module in pairs(moduleManifest) do snapshot[name]=module end
  local services={}

  local function publish(name,service)
    assert(type(name)=="string" and name~="","service registry requires a service name")
    assert(snapshot[name]~=nil,"service registry has no module named "..name)
    assert(type(service)=="table","service registry "..name.." must be a table")
    assert(services[name]==nil,"service registry already published "..name)
    assert(service~=snapshot[name],"service registry cannot publish factory "..name.." as its service")
    services[name]=service
    return service
  end

  local function publishAll(nextServices)
    assert(type(nextServices)=="table","service registry publishAll requires a table")
    for name,service in pairs(nextServices) do
      if name~="status" then publish(name,service) end
    end
    return nextServices
  end

  local function status()
    local immutable,separated=true,true
    local factoryCount,serviceCount=0,0
    for name,module in pairs(snapshot) do
      factoryCount=factoryCount+1
      if moduleManifest[name]~=module then immutable=false end
    end
    for name,service in pairs(services) do
      serviceCount=serviceCount+1
      if service==snapshot[name] then separated=false end
    end
    return {immutable=immutable,separated=separated,factoryCount=factoryCount,serviceCount=serviceCount}
  end

  return {services=services,publish=publish,publishAll=publishAll,status=status}
end

return {new=new}
