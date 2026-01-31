-- @description Monitor Volume Controller Shortcut - Listen High
-- @author Misha Oshkanov
-- @version 0.3
-- @about
--  Action to solo certain frequency in monitor controller script



l = 4000
h = 20000
button_index = 5

SLOPE = 2 -- 1 = 12db, 2 = 24db, 3 = 36db, 4 = 48db,5 = 60db, 6 = 72db 

USE_METRICAB = true
USE_METRIC_IN_MONITORINGFX = true
------------------------------------------------------------------------------
------------------------------------------------------------------------------
master = reaper.GetMasterTrack()
controller_fx = 'Monitor Volume Controller'
METRIC_AB = 'ADPTR MetricAB'
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

function frequency_to_normalized(f)
    local f_min = 10
    local f_mid = 2637
    local f_max = 22050
    
    local t = math.log(f / f_min) / math.log(f_mid / f_min)
    
    -- Проверяем СНАЧАЛА самые высокие частоты!
    if f >= 4000 then
        -- print('da')  -- Теперь это сработает для f >= 4000
        t = t ^ 2.302
    elseif f >= 801 then 
        t = t ^ 2.374
    elseif f >= 301 then
        t = t ^ 2.59 
    elseif f >= 61 then
        t = t ^ 2.68  
    elseif f >= 41 then
        t = t ^ 2.51 
    elseif f >= 10 then
        t = t ^ 2.1 
    end
    
    return 0.5 * t
end

function set_param_freq(master,param,value)
  if USE_METRICAB then 
    if param == 2 then param = 19
    elseif param == 3 then param = 20 
    end 
    local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
    if index then 
      if not USE_METRIC_IN_MONITORINGFX then mon = 0 else mon = (0x1000000) end
      reaper.TrackFX_SetParam(master, index+mon, param, frequency_to_normalized(value))
    end 
  else 
    listen_index = reaper.TrackFX_AddByName(master, controller_fx, true, 100)
    value = (math.log(value) - math.log(min_hz)) * (100 - 0) / (math.log(max_hz) - math.log(min_hz)) + 0
    reaper.TrackFX_SetParam(master, listen_index+(0x1000000), param, value)
  end
end
function set_listen_state(master, state)
    if USE_METRICAB then 
      local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
      if index then 
        if not USE_METRIC_IN_MONITORINGFX then mon = 0 else mon = (0x1000000) end
        reaper.TrackFX_SetParam(master, index+mon, 16, state)
      end 
    else
        index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
        reaper.TrackFX_SetParam(master, index+mon, 0, state)
    end
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