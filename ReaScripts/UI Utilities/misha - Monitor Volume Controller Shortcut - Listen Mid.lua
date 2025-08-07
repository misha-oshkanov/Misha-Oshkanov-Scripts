-- @description Monitor Volume Controller Shortcut - Listen Mid
-- @author Misha Oshkanov
-- @version 0.2
-- @about
--  Action to solo certain frequency in monitor controller script



l = 800
h = 3570 
button_index = 4

SLOPE = 2 -- 1 = 12db, 2 = 24db, 3 = 36db, 4 = 48db,5 = 60db, 6 = 72db 

------------------------------------------------------------------------------
------------------------------------------------------------------------------
master = reaper.GetMasterTrack()
controller_fx = 'Monitor Volume Controller'
mon = (0x1000000)

min_hz = 20
max_hz = 20000

base_freq_ext  = tonumber(reaper.GetExtState('MISHA_MONITOR', 'BASE_FREQ'))
base_width_ext = tonumber(reaper.GetExtState('MISHA_MONITOR', 'BASE_WIDTH'))
base_slope_ext = tonumber(reaper.GetExtState('MISHA_MONITOR', 'BASE_SLOPE'))

if base_width_ext == nil then base_width_ext = 2 end
if base_freq_ext == nil then base_freq_ext = 1000 end
if base_slope_ext == nil then base_slope_ext = SLOPE end

ext = tonumber(reaper.GetExtState('MISHA_MONITOR', 'LISTEN'))

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function set_param_freq(master,param,value)
    listen_index = reaper.TrackFX_AddByName(master, controller_fx, true, 100)
    value = (math.log(value) - math.log(min_hz)) * (100 - 0) / (math.log(max_hz) - math.log(min_hz)) + 0
    reaper.TrackFX_SetParam(master, listen_index+mon, param, value)
end

function set_listen_state(master, state)
    index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
    reaper.TrackFX_SetParam(master, index+mon, 0, state)
end 

if ext == 0 or (ext > 0 and ext ~= button_index) then 

    reaper.SetExtState('MISHA_MONITOR', 'LISTEN', button_index, true)
    set_listen_state(master, base_slope_ext)
elseif ext == button_index then 
    set_listen_state(master,0)
    reaper.SetExtState('MISHA_MONITOR', 'LISTEN', '0', true)
end

set_param_freq(master,2,l)
set_param_freq(master,3,h)