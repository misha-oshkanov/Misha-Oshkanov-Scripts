-- @description Monitor Volume Controller Shortcut - AB Switch
-- @author Misha Oshkanov
-- @version 0.2
-- @about
--  Action to activate MetricAB Switch


------------------------------------------------------------------------------
------------------------------------------------------------------------------
button_index = 0
master = reaper.GetMasterTrack()
METRIC_AB = 'ADPTR MetricAB'
mon = (0x1000000)

ext = tonumber(reaper.GetExtState('MISHA_MONITOR', 'AB'))

local index = reaper.TrackFX_AddByName(master, METRIC_AB, true, 0)
if index then
    retval, minval, maxval = reaper.TrackFX_GetParam(master, index+mon, 0)
    reaper.TrackFX_SetParam(master, index+mon, 0, retval==1 and 0 or 1)
    reaper.SetExtState('MISHA_MONITOR', 'AB', retval==1 and '0' or '1', true)
end
