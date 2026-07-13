-- @description Sender
-- @author Misha Oshkanov
-- @version 2.0.1
-- @about
--   Ui panel for controlling sends for selected track
--   You should create folder for sends in the project (Name in Sends, Rhythm Sends, Special FX and etc.)
--   You can change send_folders table to add your own send folders


function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

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

function table_contains(table, element)
    for _, value in pairs(table) do
      if value == element then
        return true
      end
    end
    return false
end

send_folders = {
    {name = 'Sends',          open=1},
    {name = 'Rhythm Sends',   open=1},
    {name = 'Special FX',     open=1}
}
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3'
r = reaper

local ctx = reaper.ImGui_CreateContext('Sender')
local font = reaper.ImGui_CreateFont('arial', 15)
-- local font = reaper.ImGui_CreateFont('Microsoft Sans Serif', 16)

reaper.ImGui_Attach(ctx, font)

local isMac = reaper.GetOS():match('OSX') or reaper.GetOS():match('macOS')

active_type = {}
decode = {}

local sliders = {}
use_color = true
mode = 15
name_w = 80
title_colors = {r=30,g=30,b=30}
extname = "MISHA"
local EXT_SECTION = "MISHA_XY_PAD"

local last_click_time = 0
local double_click_threshold = 0.3 -- 300 мс для двойного клика
local is_double_click = false

reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_WindowsMoveFromTitleBarOnly(), 1 )

window_flags =  
reaper.ImGui_WindowFlags_NoFocusOnAppearing() +
reaper.ImGui_WindowFlags_NoNavFocus() +
reaper.ImGui_WindowFlags_NoNavInputs() +
reaper.ImGui_WindowFlags_NoScrollbar() 
-- reaper.ImGui_WindowFlags_NoMove()
-- reaper.ImGui_WindowFlags_NoScrollWithMouse() 
-- reaper.ImGui_WindowFlags_NoResize()

local xy_send_TL = nil -- Верхний левый
local xy_send_TR = nil -- Верхний правый
local xy_send_BL = nil -- Нижний левый
local xy_send_BR = nil -- Нижний правый

if xp_val == nil then xp_val = 0.5 end
if yp_val == nil then yp_val = 0.5 end

if xy_max_limit == nil then xy_max_limit = 1.0 end  -- Максимум (100%)
if xy_min_center == nil then xy_min_center = 0.25 end -- Минимум в центре (25%)
if xy_folder_open_state == nil then xy_folder_open_state = 0 end


local function SaveXYSliders()
    reaper.SetProjExtState(0, EXT_SECTION, "xy_min_center", xy_min_center)
    reaper.SetProjExtState(0, EXT_SECTION, "xy_max_limit",  xy_max_limit)
end 

local function LoadXYSliders()
    local _, xy_min_center_str = reaper.GetProjExtState(0, EXT_SECTION, "xy_min_center")
    local _, xy_max_limit_str  = reaper.GetProjExtState(0, EXT_SECTION, "xy_max_limit")
    if xy_min_center_str ~= "" then 
        xy_min_center = tonumber(xy_min_center_str)
    end
    if xy_max_limit_str ~= "" then 
        xy_max_limit = tonumber(xy_max_limit_str)
    end

end 

local function SaveXYPadState()
    local function GetTrackGUIDString(track)
        if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return "" end
        return reaper.GetTrackGUID(track)
    end

    local guid_TL = GetTrackGUIDString(xy_send_TL)
    local guid_TR = GetTrackGUIDString(xy_send_TR)
    local guid_BL = GetTrackGUIDString(xy_send_BL)
    local guid_BR = GetTrackGUIDString(xy_send_BR)

    reaper.SetProjExtState(0, EXT_SECTION, "guid_TL", guid_TL)
    reaper.SetProjExtState(0, EXT_SECTION, "guid_TR", guid_TR)
    reaper.SetProjExtState(0, EXT_SECTION, "guid_BL", guid_BL)
    reaper.SetProjExtState(0, EXT_SECTION, "guid_BR", guid_BR)
    reaper.SetProjExtState(0, EXT_SECTION, "xy_open_state", tostring(xy_folder_open_state))
end

local function LoadXYPadState()
    local function GetTrackByGUIDString(guid_str)
        if not guid_str or guid_str == "" then return nil end
        -- Проходим по всем трекам проекта в поисках нужного GUID
        local count = reaper.CountTracks(0)
        for i = 0, count - 1 do
            local track = reaper.GetTrack(0, i)
            if reaper.GetTrackGUID(track) == guid_str then
                return track
            end
        end
        return nil
    end

    local _, saved_open = reaper.GetProjExtState(0, EXT_SECTION, "xy_open_state")
    if saved_open and saved_open ~= "" then
        xy_folder_open_state = tonumber(saved_open)
    end

    local _, guid_TL = reaper.GetProjExtState(0, EXT_SECTION, "guid_TL")
    local _, guid_TR = reaper.GetProjExtState(0, EXT_SECTION, "guid_TR")
    local _, guid_BL = reaper.GetProjExtState(0, EXT_SECTION, "guid_BL")
    local _, guid_BR = reaper.GetProjExtState(0, EXT_SECTION, "guid_BR")

    xy_send_TL = GetTrackByGUIDString(guid_TL)
    xy_send_TR = GetTrackByGUIDString(guid_TR)
    xy_send_BL = GetTrackByGUIDString(guid_BL)
    xy_send_BR = GetTrackByGUIDString(guid_BR)
end

function decode(encodedInt)
    local mask = 0xFFFF -- Mask to extract the lower 2 bytes
    local firstInteger = encodedInt & mask
    local secondInteger = (encodedInt >> 16) & mask
    local dec = {firstInteger,secondInteger}
    return dec
end 

function trunc(num, digits)
    local mult = 10^(digits)
    return math.modf(num*mult)/mult
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

function scroll_to_track(track)
    mainHWND = reaper.GetMainHwnd()
    windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
    reaper.PreventUIRefresh( 1 )
    local track_tcpy = reaper.GetMediaTrackInfo_Value( track, "I_TCPY" )
    local scroll_retval, scroll_position, scroll_pageSize, scroll_min, scroll_max, scroll_trackPos = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
    reaper.SetOnlyTrackSelected(track)
    reaper.SetMixerScroll(track)
    reaper.JS_Window_SetScrollPos( windowHWND, "v", track_tcpy + scroll_position)
    reaper.TrackList_AdjustWindows(true)
    reaper.PreventUIRefresh( -1 )
end

data = {}
pinned_mode = false
LoadXYPadState()
LoadXYSliders()


function rgba(r, g, b, a)
    local b = b/255
    local g = g/255 
    local r = r/255 
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

function col_sat(col,sat)
    sat = math.ceil(255 * sat)
    r, g, b = reaper.ColorFromNative(col)
    h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)
    if v < 100 then 
        v = 180 - v
        r, g, b = reaper.ImGui_ColorConvertHSVtoRGB( h, s, v )
    end 

    if sat > 0 then 
        r = math.min(r+sat,255)
        g = math.min(g+sat,255)
        b = math.min(b+sat,255)
    else
        r = math.max(r+sat,0)
        g = math.max(g+sat,0)
        b = math.max(b+sat,0)
    end

    result = rgba(r,g,b,1)
    return result
end

function draw_text(text)
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddText(draw_list, min_x+10, max_y+10, rgba(250, 102, 102, 1), text)
end

function draw_color_fill(color)
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRectFilled(draw_list, max_x, min_y, max_x+40, max_y, color)
end

function draw_color(color,px)
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x, max_y,  color,0,0,px)
end

function get_parent(track)
    depth = reaper.GetTrackDepth( track )
    for d=1,depth do 
        track =  reaper.GetParentTrack(track)
    end 
    return track
end

function get_parentnames_table(track)
    local parentlist = {}
    local oldparent
    local parent = get_parent(track)
    if parent ~= oldparent then
        local _, name = reaper.GetTrackName(parent)
        local name = remove_arch_prefix(name)
        table.insert(parentlist, name)
    end
        oldparent = parent
    return parentlist
end

function get_children(parent)
    if parent then 
        local parentdepth = reaper.GetTrackDepth(parent)
        local parentnumber = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
        local children = {}
        for i=parentnumber, reaper.CountTracks(0)-1 do
                local track = reaper.GetTrack(0,i)
                local depth = reaper.GetTrackDepth(track)
                if depth > parentdepth then
                    table.insert(children, track)
                else
                    break
                end
        end
        return children
    end
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

function get_sends(track)
    local count_sends = reaper.GetTrackNumSends(track, 0)
    local sends = {}
    if count_sends > 0 then 
        for s=1, count_sends do 
            local send_data = {}
            local vol = reaper.GetTrackSendInfo_Value(track, 0, s-1, 'D_VOL')
            local pan = reaper.GetTrackSendInfo_Value(track, 0, s-1, 'D_PAN')
            local dest = reaper.GetTrackSendInfo_Value(track, 0, s-1, 'P_DESTTRACK')
            local mode = reaper.GetTrackSendInfo_Value(track, 0, s-1, 'I_SENDMODE')
            local _, mute = reaper.GetTrackSendUIMute(track, s-1)
            local _, name = reaper.GetTrackSendName(track, s-1)
            
            send_data.vol  = vol
            send_data.pan  = pan
            send_data.dest = dest
            send_data.mode = mode
            send_data.mute = mute
            send_data.name = name
            send_data.id = s-1

            table.insert(sends, send_data)
        end
        return sends
    end
end

function get_receives(track)
    local count_receives = reaper.GetTrackNumSends(track, -1)
    local receives = {}
    if count_receives > 0 then 
        for r=1, count_receives do 
            local receive_data = {}
            local vol = reaper.GetTrackSendInfo_Value(track, -1, r-1, 'D_VOL')
            local dest = reaper.GetTrackSendInfo_Value(track, -1, r-1, 'P_SRCTRACK')
            local mode = reaper.GetTrackSendInfo_Value(track, -1, r-1, 'I_SENDMODE')
            local mute = reaper.GetTrackSendInfo_Value(track, -1, r-1, 'B_MUTE')
        
            local color = reaper.GetTrackColor(dest)
            if color == 0 then color = '28290987' end
            local _, name = reaper.GetTrackReceiveName(track, r-1)
            
            receive_data.vol  = vol
            receive_data.dest = dest
            receive_data.mode = mode
            receive_data.mute = mute
            receive_data.name = name
            receive_data.color = color
            receive_data.id = r-1

            table.insert(receives, receive_data)
        end
    end
    return receives
end

function get_send_id_by_dest(track,dest_track)
    if not track or not dest_track then return -1 end
    local count_sends = reaper.GetTrackNumSends(track, 0)
    if count_sends > 0 then 
        for s=0, count_sends do 
        local dest = reaper.GetTrackSendInfo_Value(track, 0, s, 'P_DESTTRACK')
        if dest == dest_track then return s end
        end 
    end
    return -1
end

function key_down()
    local key = reaper.JS_Mouse_GetState(95)
    if key == 4 or key == 5 then return 'ctrl'
    elseif key == 8 or key == 9 then return 'shift'
    elseif key == 16 or key == 17 then return 'alt'
    else return nil 
    end
end

gfx_c_value = 0.8
coeff_value = 80

function VF_lim(val, min,max) if not min or not max then min, max = 0,1 end return math.max(min,  math.min(val, max) )  end

function Convert_Val2Fader(rea_val)
    if not rea_val then return end 
    local rea_val = VF_lim(rea_val, 0, 4)
    local val 
    local gfx_c, coeff = gfx_c_value, coeff_value
    local real_dB = 20*math.log(rea_val, 10)
    local lin2 = 10^(real_dB/coeff)  
    if lin2 <=1 then val = lin2*gfx_c else val = gfx_c + (real_dB/12)*(1-gfx_c) end
    if val > 1 then val = 1 end
    return VF_lim(val, 0.0001, 1)
end

function Convert_Fader2Val(fader_val)
    local fader_val = VF_lim(fader_val,0,1)
    local gfx_c, coeff = gfx_c_value, coeff_value
    local val
    if fader_val <=gfx_c then
      local lin2 = fader_val/gfx_c
      local real_dB = coeff*math.log(lin2, 10)
      val = 10^(real_dB/20)
     else
      local real_dB = 12 * (fader_val  / (1 - gfx_c) - gfx_c/ (1 - gfx_c))
      val = 10^(real_dB/20)
    end
    if val > 4 then val = 4 end
    if val < 0 then val = 0 end
    return val
end


function remove_arch_prefix(string)
    return string:gsub('_','')
end

function toggle_mute_all_sends(track,state)
    local sends = get_sends(track)
    if not sends then return end
    if sends then 
        for k,s in ipairs(sends) do 
            local found = false
            local parents = get_parentnames_table(s.dest)
            for k1,s1 in ipairs(send_folders) do 
                if table_contains(parents,s1.name) then found = true end 
            end 
            if found then reaper.SetTrackSendInfo_Value(track, 0, k-1, 'B_MUTE', state==true and 1 or 0) end
        end 
    end 
end 


function get_env_dest(track,desttr0)
    for envidx = 1, reaper.CountTrackEnvelopes(track) do
        local envelope = reaper.GetTrackEnvelope(track, envidx-1)
        local desttr = reaper.GetEnvelopeInfo_Value(envelope, 'P_DESTTRACK')
        if desttr == desttr0 then
        return envelope 
      end
    end
end

function OD_ToggleShowEnvelope(env, show) --- from Odedd: Send Buddy
    local ret, chunk = reaper.GetEnvelopeStateChunk(env, '', false)
    if chunk then
        local nchunk
        if show == nil and chunk:find('VIS 1') then show = false else show = true end
        if show == true then
            nchunk = string.gsub(chunk, 'ACT 0', 'ACT 1')
            nchunk = string.gsub(nchunk, 'VIS 0', 'VIS 1')
            nchunk = string.gsub(nchunk, 'ARM 0', 'ARM 1')
            if not nchunk:find('PT') then nchunk = nchunk:gsub('>', 'PT 0 1 0\n>') end
        elseif show == false then
            nchunk = string.gsub(chunk, 'ACT 1', 'ACT 0')
            nchunk = string.gsub(nchunk, 'VIS 1', 'VIS 0')
            nchunk = string.gsub(nchunk, 'ARM 1', 'ARM 0')
        end
        reaper.SetEnvelopeStateChunk(env, nchunk, true)
    end
end

function get_send_folders_data()
    local folder_data = {}
    local count = reaper.CountTracks(0)
    
    for i = 1, count do 
        local track = reaper.GetTrack(0, i - 1)
        local is_parent = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH') == 1
        
        if is_parent then 
            local _, parent_name = reaper.GetTrackName(track)
            parent_name = parent_name:gsub('_', '')
            
            for i2 = 1, #send_folders do
                local config = send_folders[i2]
                if parent_name == config.name then 
                    local parent_color = reaper.GetTrackColor(track)
                    local children_tracks = get_children(track) or {}
                    
                    local children_with_colors = {}
                    for c = 1, #children_tracks do
                        local child = children_tracks[c]
                        table.insert(children_with_colors, {
                            track = child,
                            color = reaper.GetTrackColor(child) -- Запоминаем цвет трека заранее
                        })
                    end
                    
                    table.insert(folder_data, {
                        name = parent_name,
                        color = parent_color,
                        open_config = config.open,
                        children = children_with_colors -- Теперь здесь таблица объектов {track, color}
                    })
                    break 
                end 
            end
        end
    end
    
    return folder_data
end


function draw_send_folder_slots(folder_data, sel_track)
    for i = 1, #folder_data do
        local folder = folder_data[i]
        local open_flag = folder.open_config == 1 and reaper.ImGui_TreeNodeFlags_DefaultOpen() or 0

        local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
        local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        reaper.ImGui_DrawList_AddRectFilled(draw_list, min_x, max_y - 10, min_x + w - 17, max_y, col(folder.color, 0.6))
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), col(folder.color, 1))
        
        if reaper.ImGui_TreeNode(ctx, folder.name, reaper.ImGui_TreeNodeFlags_SpanFullWidth() + open_flag) then
            for i3 = 1, #folder.children do 
                reaper.ImGui_PushID(ctx, i3)
                local child = folder.children[i3].track
                
                send_slot(child, sel_track) 
                
                reaper.ImGui_PopID(ctx)
            end
            reaper.ImGui_TreePop(ctx) 
        end
        
        reaper.ImGui_Dummy(ctx, 4, 10)
        reaper.ImGui_PopStyleColor(ctx)
    end
end

function calculate_text_fxnames(dest_track)
    local fx_count = reaper.TrackFX_GetCount(dest_track)
    local name_w = 90
    if fx_count > 0 then 
        for fx=1,fx_count do 
            local _, fx_name = reaper.TrackFX_GetFXName(dest_track, fx-1)
            fx_name =  fx_name:gsub('.-%:', ''):gsub('%(.-%)$', ''):gsub("^%s+", ''):gsub("%s+$", '')
            tw, _ = reaper.ImGui_CalcTextSize(ctx, fx_name)
            if tw > name_w then name_w = tw end
        end 
    end
    return name_w
end

function count_active_sends(track)
    local sendnum = reaper.GetTrackNumSends(track, -1)
    local count = 0
    for i=0, sendnum-1 do 
        local _, mute = reaper.GetTrackReceiveUIMute(track, i)
        local _, receive_name = reaper.GetTrackReceiveName(track, i)

        if not mute and not receive_name:find('_') then count = count + 1 end 
    end
    return count
end

mute_states = {}

function send_slot(dest_track,sel_track)
    local _, name = reaper.GetTrackName(dest_track)
    local _, mute = reaper.GetTrackUIMute(dest_track)
    local solo = reaper.GetMediaTrackInfo_Value(dest_track, 'I_SOLO') > 0
    color = reaper.GetTrackColor(dest_track)
    local arch = name:sub(1,1) == '_'
    if arch then return end

    local sendnum = count_active_sends(dest_track)
    
    if solo then 
        text_color = rgba(255,216,50,1)
        val_color = rgba(255,216,50,1)
    else 
        text_color = rgba(255,255,255,1)
        val_color = col_sat(color,0.1)
    end
    
    local vol = 0
    local a = 0
    local pan = 0
    local name_w = 100
    
    if sel_track then 
        found = false
        sends = get_sends(sel_track)
        if sends then 
            for k,s in ipairs(sends) do 
                if dest_track == s.dest then 
                    if s.mute then 
                        text_color = rgba(255, 255, 255, 0.4) 
                        val_color = rgba(255, 255, 255, 0.4) 
                    end
                    vol = s.vol
                    pan = s.pan
                    id = s.id
                    found = true
                    a = 0.7
                    break
                end
            end
        end
    end
    
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_SliderGrab(),              col(color,0))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_SliderGrabActive(),        col(color,0))

    if found then 
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBg(),              col(color,math.max(a-0.5,0)))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgHovered(),       col(color,math.max(a-0.4,0)))
    else 
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBg(),              col(color,0.1))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgHovered(),       col(color,math.max(a-0.2,0.2)))
    end
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgActive(),            col(color,math.max(a-0.3,0)))
    reaper.ImGui_PushItemWidth(ctx, w-17)
    
    slider_retval, slider_value = reaper.ImGui_SliderDouble(ctx, '##slider'..tostring(dest_track), Convert_Val2Fader(vol), 0, 1,'',reaper.ImGui_SliderFlags_None()+
    reaper.ImGui_SliderFlags_NoInput())

    reaper.ImGui_PopItemWidth(ctx)
    reaper.ImGui_PopStyleColor(ctx,5)

    if ImGui.IsItemHovered(ctx) and (key_down()=='shift' or key_down()=='ctrl') then
        local wheel = ImGui.GetMouseWheel(ctx)
        if wheel ~= 0 then
            if found then 
                if vol > 0.03 then 
                    reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_VOL', dbToNormalized(VAL2DB(vol) + (wheel * 0.5)))
                else 
                    reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_VOL', dbToNormalized(VAL2DB(vol) + (wheel * 2)))
                end
            else 
               local new_send = reaper.CreateTrackSend(sel_track, dest_track) 
               reaper.SetTrackSendInfo_Value(sel_track, 0, new_send, 'D_VOL', dbToNormalized(-10))
            end
        end 
    end 

    if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) then 
        reaper.ImGui_OpenPopup(ctx, 'fx_popup')    
    end

    if reaper.ImGui_BeginPopup(ctx, 'fx_popup',reaper.ImGui_WindowFlags_NoMove()) then
        -- pw, ph = reaper.ImGui_GetWindowSize(ctx)
        pw, ph = reaper.ImGui_GetContentRegionAvail(ctx)
        px, py = reaper.ImGui_GetWindowPos(ctx)
        name_w = calculate_text_fxnames(dest_track)
        if name_w then 
            local scroll_to_button = reaper.ImGui_Button(ctx, 'Go to', (name_w/2)+19,24)
            if scroll_to_button then 
                pinned_mode = true
                pinned_track = sel_track
                scroll_to_track(dest_track)
            end
            reaper.ImGui_SameLine(ctx)
            local env_button = reaper.ImGui_Button(ctx, 'Env', (name_w/2)+19,24)
            if env_button then 
                local env = reaper.GetTrackSendInfo_Value(sel_track, 0, id, "P_ENV:<VOLENV")
                OD_ToggleShowEnvelope(env,true)
                reaper.ImGui_CloseCurrentPopup(ctx)
            end 

            reaper.ImGui_SetNextItemWidth( ctx, pw)
            send_retval, send_pan = reaper.ImGui_SliderDouble(ctx, '##pan', pan, -1, 1, math.floor(trunc(pan,2)*100), reaper.ImGui_SliderFlags_NoInput())

            if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) then 
                reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_PAN', 0)
            end

            if send_retval then reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_PAN', send_pan) end
            reaper.ImGui_PushStyleVar(ctx,  reaper.ImGui_StyleVar_ItemSpacing(),2,2)

            local fx_count = reaper.TrackFX_GetCount(dest_track)
            if fx_count > 0 then 
                for fx=1,fx_count do 
                    reaper.ImGui_PushID(ctx, fx-1)
                    local _, fx_name = reaper.TrackFX_GetFXName(dest_track, fx-1)
                    local fx_enabled = reaper.TrackFX_GetEnabled(dest_track, fx-1)

                    if fx_enabled then fx_text_color = rgba(255,255,255,1) else fx_text_color = rgba(140,140,140,1) end

                    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Text(),          fx_text_color)

                    fx_name =  fx_name:gsub('.-%:', ''):gsub('%(.-%)$', ''):gsub("^%s+", ''):gsub("%s+$", '')
                    -- tw, _ = reaper.ImGui_CalcTextSize(ctx, fx_name)
                    -- if tw > name_w then name_w = tw end

                    local fx_button = reaper.ImGui_Button(ctx, fx_name,pw)
                    if fx_button then 
                        if key_down() == 'shift' then 
                            reaper.TrackFX_SetEnabled(dest_track, fx-1, not fx_enabled)
                        else 
                        reaper.ImGui_CloseCurrentPopup(ctx)
                        reaper.TrackFX_SetOpen(dest_track, fx-1, 1)
                        end
                    end 
                    reaper.ImGui_PopStyleColor(ctx)
                    reaper.ImGui_PopID(ctx)
                end
                reaper.ImGui_Dummy(ctx, 2, 2)

            end
        end
        reaper.ImGui_Dummy(ctx, 2, 2)

        local receives = get_receives(dest_track)
        reaper.ImGui_SeparatorText( ctx, "Receives" )
        for ir,r in ipairs(receives) do 
            reaper.ImGui_PushID(ctx, ir-1)
            reaper.ImGui_SetNextItemWidth(ctx, pw)

            if r.mute == 1 and r then rc = rgba(255, 255, 255, 0.4) else rc = rgba(255, 255, 255, 1) end

            reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_SliderGrab(),               col(r.color,0))
            reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_SliderGrabActive(),         col(r.color,0))
            reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBg(),                  col(r.color,math.max(a-0.5,0)))
            reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgHovered(),           col(r.color,math.max(a-0.4,0)))
            reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgActive(),            col(r.color,math.max(a-0.3,0)))

            rslider_retval, rslider_value = reaper.ImGui_SliderDouble(ctx, '##rslider'..tostring(r.dest), Convert_Val2Fader(r.vol), 0, 1,'',reaper.ImGui_SliderFlags_None()+
            reaper.ImGui_SliderFlags_NoInput())

            if rslider_retval then 
                reaper.SetTrackSendInfo_Value(dest_track, -1, r.id, 'D_VOL', Convert_Fader2Val(rslider_value))
            end 

            pmin_x, pmin_y = reaper.ImGui_GetItemRectMin(ctx)
            pmax_x, pmax_y = reaper.ImGui_GetItemRectMax(ctx)
            pdraw_list = reaper.ImGui_GetWindowDrawList(ctx)
            
            reaper.ImGui_PopStyleColor(ctx,5)
            
            local draw_rslider_r = (pmax_x-pmin_x)-((pmax_x-pmin_x)*(rslider_value))
            ImGui.DrawList_AddRectFilled(pdraw_list, pmin_x, pmin_y, pmax_x - draw_rslider_r, pmax_y, col(r.color,0.2))
            reaper.ImGui_DrawList_AddText(pdraw_list, px+14, pmin_y+4, rc, r.name)
            
            r_text_value = tostring(trunc(VAL2DB(r.vol),1))
            r_text_w, _ = reaper.ImGui_CalcTextSize(ctx, r_text_value)
            reaper.ImGui_DrawList_AddText(pdraw_list, (px+pw-14)-r_text_w, pmin_y+4, col(r.color,1), r_text_value)

            if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left()) then 
                if key_down() == 'alt' then 
                    reaper.RemoveTrackSend(dest_track, -1, r.id)                    
                elseif key_down() == 'shift' then 
                    reaper.SetTrackSendInfo_Value(dest_track, -1, r.id, 'B_MUTE', r.mute==1 and 0 or 1)
                elseif key_down() == 'ctrl' then 
                    if reaper.AnyTrackSolo(0) and not solo then reaper.Main_OnCommand(40340, 0) end
                    reaper.SetMediaTrackInfo_Value(dest_track, 'I_SOLO', reaper.GetMediaTrackInfo_Value(dest_track, 'I_SOLO')==2 and 0 or 2)
                end
                if reaper.ImGui_IsMouseDoubleClicked( ctx, reaper.ImGui_MouseButton_Left() ) then 
                    reaper.SetTrackSendInfo_Value(dest_track, -1, r.id, 'D_VOL', 1)
                end
            end
            reaper.ImGui_PopID(ctx)
        end
        
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_EndPopup(ctx)
    end
    local current_time = reaper.time_precise()

    if slider_retval and (key_down() == nil or key_down() == 1) then 
        
        if found then 
            reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_VOL', Convert_Fader2Val(slider_value))
        else 
            reaper.CreateTrackSend(sel_track, dest_track)
        end
    end
    
    if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left()) and found then 
        if key_down() == 'alt' then 
            reaper.RemoveTrackSend(sel_track, 0, get_send_id_by_dest(sel_track,dest_track))
        elseif key_down() == 'shift' then 
            reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'B_MUTE', reaper.GetTrackSendInfo_Value(sel_track, 0, id, 'B_MUTE')==1 and 0 or 1)
        elseif key_down() == 'ctrl' then 
            if reaper.AnyTrackSolo(0) and not solo then reaper.Main_OnCommand(40340, 0) end
            reaper.SetMediaTrackInfo_Value(dest_track, 'I_SOLO', reaper.GetMediaTrackInfo_Value(dest_track, 'I_SOLO')==2 and 0 or 2)
        end
        if reaper.ImGui_IsMouseDoubleClicked( ctx, reaper.ImGui_MouseButton_Left() ) then 
            reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_VOL', 1)
            reaper.SetCursorContext( 1, nil )
        end
    end

    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    
    local draw_slider_r = (max_x-min_x)-((max_x-min_x)*(slider_value))
    ImGui.DrawList_AddRectFilled(draw_list, min_x, min_y, max_x - draw_slider_r, max_y, col(color,0.3))
    if sendnum > 0 then 
        sendnum_text_w = reaper.ImGui_CalcTextSize(ctx, sendnum)
        reaper.ImGui_DrawList_AddText(draw_list, x+14+sendnum_text_w, min_y+2, text_color, name)
        reaper.ImGui_DrawList_AddText(draw_list, x+10, min_y+2, val_color, sendnum)
    else 
        reaper.ImGui_DrawList_AddText(draw_list, x+14, min_y+2, text_color, name)
    end
    
    if found then 
        text_value = trunc(VAL2DB(vol),1)
        if VAL2DB(vol) < -60 then
            text_value = '-inf'
        end    
    else 
        text_value = '+'
    end
    text_w, _ = reaper.ImGui_CalcTextSize(ctx, text_value)
    reaper.ImGui_DrawList_AddText(draw_list, (x+w-14)-text_w, min_y+2, val_color, text_value)
    if solo then draw_color(rgba(255,216,50,0.6),1) end
end

presets = {}
all_sends_vols = {}

function frame()
    sel_track = reaper.GetSelectedTrack(0, 0)
    all_clicked = false
    local a = 0.5
    if not pinned_mode then 
        target_track = sel_track
    else 
        target_track = pinned_track 
        a = 0.6
    end
    if target_track then
        mute_state = get_slot_mute_state(target_track)
        _, target_track_name = reaper.GetTrackName(target_track)
        if pinned_mode then target_track_name = target_track_name.. ' (Pin)' end
        target_color = reaper.GetTrackColor(target_track)
        if target_color == 0 then target_color = '28290987' end

        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Button(),          col(target_color,a))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonHovered(),   col(target_color,a+0.1))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonActive(),    col(target_color,a))

        track_button  = reaper.ImGui_Button(ctx, target_track_name, w-17, 30 )
        if pinned_mode then 
            draw_color(col(target_color,0.7),2)
        end            

        if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) then reaper.ImGui_OpenPopup(ctx, 'pin_popup')   end 
        reaper.ImGui_PopStyleColor(ctx,3)

        
        reaper.ImGui_PushStyleVar(ctx,  reaper.ImGui_StyleVar_ItemSpacing(),2,2)
        local scroll_to_button = reaper.ImGui_Button(ctx, 'Go to track', w-17,  24)
            -- reaper.ImGui_Dummy(ctx, 2, 2)

        local bypass_button = reaper.ImGui_Button(ctx, 'Mute all', w/2-9, 24)
        reaper.ImGui_SameLine(ctx)
        local remove_button = reaper.ImGui_Button(ctx, 'Remove all', w/2-10, 24)

        -- reaper.ImGui_Dummy(ctx, 4, 10)
        local current_folders = get_send_folders_data()

        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_SliderGrab(),              col(target_color,0.4))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_SliderGrabActive(),        col(target_color,0.5))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBg(),                 col(target_color,0.2))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgHovered(),          col(target_color,0.4))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgActive(),           col(target_color,0.5))

        local xy_open_flags = reaper.ImGui_TreeNodeFlags_SpanFullWidth()
        if xy_folder_open_state == 1 then
            xy_open_flags = xy_open_flags + reaper.ImGui_TreeNodeFlags_DefaultOpen()
        end
        
        reaper.ImGui_Dummy(ctx, 2, 4)

        xy = reaper.ImGui_TreeNode(ctx, "XY", xy_open_flags)
        if xy then 
            xy_folder_open_state = 1
            local s1, s2, s3, s4 = DrawXYPad(ctx, w-16, 180, current_folders, target_track, target_color)
            reaper.ImGui_TreePop(ctx)
        else 
            xy_folder_open_state = 0
        end
        reaper.ImGui_Dummy(ctx, 2, 4)

        for preset=1,4 do 
            reaper.ImGui_PushID(ctx, preset)

            local preset_ret, _ = reaper.GetProjExtState(0, extname, 'P'..preset)
            if preset_ret == 1 then 
                preset_button_color = target_color
            else 
                preset_button_color = reaper.ColorToNative(50, 50, 50)
            end

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),       col(preset_button_color,0.5))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),col(preset_button_color,0.8))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col(preset_button_color,0.7))

            preset_button = reaper.ImGui_Button(ctx, tostring(preset), w/4-6, 24)
            if preset < 4 then reaper.ImGui_SameLine(ctx) end

            if preset_button then 
                if key_down() == 'alt' then remove_preset(preset) else
                    if preset_ret == 1 then 
                        load_preset(preset,target_track)
                    else 
                        save_preset(preset,target_track)
                    end 
                end
            end
            reaper.ImGui_PopStyleColor(ctx,3)
            reaper.ImGui_PopID(ctx)
        end
        
        reaper.ImGui_SetNextItemWidth( ctx, w-17)

        all_retval, all_adjust_slider = reaper.ImGui_SliderDouble(ctx, '##all', all_vol, -0.8, 0.8,'',reaper.ImGui_SliderFlags_None()+
        reaper.ImGui_SliderFlags_NoInput())

        if reaper.ImGui_IsItemHovered(ctx) then 
            if not all_retval and reaper.ImGui_IsMouseDown( ctx,reaper.ImGui_MouseButton_Left()) then 
                all_vol = 0
                save_sends_states(target_track)
            end
        end

        if all_retval then 
            adjust_all_sends(target_track,all_adjust_slider)
        end

        if scroll_to_button then scroll_to_track(target_track) end
        if bypass_button then 
            set_slot_mute_state(target_track,not mute_state)
            toggle_mute_all_sends(target_track,not mute_state)
            reaper.ImGui_CloseCurrentPopup(ctx)
        end 
        if remove_button then
            reaper.Undo_BeginBlock()
            remove_all_sends(target_track) reaper.ImGui_CloseCurrentPopup(ctx) 
            reaper.Undo_EndBlock( 'Sender: Remove sends', -1)
        end
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_PopStyleColor(ctx,5)

        
        reaper.ImGui_Dummy(ctx, 4, 10)
        if track_button then 
            pinned_mode = not pinned_mode 
            pinned_track = target_track
        end 
        draw_send_folder_slots(current_folders, target_track)
    end
end 

function save_sends_states(track)
    local sends = get_sends(track)
    if not sends then return end
    if sends then
        for k,s in ipairs(sends) do 
            local found = false
            local parents = get_parentnames_table(s.dest)
            for k1,s1 in ipairs(send_folders) do 
                if table_contains(parents,s1.name) then 
                    found = true 
                end 
            end 
            if found then 
                local data = {}
                data.id = s.id 
                data.vol = s.vol 
                table.insert(all_sends_vols, data)
            end 
        end 
    end 
end 

function adjust_all_sends(track,val)
    for k,s in ipairs(all_sends_vols) do 
        reaper.SetTrackSendInfo_Value(track, 0, s.id, 'D_VOL', s.vol + val)
    end 
end 

function remove_all_sends(track)
    local sends = get_sends(track)
    if not sends then return end
    local ids = {}
    if sends then
        for k,s in ipairs(sends) do 
            local found = false
            local parents = get_parentnames_table(s.dest)
            for k1,s1 in ipairs(send_folders) do 
                if table_contains(parents,s1.name) then found = true end 
            end 
            if found then 
                table.insert(ids,s.id)
            end
        end 
        for id=1,#ids do 
            reaper.RemoveTrackSend(track, 0, ids[id]-(id-1))
        end
    end 
end 

function get_slot_mute_state(dest_track)
    local found = false 
    for mute=1,#mute_states do 
        if mute_states[mute].dest == dest_track then
            found = true
            id = mute
            break
        end 
    end
    if found then return mute_states[id].state else return false end
end

function set_slot_mute_state(dest_track,state)
    local found = false 
    for mute=1,#mute_states do 
        if mute_states[mute].dest == dest_track then 
           found = true 
            mute_states[mute].state = state
            return
        end 
    end 
    if not found then 
        local data = {}
        data.dest = dest_track
        data.state = state 
        table.insert(mute_states, data)
    end
end

function save_preset(preset,target_track)
    local sends = get_sends(target_track)
    if not sends then return end
    local data = {}
    for k,s in ipairs(sends) do 
        local found = false
        local parents = get_parentnames_table(s.dest)
        for k1,s1 in ipairs(send_folders) do 
            if table_contains(parents,s1.name) then 
                found = true 
            end 
        end 
        if found then 
            local _, guid = reaper.GetSetMediaTrackInfo_String(s.dest, 'GUID', '', false )
            local str = string.format("{dest=%s,vol=%.14f,mute=%s,mode=%s}", 
            guid, s.vol, tostring(s.mute), tostring(s.mode))
            table.insert(data, str)
        end
    end
    reaper.SetProjExtState(0, extname, "P"..preset, table.concat(data, ";"))
end 

function load_preset(preset,target_track)
    local _, str = reaper.GetProjExtState(0, extname, "P"..preset)
    str = str:match("{(.*)}")
    local items = {}
    for item in str:gmatch("[^;]+") do table.insert(items, item) end
    remove_all_sends(target_track)
    for i, entry in ipairs(items) do
        local dest = entry:match('dest=({.-})')
        local vol = tonumber(entry:match('vol=([%d%.]+)'))
        local mute = entry:match('mute=([01])')  or 0
        local mode = tonumber(entry:match('mode=([%d%.]+)')) or 0.0

        local send_id = reaper.CreateTrackSend(target_track, reaper.BR_GetMediaTrackByGUID(0, dest))
        reaper.SetTrackSendInfo_Value(target_track, 0, send_id, "D_VOL", vol)
        reaper.SetTrackSendInfo_Value(target_track, 0, send_id, "B_MUTE", mute)
        reaper.SetTrackSendInfo_Value(target_track, 0, send_id, "I_SENDMODE", mode)
    end
end

function remove_preset(preset)
    reaper.SetProjExtState(0, extname, "P"..preset, "" )
end 

function GetSendIndexByTarget(src_track, target_track)
    if not src_track or not target_track then return -1 end
    local send_count = reaper.GetTrackNumSends(src_track, 0) -- 0 = обычные посылы (sends)
    for s = 0, send_count - 1 do
        local current_target = reaper.GetTrackSendInfo_Value(src_track, 0, s, "P_DESTTRACK")
        if current_target == target_track then
            return s
        end
    end
    return -1
end

function DrawXYPad(ctx, width, height, folder_data, sel_track, sel_track_color)
    reaper.ImGui_BeginGroup(ctx)
    local sliders_active = false
    if xy_send_TL and xy_send_TR and xy_send_BL and xy_send_BR then all_selected = true else all_selected = false end

    if all_selected then 
        reaper.ImGui_PushItemWidth(ctx, width)
        local changed_min, val_min = reaper.ImGui_SliderDouble(ctx, "##xymin", xy_min_center * 100, 1, 100.0,"Center:        ".. "%.0f %%", reaper.ImGui_SliderFlags_NoInput())
        local active_min = reaper.ImGui_IsItemActive(ctx)
        if changed_min then xy_min_center = val_min / 100 SaveXYSliders() end
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, reaper.ImGui_MouseButton_Right()) then
            xy_min_center = 0.25
            SaveXYSliders()
        end

        local changed_max, val_max = reaper.ImGui_SliderDouble(ctx, "##xymax", xy_max_limit * 100, 5, 200.0,"Corners:         ".."%.0f %%", reaper.ImGui_SliderFlags_NoInput())
        if changed_max then xy_max_limit = val_max / 100 SaveXYSliders() end
        local active_max = reaper.ImGui_IsItemActive(ctx)
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, reaper.ImGui_MouseButton_Right()) then
            xy_max_limit = 1.0 -- Дефолтное значение (100%)
            SaveXYSliders()
        end
        reaper.ImGui_Dummy(ctx,1,2)
        reaper.ImGui_PopItemWidth(ctx)
        sliders_active = active_max or active_min
    end
    
    local start_x, start_y = reaper.ImGui_GetCursorScreenPos(ctx)
    reaper.ImGui_InvisibleButton(ctx, "##xypad", width, height)
    local is_active = reaper.ImGui_IsItemActive(ctx)
    local is_hovered = reaper.ImGui_IsItemHovered(ctx)
    
    local any_active = is_active or sliders_active

    if not any_active and sel_track and reaper.ValidatePtr(sel_track, "MediaTrack*") then
        local s_TL = GetSendIndexByTarget(sel_track, xy_send_TL)
        local s_TR = GetSendIndexByTarget(sel_track, xy_send_TR)
        local s_BL = GetSendIndexByTarget(sel_track, xy_send_BL)
        local s_BR = GetSendIndexByTarget(sel_track, xy_send_BR)
        
        local v_TL = s_TL >= 0 and reaper.GetTrackSendInfo_Value(sel_track, 0, s_TL, "D_VOL") or 0.0
        local v_TR = s_TR >= 0 and reaper.GetTrackSendInfo_Value(sel_track, 0, s_TR, "D_VOL") or 0.0
        local v_BL = s_BL >= 0 and reaper.GetTrackSendInfo_Value(sel_track, 0, s_BL, "D_VOL") or 0.0
        local v_BR = s_BR >= 0 and reaper.GetTrackSendInfo_Value(sel_track, 0, s_BR, "D_VOL") or 0.0
        
        local function ReverseAdvancedWeight(v)
            if v <= 0 then return 0.0 end
            if v <= xy_min_center then
                if xy_min_center > 0.001 then
                    return (v / xy_min_center) * 0.25
                else
                    return 0.0
                end
            else
                local denom = xy_max_limit - xy_min_center
                if math.abs(denom) > 0.001 then
                    local factor = (v - xy_min_center) / denom
                    return 0.25 + (factor * 0.75)
                else
                    return 0.25
                end
            end
        end
        local w_TL = ReverseAdvancedWeight(v_TL)
        local w_TR = ReverseAdvancedWeight(v_TR)
        local w_BL = ReverseAdvancedWeight(v_BL)
        local w_BR = ReverseAdvancedWeight(v_BR)
        
        local sum = w_TL + w_TR + w_BL + w_BR
        if sum > 0.001 then
            xp_val = (w_TR + w_BR) / sum
            yp_val = (w_BL + w_BR) / sum
        end
    end

    if is_active and reaper.ImGui_IsMouseDown(ctx, reaper.ImGui_MouseButton_Left()) then
        local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
        xp_val = (mouse_x - start_x) / width
        if xp_val < 0.0 then xp_val = 0.0 elseif xp_val > 1.0 then xp_val = 1.0 end
        yp_val = (mouse_y - start_y) / height
        if yp_val < 0.0 then yp_val = 0.0 elseif yp_val > 1.0 then yp_val = 1.0 end
    end
    
    local w_TL = (1.0 - xp_val) * (1.0 - yp_val)
    local w_TR = xp_val * (1.0 - yp_val)
    local w_BL = (1.0 - xp_val) * yp_val
    local w_BR = xp_val * yp_val
    
    local function CalculateAdvancedWeight(base_weight)
        if base_weight <= 0.25 then
            return (base_weight / 0.25) * xy_min_center
        else
            local factor = (base_weight - 0.25) / 0.75
            return xy_min_center + factor * (xy_max_limit - xy_min_center)
        end
    end

    local function DrawCornerMenu(corner_id)
        if reaper.ImGui_BeginPopup(ctx, "xy_menu_" .. corner_id) then
            for f = 1, #folder_data do
                local folder = folder_data[f]
                
                local has_available_tracks = false
                for c = 1, #folder.children do
                    local child_data = folder.children[c]
                    local child_track = child_data.track
                    local is_used_elsewhere = false
                    if corner_id ~= 1 and xy_send_TL == child_track then is_used_elsewhere = true end
                    if corner_id ~= 2 and xy_send_TR == child_track then is_used_elsewhere = true end
                    if corner_id ~= 3 and xy_send_BL == child_track then is_used_elsewhere = true end
                    if corner_id ~= 4 and xy_send_BR == child_track then is_used_elsewhere = true end
                    if not is_used_elsewhere then has_available_tracks = true break end
                end
                
                if has_available_tracks then
                    local node_flags = reaper.ImGui_TreeNodeFlags_NavLeftJumpsToParent()+reaper.ImGui_TreeNodeFlags_DefaultOpen()
                    
                    local folder_color_pushed = false
                    if folder.color and folder.color > 0 then
                        local r, g, b = reaper.ColorFromNative(folder.color)
                        local imgui_color = (r << 24) | (g << 16) | (b << 8) | 0xFF
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), imgui_color)
                        folder_color_pushed = true
                    end
                    
                    local is_node_open = reaper.ImGui_TreeNode(ctx, folder.name, node_flags)
                    if folder_color_pushed then reaper.ImGui_PopStyleColor(ctx) end
                    
                    if is_node_open then
                        for c = 1, #folder.children do
                            local child_data = folder.children[c]
                            local child_track = child_data.track
                            local child_color = child_data.color
                            
                            local is_used_elsewhere = false
                            if corner_id ~= 1 and xy_send_TL == child_track then is_used_elsewhere = true end
                            if corner_id ~= 2 and xy_send_TR == child_track then is_used_elsewhere = true end
                            if corner_id ~= 3 and xy_send_BL == child_track then is_used_elsewhere = true end
                            if corner_id ~= 4 and xy_send_BR == child_track then is_used_elsewhere = true end
                            
                            local is_selected = false
                            if corner_id == 1 and xy_send_TL == child_track then is_selected = true end
                            if corner_id == 2 and xy_send_TR == child_track then is_selected = true end
                            if corner_id == 3 and xy_send_BL == child_track then is_selected = true end
                            if corner_id == 4 and xy_send_BR == child_track then is_selected = true end
                            
                            if not is_used_elsewhere or is_selected then
                                local _, track_name = reaper.GetTrackName(child_track)
                                local track_color_pushed = false
                                if child_color and child_color > 0 then
                                    local r, g, b = reaper.ColorFromNative(child_color)
                                    local imgui_color = (r << 24) | (g << 16) | (b << 8) | 0xFF
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), imgui_color)
                                    track_color_pushed = true
                                end
                                
                                if reaper.ImGui_MenuItem(ctx, track_name, nil, is_selected) then
                                    if corner_id == 1 then xy_send_TL = child_track
                                    elseif corner_id == 2 then xy_send_TR = child_track
                                    elseif corner_id == 3 then xy_send_BL = child_track
                                    elseif corner_id == 4 then xy_send_BR = child_track end
                                    SaveXYPadState() 
                                end
                                
                                if track_color_pushed then
                                    reaper.ImGui_PopStyleColor(ctx)
                                end
                            end
                        end
                        reaper.ImGui_TreePop(ctx)
                    end
                end
            end
            reaper.ImGui_Dummy(ctx, 4,10)

            if reaper.ImGui_MenuItem(ctx, " - Remove send", nil, false) then
                if corner_id == 1 then xy_send_TL = nil
                elseif corner_id == 2 then xy_send_TR = nil
                elseif corner_id == 3 then xy_send_BL = nil
                elseif corner_id == 4 then xy_send_BR = nil end
                SaveXYPadState() 
            end
            if reaper.ImGui_MenuItem(ctx, " - Remove ALL sends", nil, false) then
                xy_send_TL = nil
                xy_send_TR = nil
                xy_send_BL = nil
                xy_send_BR = nil
                SaveXYPadState() 
            end
            reaper.ImGui_EndPopup(ctx)
        end
    end

    if is_hovered and reaper.ImGui_IsMouseClicked(ctx, reaper.ImGui_MouseButton_Right()) then
        local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
        local rel_x = mouse_x - start_x
        local rel_y = mouse_y - start_y
        if rel_x < width / 2 and rel_y < height / 2 then reaper.ImGui_OpenPopup(ctx, "xy_menu_1")
        elseif rel_x >= width / 2 and rel_y < height / 2 then reaper.ImGui_OpenPopup(ctx, "xy_menu_2")
        elseif rel_x < width / 2 and rel_y >= height / 2 then reaper.ImGui_OpenPopup(ctx, "xy_menu_3")
        else reaper.ImGui_OpenPopup(ctx, "xy_menu_4") end
    end
    DrawCornerMenu(1) DrawCornerMenu(2) DrawCornerMenu(3) DrawCornerMenu(4)

    local weight_TL = CalculateAdvancedWeight(w_TL)
    local weight_TR = CalculateAdvancedWeight(w_TR)
    local weight_BL = CalculateAdvancedWeight(w_BL)
    local weight_BR = CalculateAdvancedWeight(w_BR)

    if any_active and sel_track and reaper.ValidatePtr(sel_track, "MediaTrack*") then
        local function SetSendVol(target_track, weight)
            if not target_track then return end
            local idx = GetSendIndexByTarget(sel_track, target_track)
            if idx == -1 then idx = reaper.CreateTrackSend(sel_track, target_track) end
            if idx >= 0 then
                reaper.SetTrackSendInfo_Value(sel_track, 0, idx, "D_VOL", weight)
            end
        end
        
        SetSendVol(xy_send_TL, weight_TL)
        SetSendVol(xy_send_TR, weight_TR)
        SetSendVol(xy_send_BL, weight_BL)
        SetSendVol(xy_send_BR, weight_BR)
        reaper.TrackList_AdjustWindows(false)
    end

    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local col_border = 0x000000FF 
    local col_lines  = 0x3D3D3D77 -- Сделаем осевые линии чуть прозрачнее (альфа 77 вместо FF), чтобы градиент лучше читался
    local col_point  = 0xCCCCCCFF 
    local col_bg     = 0x2D2D2DFF 
    
    if all_selected then 
        local function GetTrackImguiColor(track, alpha)
            local default_bg = 0x2D2D2D -- Серый цвет, если трек без цвета
            if track and reaper.ValidatePtr(track, "MediaTrack*") then
                local native_color = reaper.GetTrackColor(track)
                if native_color > 0 then
                    local r, g, b = reaper.ColorFromNative(native_color)
                    return (r << 24) | (g << 16) | (b << 8) | alpha
                end
            end
            return (default_bg << 8) | alpha
        end

        local color_TL = GetTrackImguiColor(xy_send_TL, 0x44) -- Верхний левый
        local color_TR = GetTrackImguiColor(xy_send_TR, 0x44) -- ... правый
        local color_BR = GetTrackImguiColor(xy_send_BR, 0x44) -- Нижний правый
        local color_BL = GetTrackImguiColor(xy_send_BL, 0x44) -- ... левый

        reaper.ImGui_DrawList_AddRectFilledMultiColor(draw_list, start_x, start_y, start_x + width, start_y + height, color_TL, color_TR, color_BR, color_BL)
    else
        reaper.ImGui_DrawList_AddRectFilled(draw_list, start_x, start_y, start_x + width, start_y + height, col_bg)
        reaper.ImGui_DrawList_AddRect(draw_list, start_x, start_y, start_x + width, start_y + height, col_border)
    end
    
    reaper.ImGui_DrawList_AddLine(draw_list, start_x + width/2, start_y, start_x + width/2, start_y + height,  0x000000FF)
    reaper.ImGui_DrawList_AddLine(draw_list, start_x, start_y + height/2, start_x + width, start_y + height/2,  0x000000FF)


    local function DrawCornerText(track, base_x, base_y, default_text, alignment)
        local name = default_text
        local text_color = 0xAAAAAFFF
        
        if track and reaper.ValidatePtr(track, "MediaTrack*") then
            _, name = reaper.GetTrackName(track)
            local native_color = reaper.GetTrackColor(track)
            if native_color > 0 then
                local r, g, b = reaper.ColorFromNative(native_color)
                text_color = (r << 24) | (g << 16) | (b << 8) | 0xFF
            end
        end
        
        local max_text_width = (width / 2) - 10
        local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, name)
        
        if text_w > max_text_width then
            while #name > 3 and text_w > max_text_width do
                name = string.sub(name, 1, -2) -- отрезаем последний символ
                text_w, text_h = reaper.ImGui_CalcTextSize(ctx, name .. "...")
            end
            name = name .. "..."
        end
        
        local final_x = base_x
        if alignment == "right" then
            final_x = base_x - text_w
        end
        
        reaper.ImGui_DrawList_AddText(draw_list, final_x, base_y, text_color, name)
    end

    DrawCornerText(xy_send_TL, start_x + 5,         start_y + 5,              " Empty  ", "left")
    DrawCornerText(xy_send_TR, start_x + width - 5, start_y + 5,              " Empty  ", "right")
    DrawCornerText(xy_send_BL, start_x + 5,         start_y + height - 20,    " Empty  ", "left")
    DrawCornerText(xy_send_BR, start_x + width - 5, start_y + height - 20,    " Empty  ", "right")

    local point_pos_x = start_x + (xp_val * width)
    local point_pos_y = start_y + (yp_val * height)

    if all_selected then
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, point_pos_x, point_pos_y, 6.0, col_point)
    reaper.ImGui_DrawList_AddCircle(draw_list, point_pos_x, point_pos_y, 8.0, col_border, 12, 1.5)
    end

    reaper.ImGui_EndGroup(ctx)
end

function exit()
    SaveXYPadState()
end

function loop()
    reaper.ImGui_PushFont(ctx, font)
    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_WindowTitleAlign(),  0.5, 0.5)
    reaper.ImGui_PushStyleVar  (ctx,   reaper.ImGui_StyleVar_SeparatorTextAlign(),  0.5,0.5)
    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_IndentSpacing(),0)
    
    reaper.ImGui_PushStyleColor(ctx,   reaper.ImGui_Col_Separator(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),           rgba(68, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_HeaderHovered(),           rgba(100, 100, 100, 1))

    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Button(),          rgba(80,80,80,1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonHovered(),    rgba(70,70,70,1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonActive(),     rgba(90,90,90,1))
    
    reaper.ImGui_SetNextFrameWantCaptureKeyboard( ctx, 1 )

    local visible, open = reaper.ImGui_Begin(ctx, 'Sender', true,  window_flags)

    w, h = reaper.ImGui_GetWindowSize(ctx)
    x, y = reaper.ImGui_GetWindowPos(ctx)

    if visible then
        frame()
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx,8)
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopFont(ctx)
    
    if open then
        reaper.defer(loop)
    end

end

loop()
reaper.atexit(exit )