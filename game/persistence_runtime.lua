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

  local function canWriteCampaign()
      return session.networkMode~="client"
  end

  local function schedule()
      if not canWriteCampaign() or not runtime.selectedSlot or not runtime.saveData then return false end
      runtime:syncForSave()
      ui.itemOrderRevision=(ui.itemOrderRevision or 0)+1
      return session:scheduleSave(Save)
  end

  local function update(dt) if canWriteCampaign() then return Save.update(dt) end; return false end
  local function read(slot) if canWriteCampaign() then return Save.read(slot) end; return nil,"host_only" end
  local function remove(slot) if canWriteCampaign() then return Save.remove(slot) end; return false end
  local function flush() if canWriteCampaign() then return Save.flush() end; return false end
  local function checkpoint()
      if not schedule() then return false end
      return flush()
  end
  local function checkpointCampaign(data)
      if not canWriteCampaign() or not runtime.selectedSlot or data~=runtime.saveData then return false end
      -- Authority already staged actor/world state. Do not overwrite it from
      -- presentation when confirming a critical operation or scene change.
      if not session:scheduleSave(Save) then return false end
      return Save.flush(runtime.selectedSlot)
  end

  local function checkpointIfPlaying()
      if not canWriteCampaign() or not runtime.selectedSlot or not runtime.saveData then return true end
      return checkpoint()
  end

  local function focus(focused)
      focusMobile(focused)
      focusAudio(focused)
      if focused then return true end
      if ui.closeDecoration then ui.closeDecoration() end
      if ui.pauseFirstAid then ui.pauseFirstAid() end
      if ui.cancelWeaponRepair then ui.cancelWeaponRepair() end
      if maintenanceSession.open then Maintenance.close(maintenanceSession) end
      local preferencesSaved=not ui.localPreferences or ui.localPreferences:save()
      local campaignSaved=checkpointIfPlaying()
      return preferencesSaved and campaignSaved
  end

  local function shutdown()
      if ui.closeDecoration then ui.closeDecoration() end
      if ui.pauseFirstAid then ui.pauseFirstAid() end
      if ui.cancelWeaponRepair then ui.cancelWeaponRepair() end
      Maintenance.release(maintenanceSession)
      local preferencesSaved=not ui.localPreferences or ui.localPreferences:save()
      local saved=checkpointIfPlaying()
      shutdownAudio()
      return saved and preferencesSaved
  end

  return {
      schedule=schedule,
      update=update,
      read=read,
      remove=remove,
      flush=flush,
      checkpoint=checkpoint,
      checkpointCampaign=checkpointCampaign,
      focus=focus,
      shutdown=shutdown,
  }
end

return {new=new}
