local Coordinator={}

function Coordinator.new(options)
    assert(type(options)=="table","stop activity minigames require explicit dependencies")
    local HelpQuest=assert(options.helpQuestSession,"stop activity minigames require help quest sessions")
    local registry={
        ["sludge-containment"]=assert(options.sludgeContainment,"stop activity minigames require sludge containment"),
        ["track-debris-clearing"]=assert(options.trackDebrisClearing,"stop activity minigames require track debris clearing"),
    }
    local atlases=options.atlases or {}
    local service={}

    function service.begin(data,activity,result)
        local kind=result and result.requiresMinigame; local module=registry[kind]
        if not module or not activity then return nil end
        local session=module.new({location=data.location,helpQuestId=activity.sessionId,progress=result.session and result.session.progress})
        if result.session then HelpQuest.activate(data,result.session.id,module.objective(session)) end
        return session
    end

    function service.keypressed(session,key)
        local module=session and registry[session.kind]
        return module and module.keypressed(session,key) or nil
    end

    function service.mousepressed(session,x,y)
        local module=session and registry[session.kind]
        return module and module.mousepressed(session,x,y) or nil
    end

    function service.draw(session,colors,clock)
        local module=session and registry[session.kind]
        if module then module.draw(session,colors,atlases[session.kind],clock) end
    end

    function service.objective(session)
        local module=session and registry[session.kind]
        return module and module.objective(session) or "Complete the community task."
    end

    function service.sync(data,session)
        if not session or not session.helpQuestId then return end
        HelpQuest.progress(data,session.helpQuestId,session.phase,service.objective(session),{
            phase=session.progress.phase,step=session.progress.step,mistakes=session.progress.mistakes,
            barrierTarget=session.progress.barrierTarget,scanStart=session.progress.scanStart})
    end

    function service.pause(data,session)
        if session and session.helpQuestId then HelpQuest.pause(data,session.helpQuestId,"Return to continue "..service.objective(session):lower()) end
    end

    function service.retry(data,session)
        if session and session.helpQuestId then HelpQuest.retry(data,session.helpQuestId,"Return to this activity for another safe attempt.") end
    end

    function service.audit()
        local sludge=registry["sludge-containment"].audit(); local track=registry["track-debris-clearing"].audit()
        return {ready=sludge.ready and track.ready,sludge=sludge,track=track,registered=2,curve="activity-minigames-v1"}
    end

    return service
end

return Coordinator
