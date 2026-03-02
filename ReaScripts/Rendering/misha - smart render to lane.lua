-- @description Smart Render to new lane (Razor or item selection)
-- @author Misha Oshkanov
-- @version 1.1
-- @about
--    Add razor edit area or select some items to render it to new lane and solo this lane
--    Use targetFXNames table to toggle bypass of everything except plugins in this table before render and set it back online after the render
--    Works with comping and automatically adds new item to comp
-- @changelog
--    fix comping lane solo

local targetFXNames = {"Melodyne", "DynAssist", "Revoice", "Vovious", "kontakt" }

---------------------------------------------------------------------------------
function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end


function IsCompingActiveViaLaneRec(track)
    local _, chunk = reaper.GetTrackStateChunk(track, "", false)
    local lanerec = chunk:match("LANEREC%s+([%-%d]+%s+[%-%d]+%s+[%-%d]+)")
    if lanerec then
        local f1, f2, f3 = lanerec:match("([%-%d]+)%s+([%-%d]+)%s+([%-%d]+)")
        if f2 then
            local compIndex = tonumber(f2)
            return compIndex ~= -1
        end
    end
    return false
end

function ManageFXState(track, restore, savedStates, foundPluginName, item_lane)
    local fx_count = reaper.TrackFX_GetCount(track)
    if fx_count == 0 then return nil, nil end
    
    if restore then
        for i = 0, fx_count - 1 do
            local _, fxName = reaper.TrackFX_GetFXName(track, i, "")
            local isTarget = false
            if foundPluginName then
            if fxName:lower():find(foundPluginName:lower()) then isTarget = true end
            end

            if isTarget then 
                reaper.TrackFX_SetEnabled(track, i, false)
                local pattern = "(" .. foundPluginName .. ")%s?%d*"
                local newName, substitutions = fxName:gsub(pattern, "%1 " .. math.floor(item_lane + 1))
                if substitutions > 0 then
                reaper.TrackFX_SetNamedConfigParm(track, i, 'renamed_name', newName)
                end
            else reaper.TrackFX_SetEnabled(track, i, savedStates[i+1])  end
        end
        return nil
    else
        local currentStates = {}
        local foundTargetName = nil
        local vsti_index = reaper.TrackFX_GetInstrument(track)
        
        for i = 0, fx_count - 1 do
            local _, fxName = reaper.TrackFX_GetFXName(track, i, "")
            for _, name in ipairs(targetFXNames) do
                if fxName:lower():find(name:lower()) then foundTargetName = name break end
                
            end
            if foundTargetName then break end
        end

        for i = 0, fx_count - 1 do
            local _, fxName = reaper.TrackFX_GetFXName(track, i, "")
            local isEnabled = reaper.TrackFX_GetEnabled(track, i)
            currentStates[i+1] = isEnabled
        
            if foundTargetName then
                local isThisTarget = fxName:lower():find(foundTargetName:lower())
                if not isThisTarget then
                    if (vsti_index > -1 and i > vsti_index) or (vsti_index == -1) then reaper.TrackFX_SetEnabled(track, i, false) end
                end
            end
        end
        return currentStates, foundTargetName
    end
end

function razors_exist()
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        
        local _, razorStr = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
        if razorStr and razorStr ~= "" then
            return true
        end
    end
end

function Main()
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    local track_count = reaper.CountTracks(0)
    local work_queue = {}

    if not razors_exist() then 
    reaper.Main_OnCommand(42409, 0) -- enclose items in razor
    end

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local _, razorStr = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
        if razorStr and razorStr ~= "" then
            local razors = {}
            for s, e in razorStr:gmatch("([%d%.]+)%s+([%d%.]+)%s*%S*%s*") do
                table.insert(razors, {st = tonumber(s), en = tonumber(e)})
            end
            table.insert(work_queue, {track = track, razors = razors})
        end
    end
    
    for _, entry in ipairs(work_queue) do
        local track = entry.track
        local savedFXStates, foundPluginName = ManageFXState(track, false, nil, nil, nil)
        local rendered_items = {}
        local temp_tracks = {}

        for _, rz in ipairs(entry.razors) do
            reaper.GetSet_LoopTimeRange(true, false, rz.st, rz.en, false)
            reaper.SetOnlyTrackSelected(track)
            reaper.Main_OnCommand(41719, 0) -- Render stereo stem pre fader
            
            local new_track = reaper.GetSelectedTrack(0, 0)
            if new_track and new_track ~= track then
                local item = reaper.GetTrackMediaItem(new_track, 0)
                if item then
                    table.insert(rendered_items, item)
                    table.insert(temp_tracks, new_track)
                end
            end
        end

        if #rendered_items > 0 then
            reaper.SetMediaTrackInfo_Value(track, "I_FREEMODE", 2, true)
            reaper.UpdateItemLanes(0)
            
            for i, item in ipairs(rendered_items) do

                reaper.MoveMediaItemToTrack(item, track)
                reaper.SelectAllMediaItems(0, false)
                reaper.SetMediaItemSelected(item, true) 
                
                reaper.UpdateItemLanes(0)
                
                reaper.Main_OnCommand(42787,0)
                item_lane = reaper.GetMediaItemInfo_Value(item, 'I_FIXEDLANE')
                
                if not IsCompingActiveViaLaneRec(track) then 
                    reaper.SetMediaTrackInfo_Value(track, "C_LANEPLAYS:" .. item_lane, 1, true)
                end

                local take = reaper.GetActiveTake(item)
                if take then
                    local oldName = reaper.GetTakeName(take)
                    local cleanName = oldName:gsub("[Ss][Tt][Ee][Mm]", foundPluginName or "Stem")
                    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", cleanName  .. ' '.. math.floor(item_lane+1), true)
                end
            end
            reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0, true)
            
            if IsCompingActiveViaLaneRec(track) then
                reaper.SelectAllMediaItems(0, false)
                for _, item in ipairs(rendered_items) do reaper.SetMediaItemSelected(item, true) end
                reaper.Main_OnCommand(42652, 0) -- Comping: Activate lane
            end
        end

        for _, t in ipairs(temp_tracks) do reaper.DeleteTrack(t) end
        reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
        if savedFXStates then ManageFXState(track, true, savedFXStates, foundPluginName, item_lane) end
    end

    reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Smart render razors to lanes (Batch mode)", -1)
end

Main()