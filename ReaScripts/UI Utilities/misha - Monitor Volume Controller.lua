-- @description Monitor Volume Controller
-- @author Misha Oshkanov
-- @version 4.0
-- @about
--  UI panel to quicly change level of your monitoring. It's a stepped contoller with defined levels. 
--  If you need more levels or change db values you can edit buttons table.
--  Use right click to change modes between volume control and listen filters

-----------------------------------------------------------------------------
REF_FOLDER_NAME = 'Refs'
USE_METRIC_IN_MONITORINGFX = true
METRIC_AB = 'ADPTR MetricAB'
CORRECTION_CONTAINER_NAME = "Corrections"

buttons = {-32,-24, -14, -8, -4, 0, 4, 12, 18, 24} -- presets in dB
SLOPE = 2 -- 1 = 12db, 2 = 24db, 3 = 36db, 4 = 48db,5 = 60db, 6 = 72db 

listen_buttons = {
  {str = 'Sub',  l = 20,    h = 60   ,col = {81,100,123,0.8}},
  {str = 'Bass', l = 20,    h = 250  ,col = {86,111,128,0.8}},
  {str = 'Low',  l = 250,   h = 800  ,col = {90,120,135,0.8}},
  {str = 'Mid',  l = 800,   h = 3570 ,col = {86,128,98,0.8}},
  {str = 'High', l = 4000,  h = 20000,col = {121,157,107,0.7}},
  {str = 'Free', l = 20,    h = 20000,col = {161,145,99,0.7}},
}

correction_buttons = {}

local should_resize = false
------------------------------------------------------------------------------------
function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function printt(t, indent)
    indent = indent or 0
    for k, v in pairs(t) do
      if type(v) == "table" then
        print(string.rep(" ", indent) .. k .. " = {")
        printt(v, indent + 2)
        print(string.rep(" ", indent) .. "}")
      else
        print(string.rep(" ", indent) .. k .. " = " .. tostring(v))
      end
    end
end

function print_name(track)
    _, buf = reaper.GetTrackName(track)
    return buf
end 

function ButtonsToString(tbl)
  return table.concat(tbl, ", ")
end

function StringToButtons(str)
  local tbl = {}
  for val in str:gmatch("([^,]+)") do
    local num = tonumber(val:match("^%s*(.-)%s*$"))
    if num then table.insert(tbl, num) end
  end
  table.sort(tbl)
  return tbl
end

local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OSX') or os:match('macOS')
local is_linux = os:match('Other')

local font_size1 = 15
local font_size2 = 14
local unit_w = 45 -- начальное значение по умолчанию
local buttons_text = ButtonsToString(buttons)

local ctx = reaper.ImGui_CreateContext('Monitor Controller')
font = reaper.ImGui_CreateFont('arial', 0)

free_l = 0
free_h = 22000

min_hz = 20
max_hz = 20000
width = 2
controller_fx = 'Monitor Volume Controller'
local SECTION = 'MISHA_MONITOR_SETTINGS'
listen_state = false
correction = false

base_freq_ext  = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_FREQ'))
base_width_ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_WIDTH'))
base_slope_ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_SLOPE'))
ext_folder_name = reaper.GetExtState( 'MISHA_MONITOR', 'REF_FOLDER')
if ext_folder_name ~= REF_FOLDER_NAME then 
  reaper.SetExtState( 'MISHA_MONITOR', 'REF_FOLDER', REF_FOLDER_NAME, true)
end

if base_width_ext == nil then base_width_ext = 2 end

if base_freq_ext == nil then base_freq_ext = 1000 end
if base_slope_ext == nil then base_slope_ext = SLOPE end

slider_range = base_freq_ext

window_flags =  reaper.ImGui_WindowFlags_NoTitleBar() +  
                -- reaper.ImGui_WindowFlags_NoDocking() +
                reaper.ImGui_WindowFlags_NoScrollbar() + 
                -- reaper.ImGui_WindowFlags_NoResize() +
                reaper.ImGui_WindowFlags_NoScrollWithMouse() 
                
local ImGui = {}
for name, func in pairs(reaper) do
  name = name:match('^ImGui_(.+)$')
  if name then ImGui[name] = func end
end

mon = (0x1000000)

function SaveSettings()
  local settings = {
    USE_VOLUME_BUTTONS = USE_VOLUME_BUTTONS and '1' or '0',
    USE_LISTEN_BANDS   = USE_LISTEN_BANDS   and '1' or '0',
    USE_REFS_SWITCH    = USE_REFS_SWITCH    and '1' or '0',
    USE_METRICAB_SWITCH = USE_METRICAB_SWITCH and '1' or '0',
    SHOW_CORRECTION_BTN = SHOW_CORRECTION_BTN and '1' or '0',
    pw = tostring(math.floor(pw or 600))
  }
  
  for key, value in pairs(settings) do
    reaper.SetExtState(SECTION, key, value, true)
  end
  reaper.SetExtState(SECTION, 'BUTTONS_LIST', ButtonsToString(buttons), true)
  reaper.SetExtState(SECTION, 'METRIC_MON', USE_METRIC_IN_MONITORINGFX and '1' or '0', true)
  reaper.SetExtState(SECTION, 'METRIC_USEAB', USE_METRICAB and '1' or '0', true)
  reaper.SetExtState(SECTION, 'REF_NAME', REF_FOLDER_NAME, true)
  reaper.SetExtState(SECTION, 'SLOPE', tostring(SLOPE), true)
  reaper.SetExtState(SECTION, 'SCROLL', tostring(scroll_accuracy), true)
  reaper.SetExtState(SECTION, 'BTN_H', tostring(button_h), true)
end

function LoadSettings()
  local function get_bool(key, default)
    local val = reaper.GetExtState(SECTION, key)
    if val == '' then return default end
    return val == '1'
  end

  USE_VOLUME_BUTTONS  = get_bool('USE_VOLUME_BUTTONS', true)
  USE_LISTEN_BANDS    = get_bool('USE_LISTEN_BANDS', true)
  USE_REFS_SWITCH     = get_bool('USE_REFS_SWITCH', true)
  USE_METRICAB_SWITCH = get_bool('USE_METRICAB_SWITCH', true)
  USE_METRICAB        = get_bool('USE_METRICAB', true)
  SHOW_CORRECTION_BTN = get_bool('SHOW_CORRECTION_BTN', true)
  USE_METRIC_IN_MONITORINGFX = get_bool('METRIC_MON', true)

  REF_FOLDER_NAME = reaper.GetExtState(SECTION, 'REF_NAME')
  if REF_FOLDER_NAME == '' then REF_FOLDER_NAME = 'Refs' end

  SLOPE = tonumber(reaper.GetExtState(SECTION, 'SLOPE')) or 2
  scroll_accuracy = tonumber(reaper.GetExtState(SECTION, 'SCROLL')) or 1.2
  button_h = tonumber(reaper.GetExtState(SECTION, 'BTN_H')) or 24


  local saved_buttons = reaper.GetExtState(SECTION, 'BUTTONS_LIST')
  if saved_buttons ~= "" then
    buttons = StringToButtons(saved_buttons)
    buttons_text = saved_buttons
  else
    buttons = {-32, -24, -14, -8, -4, 0, 4, 12, 18, 24} -- дефолт
  end

  
  local saved_pw = tonumber(reaper.GetExtState(SECTION, 'pw'))
  if saved_pw and saved_pw > 100 then pw = saved_pw end
end

LoadSettings()

function rgba(r, g, b, a)
    b = b/255
    g = g/255 
    r = r/255 
    local b = math.floor(b * 255) * 256
    local g = math.floor(g * 255) * 256 * 256
    local r = math.floor(r * 255) * 256 * 256 * 256
    local a = math.floor(a * 255)
    return r + g + b + a
end

function col(col,a)
    r, g, b = reaper.ColorFromNative(col)
    result = rgba(r,g,b,a)
    return result
end

function draw_color(color,px)
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x, max_y,  color,0,0,px)
end

function draw_text(text,color,x_offset,y_offset)
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddText(draw_list, min_x+x_offset, max_y+y_offset, color, text)
end

function get_state(master)
  index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
  retval, minval, maxval = reaper.TrackFX_GetParam(master, index+(0x1000000), 4)
  return retval
end

function get_listen_freq(master)
  index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
  low_retval,  _, _ = reaper.TrackFX_GetParam(master, index+(0x1000000), 2)
  high_retval, _, _ = reaper.TrackFX_GetParam(master, index+(0x1000000), 3)
  return low_retval, high_retval
end 

function get_listen_state(master)
  index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
  enabled,  _, _ = reaper.TrackFX_GetParam(master, index+(0x1000000), 0)
  return enabled
end 

function get_ab_state(master)
    local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
    if index then 
      if not USE_METRIC_IN_MONITORINGFX then mon = 0 else mon = (0x1000000) end
      return reaper.TrackFX_GetParam(master, index+mon, 0)
    end        
end 

function set_listen_state(master,state)
  if USE_METRICAB then 
      local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
      if index then 
        if not USE_METRIC_IN_MONITORINGFX then mon = 0 else mon = (0x1000000) end
        reaper.TrackFX_SetParam(master, index+mon, 16, state)
      end 
  else 
    index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
    reaper.TrackFX_SetParam(master, index+(0x1000000), 0, state)
  end
  -- enabled = reaper.TrackFX_SetEnabled(master, index+mon, state)
end 

function trunc(num, digits)
  local mult = 10^(digits)
  return math.modf(num*mult)/mult
end

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

function draw_volume_buttons(master,w)
  for i,b in ipairs(buttons) do
    if state == b then s = 1 else s = 0 end
    ImGui.PushID(ctx, i)
    if s == 0 then
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(195,105,105,0.2))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(195,105,105,0.4))
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(),           rgba(240,240,240,1))
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(100,100,100,0.8))
    else
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(195,105,105,0.9))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(205,105,105,0.8))
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(195,105,105,0.6))
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(),           rgba(224,224,224,1))
    end

    b_button = ImGui.Button(ctx, tostring(b), w, button_h)
    
    if i < #buttons then ImGui.SameLine(ctx) end
    ImGui.PopID(ctx)
    ImGui.PopStyleColor(ctx, 4)
    
    if b_button then
      index = reaper.TrackFX_AddByName(master, controller_fx, true, 100)
      if reaper.TrackFX_GetOpen(master, index+(0x1000000)) then reaper.TrackFX_Show(master, index+(0x1000000), 0 ) end
      reaper.TrackFX_SetParam(master, index+(0x1000000), 4, b)
    end
  end
  if free_mode then free_mode = false end
end 

function set_correction(master, name, state)
  local fx = reaper.TrackFX_AddByName(master, CORRECTION_CONTAINER_NAME, true, 0)
  local _, container_count = reaper.TrackFX_GetNamedConfigParm(master, fx+(0x1000000), "container_count" )
  for i=0,container_count-1 do
    local _, item = reaper.TrackFX_GetNamedConfigParm(master, fx+(0x1000000), "container_item."..i)
    local _, fxname = reaper.TrackFX_GetFXName(master, item)
    local enabled = reaper.TrackFX_GetEnabled(master, item)
    if fxname == name then 
      reaper.TrackFX_SetEnabled(master, item, state)
    else
      reaper.TrackFX_SetEnabled(master, item, not state)
    end
  end
end

function draw_correction_single_button(w)
    local active_name = get_active_correction_name()

    local btn_color = (active_name == "OFF") and rgba(100,100,100,0.5) or rgba(211,161,85,0.6)
    
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), btn_color)
    if ImGui.Button(ctx, active_name .. "##corr_pop", w, button_h) then
        ImGui.OpenPopup(ctx, 'corr_popup_menu')
    end
    ImGui.PopStyleColor(ctx)

    if ImGui.BeginPopup(ctx, 'corr_popup_menu') then


        

        -- 2. Список плагинов
        local fx_container = reaper.TrackFX_AddByName(master, CORRECTION_CONTAINER_NAME, true, 0)
        if fx_container ~= -1 then
            local _, count_str = reaper.TrackFX_GetNamedConfigParm(master, fx_container+(0x1000000), "container_count")
            local count = tonumber(count_str) or 0
            
            if count == 0 then 
                ImGui.Text(ctx, "(Container is empty)")
            end

            ImGui.PushStyleColor(ctx, ImGui.Col_Header(),         rgba(211, 161, 85, 0.3)) -- Цвет активной строки
            ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(),  rgba(211, 161, 85, 0.5)) -- Цвет при наведении
            ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(),   rgba(211, 161, 85, 0.7)) -- Цвет при клике


            for i = 0, count - 1 do
                local _, item = reaper.TrackFX_GetNamedConfigParm(master, fx_container+(0x1000000), "container_item."..i)
                local _, full_fxname = reaper.TrackFX_GetFXName(master, item)
                local clean_name = full_fxname:gsub("^%w+:%s*", "")
                
                local is_selected = (active_name == clean_name)

                if ImGui.Selectable(ctx, clean_name .. "##" .. i, is_selected) then
                    for j = 0, count - 1 do
                        local _, other_item = reaper.TrackFX_GetNamedConfigParm(master, fx_container+(0x1000000), "container_item."..j)
                        reaper.TrackFX_SetEnabled(master, other_item, (i == j))
                    end
                end
            end
                        
            ImGui.PopStyleColor(ctx, 3)
        else
            ImGui.Text(ctx, "Container not found")
            if ImGui.Button(ctx, " + Add Corrections Container ", -1) then
              check_or_create_correction_container()
            end
        end
        ImGui.Separator(ctx)

        ImGui.PushStyleColor(ctx, ImGui.Col_Header(),         rgba(150, 50, 50, 0.4)) -- Фоновый цвет если выбрано
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered(),  rgba(180, 60, 60, 0.6)) -- Цвет при наведении
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive(),   rgba(200, 70, 70, 0.8)) -- Цвет при клике
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(),    rgba(180, 70, 70, 0.8)) 

        if ImGui.Selectable(ctx, "OFF", active_name == "OFF") then
            local fx_container = reaper.TrackFX_AddByName(master, CORRECTION_CONTAINER_NAME, true, 0)
            if fx_container ~= -1 then
                local _, count = reaper.TrackFX_GetNamedConfigParm(master, fx_container+(0x1000000), "container_count")
                for i = 0, tonumber(count or 0)-1 do
                    local _, item = reaper.TrackFX_GetNamedConfigParm(master, fx_container+(0x1000000), "container_item."..i)
                    reaper.TrackFX_SetEnabled(master, item, false)
                end
            end
        end
        ImGui.PopStyleColor(ctx, 4)
        ImGui.EndPopup(ctx)
    end

    local corr_hovered = reaper.ImGui_IsItemHovered(ctx)

  if reaper.ImGui_IsMouseClicked( ctx, reaper.ImGui_MouseButton_Right() ) and corr_hovered then 
      local index = reaper.TrackFX_AddByName(master, CORRECTION_CONTAINER_NAME, true, 0)
      reaper.TrackFX_SetOpen(master, index+mon, not reaper.TrackFX_GetOpen(master, index+mon))
  end
  

end

function draw_free_mode_slider(master)
  if not free_mode then return end

  local minFreq, maxFreq = 20, 22000
  
  lowCut  = slider_range / (2 ^ (base_width_ext / 2))
  highCut = slider_range * (2 ^ (base_width_ext / 2))
  lowCut  = math.max(lowCut, minFreq)
  highCut = math.min(highCut, maxFreq)

  local vertical = reaper.ImGui_GetMouseWheel(ctx)
  if vertical ~= 0 then
    local dir = vertical > 0 and 1 or -1 
    local is_ctrl = reaper.JS_Mouse_GetState(-1) == 4 
    
    if is_ctrl then
      base_width_ext = math.min(math.max(base_width_ext + (0.3 * dir), 0.4), 10)
      reaper.SetExtState('MISHA_MONITOR', 'BASE_WIDTH', base_width_ext, true)
    else
      local step = math.floor(((math.log(slider_range) - math.log(min_hz)) * 100 / (math.log(max_hz) - math.log(min_hz))) / scroll_accuracy)
      slider_range = slider_range + (step * dir)
      reaper.SetExtState('MISHA_MONITOR', 'BASE_FREQ', slider_range, true)
    end
    set_param_freq(master, 2, lowCut)
    set_param_freq(master, 3, highCut)
  end


  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab(),          rgba(195,105,105,0.7))
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive(),    rgba(195,105,105,0.9))
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(),             rgba(96,68,68,0.4))
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive(),       rgba(100,72,72,0.8))
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(),      rgba(100,72,72,0.6))

  reaper.ImGui_PushItemWidth(ctx, -1) 
  local range_retval
  range_retval, slider_range = reaper.ImGui_SliderInt(ctx, '##free_slider', slider_range, 20, 20000, formatIn, reaper.ImGui_SliderFlags_Logarithmic())
  
  if range_retval then 
    reaper.SetExtState('MISHA_MONITOR', 'BASE_FREQ', slider_range, true)
    set_param_freq(master, 2, lowCut)
    set_param_freq(master, 3, highCut)
  end

  local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  local w = max_x - min_x
  
  local function freq_to_pos(f) return (math.log(f) - math.log(20)) / (math.log(20000) - math.log(20)) end
  local low_x = min_x + (freq_to_pos(lowCut) * w)
  local high_x = min_x + (freq_to_pos(highCut) * w)

  reaper.ImGui_DrawList_AddRectFilled(draw_list, low_x, min_y, high_x, max_y, rgba(200,200,200,0.2), 2)
  
  ImGui.PopStyleColor(ctx, 5)
  reaper.ImGui_PopItemWidth(ctx)
end

function draw_ab_button(master, w)
  if not USE_METRICAB_SWITCH then return end

  local ab_state = get_ab_state(master)
  local ab_col = {}
  
  if ab_state == 1 then 
    ab_col = {r=225, g=176, b=116} -- Оранжевый (Активен)
  else 
    ab_col = {r=26, g=148, b=225}  -- Синий (Выключен)
  end

  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(ab_col.r, ab_col.g, ab_col.b, 0.9))
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(ab_col.r, ab_col.g, ab_col.b, 0.8))
  ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(ab_col.r, ab_col.g, ab_col.b, 0.6))

  if ImGui.Button(ctx, 'AB', w, button_h) then 
    local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
    if index ~= -1 then
      local mon = USE_METRIC_IN_MONITORINGFX and 0x1000000 or 0
      reaper.TrackFX_SetParam(master, index + mon, 0, ab_state == 1 and 0 or 1)
      reaper.SetExtState('MISHA_MONITOR', 'AB', ab_state == 1 and '0' or '1', true)
    end  
  end

  ab_hovered = reaper.ImGui_IsItemHovered(ctx)

  if reaper.ImGui_IsMouseClicked( ctx, reaper.ImGui_MouseButton_Right() ) and ab_hovered then 
      local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
      if not USE_METRIC_IN_MONITORINGFX then mon = 0 else mon = (0x1000000) end
      reaper.TrackFX_SetOpen(master, index+mon, not reaper.TrackFX_GetOpen(master, index+mon))
  end
  
  ImGui.PopStyleColor(ctx, 3)
  
  if ab_state == 1 and draw_color then 
    draw_color(rgba(242,170,81,1), 1) 
  end
end

function draw_listen_buttons(master,w)
  for i2,lb in ipairs(listen_buttons) do
    ImGui.PushID(ctx, i)
    ImGui.PushFont(ctx, font2, font_size2)

    listen_low, listen_high = get_listen_freq(master)
    listen_state = get_listen_state(master)
    if USE_METRICAB_SWITCH then ab_state = get_ab_state(master) end

    if ext == i2 then
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(195,105,105,0.9))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(205,105,105,0.8))
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(195,105,105,0.6))
    else
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(lb.col[1]+10,lb.col[2]+10,lb.col[3]+10,lb.col[4]))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(lb.col[1]+20,lb.col[2]+20,lb.col[3]+20,1))
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(lb.col[1],lb.col[2],lb.col[3],lb.col[4]))
    end
    listen_button = ImGui.Button(ctx, lb.str, w, button_h)
    if i2 < #listen_buttons then ImGui.SameLine(ctx) end

    ImGui.PopID(ctx)
    ImGui.PopFont(ctx)
    ImGui.PopStyleColor(ctx, 3)
    
    if listen_button then 
      if ext == 0 or (ext > 0 and ext ~= i2) then 
        reaper.SetExtState('MISHA_MONITOR', 'LISTEN', i2, true)
        set_listen_state(master,base_slope_ext)
      elseif ext == i2 then 
        set_listen_state(master,0)
        reaper.SetExtState('MISHA_MONITOR', 'LISTEN', '0', true)
      end

      if lb.str == 'Free' then 
        lowCut  = slider_range / (2 ^ (base_width_ext / 2))
        highCut = slider_range * (2 ^ (base_width_ext / 2))
        set_param_freq(master,2,lowCut)
        set_param_freq(master,3,highCut)
      else 
        set_param_freq(master,2,lb.l)
        set_param_freq(master,3,lb.h)
      end 
    end

    if ext == #listen_buttons then free_mode = true else free_mode = false end 
  
  end

  if reaper.ImGui_IsMouseClicked( ctx, reaper.ImGui_MouseButton_Right() ) then 
    if ab_hovered then 
      local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
      if not USE_METRIC_IN_MONITORINGFX then mon = 0 else mon = (0x1000000) end
      reaper.TrackFX_SetOpen(master, index+mon, not reaper.TrackFX_GetOpen(master, index+mon))
    end
  end
end 

function solo_children(parent,state)
  if parent then 
      local parentdepth = reaper.GetTrackDepth(parent)
      local parentnumber = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
      local children = {}
      for i=parentnumber, reaper.CountTracks(0)-1 do
        local track = reaper.GetTrack(0,i)
        local depth = reaper.GetTrackDepth(track)
        local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO') ~= 0

        if depth > parentdepth then
          reaper.SetMediaTrackInfo_Value(track, "I_SOLO", state == true and 2 or 0)
        else
          break
        end
      end
    end
end

function get_children_refs(parent)
    if parent then 
      local parentdepth = reaper.GetTrackDepth(parent)
      local parentnumber = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
      local children = {}
      for i=parentnumber, reaper.CountTracks(0)-1 do
        local data = {}
        donotmute = false
        local track = reaper.GetTrack(0,i)
        local depth = reaper.GetTrackDepth(track)
        local color = reaper.GetTrackColor(track)
        local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO') ~= 0
        local mute = reaper.GetMediaTrackInfo_Value(track, 'B_MUTE')
        local _, name = reaper.GetTrackName(track)
        local is_folder = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH" ) == 1
        if is_folder and reaper.CountTrackMediaItems(track) == 0 then 
          donotmute = true
          name = name ..' (folder)'
        end

        data.track = track
        data.color = color 
        data.solo = solo 
        data.name = name
        data.donotmute = donotmute
        
        if depth > parentdepth then
          if donotmute then 
            if mute == 1 then reaper.SetMediaTrackInfo_Value(track, 'B_MUTE', 0) end
          else
            if mute == 0 then reaper.SetMediaTrackInfo_Value(track, 'B_MUTE', 1) end
          end
            table.insert(children, data)
        else
            break
        end
      end
      return children
    end
end

ref_data = {}
solos = {}

function save_solos()
  local count = reaper.CountTracks(0)
  for k,v in ipairs(ref_data) do 
    if v.solo then 
      is_ref_soloed = true
    end 
  end
  if not is_ref_soloed then solos = {} end
  for i=0,count-1 do 
    local track = reaper.GetTrack(0, i) 
    local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO')
    if solo > 0 then 
      is_ref = false
      is_ref_soloed = false 
      for k,v in ipairs(ref_data) do 
        -- if v.solo then 
        --   is_ref_soloed = true 
        -- end 
        if v.track == track then 
          is_ref = true
        end 
      end
      if not is_ref then 
        local data = {}
        data.solo = solo 
        data.track = track 
        table.insert(solos, data)
      end 
    end
  end 
  write_solos_to_ext()
end 

function write_solos_to_ext()
  local parts = {}
  for i, v in ipairs(solos) do
    local guid = reaper.GetTrackGUID(v.track)
    parts[#parts+1] = string.format("%d:%s:%.1f", i, guid, v.solo)
  end
  local str = table.concat(parts, "|")
  reaper.SetProjExtState(0, "MISHA_MONITOR", "SOLOS", str)
end

function unsolo_all_tracks()
  local count = reaper.CountTracks(0)
  for i=0,count-1 do 
    local track = reaper.GetTrack(0, i) 
    local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO')
    if solo > 0 then 
      reaper.SetMediaTrackInfo_Value(track, 'I_SOLO',0)
    end  
  end 
end 

function restore_solos()
  unsolo_all_tracks()
  if #solos < 0 then return end  
  for k,v in ipairs(solos) do 
      reaper.SetMediaTrackInfo_Value(v.track, 'I_SOLO',v.solo)
  end
  reaper.SetProjExtState(0, "MISHA_MONITOR", "SOLOS", "")
end 

function save_last_ref_solo(value)
  reaper.SetProjExtState(0, 'MISHA_MONITOR', 'LAST_SOLO', value)
end

function draw_refs_button(w)
  if not USE_REFS_SWITCH then return end

  -- Проверяем, есть ли хоть один активный реф для цвета кнопки
  local any_solo = false
  if ref_data then
    for _, r in ipairs(ref_data) do if r.solo then any_solo = true; break end end
  end

  if any_solo then 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), rgba(112, 229, 150, 0.6)) 
  end

  if reaper.ImGui_Button(ctx, "REF", w, button_h) then
    show_refs_panel = not show_refs_panel
    
  end

  if any_solo then reaper.ImGui_PopStyleColor(ctx) end
end

function get_max_refs_width()
  local max_w = 150
  if not ref_data or #ref_data == 0 then return max_w end
  for _, ref in ipairs(ref_data) do
    local text_w, _ = reaper.ImGui_CalcTextSize(ctx, ref.name)
    local total_w = text_w + 80 
    if total_w > max_w then max_w = total_w end
  end
  return max_w
end

function DrawRefsWindow()
  local required_w = get_max_refs_width()
  local flags = reaper.ImGui_WindowFlags_AlwaysAutoResize() | 
                reaper.ImGui_WindowFlags_NoScrollbar()

  reaper.ImGui_SetNextWindowSize(ctx, required_w, 20*#ref_data, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'Reference Tracks', true)
  
  if visible then
    local lufs_string = ""
    local ref_folder_track = nil
    
    local count = reaper.CountTracks(0)
    for i = 0, count - 1 do 
      local track = reaper.GetTrack(0, i) 
      local _, name = reaper.GetTrackName(track)
      if name == REF_FOLDER_NAME then 
        ref_folder_track = track
        
        if reaper.GetMediaTrackInfo_Value(track, 'B_MUTE') == 1 then 
          reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
        end
        if reaper.GetMediaTrackInfo_Value(track, 'B_MAINSEND') == 1 then 
          reaper.CreateTrackSend(track, nil) 
          reaper.SetMediaTrackInfo_Value(track, 'B_MAINSEND', 0)
        end

        local fx = reaper.TrackFX_AddByName(track, 'Loudness Meter', false, 1)
        if fx ~= -1 and reaper.GetPlayState() == 1 then 
          local meter_lufs = reaper.TrackFX_GetParam(track, fx, 19) -- параметр 19 (LUFS-S)
          if meter_lufs > -40 then
            lufs_string = string.format("%.1f", meter_lufs)
          end
        end
        
        ref_data = get_children_refs(track)
        break
      end 
    end

    if ref_data and #ref_data > 0 then
      for k, ref in ipairs(ref_data) do
        reaper.ImGui_PushID(ctx, k)
      
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col(ref.color, 0.3))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col(ref.color, 0.5))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col(ref.color, 0.6))

        if reaper.ImGui_Button(ctx, ref.name .. "##btn", -1, 26) then
          if ref.solo then
            restore_solos()
            unsolo_all_tracks()
          else
            save_last_ref_solo(reaper.GetTrackGUID(ref.track))
            save_solos()
            unsolo_all_tracks()
            reaper.SetMediaTrackInfo_Value(ref.track, 'I_SOLO', 2)
            if ref.donotmute then solo_children(ref.track, true) end
          end
        end

        if ref.solo then
          local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
          local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
          local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
          
          reaper.ImGui_DrawList_AddCircleFilled(draw_list, min_x + 10, min_y + 13, 3, rgba(229,201,112,1))
          
          if lufs_string ~= "" then
            local tw, _ = reaper.ImGui_CalcTextSize(ctx, lufs_string)
            reaper.ImGui_DrawList_AddText(draw_list, max_x - tw - 10, min_y + 3, rgba(244, 234, 123, 1), lufs_string)
          end
        end

        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_PopID(ctx)
      end
    else
      reaper.ImGui_Text(ctx, "Ref folder not found or empty")
    end
    
    reaper.ImGui_End(ctx)
  end

  if not open then show_refs_panel = false end
end

function get_active_correction_name()
  local fx = reaper.TrackFX_AddByName(master, CORRECTION_CONTAINER_NAME, true, 0)
  if fx == -1 then return "OFF" end
  
  local _, container_count = reaper.TrackFX_GetNamedConfigParm(master, fx+(0x1000000), "container_count")
  container_count = tonumber(container_count) or 0
  
  for i = 0, container_count - 1 do
    local _, item = reaper.TrackFX_GetNamedConfigParm(master, fx+(0x1000000), "container_item."..i)
    if reaper.TrackFX_GetEnabled(master, item) then
      local _, fxname = reaper.TrackFX_GetFXName(master, item)
      return fxname:gsub("^%w+:%s*", "") 
    end
  end
  
  return "OFF"
end

function get_correction_button_width()
    if not SHOW_CORRECTION_BTN then return 0 end
    local name = get_active_correction_name() 
    local text_w, _ = reaper.ImGui_CalcTextSize(ctx, name)
    return text_w + 10
end

function check_or_create_correction_container()
  local fx_index = reaper.TrackFX_AddByName(master, "Corrections", true, 0)
  local _, fx_name = reaper.TrackFX_GetFXName(master, fx_index+mon)
  
  if not fx_name:find("Corrections") then
    local new_fx = reaper.TrackFX_AddByName(master, "Container", true, 1000)
    reaper.TrackFX_SetNamedConfigParm(master, new_fx+mon, "renamed_name", "Corrections")
    return new_fx
  end
  return fx_index
end

function DrawSettingsWindow()
  reaper.ImGui_SetNextWindowSize(ctx, 400, 400, reaper.ImGui_Cond_FirstUseEver())

  local visible, open = reaper.ImGui_Begin(ctx, 'Monitor Settings', true, reaper.ImGui_WindowFlags_None())
  if visible then
    local function Toggle(label, var_name)
        local current_val = _G[var_name] 
        local changed, new_val = reaper.ImGui_Checkbox(ctx, label, current_val)
        if changed then
            _G[var_name] = new_val
            should_resize = true
            SaveSettings()
        end
    end

    Toggle("Volume Buttons", "USE_VOLUME_BUTTONS")
    Toggle("Listen Bands",   "USE_LISTEN_BANDS")
    Toggle("Corrections", "SHOW_CORRECTION_BTN")
    Toggle("Metric AB",      "USE_METRICAB_SWITCH")
    Toggle("References",   "USE_REFS_SWITCH")

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_TreeNode(ctx, "Advanced Settings") then
      reaper.ImGui_Spacing(ctx)

      local changed_useab, new_useab = reaper.ImGui_Checkbox(ctx, "Use Metric AB instead of JS", USE_METRICAB)
      if changed_useab then
        USE_METRICAB = new_useab
        SaveSettings()
      end

      local changed_mon, new_mon = reaper.ImGui_Checkbox(ctx, "Metric AB in Monitoring FX", USE_METRIC_IN_MONITORINGFX)
      if changed_mon then
        USE_METRIC_IN_MONITORINGFX = new_mon
        SaveSettings()
      end
      
      local changed, new_text = reaper.ImGui_InputText(ctx, "Volume Buttons", buttons_text)
      if changed then buttons_text = new_text end

      reaper.ImGui_PushItemWidth(ctx, 120)
      local slopes_txt = {"12dB", "24dB", "36dB", "48dB", "60dB", "72dB"}
      local rv_sl, new_sl = reaper.ImGui_SliderInt(ctx, "Listen Filter Slope", SLOPE, 1, 6, slopes_txt[SLOPE])
      if rv_sl then SLOPE = new_sl; SaveSettings() end

      local rv_sc, new_sc = reaper.ImGui_SliderDouble(ctx, "Scroll Speed in free mode", scroll_accuracy, 0.1, 5.0, "%.1f")
      if rv_sc then scroll_accuracy = new_sc; SaveSettings() end

      local rv_ref, new_ref = reaper.ImGui_InputText(ctx, "Refs Folder Name", REF_FOLDER_NAME)
      if rv_ref then REF_FOLDER_NAME = new_ref; SaveSettings() end

      local rv_bh, new_bh = reaper.ImGui_SliderInt(ctx, "Global Button Height", button_h, 16, 50)
      if rv_bh then button_h = new_bh; should_resize = true; SaveSettings() end

      reaper.ImGui_Separator(ctx)

      reaper.ImGui_PopItemWidth(ctx)

      local reset_btn_w = 50
      
      if reaper.ImGui_Button(ctx, "Save", -reset_btn_w - 4) then
        buttons = StringToButtons(buttons_text)
        should_resize = true 
      end 
      
      reaper.ImGui_SameLine(ctx)

      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), rgba(150, 50, 50, 0.6))
      if reaper.ImGui_Button(ctx, "RESET TO DEFAULTS", reset_btn_w) then

        USE_VOLUME_BUTTONS = true
        USE_LISTEN_BANDS = true
        USE_REFS_SWITCH = false
        USE_METRICAB_SWITCH = false
        SHOW_CORRECTION_BTN = false
        REF_FOLDER_NAME = 'Refs'
        SLOPE = 2
        scroll_accuracy = 1.2
        button_h = 24
        buttons = {-32, -24, -14, -8, -4, 0, 4, 12, 18, 24}
        buttons_text = ButtonsToString(buttons)
        USE_METRIC_IN_MONITORINGFX = true
        pw = 600
        should_resize = true
        SaveSettings()
      end
      reaper.ImGui_PopStyleColor(ctx)

      reaper.ImGui_TreePop(ctx)
    end
   

    reaper.ImGui_End(ctx)
  end
  if not open then show_settings_window = false end
end


function draw_settings_button(settings_w)
  if reaper.ImGui_Button(ctx, "?", settings_w, button_h) then
    show_settings_window = not show_settings_window
  end
end

function Main(unit_w, settings_w, corr_w, ab_ref_w, gap)
  state = get_state(master)
  ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'LISTEN'))
  if ext == nil then ext = 0 end 

  draw_settings_button(settings_w)
  reaper.ImGui_SameLine(ctx)

  if SHOW_CORRECTION_BTN then
    draw_correction_single_button(corr_w)
    reaper.ImGui_SameLine(ctx)
  end

  if USE_VOLUME_BUTTONS then
      reaper.ImGui_Dummy(ctx, gap, 1)
      reaper.ImGui_SameLine(ctx)
      draw_volume_buttons(master, unit_w)
      reaper.ImGui_SameLine(ctx)
  end
  
  if USE_LISTEN_BANDS then
      reaper.ImGui_Dummy(ctx, gap, 1)
      reaper.ImGui_SameLine(ctx)
      draw_listen_buttons(master, unit_w * 1.5)
      reaper.ImGui_SameLine(ctx)
  end

  if USE_METRICAB_SWITCH then
    reaper.ImGui_Dummy(ctx, gap, 1)
    reaper.ImGui_SameLine(ctx)
    draw_ab_button(master, ab_ref_w)
    reaper.ImGui_SameLine(ctx)
  end

  if USE_REFS_SWITCH then
    if not USE_METRICAB_SWITCH then 
      reaper.ImGui_Dummy(ctx, gap, 1)
      reaper.ImGui_SameLine(ctx)
    end
    draw_refs_button(ab_ref_w)
  end

  if free_mode then
    reaper.ImGui_Spacing(ctx)
    draw_free_mode_slider(master)
  end

  if reaper.ImGui_IsMouseReleased(ctx, 0) and ImGui.IsWindowFocused(ctx) then 
    reaper.SetCursorContext(1, nil) 
  end
end

function GetClientBounds(hwnd)
    ret, left, top, right, bottom = reaper.JS_Window_GetClientRect(hwnd)
    return left, top, right-left, bottom-top
end

function FindChildByClass(hwnd, classname, occurance) 
    local arr = reaper.new_array({}, 255)
    reaper.JS_Window_ArrayAllChild(hwnd, arr)
    local adr = arr.table() 
    local control_occurance = 0
    for j = 1, #adr do
        local hwnd = reaper.JS_Window_HandleFromAddress(adr[j]) 
        if reaper.JS_Window_GetClassName(hwnd)== classname then
            control_occurance = control_occurance + 1
            if occurance == control_occurance then return hwnd end
        end
    end
end

function get_bounds(hwnd)
  local _, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
  if reaper.GetOS():match("^OSX") then
      local screen_height = reaper.ImGui_GetMainViewport(ctx).WorkSize.y
      top = screen_height - bottom
      bottom = screen_height - top
  end
  -- return left, top, right-left, bottom-top
  return left, top, right, bottom
end

function loop()  
    if not pw then pw = 800 end 
    local window_h = button_h + 8 + (free_mode and 26 or 0)
      local current_pw, _ = reaper.ImGui_GetWindowSize(ctx)
    if not current_pw or current_pw < 50 then current_pw = pw or 600 end

    local current_unit_w = unit_w or 45 

    if should_resize then
        local base_unit = current_unit_w
        local settings_w = 16
        local ab_ref_w = 30
        local gap = 2
        local spacing = 2
        local target_pw = settings_w + 16
        
        if SHOW_CORRECTION_BTN then 
            target_pw = target_pw + get_correction_button_width(master) + spacing 
        end
        
        if USE_VOLUME_BUTTONS then 
            target_pw = target_pw + gap + (#buttons * base_unit) + ((#buttons-1) * spacing)
        end
        
        if USE_LISTEN_BANDS then 
            target_pw = target_pw + gap + (#listen_buttons * base_unit * 1.5) + ((#listen_buttons-1) * spacing) + 35 + spacing
        end
        
        if USE_METRICAB_SWITCH or USE_REFS_SWITCH then
            target_pw = target_pw + gap + 10
            if USE_METRICAB_SWITCH then target_pw = target_pw + ab_ref_w + spacing end
            if USE_REFS_SWITCH then target_pw = target_pw + ab_ref_w + spacing end
        end

        reaper.ImGui_SetNextWindowSize(ctx, target_pw, window_h, reaper.ImGui_Cond_Always())
        pw = target_pw
        should_resize = false
    else
        reaper.ImGui_SetNextWindowSize(ctx, pw, window_h, reaper.ImGui_Cond_Always())
    end

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 6, 3) 
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 2, 2) 
    reaper.ImGui_PushFont(ctx, nil, font_size1)

    local visible, open = reaper.ImGui_Begin(ctx, 'Monitor Controller', true, window_flags)
    
    pw, ph = reaper.ImGui_GetWindowSize(ctx)
    px, py = reaper.ImGui_GetWindowPos(ctx)
    local win_content_w = pw - 16

    if visible then
        local settings_w = 16
        local ab_ref_w = 30
        local gap = 2 
        local spacing = 2

        local corr_w = 0
        if SHOW_CORRECTION_BTN then 
            corr_w = get_correction_button_width(master) 
        end
        
        local occupied = settings_w + spacing
        if SHOW_CORRECTION_BTN then occupied = occupied + corr_w + spacing end
        
        if USE_METRICAB_SWITCH or USE_REFS_SWITCH then
            occupied = occupied + gap
            if USE_METRICAB_SWITCH then occupied = occupied + ab_ref_w end
            if USE_REFS_SWITCH then 
                local internal_s = USE_METRICAB_SWITCH and spacing or 0
                occupied = occupied + internal_s + ab_ref_w + 4
            end
        end

        if USE_LISTEN_BANDS then occupied = occupied + spacing end

        local units = 0
        local add_fixed = 0
        local active_groups = 0
        
        if USE_VOLUME_BUTTONS then 
            units = units + #buttons 
            add_fixed = add_fixed + ((#buttons - 1) * spacing)
            active_groups = active_groups + 1
        end
        if USE_LISTEN_BANDS then 
            units = units + (#listen_buttons * 1.5) 
            add_fixed = add_fixed + ((#listen_buttons - 1) * spacing)
            active_groups = active_groups + 1
        end

        occupied = occupied + (active_groups * gap) + add_fixed

        local dynamic_area = win_content_w - occupied
        if unit_w < 15 then unit_w = 15 end

        unit_w = (units > 0) and (dynamic_area / units) or 45 

        Main(unit_w, settings_w, corr_w, ab_ref_w, gap)  
        
        reaper.ImGui_End(ctx)
    end

    if show_settings_window then DrawSettingsWindow() end
    if show_refs_panel then DrawRefsWindow() end

    if reaper.ImGui_IsMouseReleased(ctx, reaper.ImGui_MouseButton_Left()) then
      SaveSettings()  
    end

    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopFont(ctx)

    if open then
        reaper.defer(loop)
    end
end

master = reaper.GetMasterTrack()
loop()