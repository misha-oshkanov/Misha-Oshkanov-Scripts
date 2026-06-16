-- @description Group selected tracks and activate inverted pan
-- @version 1.2
-- @about
--     Adds pairs of selected tracks in free group and activates inverted pan, applies pan based on track name (gtr L, vocal R40 and so on)

function Main()
    local sel_track_count = reaper.CountSelectedTracks(0)
    if sel_track_count < 2 then 
        reaper.ShowMessageBox("Выберите как минимум 2 трека", "Ошибка", 0)
        return 
    end

    reaper.Undo_BeginBlock()

    local tracks = {}
    for i = 0, sel_track_count - 1 do
        tracks[i + 1] = reaper.GetSelectedTrack(0, i)
    end

    local group_idx = -1
    for g = 0, 31 do
        local mask = 1 << g
        local is_used = false
        for t = 0, reaper.CountTracks(0) - 1 do
            local tr = reaper.GetTrack(0, t)
            if (reaper.GetSetTrackGroupMembership(tr, "PAN_LEAD", 0, 0) & mask) ~= 0 then
                is_used = true; break
            end
        end
        if not is_used then group_idx = g; break end
    end

    if group_idx ~= -1 then
        local mask = 1 << group_idx
        
        for _, track in ipairs(tracks) do
            reaper.GetSetTrackGroupMembership(track, "PAN_LEAD", mask, mask)
            reaper.GetSetTrackGroupMembership(track, "PAN_FOLLOW", mask, mask)
            reaper.GetSetTrackGroupMembership(track, "VOLUME_LEAD", mask, mask)
            reaper.GetSetTrackGroupMembership(track, "VOLUME_FOLLOW", mask, mask)
        end
        
        local half = math.floor(#tracks / 2)
        for i = half + 1, #tracks do
            reaper.GetSetTrackGroupMembership(tracks[i], "PAN_REVERSE", mask, mask)
        end

        
        for _, track in ipairs(tracks) do
            local _, name = reaper.GetTrackName(track)
            local side, val = name:upper():match("[%s_%-]([LR])(%d*)$")
            
            if side then
                local num = tonumber(val) or 100
                local pan_value = math.max(0, math.min(num, 100)) / 100
                
                if side == "L" then
                    reaper.SetMediaTrackInfo_Value(track, "D_PAN", -pan_value)
                else
                    reaper.SetMediaTrackInfo_Value(track, "D_PAN", pan_value)
                end
            end
        end
    end

    reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
    for _, track in ipairs(tracks) do
        reaper.SetTrackSelected(track, true)
    end
    
    reaper.SetOnlyTrackSelected( tracks[1] )

    reaper.Undo_EndBlock("Smart inverted pan grouping selected tracks", -1)
    reaper.TrackList_AdjustWindows(false)
end

Main()