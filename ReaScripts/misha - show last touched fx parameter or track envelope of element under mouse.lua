-- @description Show last touched fx parameter or track envelope of element under mouse (volume, pan, width, send volume, fx wet)
-- @author Misha Oshkanov
-- @version 1.0
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
    reaper.Main_OnCommand(41142, 1) -- show last touched env
end
