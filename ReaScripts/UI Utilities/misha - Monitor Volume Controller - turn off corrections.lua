-- @description Monitor Volume Controller Shortcut - turn off corrections
-- @author Misha Oshkanov
-- @version 0.1
-- @about
--  bypass all active corrections in Corrections container made by Monitor Controller script

function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end


CORRECTION_CONTAINER_NAME = "Corrections"

master = reaper.GetMasterTrack()

local fx_container = reaper.TrackFX_AddByName(master, CORRECTION_CONTAINER_NAME, true, 0)
if fx_container ~= -1 then
    local _, count = reaper.TrackFX_GetNamedConfigParm(master, fx_container+(0x1000000), "container_count")
    for i = 0, tonumber(count or 0)-1 do
        local _, item = reaper.TrackFX_GetNamedConfigParm(master, fx_container+(0x1000000), "container_item."..i)
        reaper.TrackFX_SetEnabled(master, item, false)
    end
end
