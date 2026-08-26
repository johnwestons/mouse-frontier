local function required(context,name,expected)
  local value=context[name]
  assert(value~=nil,"persistence runtime requires "..name)
  if expected then assert(type(value)==expected,"persistence runtime "..name.." must be a "..expected) end
  return value
end

local function new(context)
  assert(type(context)=="table","persistence runtime requires a context")
  local runtime=required(context,"runtime","table")
  local ui=required(context,"ui","table")
  local session=required(context,"session","table")
  local Save=required(context,"save","table")
  local Maintenance=required(context,"maintenance","table")
  local maintenanceSession=required(context,"maintenanceSession","table")
  local focusMobile=required(context,"focusMobile","function")
  local focusAudio=required(context,"focusAudio","function")
  local shutdownAudio=required(context,"shutdownAudio","function")

  local function schedule()
      if not runtime.selectedSlot or not runtime.saveData then return false end
      runtime:syncForSave()
      ui.itemOrderRevision=(ui.itemOrderRevision or 0)+1
      return session:scheduleSave(Save)
  end

  local function update(dt) return Save.update(dt) end
  local function read(slot) return Save.read(slot) end
  local function remove(slot) return Save.remove(slot) end
  local function flush() return Save.flush() end

  local function focus(focused)
      focusMobile(focused)
      focusAudio(focused)
      if focused then return true end
      schedule()
      return flush()
  end

  local function shutdown()
      Maintenance.release(maintenanceSession)
      schedule()
      local saved=flush()
      shutdownAudio()
      return saved
  end

  return {
      schedule=schedule,
      update=update,
      read=read,
      remove=remove,
      flush=flush,
      focus=focus,
      shutdown=shutdown,
  }
end

return {new=new}
