local WorldPause = {}

-- Local movement and attacks share one modal boundary. The co-op host's
-- shared simulation uses isSimulationPaused instead.
function WorldPause.isPaused(runtime,ui,maintenanceSession,options)
    runtime,ui,maintenanceSession=runtime or {},ui or {},maintenanceSession or {}
    options=options or {}
    return runtime.state~="game"
        or runtime.saveData and runtime.saveData.roamingEncounter~=nil
        or runtime.session and runtime.session.checkpointPending==true
        or runtime.exitPrompt~=nil and runtime.exitPrompt~=false
        or runtime.travelConfirm==true or runtime.travelTransition~=nil and runtime.travelTransition~=false
        or runtime.carTransition~=nil and runtime.carTransition~=false
        or maintenanceSession.open==true
        or runtime.inventoryOpen==true or runtime.mapOpen==true or runtime.journeyLogOpen==true or runtime.editMode==true
        or runtime.tradeOpen==true or runtime.trainUpgradeOpen==true or runtime.poseMenu==true or runtime.outfitCraftingOpen==true
        or ui.optionsOpen==true or ui.escMenuOpen==true or ui.radioOpen==true or ui.mobileMenuOpen==true or ui.playerToolsOpen==true
        or ui.localPlay and (ui.localPlay.menuOpen==true or WorldPause.isSharedHost(runtime) and ui.localPlay.focused==false)
        or runtime.firstAid~=nil and runtime.firstAid~=false
        or runtime.shootingRange~=nil and runtime.shootingRange~=false
        or runtime.helpDialogue~=nil and runtime.helpDialogue~=false
        or runtime.lastStand and runtime.lastStand.capture==true
        or not options.allowDialogue and runtime.dialogue~=nil and runtime.dialogue~=false
        or false
end

-- The host's local controls can stop without stopping the other traveler or
-- shared world. Offline play retains its original modal pause behavior.
function WorldPause.isSharedHost(runtime)
    return runtime and runtime.session and runtime.session.networkMode=="host" or false
end

function WorldPause.isSimulationPaused(runtime,ui,maintenanceSession,options)
    if not WorldPause.isSharedHost(runtime) then return WorldPause.isPaused(runtime,ui,maintenanceSession,options) end
    return runtime.state~="game" or runtime.session.checkpointPending==true
        or runtime.saveData and runtime.saveData.roamingEncounter~=nil
        or runtime.travelTransition~=nil and runtime.travelTransition~=false
        or runtime.battle~=nil and runtime.battle~=false
        or runtime.lastStand and runtime.lastStand.capture==true
        or runtime.trainAmbush and runtime.trainAmbush.phase~="complete"
        or false
end

return WorldPause
