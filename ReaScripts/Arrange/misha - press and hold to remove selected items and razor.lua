-- @description press key to remove selected items and razor
-- @author Misha Oshkanov
-- @version 1.1
-- @about
--    It deletes all selected items and razor when you press and hold script key button
--    Ruler, peaks and item names change color if script is active
--    you can swap right mouse buttom modifier when script is active

UNSELECT_AT_START = true -- script unselects all items during key press and selects it again after key release
RAZOR_ON_RIGHT_MB = true -- script changes right mouse button modifier during key press for quick razor editing
action = 'Add to razor edit area ignoring snap' -- name of action for right mouse button modifier 
-- 'Add to razor edit area ignoring snap' by default
-- 'Add to razor edit area' if you need snap

-----------------------------------------------------------------
-----------------------------------------------------------------
function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

color = "##4E1414" -- Ruler color

theme_elements_by_modes = {
  {"col_tr1_bg", "col_tr2_bg", "selcol_tr1_bg", "selcol_tr2_bg", "ts_lane_bg" }, 
}

local mouse_action = nil
local start_time = reaper.time_precise()
local key_state, KEY = reaper.JS_VKeys_GetState(start_time - 2), nil
for i = 1, 255 do
  if key_state:byte(i) ~= 0 then
    KEY = i; reaper.JS_VKeys_Intercept(KEY, 1)
  end
end
if not KEY then return end
local cur_pref = reaper.SNM_GetIntConfigVar("alwaysallowkb", 1)
reaper.SNM_SetIntConfigVar("alwaysallowkb", 1)

function Key_held()
  key_state = reaper.JS_VKeys_GetState(start_time - 2)
  return key_state:byte(KEY) == 1
end

function Release()
  reaper.JS_VKeys_Intercept(KEY, -1)
  reaper.SNM_SetIntConfigVar("alwaysallowkb", cur_pref)
  exit()
end

function Handle_errors(err)
  reaper.ShowConsoleMsg(err .. '\n' .. debug.traceback())
  Release()
end


function HexToInt(hex)
  local r, g, b = HexToRGB(hex)
  local int =  reaper.ColorToNative( r, g, b )|16777216
  return int
end

function HexToRGB(hex)
  local hex = hex:gsub("#","")
  local R = tonumber("0x"..hex:sub(1,2))
  local G = tonumber("0x"..hex:sub(3,4))
  local B = tonumber("0x"..hex:sub(5,6))
  return R, G, B
end

function SetButtonState(set)
  if not set then set = 0 end
  local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  local state = reaper.GetToggleCommandStateEx(sec, cmd)
  reaper.SetToggleCommandState( sec, cmd, set ) -- Set ON
  reaper.RefreshToolbar2(sec, cmd)
end

function exit()
--   SetButtonState()
  for i, theme_elements_mode in ipairs( theme_elements_by_modes ) do
    for k, v in ipairs( theme_elements_mode ) do reaper.SetThemeColor( v, -1,  0) end
  end

  if UNSELECT_AT_START then 
    for k,item in ipairs(selected_items) do reaper.SetMediaItemSelected(item, 1) end
  end
  if RAZOR_ON_RIGHT_MB then 
    reaper.SetMouseModifier('MM_CTX_ARRANGE_RMOUSE', 0, mouse_action)
  end

  reaper.UpdateTimeline()
  reaper.UpdateArrange()
end

function loop()
  if not Key_held() then return end
  reaper.Main_OnCommand(40006, 0)
  reaper.defer(function() xpcall(loop, Handle_errors) end)
end

reaper.Main_OnCommand(40312, 0)

-- SetButtonState(1)
selected_items = {}

if UNSELECT_AT_START then 
  local count = reaper.CountMediaItems(0)
  for i=0, count-1 do 
    local item = reaper.GetMediaItem(0, i)
    if reaper.IsMediaItemSelected(item) then table.insert(selected_items, item) end
  end
  reaper.SelectAllMediaItems(0, 0)
end 

if RAZOR_ON_RIGHT_MB then 
  mouse_action = reaper.GetMouseModifier(  'MM_CTX_ARRANGE_RMOUSE', 0)
  reaper.SetMouseModifier('MM_CTX_ARRANGE_RMOUSE', 0, action)
end

for i, v in ipairs(theme_elements_by_modes[1]) do
  reaper.SetThemeColor(v, HexToInt(color),  0)
end

reaper.UpdateTimeline()
reaper.UpdateArrange()

reaper.defer(function() xpcall(loop, Handle_errors) end)
reaper.atexit(Release)