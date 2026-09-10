local WorldPause = {}

-- World movement, roaming enemies, and attacks share one modal boundary.
-- Dialogue may still expose its close action while the simulation is paused.
function WorldPause.isPaused(runtime,ui,maintenanceSession,options)
    runtime,ui,maintenanceSession=runtime or {},ui or {},maintenanceSession or {}
    options=options or {}
    return runtime.state~="game"
        or runtime.exitPrompt~=nil and runtime.exitPrompt~=false
        or runtime.travelConfirm==true or runtime.travelTransition~=nil and runtime.travelTransition~=false
        or runtime.carTransition~=nil and runtime.carTransition~=false
        or maintenanceSession.open==true
        or runtime.inventoryOpen==true or runtime.mapOpen==true or runtime.editMode==true
        or runtime.tradeOpen==true or runtime.trainUpgradeOpen==true or runtime.poseMenu==true
        or ui.optionsOpen==true or ui.radioOpen==true or ui.mobileMenuOpen==true
        or runtime.firstAid~=nil and runtime.firstAid~=false
        or runtime.shootingRange~=nil and runtime.shootingRange~=false
        or runtime.helpDialogue~=nil and runtime.helpDialogue~=false
        or runtime.lastStand and runtime.lastStand.capture==true
        or not options.allowDialogue and runtime.dialogue~=nil and runtime.dialogue~=false
        or false
end

return WorldPause
