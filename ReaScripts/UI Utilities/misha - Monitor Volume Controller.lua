-- @description Monitor Volume Controller
-- @author Misha Oshkanov
-- @version 1.7
-- @about
--  UI panel to quicly change level of your monitoring. It's a stepped contoller with defined levels. 
--  If you need more levels or change db values you can edit buttons table.
--  Use right click to change modes between volume control and listen filters

-------------------------- SETTINGS -----------------------------

USE_LISTEN_BANDS = false -- mode by default

buttons = {-24, -14, -8, -4, 0, 4, 12, 18, 24} -- in dB

listen_buttons = {
  {str = 'Sub',  l = 0,    h = 60   ,col = {81,100,123,0.8}},
  {str = 'Bass', l = 0,    h = 250  ,col = {86,111,128,0.8}},
  {str = 'Low',  l = 250,  h = 800  ,col = {90,120,135,0.8}},
  {str = 'Mid',  l = 800,  h = 3570 ,col = {86,128,98,0.8}},
  {str = 'High', l = 4000, h = 22000,col = {121,157,107,0.7}},
  {str = 'Free', l = 0,    h = 22000,col = {161,145,99,0.7}},
}

move_x = 10 -- move panel in x coordinate
move_y = 20 -- move panel in y coordinate

POS = 'TOP' -- 'BOTTOM' -- position presets

button_h = 24 -- height default - 24
button_w = 54 -- width  default - 54

listen_button_h = 24

floating_window = false -- use floating window to freely place the panel
listen_state = false

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

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.6')
local ctx = reaper.ImGui_CreateContext('Show/Hide')
local font = reaper.ImGui_CreateFont('sans-serif', 18)
local font2 = reaper.ImGui_CreateFont('sans-serif', 14)

reaper.ImGui_AttachFont(ctx, font)
reaper.ImGui_AttachFont(ctx, font2)

free_l = 0
free_h = 22000
width = 2

controller_fx = 'Monitor Volume Controller'

base_freq_ext  = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_FREQ'))
base_width_ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'BASE_WIDTH'))
if base_width_ext == nil then base_width_ext = 2 end

slider_range = base_freq_ext
if base_freq_ext == nil then base_freq_ext = 1000 end

window_flags =  reaper.ImGui_WindowFlags_NoTitleBar() +  
                reaper.ImGui_WindowFlags_NoDocking() +
                reaper.ImGui_WindowFlags_NoScrollbar() + 
                reaper.ImGui_WindowFlags_NoResize() 
                -- reaper.ImGui_WindowFlags_NoBackground()-
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

function get_state(master)
  index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
  retval, minval, maxval = reaper.TrackFX_GetParam(master, index+mon, 2)
  return retval
end

function get_listen_freq(master)
  index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
  low_retval,  _, _ = reaper.TrackFX_GetParam(master, index+mon, 0)
  high_retval, _, _ = reaper.TrackFX_GetParam(master, index+mon, 1)
  return low_retval, high_retval
end 

function get_listen_state(master)
  index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
  -- enabled = reaper.TrackFX_GetEnabled(master, index+mon)
  enabled,  _, _ = reaper.TrackFX_GetParam(master, index+mon, 3)
  return enabled
end 

function set_listen_state(master,state)
  index = reaper.TrackFX_AddByName(master, controller_fx, true, 0)
  reaper.TrackFX_SetParam(master, index+mon, 3, state)
  -- enabled = reaper.TrackFX_SetEnabled(master, index+mon, state)
end 

function set_param_freq(master,param,value)
  listen_index = reaper.TrackFX_AddByName(master, controller_fx, true, 100)
  reaper.TrackFX_SetParam(master, listen_index+mon, param, value)
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
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopID(ctx)
    
    if b_button then
        index = reaper.TrackFX_AddByName(master, controller_fx, true, 100)
        if reaper.TrackFX_GetOpen(master, mon+index) then reaper.TrackFX_Show(master, mon+index, 2 ) end
        reaper.TrackFX_SetParam(master, index+mon, 2, b )
    end
  end
end 


function draw_listen_buttons(master)
  for i2,lb in ipairs(listen_buttons) do
    ImGui.PushID(ctx, i)
    ImGui.PushFont(ctx, font2)

    listen_low, listen_high = get_listen_freq(master)
    listen_state = get_listen_state(master)

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
    ImGui.PopStyleColor(ctx, 3)
    ImGui.PopFont(ctx)
    ImGui.PopID(ctx)
    
    if listen_button then 
        if ext == 0 or (ext > 0 and ext ~= i2) then 
          reaper.SetExtState('MISHA_MONITOR', 'LISTEN', i2, true)
          set_listen_state(master,1)
        elseif ext == i2 then 
          set_listen_state(master,0)
          reaper.SetExtState('MISHA_MONITOR', 'LISTEN', '0', true)
        end

        if lb.str == 'Free' then 
          lowCut  = slider_range / (2 ^ (base_width_ext / 2))
          highCut = slider_range * (2 ^ (base_width_ext / 2))
          set_param_freq(master,0,lowCut)
          set_param_freq(master,1,highCut)
        else 
          set_param_freq(master,0,lb.l)
          set_param_freq(master,1,lb.h)
        end 
    end
    if ext == #listen_buttons then free_mode = true else free_mode = false end
  end
end 

function Main()
  master = reaper.GetMasterTrack()
  state = get_state(master)
  ext = tonumber(reaper.GetExtState( 'MISHA_MONITOR', 'LISTEN'))
  
  if USE_LISTEN_BANDS then 
    draw_listen_buttons(master)
  else 
    if ext > 0 then 
      reaper.SetExtState('MISHA_MONITOR', 'LISTEN', '0', true) 
      set_listen_state(master,0)
    end 
    draw_volume_buttons(master)
  end

  reaper.ImGui_PushItemWidth( ctx, tcp_w-4 )

  if free_mode then 
    vertical, horizontal = reaper.ImGui_GetMouseWheel( ctx )
    if vertical ~= 0 then 
      if vertical > 0 then 
        base_width_ext = base_width_ext + 0.3 
      else 
        base_width_ext = base_width_ext - 0.3 
      end 
      reaper.SetExtState('MISHA_MONITOR', 'BASE_WIDTH', base_width_ext, true)
      lowCut  = slider_range / (2 ^ (base_width_ext / 2))
      highCut = slider_range * (2 ^ (base_width_ext / 2))
      set_param_freq(master,0,lowCut)
      set_param_freq(master,1,highCut)
    end
  end

  local minFreq = 20     -- minimum frequency in Hz
  local maxFreq = 22000  -- maximum frequency in Hz

  lowCut  = slider_range / (2 ^ (base_width_ext / 2))
  highCut = slider_range * (2 ^ (base_width_ext / 2))

  if lowCut < minFreq then lowCut = minFreq end
  if highCut > maxFreq then highCut = maxFreq end

  if free_mode == true then 
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab(),          rgba(195,105,105,0.7))
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive(),    rgba(195,105,105,0.9))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg(),             rgba(96,68,68,0.4))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive(),       rgba(100,72,72,0.8))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered(),      rgba(100,72,72,0.6))

    range_retval, slider_range = reaper.ImGui_SliderInt( ctx, 'slider_range', slider_range, 20, 20000,  formatIn, reaper.ImGui_SliderFlags_Logarithmic() )
    if range_retval then 
      reaper.SetExtState('MISHA_MONITOR', 'BASE_FREQ', slider_range, true)
      set_param_freq(master,0,lowCut)
      set_param_freq(master,1,highCut)
    end
    
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    sliderWidth = (max_x -tcp_w/4) - min_x

    local lowCutPos =  (math.log(lowCut)  - math.log(20)) / (math.log(20000) - math.log(20))
    local highCutPos = (math.log(highCut) - math.log(20)) / (math.log(20000) - math.log(20))
    low_cut_x = min_x + (lowCutPos * sliderWidth)
    high_cut_x = min_x + (highCutPos * sliderWidth)

    reaper.ImGui_DrawList_AddRectFilled( draw_list, low_cut_x, min_y, high_cut_x, max_y,  rgba(200,200,200,0.2),2,0)
    ImGui.PopStyleColor(ctx, 5)
  end
  reaper.ImGui_PopItemWidth( ctx )

  if reaper.ImGui_IsMouseClicked( ctx, reaper.ImGui_MouseButton_Right() ) then 
    USE_LISTEN_BANDS = not USE_LISTEN_BANDS 
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
            if occurance == control_occurance then
                return hwnd
            end
        end
    end
end

function loop()  
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(36, 37, 38, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(68, 69, 70, 1))
  
    reaper.ImGui_PushStyleVar( ctx,    reaper.ImGui_StyleVar_WindowPadding(), 3,4) 
    reaper.ImGui_PushStyleVar( ctx,     reaper.ImGui_StyleVar_ItemSpacing(), 2,2) 
  
    reaper.ImGui_PushFont(ctx, font)

    scale = reaper.ImGui_GetWindowDpiScale( ctx )
    mainHWND = reaper.GetMainHwnd()
    windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
    retval, ar_left, ar_top, ar_right, ar_bottom = reaper.JS_Window_GetClientRect( windowHWND )

    cw, ch = reaper.ImGui_GetWindowSize( ctx )

    tcp_hwnd = FindChildByClass(reaper.GetMainHwnd(),'REAPERTCPDisplay',1)
    if tcp_hwnd then
      tcp_x,tcp_y,tcp_w,tcp_h = GetClientBounds(tcp_hwnd)
      retval, tcp_left, tcp_top, tcp_right, tcp_bottom = reaper.JS_Window_GetClientRect( mainHWND )
    end

    button_w = (tcp_w/#buttons)-2
    listen_button_w = (tcp_w/#listen_buttons)-2

    -- reaper.ImGui_SetNextWindowPos(ctx,600,600)
    -- reaper.ImGui_SetNextWindowSize(ctx, 300, 50)
    
    -- reaper.ImGui_SetNextWindowSize(ctx, tcp_w*(1/scale)-10, (button_h+8)*(1/scale))


    -- if USE_LISTEN_BANDS then 
    --   if free_mode then free_offset = 30 else free_offset = 0 end
    --   reaper.ImGui_SetNextWindowSize(ctx, tcp_w*(1/scale)+4, ((button_h)+10+listen_button_h)*(1/scale)+free_offset)
    -- else
    --   reaper.ImGui_SetNextWindowSize(ctx, tcp_w*(1/scale)+4, (button_h+8)*(1/scale))
    -- end

    if free_mode then free_offset = 24 else free_offset = 0 end
    reaper.ImGui_SetNextWindowSize(ctx, tcp_w*(1/scale)+4, (button_h+8)*(1/scale)+free_offset)

    
    if not floating_window then 
      if POS == 'BOTTOM' then 
        reaper.ImGui_SetNextWindowPos( ctx,  move_x + (tcp_right-(tcp_right-right)-(tcp_w/2))*(1/scale), move_y + (ar_bottom-(ch))*(1/scale), condIn, 0.5, 0.5 )
      elseif POS == 'TOP' then 
        reaper.ImGui_SetNextWindowPos( ctx,  move_x + (tcp_left+(tcp_right/6))*(1/scale), move_y + (tcp_top+30)*(1/scale), condIn, 0.5, 0.5 )
      end 
    end
  
    local visible, open = reaper.ImGui_Begin(ctx, 'Show/Hide', true, window_flags)
  
    if visible  then
      Main()     
      reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar( ctx, 2 )
    reaper.ImGui_PopFont(ctx)
  
    if open then
      reaper.defer(loop)
    else
      reaper.ImGui_DestroyContext(ctx)
    end
  
end

reaper.defer(loop)