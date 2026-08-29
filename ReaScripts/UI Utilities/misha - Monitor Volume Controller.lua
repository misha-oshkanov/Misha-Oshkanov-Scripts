-- @description Monitor Volume Controller
-- @author Misha Oshkanov
-- @version 5.0
-- @about
--  UI panel to quicly change level of your monitoring. It's a stepped contoller with defined levels. 
--  If you need more levels or change db values you can edit buttons table.
--  Use right click to change modes between volume control and listen filters
-- @changelog
--  big ui overhaul
--  new meter module
--  new monitoring fx module (create custom buttons in settings to float fx on monitoring fx chain)
--  new settings and sliders
--  FTC gridbox support as module (use mousewheel)
--  Use mousewheel to change tracks in MetricAB
--  Use mousewheel to change ref tracks 
--  many bug fixes

-----------------------------------------------------------------------------
REF_FOLDER_NAME = 'Refs'
USE_METRIC_IN_MONITORINGFX = true
METRIC_AB = 'ADPTR MetricAB'
CORRECTION_CONTAINER_NAME = "Corrections"
ROW_TAIL_GAP = 1

buttons = {} -- presets in dB
SLOPE = 2 -- 1 = 12db, 2 = 24db, 3 = 36db, 4 = 48db,5 = 60db, 6 = 72db 

listen_buttons = {
  {str = 'Sub',  l = 20,    h = 60   ,col = {81,100,123,0.8}},
  {str = 'Bass', l = 20,    h = 250  ,col = {86,111,128,0.8}},
  {str = 'Low',  l = 250,   h = 800  ,col = {90,120,135,0.8}},
  {str = 'Mid',  l = 800,   h = 3570 ,col = {86,128,98,0.8}},
  {str = 'High', l = 4000,  h = 20000,col = {121,157,107,0.7}},
  {str = 'Free', l = 20,    h = 20000,col = {161,145,99,0.7}},
}

local layers = {
  [1] = { vol = true,  lis = false,  corr = true,  ref = false,  ab = false },
  [2] = { vol = false, lis = false,  corr = true,  ref = true,   ab = false },
  [3] = { vol = false, lis = true,   corr = false, ref = false,  ab = false },
}

for i = 1, 3 do
  layers[i].grid = i <= 2
  layers[i].mtr = true
end


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


local layer_colors = {
  [1] = {r=70, g=105, b=126}, 
  [2] = {r=86, g=133, b=80},
  [3] = {r=126,g=71,  b=70},
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

local font_size1 = 14
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
item_count_total_width = 0

base_freq_ext  = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_FREQ'))
base_width_ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_WIDTH'))
base_slope_ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_SLOPE'))
ext_folder_name = reaper.GetExtState( 'MISHA_MONITOR', 'REF_FOLDER')
local MAX_LAYERS = tonumber(reaper.GetExtState(SECTION, 'MAX_LAYERS')) or 3
local current_layer = tonumber(reaper.GetExtState(SECTION, 'CURRENT_LAYER')) or 1

local pdc_button_idx = tonumber(reaper.GetExtState(SECTION, 'PDC_IDX')) or 0
local last_regular_idx = tonumber(reaper.GetExtState(SECTION, 'LAST_REG_IDX')) or 1
local current_volume_idx = 1 -- текущая активная кнопка (виртуальная)

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

function update_pdc_logic(master)
  -- Проверяем опцию 43150 (Auto-bypass FX with PDC on record arm)
  -- 0 = выкл, 1 = вкл. Используем GetConfigVar
  local auto_bypass_pdc = reaper.SNM_GetIntConfigVar("pdcbypass", -1) == 1
  print(auto_bypass_pdc)
  
  -- Проверяем, есть ли хоть один трек на записи
  local any_record_arm = false
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then
      any_record_arm = true
      break
    end
  end
  -- ЛОГИКА ПЕРЕКЛЮЧЕНИЯ
  if pdc_button_idx > 0 and auto_bypass_pdc and any_record_arm then
    -- Если условия PDC соблюдены — включаем PDC кнопку
    if current_volume_idx ~= pdc_button_idx then
      current_volume_idx = pdc_button_idx
      set_volume(master, buttons[pdc_button_idx]) -- ваша функция установки громкости
    end
  else
    -- Иначе возвращаемся к последней выбранной вручную кнопке
    if current_volume_idx ~= last_regular_idx then
      current_volume_idx = last_regular_idx
      set_volume(master, buttons[last_regular_idx])
    end
  end
end


function SaveSettings()
  local settings = {
    USE_VOLUME_BUTTONS = USE_VOLUME_BUTTONS and '1' or '0',
    USE_LISTEN_BANDS   = USE_LISTEN_BANDS   and '1' or '0',
    USE_REFS_SWITCH    = USE_REFS_SWITCH    and '1' or '0',
    USE_METRICAB_SWITCH = USE_METRICAB_SWITCH and '1' or '0',
    USE_METRICAB = USE_METRICAB and '1' or '0',
    USE_METRIC_IN_MONITORINGFX = USE_METRIC_IN_MONITORINGFX and '1' or '0',
    SHOW_CORRECTION_BTN = SHOW_CORRECTION_BTN and '1' or '0',
    USE_ITEM_COUNT = USE_ITEM_COUNT and '1' or '0',
    USE_MONFX = USE_MONFX and '1' or '0',
    USE_GRID_BOX = USE_GRID_BOX and '1' or '0',
    DISABLE_CORR_ON_START = DISABLE_CORR_ON_START and '1' or '0',
    FREE_MODE_TOP = FREE_MODE_TOP and '1' or '0',

    pw = tostring(math.floor(pw or 600))
  }
  
  for key, value in pairs(settings) do
    reaper.SetExtState(SECTION, key, value, true)
  end
  reaper.SetExtState(SECTION, 'BUTTONS_LIST', ButtonsToString(buttons), true)
  local mfx_parts = {}
  for _, p in ipairs(mon_fx_presets or {}) do
    mfx_parts[#mfx_parts + 1] = tostring(p.fx) .. '|' .. tostring(p.name) .. '|' ..
      tostring(tonumber(p.w) or 20) .. '|' .. string.format('%08x', p.col_u32 or 0x6CAEEBFF)
  end
  reaper.SetExtState(SECTION, 'MON_FX_PRESETS', table.concat(mfx_parts, ';'), true)
  reaper.SetExtState(SECTION, 'METRIC_MON', USE_METRIC_IN_MONITORINGFX and '1' or '0', true)
  -- reaper.SetExtState(SECTION, 'USE_METRICAB', USE_METRICAB and '1' or '0', true)
  reaper.SetExtState(SECTION, 'REF_NAME', REF_FOLDER_NAME, true)
  reaper.SetExtState(SECTION, 'SLOPE', tostring(SLOPE), true)
  reaper.SetExtState(SECTION, 'SCROLL', tostring(scroll_accuracy), true)
  reaper.SetExtState(SECTION, 'BTN_H', tostring(button_h), true)
  reaper.SetExtState(SECTION, 'GRID_W', tostring(grid_width), true)
  reaper.SetExtState(SECTION, 'TAIL_GAP', tostring(ROW_TAIL_GAP), true)
  reaper.SetExtState(SECTION, 'METER_W', tostring(meter_width), true)

  reaper.SetExtState(SECTION, 'MAX_LAYERS', tostring(MAX_LAYERS), true)
  reaper.SetExtState(SECTION, 'CURRENT_LAYER', tostring(current_layer), true)
  
  for i = 1, #layers do
    local l = layers[i]
    local str = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d",
        l.vol and 1 or 0, l.lis and 1 or 0, l.corr and 1 or 0,
        l.ref and 1 or 0, l.ab and 1 or 0, l.item_count and 1 or 0, l.monfx and 1 or 0, l.grid and 1 or 0, l.mtr and 1 or 0)
    reaper.SetExtState(SECTION, "LAYER_"..i, str, true)
  end
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
  USE_ITEM_COUNT = get_bool('USE_ITEM_COUNT', true)
  USE_MONFX = get_bool('USE_MONFX', true)
  USE_GRID_BOX = get_bool('USE_GRID_BOX', true)

  REF_FOLDER_NAME = reaper.GetExtState(SECTION, 'REF_NAME')
  if REF_FOLDER_NAME == '' then REF_FOLDER_NAME = 'Refs' end

  SLOPE = tonumber(reaper.GetExtState(SECTION, 'SLOPE')) or 2
  scroll_accuracy = tonumber(reaper.GetExtState(SECTION, 'SCROLL')) or 1.2
  button_h = tonumber(reaper.GetExtState(SECTION, 'BTN_H')) or 24
  grid_width = tonumber(reaper.GetExtState(SECTION, 'GRID_W')) or 60
  ROW_TAIL_GAP = tonumber(reaper.GetExtState(SECTION, 'TAIL_GAP')) or 1
  meter_width = tonumber(reaper.GetExtState(SECTION, 'METER_W')) or 70
  DISABLE_CORR_ON_START = get_bool('DISABLE_CORR_ON_START', false)
  FREE_MODE_TOP = get_bool('FREE_MODE_TOP', false)

  local saved_buttons = reaper.GetExtState(SECTION, 'BUTTONS_LIST')
  if saved_buttons ~= "" then
    buttons = StringToButtons(saved_buttons)
    buttons_text = saved_buttons
  else
    buttons = {-32, -24, -14, -8, -4, 0, 4, 12, 18} -- дефолт
  end

  mon_fx_presets = {}
  local saved_mfx = reaper.GetExtState(SECTION, 'MON_FX_PRESETS')
  for entry in saved_mfx:gmatch('[^;]+') do
    local fx, nm, w, cl = entry:match('^(.-)|(.-)|(.-)|(.+)$')
    if not fx then fx, nm, w = entry:match('^(.-)|(.-)|(.+)$') end
    if fx then
      local cu32
      if cl and cl ~= '' then
        cu32 = tonumber(cl, 16)
        if #cl == 6 then cu32 = cu32 * 256 + 255 end
      end
      mon_fx_presets[#mon_fx_presets + 1] =
        { fx = fx, name = nm, w = tonumber(w) or 20, col_u32 = cu32 or 0x6CAEEBFF }
    end
  end

  local saved_pw = tonumber(reaper.GetExtState(SECTION, 'pw'))
  if saved_pw then pw = saved_pw end

  for i = 1, #layers do
    local str = reaper.GetExtState(SECTION, "LAYER_"..i)
    if str ~= "" then
        local v, li, c, r, a, ic, mf, gr, mt = str:match("(%d),(%d),(%d),(%d),(%d),(%d),(%d),?(%d?),?(%d?)")
        if v then
          local l = { vol = v=='1', lis = li=='1', corr = c=='1', ref = r=='1', ab = a=='1',
                      item_count = ic=='1', monfx = mf=='1', grid = layers[i].grid, mtr = layers[i].mtr }
          if gr ~= '' then l.grid = gr=='1' end
          if mt ~= '' and mt ~= nil then l.mtr = mt=='1' end
          layers[i] = l
        end
    end
  end
end

LoadSettings()

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

function count_playing_items_in_lanes(track)
    local items = reaper.CountTrackMediaItems(track)
    num = 0
    not_playing_num = 0
    for i=0,items-1 do 
        local item = reaper.GetTrackMediaItem(track, i)
        is_mute = reaper.GetMediaItemInfo_Value(item, 'B_MUTE') == 1
        local lane_plays = reaper.GetMediaItemInfo_Value(item, 'C_LANEPLAYS') > 0 
        if not is_mute then 
            if lane_plays then num = num + 1 else not_playing_num = not_playing_num + 1 end
        else not_playing_num = not_playing_num + 1 end
    end
    return num, not_playing_num
end 

function count_child_playing_items(track)
    local is_folder = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')==1
    local num = 0
    local not_playing_num = 0
    if is_folder then 
        local children = get_children(track)
        for c=1,#children do 
            local child = children[c]
            if not reaper.IsTrackSelected(child) then 
                child_playing, child_not_playing = count_playing_items_in_lanes(child)
                num = num + child_playing
                not_playing_num = not_playing_num + child_not_playing
            end
        end 
    end
    return num, not_playing_num
end

function get_children(parent)
  if parent then 
    local parentdepth = reaper.GetTrackDepth(parent)
    local parentnumber = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
    local children = {}
    for i=parentnumber, reaper.CountTracks(0)-1 do
      local track = reaper.GetTrack(0,i)
      local depth = reaper.GetTrackDepth(track)
      if depth > parentdepth then table.insert(children, track) else break end
    end
    return children
  end
end

------------------------------------------------------------------------------------
-- Grid Box module (logic ported from FeedTheCat's Gridbox / Adaptive Grid, MIT)

GRID_EXT = 'FTC.AdaptiveGrid'

local _, grid_script_path = reaper.get_action_context()
local grid_dir = grid_script_path:match('^(.+)[\\/]')
local function gpath(...)
  return table.concat({...}, package.config:sub(1, 1))
end
local grid_adapt_script = gpath(grid_dir, '..', '..', 'FTC Tools', 'Adaptive grid', 'Adapt grid to zoom level.lua')
local grid_service_script = gpath(grid_dir, '..', '..', 'FTC Tools', 'Adaptive grid', 'Adaptive grid (background service).lua')
local grid_has_adaptive = reaper.file_exists(grid_adapt_script) and reaper.file_exists(grid_service_script)

grid_text = '1/4'
grid_hovered = false

local function GridGetMultiplier(is_midi)
  return tonumber(reaper.GetExtState(GRID_EXT, is_midi and 'midi_mult' or 'main_mult')) or 0
end

local function GridSetMultiplier(mult, is_midi)
  reaper.SetExtState(GRID_EXT, is_midi and 'midi_mult' or 'main_mult', tostring(mult), true)
end

local function GridServiceRunning()
  return reaper.GetExtState(GRID_EXT, 'is_service_running') ~= ''
end

local function GridRunAdapt(is_midi)
  if is_midi and not reaper.MIDIEditor_GetActive() then return end
  local env = setmetatable({ _G = { mode = is_midi and 2 or 1 } }, { __index = _G })
  local chunk = loadfile(grid_adapt_script, 'bt', env)
  if chunk then chunk() end
end

local function GridStartService()
  if not reaper.file_exists(grid_service_script) then return end
  local cmd = reaper.AddRemoveReaScript(true, 0, grid_service_script, true)
  reaper.Main_OnCommand(cmd, 0)
  reaper.AddRemoveReaScript(false, 0, grid_service_script, true)
end

local function DecimalToFraction(x, error)
  error = error or 0.0000000001
  local n = math.floor(x)
  x = x - n
  if x < error then return n, 1 end
  if 1 - error < x then return n + 1, 1 end
  local lower_n, lower_d = 0, 1
  local upper_n, upper_d = 1, 1
  while true do
    local middle_n = lower_n + upper_n
    local middle_d = lower_d + upper_d
    if middle_d * (x + error) < middle_n then
      upper_n, upper_d = middle_n, middle_d
    elseif middle_n < (x - error) * middle_d then
      lower_n, lower_d = middle_n, middle_d
    else
      return n * middle_d + middle_n, middle_d
    end
  end
end

local function curr_grid_div() return select(2, reaper.GetSetProjectGrid(0, 0)) end

local function IsStraightGrid(d)
  d = d or curr_grid_div()
  return math.log(d, 2) % 1 == 0
end

local function IsTripletGrid(d)
  d = d or curr_grid_div()
  if d > 1 then return 2 * d % (2 / 3) == 0 else return 2 / d % 3 == 0 end
end

local function IsQuintupletGrid(d)
  d = d or curr_grid_div()
  if d > 1 then return 4 * d % (4 / 5) == 0 else return 4 / d % 5 == 0 end
end

local function IsSeptupletGrid(d)
  d = d or curr_grid_div()
  if d > 1 then return 4 * d % (4 / 7) == 0 else return 4 / d % 7 == 0 end
end

local function IsDottedGrid(d)
  d = d or curr_grid_div()
  if d > 1 then return 2 * d % 3 == 0 else return 2 / d % (2 / 3) == 0 end
end

local function ClosestStraightGrid(d)
  d = d or curr_grid_div()
  return 2 ^ math.floor(math.log(d, 2) + 0.5)
end

local function StraightenDiv(d)
  if IsStraightGrid(d) then return d end
  if IsTripletGrid(d) then return d * (3 / 2) end
  if IsQuintupletGrid(d) then return d * (5 / 4) end
  if IsSeptupletGrid(d) then return d * (7 / 4) end
  if IsDottedGrid(d) then return d * (2 / 3) end
  return ClosestStraightGrid(d)
end

local function SaveProjGridType(d, swing, amt)
  if reaper.GetExtState(GRID_EXT, 'preserve_grid_type') ~= '1' then return end
  local sd = StraightenDiv(d)
  if not sd then return end
  local state = ''
  if swing == 1 and amt then state = 's' .. amt
  elseif sd ~= d then state = ('%.32f'):format(d) end
  reaper.SetProjExtState(0, GRID_EXT, sd, state)
end

local function LoadProjGridType(d)
  if reaper.GetExtState(GRID_EXT, 'preserve_grid_type') ~= '1' then return false end
  local sd = StraightenDiv(d)
  if not sd then return false end
  local _, state = reaper.GetProjExtState(0, GRID_EXT, sd)
  local swing, amt = 0, nil
  d = sd
  if state ~= '' then
    if state:sub(1, 1) == 's' then
      swing, amt = 1, tonumber(state:sub(2))
    else
      d = tonumber(state)
    end
  end
  reaper.GetSetProjectGrid(0, 1, d, swing, amt)
  return true
end

local function GridSetStraight()
  local _, d, _, amt = reaper.GetSetProjectGrid(0, 0)
  if not IsStraightGrid(d) then
    d = StraightenDiv(d)
    reaper.GetSetProjectGrid(0, 1, d, 0, amt)
    SaveProjGridType(d, 0, amt)
  end
end

local function GridSetKind(target)
  local _, d, _, amt = reaper.GetSetProjectGrid(0, 0)
  local cur_t, cur_q = IsTripletGrid(d), IsQuintupletGrid(d)
  local cur_s, cur_do = IsSeptupletGrid(d), IsDottedGrid(d)
  local has = ({ triplet = cur_t, quint = cur_q, sept = cur_s, dotted = cur_do })[target]
  if has then return end
  local f = ({ triplet = 2 / 3, quint = 4 / 5, sept = 4 / 7, dotted = 3 / 2 })[target]
  if cur_t then d = d * (3 / 2) * f
  elseif cur_q then d = d * (5 / 4) * f
  elseif cur_s then d = d * (7 / 4) * f
  elseif cur_do then d = d * (2 / 3) * f
  else d = ClosestStraightGrid(d) * f end
  reaper.GetSetProjectGrid(0, 1, d, 0, amt)
  SaveProjGridType(d, 0, amt)
end

local function GridSwingEnabled()
  local _, _, s, a = reaper.GetSetProjectGrid(0, 0)
  return s == 1 and (a or 0) ~= 0
end

local function GridSetSwing(on)
  local _, d, _, a = reaper.GetSetProjectGrid(0, 0)
  reaper.GetSetProjectGrid(0, 1, d, on and 1 or 0, a)
  SaveProjGridType(d, on and 1 or 0, a)
end

local function GridSetSwingAmount(pct)
  GridSetStraight()
  local _, d = reaper.GetSetProjectGrid(0, 0)
  reaper.GetSetProjectGrid(0, 1, nil, 1, pct / 100)
  SaveProjGridType(d, 1, pct / 100)
end

local function GridSetFixed(div)
  if reaper.GetToggleCommandState(41885) == 1 then reaper.Main_OnCommand(41885, 0) end
  if reaper.GetToggleCommandState(40725) == 1 then reaper.Main_OnCommand(40725, 0) end
  if reaper.GetToggleCommandState(40145) == 0 then reaper.Main_OnCommand(40145, 0) end
  GridSetMultiplier(0, false)
  if LoadProjGridType(div) then return end
  local _, d, s, a = reaper.GetSetProjectGrid(0, 0)
  if IsTripletGrid(d) then div = div * 2 / 3 end
  if IsQuintupletGrid(d) then div = div * 4 / 5 end
  if IsSeptupletGrid(d) then div = div * 4 / 7 end
  if IsDottedGrid(d) then div = div * 3 / 2 end
  reaper.GetSetProjectGrid(0, 1, div, s, a)
end

local function GridCheckFixed(div)
  if reaper.GetToggleCommandState(41885) == 1 or reaper.GetToggleCommandState(40725) == 1 then return false end
  if reaper.GetToggleCommandState(40145) == 0 or GridGetMultiplier(false) ~= 0 then return false end
  local _, d = reaper.GetSetProjectGrid(0, 0)
  if IsTripletGrid(d) then div = div * 2 / 3 end
  if IsQuintupletGrid(d) then div = div * 4 / 5 end
  if IsSeptupletGrid(d) then div = div * 4 / 7 end
  if IsDottedGrid(d) then div = div * 3 / 2 end
  return div == d
end

local function GridPromptSpacing(is_midi)
  local key = is_midi and 'midi_custom_spacing' or 'custom_spacing'
  local cur = reaper.GetExtState(GRID_EXT, key)
  local ret, val = reaper.GetUserInputs('Adaptive Grid', 1, 'Minimum grid spacing in pixels:', cur)
  if not ret then return false end
  val = tonumber(val)
  if not val or val <= 0 then return false end
  reaper.SetExtState(GRID_EXT, key, tostring(val), true)
  return true
end

local function GridSetAdaptive(mult, is_midi)
  if mult == -1 and not GridPromptSpacing(is_midi) then return end
  if GridGetMultiplier(is_midi) == mult then mult = 0 end
  if not is_midi then
    if reaper.GetToggleCommandState(41885) == 1 then reaper.Main_OnCommand(41885, 0) end
    if reaper.GetToggleCommandState(40725) == 1 then reaper.Main_OnCommand(40725, 0) end
    if reaper.GetToggleCommandState(40145) == 0 then reaper.Main_OnCommand(40145, 0) end
  else
    local ed = reaper.MIDIEditor_GetActive()
    if ed and reaper.GetToggleCommandStateEx(32060, 1017) == 0 then
      reaper.MIDIEditor_OnCommand(ed, 1017)
    end
  end
  GridSetMultiplier(mult, is_midi)
  if mult ~= 0 then
    GridRunAdapt(is_midi)
    if not GridServiceRunning() then GridStartService() end
  end
end

local function GridChangeDivision(wph)
  local factor = tonumber(reaper.GetExtState(GRID_EXT, 'zoom_div')) or 2
  local _, d, s, a = reaper.GetSetProjectGrid(0, 0)
  if d ~= d then d = 1 end
  SaveProjGridType(d, s, a)
  d = wph < 0 and d * factor or d / factor
  if d > 8 then d = 8 elseif d < 1 / 32 then d = 1 / 32 end
  if not LoadProjGridType(d) then
    reaper.GetSetProjectGrid(0, 1, d, s, a)
  end
end

local function GridAdjustSwing(wph)
  local _, d, s, a = reaper.GetSetProjectGrid(0, 0)
  if s == 0 then
    GridSetStraight()
    s, a = 1, 0.5
  end
  a = a + wph * 0.02
  if a <= 0.005 then s, a = 0, 0
  elseif a > 1 then a = 1 end
  a = math.floor(a * 100 + 0.5) / 100
  reaper.GetSetProjectGrid(0, 1, nil, s, a)
  SaveProjGridType(d, s, a)
end

local function GridUpdateText()
  local _, d, s = reaper.GetSetProjectGrid(0, 0)
  if d ~= d then d = 1 end
  local t
  if reaper.GetToggleCommandState(40904) == 1 then
    t = 'Frame'
  elseif s == 3 then
    t = 'Meas'
  else
    local num, denom = DecimalToFraction(d)
    local suf = ''
    local is_t, is_q, is_s, is_do
    if d > 1 then
      is_t = 2 * d % (2 / 3) == 0
      is_q = 4 * d % (4 / 5) == 0
      is_s = 4 * d % (4 / 7) == 0
      is_do = 2 * d % 3 == 0
    else
      is_t = 2 / d % 3 == 0
      is_q = 4 / d % 5 == 0
      is_s = 4 / d % 7 == 0
      is_do = 2 / d % (2 / 3) == 0
    end
    if is_t then suf = 'T'; denom = denom * 2 / 3
    elseif is_q then suf = 'Q'; denom = denom * 4 / 5
    elseif is_s then suf = 'S'; denom = denom * 4 / 7
    elseif is_do then suf = 'D'; denom = denom / 2; num = num / 3 end
    if num > 1 then
      local rest = denom % num
      if rest == 0 then denom = denom / num; num = 1 end
    end
    if num >= denom and num % denom == 0 then
      t = ('%.0f%s'):format(num / denom, suf)
    else
      t = ('%.0f/%.0f%s'):format(num, denom, suf)
    end
  end
  grid_text = t
end

local b_col   = rgba(82, 81, 77, 0.7)
local bh_col  = rgba(88, 73, 55, 0.9)
local ba_col  = rgba(192, 157, 13, 0.4)
local t_col   = rgba(205, 175, 50, 1)

function draw_grid_button()
  GridUpdateText()
  local snap =  reaper.GetToggleCommandState(1157) == 1

  local label = grid_text
  if GridGetMultiplier(false) ~= 0 then label = 'A ' .. label end
  if grid_hovered then
    local _, _, s, a = reaper.GetSetProjectGrid(0, 0)
    if s == 1 and (a or 0) ~= 0 then
      label = ('sw %d%%'):format(math.floor(a * 100 + 0.5))
    end
  end

  if not snap then 
    b_col   = rgba(82, 81, 77, 0.7)
    bh_col  = rgba(88, 73, 55, 0.9)
    ba_col  = rgba(98, 83, 65, 1)
    t_col   = rgba(215, 185, 60, 1)
  else 
    b_col   = rgba(38, 117, 149, 0.4)
    bh_col  = rgba(38, 117, 149, 0.6)
    ba_col  = rgba(192, 157, 13, 0.4)
    t_col   = rgba(106, 198, 235, 1)
  end
  ImGui.PushStyleColor(ctx, ImGui.Col_Button(),        b_col)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), bh_col)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),  ba_col)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text(),          t_col)

  -- reaper.ImGui_PushFont(ctx, font, 12)

  
  -- reaper.ImGui_PushStyleVar( ctx, reaper.ImGui_StyleVar_FramePadding(), 0, 5)
  -- reaper.ImGui_AlignTextToFramePadding( ctx )

  ImGui.Button(ctx, label .. '##grid', grid_width, button_h)
  -- reaper.ImGui_PopFont( ctx )
  -- reaper.ImGui_PopStyleVar( ctx )


  if ImGui.IsItemClicked(ctx, 1) then
    ImGui.OpenPopup(ctx, 'grid_settings_menu')
  end
  -- if ImGui.IsItemClicked(ctx, 0) then
  --   reaper.Main_OnCommand(1157, 0)
  -- end
  ImGui.PopStyleColor(ctx, 4)

  -- if snap then
  --   local min_x, min_y = ImGui.GetItemRectMin(ctx)
  --   local max_x, max_y = ImGui.GetItemRectMax(ctx)
  --   local draw_list = ImGui.GetWindowDrawList(ctx)
  --   ImGui.DrawList_AddRect(draw_list, min_x, min_y, max_x, max_y, rgba(38,176,167,1), 0, 0, 1)
  -- end

  grid_hovered = reaper.ImGui_IsItemHovered(ctx)

  if grid_hovered and not ImGui.IsPopupOpen(ctx, 'grid_settings_menu') then
    local vertical, horizontal = reaper.ImGui_GetMouseWheel(ctx)
    if vertical ~= 0 then GridChangeDivision(vertical) end
    if horizontal ~= 0 then GridAdjustSwing(horizontal) end
  end

  if reaper.ImGui_IsMouseClicked( ctx, reaper.ImGui_MouseButton_Left() ) and grid_hovered then 
      reaper.Main_OnCommand(1157, 0)
  end


  if ImGui.BeginPopup(ctx, 'grid_settings_menu') then
    local _, d, s, a = reaper.GetSetProjectGrid(0, 0)

    local type_w = 60
    local types = {
      { 'Straight', IsStraightGrid(d), GridSetStraight },
      { 'Triplet',  IsTripletGrid(d),  function() GridSetKind('triplet') end },
      { 'Dotted',   IsDottedGrid(d),   function() GridSetKind('dotted') end },
    }
    for ti, t in ipairs(types) do
      if t[2] then
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(195,105,105,0.6))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(205,105,105,0.8))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(205,105,105,1))
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(),           rgba(224,224,224,1))
      else
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(100,100,100,0.5))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(120,120,120,0.6))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(140,140,140,0.7))
      end
      if ImGui.Button(ctx, t[1], type_w) then t[3]() end
      ImGui.PopStyleColor(ctx, t[2] and 4 or 3)
      if ti < #types then ImGui.SameLine(ctx) end
    end
    ImGui.Separator(ctx)

    if ImGui.BeginMenu(ctx, 'Swing') then
      local swing_on = s == 1 and (a or 0) ~= 0
      if ImGui.Selectable(ctx, 'Off', not swing_on) then GridSetSwing(false) end
      ImGui.Separator(ctx)
      for _, pct in ipairs({53, 55, 57, 59, 61, 64, 67, 70, 73, 75}) do
        if ImGui.Selectable(ctx, pct .. '%', swing_on and math.floor(a * 100 + 0.5) == pct) then
          GridSetSwingAmount(pct)
        end
      end
      ImGui.Separator(ctx)
      if ImGui.Selectable(ctx, 'Other...') then
        local ret, val = reaper.GetUserInputs('Set swing', 1, 'Amount: (-100% to 100%)', '')
        val = ret and tonumber(val) or nil
        if val and val >= -100 and val <= 100 and val ~= 0 then GridSetSwingAmount(val) end
      end
      ImGui.EndMenu(ctx)
    end

    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, 'Fixed')
    for _, f in ipairs({
      {'1/128', 0.0078125}, {'1/64', 0.015625}, {'1/32', 0.03125},
      {'1/16', 0.0625}, {'1/8', 0.125}, {'1/4', 0.25}, {'1/2', 0.5},
      {'1', 1}, {'2', 2}, {'4', 4},
    }) do
      if ImGui.Selectable(ctx, f[1], GridCheckFixed(f[2])) then GridSetFixed(f[2]) end
    end

    if grid_has_adaptive then
      ImGui.Separator(ctx)
      ImGui.TextDisabled(ctx, 'Adaptive')
      for _, m in ipairs({{'Narrowest', 1}, {'Narrow', 2}, {'Medium', 3}, {'Wide', 4}, {'Widest', 6}}) do
        if ImGui.Selectable(ctx, m[1], GridGetMultiplier(false) == m[2]) then
          GridSetAdaptive(m[2], false)
        end
      end
      if ImGui.Selectable(ctx, 'Custom', GridGetMultiplier(false) == -1) then
        GridSetAdaptive(-1, false)
      end

      if ImGui.BeginMenu(ctx, 'MIDI editor') then
        if ImGui.Selectable(ctx, 'Fixed', GridGetMultiplier(true) == 0) then
          GridSetAdaptive(0, true)
        end
        ImGui.Separator(ctx)
        for _, m in ipairs({{'Narrowest', 1}, {'Narrow', 2}, {'Medium', 3}, {'Wide', 4}, {'Widest', 6}}) do
          if ImGui.Selectable(ctx, m[1], GridGetMultiplier(true) == m[2]) then
            GridSetAdaptive(m[2], true)
          end
        end
        if ImGui.Selectable(ctx, 'Custom', GridGetMultiplier(true) == -1) then
          GridSetAdaptive(-1, true)
        end
        ImGui.EndMenu(ctx)
      end
    end

    ImGui.Separator(ctx)
    local preserve = reaper.GetExtState(GRID_EXT, 'preserve_grid_type') == '1'
    if ImGui.Selectable(ctx, 'Preserve grid type per size', preserve) then
      reaper.SetExtState(GRID_EXT, 'preserve_grid_type', preserve and '0' or '1', true)
    end

    ImGui.EndPopup(ctx)
  end

  
end

function toggle_monitor_fx(fxname)
  index = reaper.TrackFX_AddByName(master, fxname, true, 0)
  is_open = reaper.TrackFX_GetOpen(master, mon+index)
  reaper.TrackFX_Show(master, mon+index, is_open and 2 or 3)
  reaper.TrackFX_SetEnabled( master, mon+index, is_open and 0 or 1 )
  reaper.SetCursorContext(1,nil)
end 

function draw_item_count()
    local num3 = 0
    local num4 = 0
    local num1_lanes_found  = false
    local num2_lanes_found  = false
    local color = '28290987' 

    local count = reaper.CountSelectedTracks(0)
    if count > 0 then 
        local folder_found = false
        for i2=0,count-1 do 
            local track = reaper.GetSelectedTrack(0, i2)
            local other_playing, other_not_playing = count_playing_items_in_lanes(track)
            local other_child_playing, other_child_not_playing = count_child_playing_items(track)
            
            num3 = num3 + other_playing + other_child_playing
            num4 = num4 + other_not_playing + other_child_not_playing
        end
    end
    if num3 ~= '' then 
        dummy_spacing1 = 3  -- между группами
        reaper.ImGui_Dummy(ctx, dummy_spacing1, 1 )
        reaper.ImGui_SameLine(ctx)
    end 

    reaper.ImGui_TextColored(ctx, rgba(200, 200, 200, 1), num3)
    if 1 then 
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Dummy(ctx, 2, 1 )
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, rgba(120, 120, 120, 1), num4)
    end

    local num3_str = tostring(num3)
    local num4_str = tostring(num4)
    local width3, height3 = reaper.ImGui_CalcTextSize(ctx, num3_str)
    local width4, height4 = reaper.ImGui_CalcTextSize(ctx, num4_str)

    item_count_total_width = width3 + width4 + 15
    -- spacing_x * 2  -- запас между элементами
    -- -10           -- немного дополнительного отsступа

    return item_count_total_width

end 

function draw_volume_buttons(master,w)
  for i,b in ipairs(buttons) do
    -- local is_pdc = (i == pdc_button_idx)
    -- local is_active = (i == current_volume_idx)

    if state == b then s = 1 else s = 0 end
    ImGui.PushID(ctx, i)
    if s == 0 then
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(195,105,105,0.2))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(195,105,105,0.4))
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(),           rgba(240,240,240,1))
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(100,100,100,0.8))
    else
      -- if is_pdc then
      --   ImGui.PushStyleColor(ctx, ImGui.Col_Button(), rgba(200, 100, 255, 0.4)) -- PDC метка (Фиолетовая)
      -- else
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(),         rgba(195,105,105,0.6))
      -- end
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),   rgba(195,105,105,0.9))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(205,105,105,0.8))
        ImGui.PushStyleColor(ctx, ImGui.Col_Text(),           rgba(224,224,224,1))
    end
    b_button = ImGui.Button(ctx, tostring(b), w, button_h)
    
    if i < #buttons then ImGui.SameLine(ctx) end
    ImGui.PopID(ctx)
    ImGui.PopStyleColor(ctx, 4)
    
    if b_button then
      -- local modifiers = reaper.JS_Mouse_GetState(-1)
      -- if modifiers == 4 then -- CTRL + ЛКМ
      --   if pdc_button_idx == i then 
      --     pdc_button_idx = 0 -- Сброс PDC
      --   else 
      --     pdc_button_idx = i -- Установка PDC
      --   end
      --   reaper.SetExtState(SECTION, 'PDC_IDX', tostring(pdc_button_idx), true)
      -- else
        -- last_regular_idx = i
        -- current_volume_idx = i
        reaper.SetExtState(SECTION, 'LAST_REG_IDX', tostring(i), true)
        index = reaper.TrackFX_AddByName(master, controller_fx, true, 100)
        if reaper.TrackFX_GetOpen(master, index+(0x1000000)) then reaper.TrackFX_Show(master, index+(0x1000000), 0 ) end
        reaper.TrackFX_SetParam(master, index+(0x1000000), 4, b)
      -- end
    end

    -- if is_pdc then
    --   local min_x, min_y = ImGui.GetItemRectMin(ctx)
    --   local draw_list = ImGui.GetWindowDrawList(ctx)
    --   ImGui.DrawList_AddText(draw_list, min_x + 2, min_y + 2, rgba(255, 255, 255, 0.8), "PDC")
    -- end
    
      -- if reaper.ImGui_IsMouseClicked( ctx, reaper.ImGui_MouseButton_Right() ) and reaper.ImGui_IsItemHovered(ctx) then
      --   USE_LISTEN_BANDS = not USE_LISTEN_BANDS
      --   should_resize = true
      --   SaveSettings()
      -- end
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
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(211,161,85,0.8))
    ImGui.PushStyleColor(ctx, ImGui.Col_Button(), btn_color)
    if ImGui.Button(ctx, active_name .. "##corr_pop", w, button_h) then
        ImGui.OpenPopup(ctx, 'corr_popup_menu')
    end
    ImGui.PopStyleColor(ctx,2)

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
            disable_corrections()
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

function draw_free_mode_slider(master, w)
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

  reaper.ImGui_PushItemWidth(ctx, w or -1)
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

  if ab_hovered and ab_state == 1 then
    local wheel = reaper.ImGui_GetMouseWheel(ctx)
    if wheel ~= 0 then
      local index = reaper.TrackFX_AddByName(master, METRIC_AB, USE_METRIC_IN_MONITORINGFX, 0)
      if index ~= -1 then
        local mon = USE_METRIC_IN_MONITORINGFX and 0x1000000 or 0
        local val = reaper.TrackFX_GetParam(master, index + mon, 4)
        local cur = math.floor(val * 15 + 0.5)
        cur = cur + (wheel > 0 and 1 or -1)
        if cur < 0 then cur = 15 end
        if cur > 15 then cur = 0 end
        reaper.TrackFX_SetParam(master, index + mon, 4, cur / 15)
      end
    end
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

local function get_reference_tracks()
  local refs = {}
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local folder = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(folder)
    if name == REF_FOLDER_NAME then
      refs = get_children_refs(folder) or {}
      break
    end
  end
  return refs
end

local function is_any_ref_soloed()
  local refs = get_reference_tracks()
  for _, r in ipairs(refs) do
    if r.solo then return true end
  end
  return false
end

local function toggle_solo_last_reference()
  local refs = get_reference_tracks()
  if #refs == 0 then return end

  -- If any ref is currently soloed, restore the previous project solo state.
  if is_any_ref_soloed() then
    for _, ref in ipairs(refs) do
      if ref.solo then
        reaper.SetMediaTrackInfo_Value(ref.track, 'I_SOLO', 0)
      end
    end
    restore_solos()
    return
  end

  -- Find the last-used reference and solo it.
  local _, guid = reaper.GetProjExtState(0, 'MISHA_MONITOR', 'LAST_SOLO')
  for i, ref in ipairs(refs) do
    if guid ~= '' and reaper.GetTrackGUID(ref.track) == guid then
      save_solos()
      unsolo_all_tracks()
      reaper.SetMediaTrackInfo_Value(ref.track, 'I_SOLO', 2)
      save_last_ref_solo(reaper.GetTrackGUID(ref.track))
      return
    end
  end

  -- Fallback: solo the last ref in the folder.
  save_solos()
  unsolo_all_tracks()
  reaper.SetMediaTrackInfo_Value(refs[#refs].track, 'I_SOLO', 2)
  save_last_ref_solo(reaper.GetTrackGUID(refs[#refs].track))
end

local function solo_reference_at(index)
  local refs = get_reference_tracks()
  if #refs == 0 then return end
  index = ((index - 1) % #refs) + 1
  save_solos()
  unsolo_all_tracks()
  reaper.SetMediaTrackInfo_Value(refs[index].track, 'I_SOLO', 2)
  save_last_ref_solo(reaper.GetTrackGUID(refs[index].track))
end

local function solo_adjacent_reference(direction)
  local refs = get_reference_tracks()
  if #refs == 0 then return end
  local _, guid = reaper.GetProjExtState(0, 'MISHA_MONITOR', 'LAST_SOLO')
  local current = 0
  for i, ref in ipairs(refs) do
    if guid ~= '' and reaper.GetTrackGUID(ref.track) == guid then current = i; break end
  end
  if current == 0 then current = direction > 0 and #refs or 1 end
  solo_reference_at(current + direction)
end

function draw_refs_button(w)
  if not USE_REFS_SWITCH then return end

  -- Use live track state, not the potentially stale global ref_data.
  local any_solo = is_any_ref_soloed()

  if any_solo then 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), rgba(112, 229, 150, 0.6)) 
  end

  if reaper.ImGui_Button(ctx, "REF", w, button_h) then
    toggle_solo_last_reference()
  end
  

  local hovered = reaper.ImGui_IsItemHovered(ctx)
  if hovered and reaper.ImGui_IsMouseClicked(ctx, reaper.ImGui_MouseButton_Right()) then
    ImGui.OpenPopup(ctx, 'ref_list_popup')
  end
  ref_data = get_reference_tracks()
  -- Calculate popup width from the longest ref name.
  local popup_w = 150
  if ref_data then
    for _, ref in ipairs(ref_data) do
      local tw, _ = reaper.ImGui_CalcTextSize(ctx, ref.name)
      if tw + 40 > popup_w then popup_w = tw + 40 end
    end
  end
  reaper.ImGui_SetNextWindowSize(ctx, popup_w, 0, reaper.ImGui_Cond_Always())
  if ImGui.BeginPopup(ctx, 'ref_list_popup') then
    if ref_data and #ref_data > 0 then
      for k, ref in ipairs(ref_data) do
        ImGui.PushID(ctx, k)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(),        col(ref.color, 0.3))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), col(ref.color, 0.5))
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),  col(ref.color, 0.6))
        if ImGui.Button(ctx, ref.name .. "##btn", popup_w - 10, 26) then
          if ref.solo then
            for _, r in ipairs(ref_data) do
              if r.solo then reaper.SetMediaTrackInfo_Value(r.track, 'I_SOLO', 0) end
            end
            restore_solos()
          else
            save_last_ref_solo(reaper.GetTrackGUID(ref.track))
            save_solos()
            unsolo_all_tracks()
            reaper.SetMediaTrackInfo_Value(ref.track, 'I_SOLO', 2)
          end
        end
        if ref.solo then
          local min_x, min_y = ImGui.GetItemRectMin(ctx)
          local dl = ImGui.GetWindowDrawList(ctx)
          ImGui.DrawList_AddCircleFilled(dl, min_x + 10, min_y + 13, 3, rgba(229, 201, 112, 1))
        end
        ImGui.PopStyleColor(ctx, 3)
        ImGui.PopID(ctx)
      end
    else
      ImGui.Text(ctx, "Ref folder not found or empty")
    end
    ImGui.EndPopup(ctx)
  end
  if hovered then
    local wheel = reaper.ImGui_GetMouseWheel(ctx)
    if wheel > 0 then solo_adjacent_reference(1)
    elseif wheel < 0 then solo_adjacent_reference(-1) end
  end

  if any_solo then reaper.ImGui_PopStyleColor(ctx) end
end

function disable_corrections()
  local fx_container = reaper.TrackFX_AddByName(master, CORRECTION_CONTAINER_NAME, true, 0)
  if fx_container ~= -1 then
    local _, count = reaper.TrackFX_GetNamedConfigParm(master, fx_container+(0x1000000), "container_count")
    for i = 0, tonumber(count or 0)-1 do
      local _, item = reaper.TrackFX_GetNamedConfigParm(master, fx_container+(0x1000000), "container_item."..i)
      reaper.TrackFX_SetEnabled(master, item, false)
    end
  end
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
    
    if reaper.ImGui_BeginTable(ctx, "LayersTable", 3, reaper.ImGui_TableFlags_BordersInnerV()) then

      -- for i = 1, MAX_LAYERS do
      --     reaper.ImGui_TableSetupColumn(ctx, "Layer " .. i)
      -- end

      -- local row_keys = {"vol", "lis", "corr", "ref", "ab"}
      -- local row_names = {"Volume", "Listen", "Corr", "Ref", "MetricAB"}

      -- for r = 1, #row_keys do
      --   reaper.ImGui_TableNextRow(ctx)
      --   for i = 1, MAX_LAYERS do
      --       reaper.ImGui_TableSetColumnIndex(ctx, i-1)
            
      --       -- Подсветка активной колонки
      --       if current_layer == i then
      --           local c = layer_colors[i]
      --           if i == current_layer then a = 0.4 else a = 0.2 end
      --           reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
      --       end

      --       local l = layers[i]
      --       if reaper.ImGui_Checkbox(ctx, row_names[r].."##"..i, l[row_keys[r]]) then 
      --           l[row_keys[r]] = not l[row_keys[r]]
      --           should_resize = true
      --           SaveSettings() 
      --       end
      --   end
      -- end
      -- reaper.ImGui_TableSetupColumn(ctx, "Blocks")

      reaper.ImGui_TableSetupColumn(ctx, "Layer 1" .. (current_layer == 1 and " [Active]" or ""))
      reaper.ImGui_TableSetupColumn(ctx, "Layer 2" .. (current_layer == 2 and " [Active]" or "") .. (MAX_LAYERS == 1 and " [OFF]" or ""))
      reaper.ImGui_TableSetupColumn(ctx, "Layer 3" .. (current_layer == 3 and " [Active]" or "") .. (MAX_LAYERS <= 2 and " [OFF]" or ""))
      reaper.ImGui_TableHeadersRow(ctx)
      -- 1-я строка: Volume
      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #layers do
        reaper.ImGui_TableSetColumnIndex(ctx, i-1)
        local c = layer_colors[i]
        local l = layers[i]
        if i == current_layer then a = 0.4 else a = 0.2 end
        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
        if reaper.ImGui_Checkbox(ctx, "Volume##"..i, l.vol) then l.vol = not l.vol; should_resize = true; SaveSettings() end
      end
      
      -- 2-я строка: Listen
      reaper.ImGui_TableNextRow(ctx)
      
      for i = 1, #layers do
        reaper.ImGui_TableSetColumnIndex(ctx, i-1)
        local c = layer_colors[i]
        local l = layers[i]
        if i == current_layer then a = 0.4 else a = 0.2 end
        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
        if reaper.ImGui_Checkbox(ctx, "Listen Bands##"..i, l.lis) then l.lis = not l.lis; should_resize = true; SaveSettings() end
      end

      -- 3-я строка: Correction
      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #layers do
        reaper.ImGui_TableSetColumnIndex(ctx, i-1)
        local c = layer_colors[i]
        local l = layers[i]
        if i == current_layer then a = 0.4 else a = 0.2 end
        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
        if reaper.ImGui_Checkbox(ctx, "Corrections##"..i, l.corr) then l.corr = not l.corr; should_resize = true; SaveSettings() end
      end

      -- 4-я строка: Reference
      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #layers do
        reaper.ImGui_TableSetColumnIndex(ctx, i-1)
        local c = layer_colors[i]
        local l = layers[i]
        if i == current_layer then a = 0.4 else a = 0.2 end
        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
        if reaper.ImGui_Checkbox(ctx, "Refs##"..i, l.ref) then l.ref = not l.ref; should_resize = true; SaveSettings() end
      end

      -- 5-я строка: Metric AB
      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #layers do
        reaper.ImGui_TableSetColumnIndex(ctx, i-1)
        local c = layer_colors[i]
        local l = layers[i]
        if i == current_layer then a = 0.4 else a = 0.2 end
        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
        if reaper.ImGui_Checkbox(ctx, "AB from Metric##"..i, l.ab) then l.ab = not l.ab; should_resize = true; SaveSettings() end
      end

      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #layers do
        reaper.ImGui_TableSetColumnIndex(ctx, i-1)
        local c = layer_colors[i]
        local l = layers[i]
        if i == current_layer then a = 0.4 else a = 0.2 end
        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
        if reaper.ImGui_Checkbox(ctx, "Item Count##"..i, l.item_count) then l.item_count = not l.item_count; should_resize = true; SaveSettings() end
      end

      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #layers do
        reaper.ImGui_TableSetColumnIndex(ctx, i-1)
        local c = layer_colors[i]
        local l = layers[i]
        if i == current_layer then a = 0.4 else a = 0.2 end
        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
        if reaper.ImGui_Checkbox(ctx, "Grid Box##"..i, l.grid) then l.grid = not l.grid; should_resize = true; SaveSettings() end
      end

      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #layers do
        reaper.ImGui_TableSetColumnIndex(ctx, i-1)
        local c = layer_colors[i]
        local l = layers[i]
        if i == current_layer then a = 0.4 else a = 0.2 end
        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
        if reaper.ImGui_Checkbox(ctx, "Meter##"..i, l.mtr) then l.mtr = not l.mtr; should_resize = true; SaveSettings() end
      end

      reaper.ImGui_TableNextRow(ctx)
      for i = 1, #layers do
        reaper.ImGui_TableSetColumnIndex(ctx, i-1)
        local c = layer_colors[i]
        local l = layers[i]
        if i == current_layer then a = 0.4 else a = 0.2 end
        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), rgba(c.r,c.g,c.b,a))
        if reaper.ImGui_Checkbox(ctx, "Monitoring FX##"..i, l.monfx) then l.monfx = not l.monfx; should_resize = true; SaveSettings() end
      end

      reaper.ImGui_EndTable(ctx)
    end

    reaper.ImGui_Separator(ctx)

    -- local function Toggle(label, var_name)
    --     local current_val = _G[var_name] 
    --     local changed, new_val = reaper.ImGui_Checkbox(ctx, label, current_val)
    --     if changed then
    --         _G[var_name] = new_val
    --         should_resize = true
    --         SaveSettings()
    --     end
    -- end

    -- Toggle("Volume Buttons", "USE_VOLUME_BUTTONS")
    -- Toggle("Listen Bands",   "USE_LISTEN_BANDS")
    -- Toggle("Corrections", "SHOW_CORRECTION_BTN")
    -- Toggle("Metric AB",      "USE_METRICAB_SWITCH")
    -- Toggle("References",   "USE_REFS_SWITCH")

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_TreeNode(ctx, "Advanced Settings") then
      reaper.ImGui_Spacing(ctx)

      local rv_ml, new_ml = reaper.ImGui_SliderInt(ctx, "Active Layers", MAX_LAYERS, 1, 3)
      if rv_ml then 
          MAX_LAYERS = new_ml 
          if current_layer > MAX_LAYERS then current_layer = 1 end
          should_resize = false
          SaveSettings() 
      end

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

      reaper.ImGui_Dummy(ctx,20,20)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Text(ctx, "Monitoring FX buttons")
      if reaper.ImGui_BeginTable(ctx, "MonFxPresets", 5, reaper.ImGui_TableFlags_BordersInnerV() + reaper.ImGui_TableFlags_RowBg()) then
        reaper.ImGui_TableSetupColumn(ctx, "Plugin name")
        reaper.ImGui_TableSetupColumn(ctx, "Button name")
        reaper.ImGui_TableSetupColumn(ctx, "Width", reaper.ImGui_TableColumnFlags_WidthFixed(), 100)
        reaper.ImGui_TableSetupColumn(ctx, "Color", reaper.ImGui_TableColumnFlags_WidthFixed(), 36)
        reaper.ImGui_TableSetupColumn(ctx, "", reaper.ImGui_TableColumnFlags_WidthFixed(), 26)
        reaper.ImGui_TableHeadersRow(ctx)

        for i, p in ipairs(mon_fx_presets) do
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_PushID(ctx, "mfx" .. i)
          reaper.ImGui_SetNextItemWidth( ctx, -1 )

          reaper.ImGui_TableSetColumnIndex(ctx, 0)
          local ch_fx, v_fx = reaper.ImGui_InputText(ctx, "##mfx_fx", p.fx)
          p.fx = ch_fx and v_fx or p.fx

          reaper.ImGui_TableSetColumnIndex(ctx, 1)
          reaper.ImGui_SetNextItemWidth( ctx, -1 )
          local ch_nm, v_nm = reaper.ImGui_InputText(ctx, "##mfx_name", p.name)
          p.name = ch_nm and v_nm or p.name

          reaper.ImGui_TableSetColumnIndex(ctx, 2)
          reaper.ImGui_SetNextItemWidth( ctx, 100 )

          local ch_w, v_w = reaper.ImGui_InputInt(ctx, "##mfx_w", tonumber(p.w) or 24)
          p.w = ch_w and v_w or p.w

          reaper.ImGui_TableSetColumnIndex(ctx, 3)
          local ch_c, new_col = reaper.ImGui_ColorEdit4(ctx, '##mfx_col',
            p.col_u32 or 0x6CAEEBFF,
            reaper.ImGui_ColorEditFlags_NoInputs() + reaper.ImGui_ColorEditFlags_NoAlpha())
          if ch_c then p.col_u32 = new_col end

          reaper.ImGui_TableSetColumnIndex(ctx, 4)
          if reaper.ImGui_Button(ctx, "-", -1, 0) then
            table.remove(mon_fx_presets, i)
            SaveSettings()
          end

          reaper.ImGui_PopID(ctx)
        end
        reaper.ImGui_EndTable(ctx)
      end
      if reaper.ImGui_Button(ctx, "+ Add") then
        mon_fx_presets[#mon_fx_presets + 1] = { fx = '', name = '', w = 20, col_u32 = 0xB37474FF }
        SaveSettings()
      end
      reaper.ImGui_Dummy(ctx,20,20)


      reaper.ImGui_PushItemWidth(ctx, 120)
      local slopes_txt = {"12dB", "24dB", "36dB", "48dB", "60dB", "72dB"}
      local rv_sl, new_sl = reaper.ImGui_SliderInt(ctx, "Listen Filter Slope", SLOPE, 1, 6, slopes_txt[SLOPE])
      if rv_sl then
        SLOPE = new_sl
        base_slope_ext = SLOPE
        reaper.SetExtState('MISHA_MONITOR', 'BASE_SLOPE', tostring(SLOPE), true)
        SaveSettings()
      end

      local rv_sc, new_sc = reaper.ImGui_SliderDouble(ctx, "Scroll Speed in free mode", scroll_accuracy, 0.1, 5.0, "%.1f")
      if rv_sc then scroll_accuracy = new_sc; SaveSettings() end

      local rv_ref, new_ref = reaper.ImGui_InputText(ctx, "Refs Folder Name", REF_FOLDER_NAME)
      if rv_ref then REF_FOLDER_NAME = new_ref; SaveSettings() end

      local rv_bh, new_bh = reaper.ImGui_SliderInt(ctx, "Global Button Height", button_h, 16, 50)
      if rv_bh then button_h = new_bh; should_resize = false; SaveSettings() end

      local rv_gw, new_gw = reaper.ImGui_SliderInt(ctx, "Grid Button Width", grid_width, 20, 150)
      if rv_gw then grid_width = new_gw; should_resize = false; SaveSettings() end

      local rv_mw, new_mw = reaper.ImGui_SliderInt(ctx, "Meter Width", meter_width, 20, 250)
      if rv_mw then meter_width = new_mw; should_resize = false; SaveSettings() end

      local changed_dco, dco = reaper.ImGui_Checkbox(ctx, "Disable corrections on start", DISABLE_CORR_ON_START)
      if changed_dco then DISABLE_CORR_ON_START = dco; SaveSettings() end

      local changed_fmt, fmt = reaper.ImGui_Checkbox(ctx, "Free mode slider on first row", FREE_MODE_TOP)
      if changed_fmt then FREE_MODE_TOP = fmt; should_resize = true; SaveSettings() end

      -- local rv_tg, new_tg = reaper.ImGui_SliderInt(ctx, "End Gap", ROW_TAIL_GAP, 0, 30)
      -- if rv_tg then ROW_TAIL_GAP = new_tg; should_resize = false; SaveSettings() end

      reaper.ImGui_Separator(ctx)

      reaper.ImGui_PopItemWidth(ctx)

      local reset_btn_w = 50
      
      if reaper.ImGui_Button(ctx, "Save", -reset_btn_w - 4) then
        buttons = StringToButtons(buttons_text)
        should_resize = true 
      end 
      
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), rgba(150, 50, 50, 0.6))
      if reaper.ImGui_Button(ctx, "RESET", reset_btn_w) then

        USE_VOLUME_BUTTONS = true
        USE_LISTEN_BANDS = false
        USE_REFS_SWITCH = false
        USE_METRICAB_SWITCH = false
        SHOW_CORRECTION_BTN = false
        REF_FOLDER_NAME = 'Refs'
        SLOPE = 2
        scroll_accuracy = 1.2
        button_h = 24
        grid_width = 60
        ROW_TAIL_GAP = 1
        meter_width = 70
        DISABLE_CORR_ON_START = false
        FREE_MODE_TOP = false
        buttons = {-32, -24, -14, -8, -4, 0, 4, 12, 18}
        buttons_text = ButtonsToString(buttons)
        USE_METRICAB = false
        USE_METRIC_IN_MONITORINGFX = true
        USE_GRID_BOX = true
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

function toggle_mon_fx_plugin(fxname)
  if not fxname or fxname == '' then return end
  local m = reaper.GetMasterTrack()
  local index = reaper.TrackFX_AddByName(m, fxname, true, 0)
  if index == -1 then return end
  local mon = (0x1000000)
  local is_open = reaper.TrackFX_GetOpen(m, mon + index)
  reaper.TrackFX_Show(m, mon + index, is_open and 2 or 3)
  reaper.TrackFX_SetEnabled(m, mon + index, is_open and 0 or 1)
  reaper.SetCursorContext(1, nil)
end

------------------------------------------------------------------------------------
-- Track Meter module (logic from ineed_slick track meter.lua)

local MTR_QUIET = -12
local MTR_HOLD_TIME = 0.7
local mtr_track = nil
local mtr_p1, mtr_p2 = 0, 0
local mtr_d1, mtr_d2 = -150, -150
local mtr_h1, mtr_h2 = -150, -150
local mtr_pk1, mtr_pk2 = -150, -150
local mtr_t1, mtr_t2 = reaper.time_precise(), reaper.time_precise()
local mtr_text = ''
local mtr_show_now = false
local mtr_prev_shown = false

local function mtr_should_show()
  return USE_METER
    and reaper.GetPlayState() ~= 0
    and mtr_text ~= '-inf'
end

function mtr_val2db(v)
  if v and v > 0.0000000298023223876953125 then return 20 * math.log(v, 10) end
  return -150.0
end

function mtr_db_norm(dB)
  return 10 ^ (dB / 20)
end

local MTR_MID_DB, MTR_MID_FRAC = -6, 0.7
local MTR_FLOOR_DB = -60

function mtr_db_to_frac(db)
  if db >= 0 then return 1 end
  if db >= MTR_MID_DB then
    return 1 + db * ((1 - MTR_MID_FRAC) / (0 - MTR_MID_DB))
  end
  local f = MTR_MID_FRAC * (db - MTR_FLOOR_DB) / (MTR_MID_DB - MTR_FLOOR_DB)
  if f < 0 then return 0 end
  if f > MTR_MID_FRAC then f = MTR_MID_FRAC end
  return f
end

function mtr_update()
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then track = mtr_track end
  if not track or not reaper.ValidatePtr(track, 'MediaTrack*') then
    mtr_track = nil
    return
  end

  mtr_track = track

  if reaper.GetPlayState() == 0 then
    reaper.Track_GetPeakHoldDB(track, 0, true)
    reaper.Track_GetPeakHoldDB(track, 1, true)
    mtr_p1, mtr_p2 = 0, 0
    mtr_d1, mtr_d2 = -150, -150
    mtr_h1, mtr_h2 = -150, -150
    mtr_pk1, mtr_pk2 = -150, -150
    mtr_text = '-inf'
    return
  end

  mtr_p1 = reaper.Track_GetPeakInfo(track, 0)
  mtr_p2 = reaper.Track_GetPeakInfo(track, 1)
  mtr_d1 = mtr_val2db(mtr_p1)
  mtr_d2 = mtr_val2db(mtr_p2)
  mtr_h1 = reaper.Track_GetPeakHoldDB(track, 0, false)
  mtr_h2 = reaper.Track_GetPeakHoldDB(track, 1, false)

  local now = reaper.time_precise()
  if mtr_d1 > mtr_pk1 or now - mtr_t1 >= MTR_HOLD_TIME then mtr_pk1 = mtr_d1; mtr_t1 = now end
  if mtr_d2 > mtr_pk2 or now - mtr_t2 >= MTR_HOLD_TIME then mtr_pk2 = mtr_d2; mtr_t2 = now end

  local peak = math.max(mtr_pk1, mtr_pk2)
  mtr_text = peak > -50 and tostring(trunc(peak, 1)) or '-inf'
end

function mtr_peak_rgb(db)
  if db > 0 then return 209, 105, 105 end
  -- if db > -3 then return 219, 172, 90 end
  if db > -6 then return 232, 204, 132 end
  if db > -18 then return 220, 218, 217 end
  if db > -30 then return 90, 219, 149 end
  return 114, 178, 255
end

function draw_meter()
  local mw = math.max(8, (meter_width or 70) - 4)
  local bh = math.max(4, math.floor(((button_h or 24)) / 2)) + 1

  local dl = reaper.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_Dummy(ctx, mw, bh * 2)

  for ch = 1, 2 do
    local d = (ch == 1) and mtr_d1 or mtr_d2
    local p = (ch == 1) and mtr_p1 or mtr_p2
    local h = (ch == 1) and mtr_h1 or mtr_h2
    local y = y0 + (ch - 1) * bh

    local quiet = d < MTR_QUIET

    local c_bg = quiet and rgba(8, 8, 8, 0.9) or rgba(22, 22, 22, 1)
    reaper.ImGui_DrawList_AddRectFilled(dl, x0, y, x0 + mw, y + bh, c_bg)

    -- Peak bar with tiered color.
    local pw = math.min(mtr_db_to_frac(d), 1) * mw
    if pw > 0 then
      local r, g, b = mtr_peak_rgb(d)
      reaper.ImGui_DrawList_AddRectFilled(dl, x0, y, x0 + pw, y + bh,
        rgba(r, g, b, quiet and 0.20 or 0.25))
    end

    -- Hold indicator.
    local hw = math.min(mtr_db_to_frac(h), 1) * mw
    if hw > 0 then
      reaper.ImGui_DrawList_AddRectFilled(dl, x0, y, x0 + hw, y + bh,
        rgba(140, 140, 140, 0.15))
    end
  end

  if mtr_text ~= '' then
    local tw, th = reaper.ImGui_CalcTextSize(ctx, mtr_text)
    local tx = x0 + 4
    local ty = y0 + math.floor((bh * 2 - th) / 2)

    local pk_db = math.max(mtr_d1, mtr_d2)
    local r, g, b = mtr_peak_rgb(pk_db)
    local col_txt = rgba(r, g, b, 1)

    -- reaper.ImGui_DrawList_AddText(dl, tx + 1, ty + 1, rgba(200, 200, 200, 0.3), mtr_text)
    reaper.ImGui_DrawList_AddText(dl, tx, ty, rgba(r, g, b, 1), mtr_text)
  end
end

local ROW_SPACING, ROW_GAP =2, 1
local SETTINGS_W, AB_REF_W = 16, 30
local ui_unit

local function row_layout()
  local fixed = SETTINGS_W
  local units = 0
  local add_fixed = 0
  local has_item = true -- settings button is always drawn

  local function same_line()
    if has_item then
      fixed = fixed + ROW_SPACING
    end
    has_item = true
  end

  local function add_fixed_item(w)
    fixed = fixed + (tonumber(w) or 0)
    has_item = true
  end

  local function add_unit_item(u)
    units = units + (tonumber(u) or 0)
    has_item = true
  end

  local function add_lead_gap()
    fixed = fixed + ROW_GAP
    same_line()
  end

  if SHOW_CORRECTION_BTN then
    same_line()
    add_fixed_item(get_correction_button_width(master)+10)
    same_line() -- Main() calls SameLine() after corrections.
  end

  if USE_VOLUME_BUTTONS then
    add_lead_gap()
    add_unit_item(#buttons)
    add_fixed = add_fixed + math.max(0, #buttons - 1) * ROW_SPACING
    same_line() -- Main() calls SameLine() after the volume group.
  end

  if USE_LISTEN_BANDS then
    add_lead_gap()
    add_unit_item(#listen_buttons * 1.5)
    add_fixed = add_fixed + math.max(0, #listen_buttons - 1) * ROW_SPACING
    same_line()
  end

  if USE_GRID_BOX then
    add_lead_gap()
    add_fixed_item(grid_width)
    same_line()
  end

  local has_switches =
    USE_METRICAB_SWITCH
    or USE_REFS_SWITCH
    or (USE_MONFX and #mon_fx_presets > 0)

  if has_switches then
    add_lead_gap()

    if USE_METRICAB_SWITCH then
      add_fixed_item(AB_REF_W)
      same_line()
    end

    if USE_MONFX and #mon_fx_presets > 0 then
      for _, p in ipairs(mon_fx_presets) do
        if p.name ~= '' then
          add_fixed_item(tonumber(p.w) or 20)
          same_line()
        end
      end
    end

    if USE_REFS_SWITCH then
      add_fixed_item(AB_REF_W)
      if USE_ITEM_COUNT then
        same_line()
      end
    end
  end

  if USE_ITEM_COUNT then
    add_fixed_item(item_count_total_width)
  end

  if mtr_show_now then
    same_line()
    add_fixed_item(ROW_GAP)
    same_line()
    add_fixed_item(meter_width or 70)
  end

  return fixed + add_fixed, units, 0
end

function Main(unit_w, settings_w, corr_w, ab_ref_w, gap)
  -- reaper.ImGui_Dummy(ctx,1,1)
  -- reaper.ImGui_SameLine(ctx)
  
  local c = layer_colors[current_layer]
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        rgba(c.r,c.g,c.b,0.7))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), rgba(c.r,c.g,c.b,1))

  if free_mode and FREE_MODE_TOP then
    draw_free_mode_slider(master)
    reaper.ImGui_Spacing(ctx)
  end

  state = get_state(master)
  ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'LISTEN'))
  if ext == nil then ext = 0 end 

  local function lead_gap()
    reaper.ImGui_Dummy(ctx, ROW_GAP, 0)
    reaper.ImGui_SameLine(ctx)
  end

  draw_settings_button(settings_w)
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_PopStyleColor(ctx, 2)

  if SHOW_CORRECTION_BTN then
    draw_correction_single_button(corr_w)
    reaper.ImGui_SameLine(ctx)
  end

  if USE_VOLUME_BUTTONS then
    lead_gap()
    draw_volume_buttons(master, unit_w)
    reaper.ImGui_SameLine(ctx)
  end

  if USE_LISTEN_BANDS then
    lead_gap()
    draw_listen_buttons(master, unit_w * 1.5)
    reaper.ImGui_SameLine(ctx)
  end

  if USE_GRID_BOX then
    lead_gap()
    draw_grid_button()
    reaper.ImGui_SameLine(ctx)
  end

  if USE_METRICAB_SWITCH or USE_REFS_SWITCH or (USE_MONFX and #mon_fx_presets > 0) then
    lead_gap()

    if USE_METRICAB_SWITCH then
      draw_ab_button(master, ab_ref_w)
      reaper.ImGui_SameLine(ctx)
    end

    if USE_MONFX and #mon_fx_presets > 0 then
      for _, mp in ipairs(mon_fx_presets) do
        if mp.name ~= '' then
          local _, dr, dg, db = reaper.ImGui_ColorConvertU32ToDouble4(mp.col_u32 or 0x6CAEEBFF)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),             reaper.ImGui_ColorConvertDouble4ToU32(dr, dg, db, 1))
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),           reaper.ImGui_ColorConvertDouble4ToU32(dr, dg, db, 0.25))
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),    reaper.ImGui_ColorConvertDouble4ToU32(dr, dg, db, 0.4))
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),     reaper.ImGui_ColorConvertDouble4ToU32(dr, dg, db, 0.6))

          if reaper.ImGui_Button(ctx, mp.name, tonumber(mp.w) or 20, button_h) then
            toggle_mon_fx_plugin(mp.fx)
          end
          reaper.ImGui_SameLine(ctx)
          reaper.ImGui_PopStyleColor( ctx,4 )
        end
      end
    end

    if USE_REFS_SWITCH then
      draw_refs_button(ab_ref_w)
      if USE_ITEM_COUNT then reaper.ImGui_SameLine(ctx) end
    end
  end

  if USE_ITEM_COUNT then
    item_count_total_width = draw_item_count()
  end

  if mtr_show_now then
    local prev_bare = USE_ITEM_COUNT or USE_REFS_SWITCH
    if prev_bare then reaper.ImGui_SameLine(ctx) end
    reaper.ImGui_Dummy(ctx, ROW_GAP, 0)
    reaper.ImGui_SameLine(ctx)
    draw_meter()
  end

  -- local has_modules = SHOW_CORRECTION_BTN or USE_VOLUME_BUTTONS or USE_LISTEN_BANDS
  --   or USE_GRID_BOX or USE_METRICAB_SWITCH or USE_REFS_SWITCH or USE_ITEM_COUNT
  --   or (USE_MONFX and #mon_fx_presets > 0)
  -- local last_sl = true
  -- if USE_ITEM_COUNT then
  --   last_sl = false
  -- elseif USE_REFS_SWITCH then
  --   last_sl = false
  -- end
  -- if has_modules then
  --   if not last_sl then reaper.ImGui_SameLine(ctx) end
  --   reaper.ImGui_Dummy(ctx, ROW_TAIL_GAP, 0)
  -- end

  if free_mode and not FREE_MODE_TOP then
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
    master = reaper.GetMasterTrack()
    local layout = layers[current_layer]
    USE_VOLUME_BUTTONS  = layout.vol
    USE_LISTEN_BANDS    = layout.lis
    SHOW_CORRECTION_BTN = layout.corr
    USE_REFS_SWITCH     = layout.ref
    USE_METRICAB_SWITCH = layout.ab
    USE_ITEM_COUNT      = layout.item_count
    USE_GRID_BOX        = layout.grid
    USE_MONFX           = layout.monfx
    USE_METER           = layout.mtr
    mtr_update()
    mtr_show_now = mtr_should_show()
    if mtr_show_now ~= mtr_prev_shown then
      mtr_prev_shown = mtr_show_now
      should_resize = true
    end
    -- -----------------------

    local window_h = button_h + 10 + (free_mode and 26 or 0)
    local snap_f, snap_u, snap_a = row_layout()

    -- Keep the resize calculation valid even when every optional module is off.
    -- In that state there may be no content width to contribute to the layout.
    snap_f = tonumber(snap_f) or 0
    snap_u = tonumber(snap_u) or 0
    snap_a = tonumber(snap_a) or 0

    if should_resize then
        local u = tonumber(ui_unit or unit_w) or 45
        local target_pw = math.floor(snap_f + snap_u * u + snap_a + 10 + 0.5)
        if target_pw < 60 then target_pw = 60 end
        reaper.ImGui_SetNextWindowSize(ctx, target_pw, window_h, reaper.ImGui_Cond_Always())
        pw = target_pw
        should_resize = false
    else
        if not pw or pw <= 0 then
            local u = tonumber(ui_unit or unit_w) or 45
            pw = math.floor(snap_f + snap_u * u + snap_a + 10 + 0.5)
            reaper.ImGui_SetNextWindowSize(ctx, pw, window_h, reaper.ImGui_Cond_Always())
        end
    end

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 5, 4) 
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 2, 2) 
    reaper.ImGui_PushFont(ctx, nil, font_size1)

    local visible, open = reaper.ImGui_Begin(ctx, 'Monitor Controller', true, window_flags)
    local real_pw, real_ph = reaper.ImGui_GetWindowSize(ctx)
    if real_pw > 50 and not should_resize and ui_unit then 
        pw = real_pw 
    else 
      pw = 40
    end
    
    local win_content_w = pw - 10

    if visible then
        if reaper.ImGui_IsWindowHovered(ctx) and reaper.ImGui_IsMouseReleased(ctx, 1) then
            current_layer = current_layer + 1
            if current_layer > MAX_LAYERS then current_layer = 1 end
            -- should_resize = true
            SaveSettings()
        end

        local corr_w = SHOW_CORRECTION_BTN and get_correction_button_width(master) or 0

        local dynamic_area = win_content_w - (snap_f + snap_a)
        unit_w = (snap_u > 0) and (dynamic_area / snap_u) or 45
        if unit_w < 10 then unit_w = 10 end
        ui_unit = unit_w

        Main(unit_w, SETTINGS_W, corr_w, AB_REF_W, ROW_GAP)
        reaper.ImGui_End(ctx)
    end

    if show_settings_window then DrawSettingsWindow() end

    if reaper.ImGui_IsMouseReleased(ctx, 0) then SaveSettings() end

    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopFont(ctx)

    if open then reaper.defer(loop) end
end

--master = reaper.GetMasterTrack()

if DISABLE_CORR_ON_START then
  master = reaper.GetMasterTrack()
  disable_corrections()
end

reaper.atexit(function()
  if pw then
    reaper.SetExtState(SECTION, 'pw', tostring(math.floor(pw)), true)
  end
end)

loop()