-- @description Project Time Tracker with Multi-Project Support and Efficient Saving
-- @author Misha Oshkanov
-- @version 1.2.2
-- @about
--  Tracks active work time per project tab in REAPER.
--  Switches timers between tabs automatically.
--  Saves time to ExtState only once per minute or on save/exit.
--------------------------------------------------------------------- 
---------------------------------------------------------------------
---------------------------------------------------------------------

floating_window = true
font_size = 26

offset_x = 54
offset_y = 50

window_w = 150

local proj = 0
local project_times = {}
local last_proj_id = nil
local last_save = reaper.time_precise()
local last_check = reaper.time_precise()

local AFK_THRESHOLD = 60 -- seconds
local last_input_time = reaper.time_precise()
local last_mouse_x, last_mouse_y = reaper.GetMousePosition()
----------------------------------------------------------------------
----------------------------------------------------------------------

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


local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OSX') or os:match('macOS')
local is_linux = os:match('Other')

local ctx = reaper.ImGui_CreateContext('Timer')
local font = reaper.ImGui_CreateFont('sans-serif', 0)
-- reaper.ImGui_Attach(ctx, font)

window_flags =  reaper.ImGui_WindowFlags_NoScrollbar() +
                reaper.ImGui_WindowFlags_NoTitleBar() +
                reaper.ImGui_WindowFlags_NoDocking()  +
                reaper.ImGui_WindowFlags_NoResize()  
                -- reaper.ImGui_WindowFlags_NoBackground()
                

function get_bounds(hwnd)
    local _, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
    -- Check voor MacOS
    if reaper.GetOS():match("^OSX") then
        local screen_height = reaper.ImGui_GetMainViewport(ctx).WorkSize.y
        top = screen_height - bottom
        bottom = screen_height - top
    end
    -- return left, top, right-left, bottom-top
    return left, top, right, bottom

    -- local _, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
    -- x, y = reaper.ImGui_PointConvertNative(ctx, x, y, false)
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

function VAL2DB(val) 
    if val ~= nil then 
        if val > 0.0000000298023223876953125 then 
            return 20 * math.log(val, 10)         
        else
            return -150.0
        end
    end 
 return
end

function log10(x)
    return math.log(x) / math.log(10)
end

function dbToLog(dB)
    return 1 - log10(-dB) / log10(1 / 10)
end

function dbToNormalized(dB)
    return 10 ^ (dB / 20)
end

function trunc(num, digits)
    local mult = 10^(digits)
    return math.modf(num*mult)/mult
end

function draw_color_fill(color)
    button_col = 0xaf1d70
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x+2, max_y,  color,2,0,2)
end


function IsReaperFocused()
  local hwnd = reaper.GetMainHwnd()
  if reaper.JS_Window_GetForeground()== hwnd then 
    return true
  else 
    retval, _, _, _, _, _ = reaper.GetTouchedOrFocusedFX(1)
    if retval then return true end
  end
end

function IsPlayingOrRecording()
  local transportState = reaper.GetPlayState()
  return (transportState & 1 == 1) or (transportState & 4 == 4)
end

function SaveTime()
  local title = GetProjectTitle()
  if title then 
    data = ti
    reaper.SetProjExtState(proj, "TIME_TRACKER", key_time, tostring(totalTime))
    reaper.SetProjExtState(proj, "TIME_TRACKER", key_title, title)
  end
end

function get_time()
    local retval, totalTime = reaper.GetProjExtState(proj, "TIME_TRACKER", key_time)
    totalTime = tonumber(totalTime) or 0
    return totalTime
end

function FormatTime(seconds)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = math.floor(seconds % 60)
  return string.format("%02d:%02d:%02d", h, m, s)
end

function save_csv(file_path, start_time_iso, duration_sec, project_title)
  local file = io.open(file_path, "a")
  if file then
    file:write(string.format("%s, %d, %s\n", start_time_iso, duration_sec, project_title))
    file:close()
  else
    reaper.ShowConsoleMsg("❌ Не удалось открыть CSV файл для записи\n")
  end
end

function GetCurrentTimeISO()
  local t = os.date("!*t")  -- UTC
  return string.format(
    "%04d-%02d-%02dT%02d:%02d:%02dZ",
    t.year, t.month, t.day, t.hour, t.min, t.sec
  )
end

function GetProjectID()
  local _, proj_fn = reaper.EnumProjects(-1, '')
  return proj_fn or "UNKNOWN"
end

function GetProjectHandle()
  local proj, _ = reaper.EnumProjects(-1, '')
  return proj
end

function GetProjectTitle()
  local _,title = reaper.GetSetProjectInfo_String(proj, "PROJECT_TITLE", "", false)
  if title == "" then
    local _,name = reaper.GetSetProjectInfo_String(proj, "PROJECT_NAME", "", false)
    if name:find('.rpp') then 
      name = name:gsub(".rpp","")
    elseif name:find('.RPP') then 
      name = name:gsub(".RPP","")
    end
    if name ~= "" then return name end
  else
    return title 
  end
end

function SaveTimeToExtState(title, seconds)
  if title then 
    reaper.SetExtState("MISHA_TIME_TRACKER", title, tostring(seconds),true)
  end
end

function LoadTimeFromExtState(title)
  local val = reaper.GetExtState("MISHA_TIME_TRACKER", title)
  return tonumber(val) or 0
end

function init()
  local proj_id = GetProjectTitle()
  if proj_id then 
    total = LoadTimeFromExtState(proj_id)
    -- print(total)
  end
end 

text_color = rgba(128,128,128,1)
local prev_dirty = reaper.IsProjectDirty(0) == 1

function frame()
  local now = reaper.time_precise()
  local delta = now - last_check
  last_check = now

  local proj_id = GetProjectTitle()

  if proj_id then 
    if proj_id ~= last_proj_id then
      if last_proj_id and project_times[last_proj_id] then
        SaveTimeToExtState(last_proj_id, project_times[last_proj_id].total)
      end
      -- Load or initialize time
      project_times[proj_id] = {
        total = LoadTimeFromExtState(proj_id),
        last_update = now
      }
      last_proj_id = proj_id
    end

    local session = project_times[proj_id]
    if IsReaperFocused() or IsPlayingOrRecording() then
      local current_dirty = reaper.IsProjectDirty(0) == 1
      if prev_dirty and not current_dirty then
        SaveTimeToExtState(proj_id, session.total)
      end
      prev_dirty = current_dirty

      local mouse_x, mouse_y = reaper.GetMousePosition()
      local mouse_state = reaper.JS_Mouse_GetState(0xFFFF)
      -- local key_input = reaper.JS_VKeys_GetState(0)

      if mouse_x ~= last_mouse_x or mouse_y ~= last_mouse_y or mouse_state ~= 0 then
        last_input_time = now
        last_mouse_x, last_mouse_y = mouse_x, mouse_y
      end

      local is_afk = (now - last_input_time) > AFK_THRESHOLD
      if is_afk then 
        text_color = rgba(128,128,128,1)
      end
      
      if delta < 60 and not is_afk then
        local prev_dirty = reaper.IsProjectDirty(0) == 1
        session.total = session.total + delta
        session.last_update = now
        text_color = rgba(232,232,232,1)
      end
    else
      text_color = rgba(128,128,128,1)
    end
    if now - last_save >= 60 then
      SaveTimeToExtState(title, session.total)
      last_save = now
    end
    -- reaper.ImGui_Text(ctx, FormatTime(session.total))
    reaper.ImGui_TextColored( ctx, text_color, FormatTime(session.total))
  end
end

function atexit()
    -- SaveTime()
  if last_proj_id and project_times[last_proj_id] then
    SaveTimeToExtState(last_proj_id, project_times[last_proj_id].total)
  end
end

function loop()
    reaper.ImGui_PushFont(ctx, nil, font_size)
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(36, 37, 38, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(52, 66, 54, 1))

    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_WindowPadding(), 3,4) 
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_ItemSpacing(),   2,2) 
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_WindowMinSize(), 2,14) 

    -- retval, left, top, right, bottom = reaper.JS_Window_GetClientRect( mainHWND )
    -- retval, ar_left, ar_top, ar_right, ar_bottom = reaper.JS_Window_GetClientRect(windowHWND)
    
    reaper.ImGui_SetNextWindowSize(ctx, 100, 38,  reaper.ImGui_Cond_Always())
    
    mainHWND = reaper.GetMainHwnd()
    windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
    left, top, right, bottom = get_bounds(windowHWND)

    -- x, y = reaper.ImGui_PointConvertNative(ctx, x, y, false)

    if not floating_window then 
        reaper.ImGui_SetNextWindowPos(ctx, right-offset_x, bottom-offset_y, condIn, 0.5, 0.5)
    end
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Meter', true, window_flags)
    if visible then
      frame()
      reaper.ImGui_End(ctx)
    end

    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopFont(ctx)
    
    if open then
      reaper.defer(loop)
    end

end

-- init()
loop()
reaper.atexit(atexit)