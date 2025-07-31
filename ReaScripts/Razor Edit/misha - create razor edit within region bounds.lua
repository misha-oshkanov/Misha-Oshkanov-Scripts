-- @description Create razor edit within region bounds (tracks and envelopes)
-- @author Misha Oshkanov
-- @version 1.6
-- @about
--  Create razor edit within region bounds (tracks and envelopes)


function p(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

local position = reaper.BR_PositionAtMouseCursor(true)
_, segment, _ = reaper.BR_GetMouseCursorContext()
local track = reaper.BR_GetMouseCursorContext_Track()
local envelope, takeEnvelope = reaper.BR_GetMouseCursorContext_Envelope()

if position == -1 then position = reaper.GetCursorPosition() end
local _, regionidx = reaper.GetLastMarkerAndCurRegion( 0, position )
if regionidx == -1 or track_cnt == 0 then return reaper.defer(function() end) end


local _, _, rgnpos, rgnend = reaper.EnumProjectMarkers( regionidx )

local tab = {}
tab[1] = rgnpos  
tab[2] = rgnend

reaper.Undo_BeginBlock2(0)

if segment == "envelope" then
    local aTrack = reaper.GetEnvelopeInfo_Value(envelope, "P_TRACK")
    if aTrack ~= 0 then
        local _, guid = reaper.GetSetEnvelopeInfo_String(envelope, "GUID", "", false)
        local str = "" .. tab[1].." "..tab[2].." \""..guid.."\""
        reaper.Undo_BeginBlock2(0)
        reaper.GetSetMediaTrackInfo_String(aTrack, "P_RAZOREDITS", str, true)
        reaper.Undo_EndBlock2(0, "Selected Envelope Points to Razor Edit", -1)
    end
elseif segment == "track" then
    _, guid = reaper.GetSetMediaTrackInfo_String(track, "GUID", "", false)
    local str = "" .. tab[1].." "..tab[2].." \""..guid.."\""
    reaper.Undo_BeginBlock2(0)
    reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", str, true)
    reaper.Undo_EndBlock2(0, "Selected Envelope Points to Razor Edit", -1)
end    