-- @description Smart Render (Razor to Time Selection if exists)
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--    Add razor edit area and start script to render ()
--    Render actin - Track: Render selected area of tracks to stereo post-fader stem tracks (and mute originals) - 41716

RENDER_ID = 41716

----------------------------------------------------------------
function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

function Main()
    local track_count = reaper.CountTracks(0)
    if track_count == 0 then return end

    local initial_selected_tracks = {}
    local razor_tracks = {}
    local has_razor = false
    local min_pos = math.huge
    local max_pos = -math.huge

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.IsTrackSelected(track) then
            table.insert(initial_selected_tracks, track)
        end

        local _, razor_str = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
        if razor_str ~= "" then
            has_razor = true
            table.insert(razor_tracks, track)
            for start_pos, end_pos in razor_str:gmatch("([%d%.]+) ([%d%.]+)") do
                min_pos = math.min(min_pos, tonumber(start_pos))
                max_pos = math.max(max_pos, tonumber(end_pos))
            end
        end
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    if has_razor then
        reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
        for _, track in ipairs(razor_tracks) do reaper.SetTrackSelected(track, true) end
        reaper.GetSet_LoopTimeRange(true, false, min_pos, max_pos, false)
    end

    reaper.Main_OnCommand(RENDER_ID, 0) ------------- RENDER

    if has_razor then
        reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
        for _, track in ipairs(initial_selected_tracks) do
            if reaper.ValidatePtr(track, "MediaTrack*") then reaper.SetTrackSelected(track, true) end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Smart Razor Render", -1)
end

Main()