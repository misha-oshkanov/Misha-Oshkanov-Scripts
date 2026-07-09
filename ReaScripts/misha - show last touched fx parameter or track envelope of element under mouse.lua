-- @description Show last touched fx parameter or track envelope of element under mouse (volume, pan, width, send volume, fx wet)
-- @author Misha Oshkanov
-- @version 1.2
-- @about
--    Show last touched fx parameter or track envelope of element under mouse

function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

local track, info = reaper.GetThingFromPoint(reaper.GetMousePosition())
local fxid = tonumber(info:match("fx:(%d+)"))
local fxid2 = tonumber(info:match("fx_(%d+)"))
local sendid = tonumber(info:match("send:(%d+)"))

function show_env(env)
    local retval, vis = reaper.GetSetEnvelopeInfo_String(env, 'VISIBLE', '', false)
    local retval, act = reaper.GetSetEnvelopeInfo_String(env, 'ACTIVE', '', false)

    local retval, stringNeedBig = reaper.GetSetEnvelopeInfo_String(env, 'VISIBLE', vis=='0' and 1 or 0, true)
    if act == "0" then 
        local retval, stringNeedBig = reaper.GetSetEnvelopeInfo_String(env, 'ACTIVE', 1, true)
    end
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)
end

if fxid then 
    if not reaper.ValidatePtr2(-1, track, 'MediaTrack*') then return end
    local parameterindex = reaper.TrackFX_GetParamFromIdent(track, fxid, ":wet")
    local env = reaper.GetFXEnvelope(track, fxid, parameterindex, false)
    if not env then
        local env = reaper.GetFXEnvelope(track, fxid, parameterindex, true)
    else
        show_env(env)
    end

elseif sendid then 
    if not reaper.ValidatePtr2(-1, track, 'MediaTrack*') then return end
    local env = reaper.GetTrackSendInfo_Value(track, 0, sendid, 'P_ENV:<VOLENV')
    show_env(env)
elseif info:find("pan") then
    if not reaper.ValidatePtr2(-1, track, 'MediaTrack*') then return end
    local env = reaper.GetMediaTrackInfo_Value(track, 'P_ENV:<PANENV2')
    show_env(env)
elseif info:find("volume") then  
    if not reaper.ValidatePtr2(-1, track, 'MediaTrack*') then return end
    local env = reaper.GetMediaTrackInfo_Value(track, 'P_ENV:<VOLENV2')
    show_env(env)
elseif info:find("width") then  
    if not reaper.ValidatePtr2(-1, track, 'MediaTrack*') then return end
    local env = reaper.GetMediaTrackInfo_Value(track, 'P_ENV:<WIDTHENV2')
    show_env(env)
 else
  if track and fxid2 and reaper.TrackFX_GetOpen(track, fxid2) then
    local x, y = reaper.GetMousePosition()
    local is_mac = reaper.GetOS():match("OSX") or reaper.GetOS():match("macOS")
    
    if is_mac then
      local _, _, _, _, _, _, _, max_y = reaper.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, false)
      y = max_y - y
    end
    
    local fx_window = reaper.TrackFX_GetFloatingWindow(track, fxid2)
    local window_under_mouse = reaper.JS_Window_FromPoint(reaper.JS_Window_ScreenToClient(reaper.GetMainHwnd(), x, y))
    
    if fx_window and window_under_mouse then
      local is_child = false
      local current = window_under_mouse
      while current and current ~= 0 do
        if current == fx_window then
          is_child = true
          break
        end
        current = reaper.JS_Window_GetParent(current)
      end
      
      if is_child then
        reaper.Main_OnCommand(reaper.NamedCommandLookup('_S&M_MOUSE_L_CLICK'), 0)
        reaper.TrackFX_SetOpen(track, fxid2, false)
      end
    end
  end
  reaper.Main_OnCommand(41142, 1) -- show last touched env
end