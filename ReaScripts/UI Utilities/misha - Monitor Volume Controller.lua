-- @description Monitor Volume Controller
-- @author Misha Oshkanov
-- @version 3.2_1
-- @about
--  UI panel to quicly change level of your monitoring. It's a stepped contoller with defined levels. 
--  If you need more levels or change db values you can edit buttons table.
--  Use right click to change modes between volume control and listen filters

------------------------------------- SETTINGS ----------------------------------------

USE_LISTEN_BANDS = false -- mode by default
USE_REFS = true
REF_FOLDER_NAME = 'Refs'

USE_METRICAB = true
USE_METRICAB_SWITCH = false
USE_METRIC_IN_MONITORINGFX = true

floating_window = true -- use floating window to freely place the panel
POS = 'TOP' -- 'BOTTOM' -- position presets if floating window is false

METRIC_AB = 'ADPTR MetricAB'

buttons = {-32,-24, -14, -8, -4, 0, 4, 12, 18, 24} -- presets in dB

SLOPE = 2 -- 1 = 12db, 2 = 24db, 3 = 36db, 4 = 48db,5 = 60db, 6 = 72db 

-- filters = {1,2,3}

listen_buttons = {
  {str = 'Sub',  l = 20,    h = 60   ,col = {81,100,123,0.8}},
  {str = 'Bass', l = 20,    h = 250  ,col = {86,111,128,0.8}},
  {str = 'Low',  l = 250,   h = 800  ,col = {90,120,135,0.8}},
  {str = 'Mid',  l = 800,   h = 3570 ,col = {86,128,98,0.8}},
  {str = 'High', l = 4000,  h = 20000,col = {121,157,107,0.7}},
  {str = 'Free', l = 20,    h = 20000,col = {161,145,99,0.7}},
}

move_x = 10 -- move panel in x coordinate if floating window is false
move_y = 20 -- move panel in y coordinate

panel_w = 400 -- PANEL SIZE
button_h = 24 -- height default - 24

listen_button_h = 24
scroll_accuracy = 1.2 -- lower is faster scroll

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

local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OSX') or os:match('macOS')
local is_linux = os:match('Other')

local font_size1 = 14
local font_size2 = 14

-- dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.6')
local ctx = reaper.ImGui_CreateContext('Show/Hide')
local font = reaper.ImGui_CreateFont('sans-serif', 0)
-- local font2 = reaper.ImGui_CreateFont('sans-serif', 14)

-- reaper.ImGui_AttachFont(ctx, font)
-- reaper.ImGui_AttachFont(ctx, font2)

free_l = 0
free_h = 22000

min_hz = 20
max_hz = 20000
width = 2
controller_fx = 'Monitor Volume Controller'
listen_state = false

base_freq_ext  = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_FREQ'))
base_width_ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_WIDTH'))
base_slope_ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_SLOPE'))

if base_width_ext == nil then base_width_ext = 2 end

if base_freq_ext == nil then base_freq_ext = 1000 end
if base_slope_ext == nil then base_slope_ext = SLOPE end

slider_range = base_freq_ext

window_flags =  reaper.ImGui_WindowFlags_NoTitleBar() +  
                reaper.ImGui_WindowFlags_NoDocking() +
                reaper.ImGui_WindowFlags_NoScrollbar() + 
                reaper.ImGui_WindowFlags_NoResize() +
                reaper.ImGui_WindowFlags_NoScrollWithMouse() 
                
local ImGui = {}
for name, func in pairs(reaper) do
  name = name:match('^ImGui_(.+)$')
  if name then ImGui[name] = func end
end

mon = (0x1000000)

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

function draw_volume_buttons(master)
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

    b_button = ImGui.Button(ctx, tostring(b), button_w, button_h)
    
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

  if reaper.ImGui_IsMouseClicked( ctx, reaper.ImGui_MouseButton_Right() ) then 
    USE_LISTEN_BANDS = not USE_LISTEN_BANDS 
  end
end 

function draw_listen_buttons(master)
  for i2,lb in ipairs(listen_buttons) do
    ImGui.PushID(ctx, i)
    ImGui.PushFont(ctx, nil, font_size2)

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
    listen_button = ImGui.Button(ctx, lb.str, listen_button_w, listen_button_h)
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
    -- if USE_METRICAB_SWITCH then free_pos = #listen_buttons-1 
    -- else free_pos = #listen_buttons end
    
    if ext == #listen_buttons then free_mode = true else free_mode = false end 
  
  end
  if USE_METRICAB_SWITCH then 
    ImGui.SameLine(ctx) 
    if ab_state == 1 then 
      ab_col = {r=225,g=176,b=116}
    else 
      ab_col = {r=26,g=148,b=225}
    end

    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(ab_col.r,ab_col.g,ab_col.b,0.9))
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(ab_col.r,ab_col.g,ab_col.b,0.8))
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(ab_col.r,ab_col.g,ab_col.b,0.6))

    ab_button = ImGui.Button(ctx, 'AB', listen_button_w, listen_button_h)

    if ab_button then 
      local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
      if index then
        if not USE_METRIC_IN_MONITORINGFX then mon = 0 end
        reaper.TrackFX_SetParam(master, index+mon, 0, ab_state==1 and 0 or 1)
        reaper.SetExtState('MISHA_MONITOR', 'AB', ab_state==1 and '0' or '1', true)
      end  
    end    
    ImGui.PopStyleColor(ctx, 3)
    if ab_state == 1 then draw_color(rgba(242,170,81,1),1) end
    ab_hovered = reaper.ImGui_IsItemHovered(ctx)
  end

  if reaper.ImGui_IsMouseClicked( ctx, reaper.ImGui_MouseButton_Right() ) then 
    if ab_hovered then 
      local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
      if not USE_METRIC_IN_MONITORINGFX then mon = 0 else mon = (0x1000000) end
      reaper.TrackFX_SetOpen(master, index+mon, not reaper.TrackFX_GetOpen(master, index+mon))
    else 
      USE_LISTEN_BANDS = not USE_LISTEN_BANDS 
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
        local track = reaper.GetTrack(0,i)
        local depth = reaper.GetTrackDepth(track)
        local color = reaper.GetTrackColor(track)
        local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO') ~= 0
        local mute = reaper.GetMediaTrackInfo_Value(track, 'B_MUTE')

        local _, name = reaper.GetTrackName(track)

        data.track = track
        data.color = color 
        data.solo = solo 
        data.name = name 
        
        if depth > parentdepth then
            if mute == 0 then reaper.SetMediaTrackInfo_Value(track, 'B_MUTE', 1) end
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
  -- print(#solos)
  if #solos < 0 then return end  
  for k,v in ipairs(solos) do 
      reaper.SetMediaTrackInfo_Value(v.track, 'I_SOLO',v.solo)
  end
end 


function draw_refs(master)
  local count = reaper.CountTracks(0)
  for i=0,count-1 do 
    local track = reaper.GetTrack(0, i) 
    local _, name = reaper.GetTrackName(track)
    if name == REF_FOLDER_NAME then 
      local main_send = reaper.GetMediaTrackInfo_Value(track, 'B_MAINSEND') == 1
      if main_send then 
        reaper.CreateTrackSend(track, 'NULL')
        reaper.SetMediaTrackInfo_Value(track, 'B_MAINSEND', 0 )
      end 
      ref_data = get_children_refs(track)
      break
    end 
  end


  if ref_data == nil then return end 
  for k,ref in ipairs(ref_data) do 
    reaper.ImGui_PushID(ctx, k)

    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Button(),        col(ref.color,0.3))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonHovered(), col(ref.color,0.5))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonActive(),  col(ref.color,0.5))

    button = reaper.ImGui_Button(ctx, ref.name, panel_w-2, 26)
    -- reaper.ImGui_SameLine(ctx,1,1)
    -- b_solostate = reaper.ImGui_RadioButton(ctx, '', ref.solo)

    if button then 
      if ref.solo then
        reaper.SetMediaTrackInfo_Value(ref.track, 'I_SOLO',0)
        restore_solos()
      else 
        save_solos()
        unsolo_all_tracks()
        reaper.SetMediaTrackInfo_Value(ref.track, 'I_SOLO',2)
      end
    end

    if ref.solo then 
        draw_color(rgba(229,201,112,1),1)
    end 

    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopID(ctx)
  end 
end

function Main()
  master = reaper.GetMasterTrack()
  state = get_state(master)
  ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'LISTEN'))
  if ext == nil then ext = 0 end 
  
  if USE_LISTEN_BANDS then 
    draw_listen_buttons(master)
    -- if USE_REFS then 
    --   draw_refs()
    -- end
  else 
    if ext > 0 then 
      reaper.SetExtState('MISHA_MONITOR', 'LISTEN', '0', true) 
      set_listen_state(master,0)
    end 
    draw_volume_buttons(master)
  end
  -- ImGui.PopStyleColor(ctx, 3)

  reaper.ImGui_PushItemWidth(ctx, panel_w-2)

  local minFreq = 20     -- minimum frequency in Hz
  local maxFreq = 22000  -- maximum frequency in Hz

  lowCut  = slider_range / (2 ^ (base_width_ext / 2))
  highCut = slider_range * (2 ^ (base_width_ext / 2))

  if lowCut < minFreq then lowCut = minFreq end
  if highCut > maxFreq then highCut = maxFreq end

  if free_mode == true then 

    vertical, horizontal = reaper.ImGui_GetMouseWheel( ctx )

    if vertical ~= 0 then
      dir = vertical > 0 and 1 or -1 
      key = reaper.JS_Mouse_GetState(-1) == 4
      if key then
        base_width_ext = base_width_ext + (0.3*dir)
        base_width_ext = math.min(math.max(base_width_ext, 0.4),10)
        reaper.SetExtState('MISHA_MONITOR', 'BASE_WIDTH', base_width_ext, true)
        set_param_freq(master,2,lowCut)
        set_param_freq(master,3,highCut)
      else
        step = math.floor(((math.log(slider_range) - math.log(min_hz)) * (100 - 0) / (math.log(max_hz) - math.log(min_hz)) + 0)/scroll_accuracy)
        slider_range = slider_range + (step*dir)
        reaper.SetExtState('MISHA_MONITOR', 'BASE_FREQ', slider_range, true)
        set_param_freq(master,2,lowCut)
        set_param_freq(master,3,highCut)
      end
    end

    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab(),          rgba(195,105,105,0.7))
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive(),    rgba(195,105,105,0.9))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(),             rgba(96,68,68,0.4))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive(),       rgba(100,72,72,0.8))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(),      rgba(100,72,72,0.6))

    range_retval, slider_range = reaper.ImGui_SliderInt( ctx, 'slider_range', slider_range, 20, 20000,  formatIn, reaper.ImGui_SliderFlags_Logarithmic() )
    if range_retval then 
      reaper.SetExtState('MISHA_MONITOR', 'BASE_FREQ', slider_range, true)
      set_param_freq(master,2,lowCut)
      set_param_freq(master,3,highCut)
    end

    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    sliderWidth = (max_x -panel_w/4) - min_x

    local lowCutPos =  (math.log(lowCut)  - math.log(20)) / (math.log(20000) - math.log(20))
    local highCutPos = (math.log(highCut) - math.log(20)) / (math.log(20000) - math.log(20))
    low_cut_x = min_x + (lowCutPos * sliderWidth)
    high_cut_x = min_x + (highCutPos * sliderWidth)

    reaper.ImGui_DrawList_AddRectFilled( draw_list, low_cut_x, min_y, high_cut_x, max_y,  rgba(200,200,200,0.2),2,0)
    ImGui.PopStyleColor(ctx, 5)
  end

  if USE_REFS then 
    draw_refs()
  end

  reaper.ImGui_PopItemWidth( ctx )

  if reaper.ImGui_IsMouseReleased( ctx, reaper.ImGui_MouseButton_Left() ) then 
    if ImGui.IsWindowFocused(ctx) then reaper.SetCursorContext(1, nil) end
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
    -- reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(36, 37, 38, 1))
    -- reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    -- reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(68, 69, 70, 1))
  
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_WindowPadding(), 3,4) 
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_ItemSpacing(), 2,2) 
  
    reaper.ImGui_PushFont(ctx, nil, font_size1)

    if USE_REFS and USE_LISTEN_BANDS then 
      ref_offset = (28 * #ref_data)
    else ref_offset = 0
    end 

    
    if USE_METRICAB_SWITCH then ab_swith = 1 else ab_swith = 0 end

    button_w = (panel_w/#buttons)-2
    listen_button_w = (panel_w/(#listen_buttons+ab_swith))-2
    if free_mode then free_offset = 25 else free_offset = 0 end

    -- scale = reaper.ImGui_GetWindowDpiScale(ctx)
    -- mainHWND = reaper.GetMainHwnd()
    -- windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
    -- retval, ar_left, ar_top, ar_right, ar_bottom = reaper.JS_Window_GetClientRect( windowHWND )

    -- cw, ch = reaper.ImGui_GetWindowSize( ctx )

    -- tcp_hwnd = FindChildByClass(reaper.GetMainHwnd(),'REAPERTCPDisplay',1)
    -- if tcp_hwnd then
    --   tcp_x,tcp_y,tcp_w,tcp_h = GetClientBounds(tcp_hwnd)
    --   retval, tcp_left, tcp_top, tcp_right, tcp_bottom = reaper.JS_Window_GetClientRect( mainHWND )
    -- end

    -- reaper.ImGui_SetNextWindowSize(ctx, panel_w*(1/scale)+4, (button_h+8)*(1/scale)+free_offset)
    
    -- if not floating_window then 
    --   if POS == 'BOTTOM' then 
    --     reaper.ImGui_SetNextWindowPos( ctx,  move_x + (tcp_right-(tcp_right-right)-(tcp_w/2))*(1/scale), move_y + (ar_bottom-(ch))*(1/scale), condIn, 0.5, 0.5 )
    --   elseif POS == 'TOP' then 
    --     reaper.ImGui_SetNextWindowPos( ctx,  move_x + (tcp_left+(tcp_right/6))*(1/scale), move_y + (tcp_top+30)*(1/scale), condIn, 0.5, 0.5 )
    --   end 
    -- end

    mainHWND = reaper.GetMainHwnd()
    windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
    left, top, right, bottom = get_bounds(windowHWND)

    reaper.ImGui_SetNextWindowSize(ctx, panel_w+4, (button_h+8)+free_offset+ref_offset)
    if not floating_window then
      reaper.ImGui_SetNextWindowPos(ctx,  left,  top + (free_offset/2), condIn, 0, 0)
    end
    local visible, open = reaper.ImGui_Begin(ctx, 'Monitor Controller', true, window_flags)
    
    if visible  then
      Main()    
      reaper.ImGui_PopStyleVar( ctx, 2 )
      reaper.ImGui_End(ctx)
    end
    -- reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopFont(ctx)
  
    if open then
      reaper.defer(loop)
    end
end

loop()