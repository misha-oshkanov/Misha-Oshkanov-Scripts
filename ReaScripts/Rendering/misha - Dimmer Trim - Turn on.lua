-- @description Dimmer Trim - Turn on
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  Sets bypass for all effect in project named Dimeer Trim. The original effect is used for applying temporary gain chainges. 
--  You can use is with Stem Manager script to change levels of tracks only for certain render preset.

fxname = 'Dimmer Trim'

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

for i=1, reaper.CountTracks(0) do 
    track     = reaper.GetTrack(0,i-1)
    fx = reaper.TrackFX_AddByName(track, fxname, false, 0)
    if fx == 0 then reaper.TrackFX_SetEnabled(track, fx, 1) end
end 

    master = reaper.GetMasterTrack(0)
    mfx = reaper.TrackFX_AddByName(master, fxname, false, 0)
    if mfx == 0 then reaper.TrackFX_SetEnabled(master, mfx, 1) end