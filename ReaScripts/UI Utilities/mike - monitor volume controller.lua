-- @description Monitor Volume Controller
-- @author Misha Oshkanov
-- @version 1.3
-- @about
--  UI panel to quicly change level of your monitoring. It's a stepped contoller with defined levels. 
--  If you need more levels or change db values you can edit buttons table.

-------------------------- SETTINGS -----------------------------
buttons = {
  --  example: {button = nil, value = 'change value here in db', s = nil},
  {button = nil, value = -23, s = nil},
  {button = nil, value = -14, s = nil},
  {button = nil, value = -8, s = nil},
  {button = nil, value = -4, s = nil},
  {button = nil, value = 0, s = nil},
  {button = nil, value = 6, s = nil},
  {button = nil, value = 12, s = nil},
}

move_x = 10 -- move panel in x coordinate
move_y = 20 -- move panel in y coordinate

POS = 'TOP' -- 'BOTTOM' -- position presets

button_h = 24 -- height default - 24
button_w = 54 -- width  default - 54
floating_window = false -- use floating window to freely place the panel


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
reaper.ImGui_AttachFont(ctx, font)

controller_fx = 'Monitor Controller Trim'

window_flags =  reaper.ImGui_WindowFlags_NoTitleBar() +  
                reaper.ImGui_WindowFlags_NoDocking() +
                reaper.ImGui_WindowFlags_NoResize() +
                reaper.ImGui_WindowFlags_NoScrollbar() 
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

function get_state()
  index = reaper.TrackFX_AddByName(reaper.GetMasterTrack(), controller_fx, true, 0)
  retval, minval, maxval = reaper.TrackFX_GetParam(reaper.GetMasterTrack(), index+mon, 0)
  return retval
end

-- function setup_plugin()
--   track = reaper.GetMasterTrack()
--   reaper.TrackFX_GetCount(track)
--   index = reaper.TrackFX_AddByName(track, controller_fx, true, 0)
--   if index == -1 then 
--     new_index = reaper.TrackFX_AddByName(track, 'JS: Volume Adjustment', true, 10)

--   end


-- end

function Main()
  state = get_state()
  for i,b in ipairs(buttons) do
      if state == b.value then s = 1 else s = 0 end
      ImGui.PushID(ctx, i)
      if s == 0 then
          -- draw_color(rgba(b.col[1], b.col[2], b.col[3], b.col[4]))
          -- draw_color_fill(rgba(b.col[1], b.col[2], b.col[3], 0.1))
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),  rgba(195,105,105,0.2))
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), rgba(195,105,105,0.4))
          ImGui.PushStyleColor(ctx, ImGui.Col_Text(),  rgba(240,240,240,1))
          ImGui.PushStyleColor(ctx, ImGui.Col_Button(),rgba(100,100,100,0.8))
  
      else
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),  rgba(195,105,105,0.9))
          ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(),  rgba(205,105,105,0.8))
          ImGui.PushStyleColor(ctx, ImGui.Col_Button(),        rgba(195,105,105,0.6))
          ImGui.PushStyleColor(ctx, ImGui.Col_Text(),  rgba(224,224,224,1))
      end

    b.button = ImGui.Button(ctx, tostring(b.value), button_w, button_h)
    ImGui.SameLine(ctx)
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopID(ctx)
    
    if b.button then

        master_track = reaper.GetMasterTrack()
        index = reaper.TrackFX_AddByName(reaper.GetMasterTrack(), controller_fx, true, 100)
        if reaper.TrackFX_GetOpen(master_track, mon+index) then reaper.TrackFX_Show( master_track, mon+index, 2 ) end
        reaper.TrackFX_SetParam(master_track, index+mon, 0, b.value )
    end
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

    -- reaper.ImGui_SetNextWindowPos(ctx,600,600)
    -- reaper.ImGui_SetNextWindowSize(ctx, 300, 50)
    
    -- reaper.ImGui_SetNextWindowSize(ctx, tcp_w*(1/scale)-10, (button_h+8)*(1/scale))
    reaper.ImGui_SetNextWindowSize(ctx, tcp_w*(1/scale)+4, (button_h+8)*(1/scale))
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
