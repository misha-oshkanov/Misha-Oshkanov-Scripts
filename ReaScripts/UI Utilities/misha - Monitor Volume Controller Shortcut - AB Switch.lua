-- @description Monitor Volume Controller Shortcut - AB Switch
-- @author Misha Oshkanov
-- @version 0.3
-- @about
--  Action to activate MetricAB Switch


------------------------------------------------------------------------------
------------------------------------------------------------------------------
button_index = 0
master = reaper.GetMasterTrack()
METRIC_AB = 'ADPTR MetricAB'
SECTION = "MISHA_MONITOR_SETTINGS"
master_or_mon = reaper.GetExtState(SECTION, "USE_METRIC_IN_MONITORINGFX")

if master_or_mon == "1" then
    mon = (0x1000000)
    addbyname_recmon_state = true
else
    mon = 0
    addbyname_recmon_state = false
end

local index = reaper.TrackFX_AddByName(master, METRIC_AB, addbyname_recmon_state, 0)
if index then
    retval, _, _ = reaper.TrackFX_GetParam(master, index+mon, 0)
    reaper.TrackFX_SetParam(master, index+mon, 0, retval==1 and 0 or 1)
    reaper.SetExtState('MISHA_MONITOR', 'AB', retval==1 and '0' or '1', true)
end
