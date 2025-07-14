-- @description UI send manager for selected track
-- @author Misha Oshkanov
-- @version 1.2


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
local font = reaper.ImGui_CreateFont('sans-serif', 16)
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

window_flags =  
reaper.ImGui_WindowFlags_NoFocusOnAppearing() +
reaper.ImGui_WindowFlags_NoNavFocus() +
reaper.ImGui_WindowFlags_NoNavInputs() +
reaper.ImGui_WindowFlags_NoScrollbar() 
-- reaper.ImGui_WindowFlags_NoScrollWithMouse() 
-- reaper.ImGui_WindowFlags_NoResize()

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

function col_vib(col,vib)
    r, g, b = reaper.ColorFromNative(col)
    h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)
    v = math.max(v,100)
    v = math.min(v * vib,230)
    r, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)
    result = rgba(r,g,b,1)
    return result
end

function col_vib_inv(col,vib)
    r, g, b = reaper.ColorFromNative(col)
    h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)
    if v < 100 then 
        v = 255 - v
    end
    v = math.min(v * vib,230)
    r, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)

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
    
-- function move_selected_tracks(dest)
--     local sel_tracks = {}
--     local count = reaper.CountSelectedTracks(0)

--     for i=1,count do 
--         local sel_track = reaper.GetSelectedTrack(0, i-1)
--         table.insert(sel_tracks, sel_track)
--     end 
-- end 

-- str_len = 0

-- function draw_tracklist(data)
--     -- data = {}
--     for k,t in ipairs(data) do 
--         reaper.ImGui_PushID(ctx, k)
        
--         reaper.ImGui_BeginGroup(ctx)

--         reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Button(),        col(t.color,0.7))
--         reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonHovered(), col(t.color,0.7+0.2))
--         reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonActive(),  col(t.color,0.7+0.2))

--         reaper.ImGui_PushStyleVar(ctx,  reaper.ImGui_StyleVar_ItemSpacing(),  2, 2)
--         reaper.ImGui_PushStyleVar(ctx,  reaper.ImGui_StyleVar_ButtonTextAlign(),   0.5, 0.5)

--         retval, slider = reaper.ImGui_SliderDouble(ctx, t.name, v, -90, 12)
        
--         reaper.ImGui_PopStyleColor(ctx,3)
--         reaper.ImGui_PopStyleVar(ctx,2)

--         -- draw_color(rgba(250,250,250,1))
--         reaper.ImGui_SameLine(ctx, 36, 1)

--         reaper.ImGui_EndGroup(ctx)
--         reaper.ImGui_PopID(ctx)
--     end 
-- end

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
            local color = reaper.GetTrackColor(dest)
            if color == 0 then color = '28290987' end
            local _, mute = reaper.GetTrackReceiveUIMute(track, r-1)
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
        return receives
    end
end


function get_send_id_by_dest(track,dest_track)
    local count_sends = reaper.GetTrackNumSends(track, 0)
    if count_sends > 0 then 
        for s=1, count_sends do 
        local dest = reaper.GetTrackSendInfo_Value(track, 0, s-1, 'P_DESTTRACK')
        if dest == dest_track then return s-1 end
        end 
    end
end
function key_down()
    local key = reaper.JS_Mouse_GetState(95)
    if key == 4 or key == 5 then return 'ctrl'
    elseif key == 8 or key == 9 then return 'shift'
    elseif key == 16 or key == 17 then return 'alt'
    else return nil 
    end
end

gfx_c_value = 0.9
coeff_value = 40

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

local function HSlider_Filled(ctx, id, width, height, value, min, max, rounding, fillColor)
    rounding = rounding or 2
    fillColor = fillColor or 0xFF4B77FF

    if not sliders[id] then
        sliders[id] = {
            value = value,
            cursor_start_x = 0,
            cursor_start_y = 0,
            dragStartPos = { x = 0, y = 0 },
            is_cursor_hidden = false,
            prev_x = 0,
            prev_y = 0,
            dragging_mac = false
        }
    end
    
    local slider = sliders[id]
    local changed = false

    ImGui.BeginGroup(ctx)
    ImGui.InvisibleButton(ctx, id, width, height)
    local x1, y1 = ImGui.GetItemRectMin(ctx)
    local x2, y2 = ImGui.GetItemRectMax(ctx)
    local active = ImGui.IsItemActive(ctx)
    local hovered = ImGui.IsItemHovered(ctx)

    local frac = (slider.value - min) / (max - min)
    -- local speed_modifier = ((max - min) * 0.0025) *
    --    (ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift) and 0.2
    --     or ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) and 0.024
    --     or 1)
    local speed_modifier = ((max - min) * 0.0025) * 1

    if active then
        local mouse_x, mouse_y = reaper.GetMousePosition()
        
        if not isMac then
            if not slider.is_cursor_hidden then
                slider.cursor_start_x, slider.cursor_start_y = mouse_x, mouse_y
                slider.dragStartPos.x, slider.dragStartPos.y = mouse_x, mouse_y
                slider.is_cursor_hidden = true
            end
            ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_None)
            
            local trackDeltaX = mouse_x - slider.dragStartPos.x
            local trackDeltaY = mouse_y - slider.dragStartPos.y
          
            if math.abs(trackDeltaX) > math.abs(trackDeltaY) then
                slider.value = math.max(min, math.min(max, slider.value + trackDeltaX * speed_modifier))
            else
                slider.value = math.max(min, math.min(max, slider.value - trackDeltaY * speed_modifier))
            end

            reaper.JS_Mouse_SetPosition(slider.dragStartPos.x, slider.dragStartPos.y)
        else
            if not slider.dragging_mac then
                slider.prev_x, slider.prev_y = mouse_x, mouse_y
                slider.dragging_mac = true
            end

            local dx = mouse_x - slider.prev_x
            local dy = mouse_y - slider.prev_y

            if math.abs(dx) > math.abs(dy) then
                slider.value = math.max(min, math.min(max, slider.value + dx * speed_modifier))
            else
                slider.value = math.max(min, math.min(max, slider.value - dy * speed_modifier))
            end

            slider.prev_x, slider.prev_y = mouse_x, mouse_y
        end

        changed = true
    else
        if slider.is_cursor_hidden then
            if not isMac then
                reaper.JS_Mouse_SetPosition(slider.cursor_start_x, slider.cursor_start_y)
                ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Arrow)
            end
            slider.is_cursor_hidden = false
        end
        slider.dragging_mac = false
    end

    if hovered then
        local wheel = ImGui.GetMouseWheel(ctx)
        if wheel ~= 0 then
            slider.value = math.max(min, math.min(max, slider.value + wheel * speed_modifier * 10))
            changed = true
        end
    end

    local draw_list = ImGui.GetWindowDrawList(ctx)
    local bg_color = active and ImGui.GetColor(ctx, ImGui.Col_FrameBgActive)
        or hovered and ImGui.GetColor(ctx, ImGui.Col_FrameBgHovered)
        or ImGui.GetColor(ctx, ImGui.Col_FrameBg)
    ImGui.DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, bg_color, rounding)

    local fill_x2 = x1 + width * frac
    ImGui.DrawList_AddRectFilled(draw_list, x1, y1, fill_x2, y2, fillColor, rounding)

    ImGui.EndGroup(ctx)
    return changed, slider.value
end


-- local function LoadTrackTemplateByName(Path_Track_Template, Name_Script_NEW, SELECTED);
--     local IO do

--         local N = ('\n'):rep(6)
--         local Path = Path_Track_Template
--         IO = io.open(Path,"r")
--         if not IO then goto MB end
--         local textTemplates = IO:read("a")..N
--         IO:close()

--         local trackX = reaper.GetLastTouchedTrack()
--         if not trackX then
--             trackX = reaper.GetTrack(0,reaper.CountTracks(0)-1)
--         end
--         local tbl = {}
--         for var in string.gmatch(textTemplates,".-\n") do
--             if var:match('^%s-<TRACK.-')then
--                 var = N..var
--             end;
--             tbl[#tbl+1] = var
--         end
--         textTemplates = table.concat(tbl)
--         reaper.SelectAllMediaItems(0,0)
--         local tbl = {}
--         local trNumb = 0
--         local several
--         for var in string.gmatch(textTemplates,"<TRACK.-"..N)do
--             reaper.InsertTrackAtIndex(trNumb,false)
--             local Track = reaper.GetTrack(0,trNumb)
--             tbl[#tbl+1] = {}
--             tbl[#tbl].track = Track
--             tbl[#tbl].str = var
--             trNumb = trNumb+1
--             if not several then
--                 reaper.SetOnlyTrackSelected(Track)
--                 several = true
--             else;
--                 reaper.SetMediaTrackInfo_Value(Track,"I_SELECTED",1)
--             end
--         end

--         local guidNum = math.random(1000,9999)
--         for i = 1,#tbl do
--             reaper.SetTrackStateChunk(tbl[i].track,tbl[i].str,false)
--             local _,guid = reaper.GetSetMediaTrackInfo_String(tbl[i].track,'GUID','',false)
--             local guid = guid:gsub('....%}',guidNum..'}')
--             reaper.GetSetMediaTrackInfo_String(tbl[i].track,'GUID',guid,true)
--             ---
--             for i = 1,reaper.CountTrackMediaItems(tbl[#tbl].track) do
--                 item = reaper.GetTrackMediaItem(tbl[#tbl].track,i-1)
--                 _,itemGuid = reaper.GetSetMediaItemInfo_String(item,'GUID','',0)
--                 local itemGuid = itemGuid:gsub('....%}',guidNum..'}')
--                 reaper.GetSetMediaItemInfo_String(item,'GUID',itemGuid,1)
--                 for i2 = 1,reaper.CountTakes(item) do
--                     local take = reaper.GetMediaItemTake(item,i2-1)
--                     local _,takeGuid = reaper.GetSetMediaItemTakeInfo_String(take,'GUID','',0)
--                     local takeGuid = takeGuid:gsub('....%}',guidNum..'}')
--                     reaper.GetSetMediaItemTakeInfo_String(take,'GUID',takeGuid,1)
--                 end
--             end
--         end

--         local Depth = reaper.GetTrackDepth(tbl[#tbl].track)
--         if Depth > 0 then
--             reaper.SetMediaTrackInfo_Value(tbl[#tbl].track,'I_FOLDERDEPTH',Depth-Depth*2)
--         end

--         local numbX
--         if trackX then numbX = reaper.GetMediaTrackInfo_Value(trackX,'IP_TRACKNUMBER') end
--         if not numbX then numbX = reaper.CountTracks(0) end

--         if numbX~=0 then reaper.ReorderSelectedTracks(numbX,0) end

--     end
--     -----------

--     -- ::MB::
--     -- if not IO then;
--     --     local
--     --     filename, scrName = ({reaper.get_action_context()})[2]:match("(.+)[/\\](.+)");
--     --     local
--     --     MB = reaper.MB(
--     --     "Rus:\n"..
--     --     " * Не существует шаблона дорожки с именем - \n"..
--     --     "    "..Name_Script_NEW..".lua\n\n"..
--     --     " * Создайте новый скрипт с помощью\n"..
--     --     "    Archie_Track; Smart template - Load Track template by name.lua\n"..
--     --     "    И существующего шаблона дорожек! \n\n\n"..
--     --     "Eng:\n"..
--     --     " * There is no track template named - \n"..
--     --     "    "..Name_Script_NEW..".lua\n\n"..
--     --     " * Create a new script using\n"..
--     --     "    Archie_Track; Smart template - Load Track template by name.lua\n"..
--     --     "    And existing track template! \n\n"..
--     --     "-----------------\n\n"..
--     --     " * УДАЛИТЬ ДАННЫЙ СКРИПТ ? - OK\n\n"..
--     --     " * REMOVE THIS SCRIPT ? - OK\n",
--     --     scrName,1);

--     --     if MB == 1 then;
--     --         reaper.AddRemoveReaScript(false,0,filename.."/"..scrName,true);
--     --         os.remove(filename.."/"..scrName);
--     --     end;
--     --     no_undo() return;
--     -- end;
-- end


function remove_arch_prefix(string)
    return string:gsub('_','')
end

function toggle_mute_all_sends(track,state)
    local sends = get_sends(track)
    if not sends then return end
    -- local mute_state = reaper.GetTrackSendInfo_Value(track, 0, sends[1].id, 'B_MUTE' )
    if sends then 
        for k,s in ipairs(sends) do 
            local found = false
            local parents = get_parentnames_table(s.dest)
            for k1,s1 in ipairs(send_folders) do 
                if table_contains(parents,s1.name) then found = true end 
            end 
            -- if found then reaper.SetTrackSendInfo_Value(track, 0, k-1, 'B_MUTE', mute_state==1 and 0 or 1) end
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


function draw_send_folder_slots(sel_track)
    local count = reaper.CountTracks(0)
    for i=1, count do 
        local track = reaper.GetTrack(0, i-1)
        parent = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH' ) == 1
        if parent then 
            local _, parent_name = reaper.GetTrackName(track)
            parent_name = parent_name:gsub('_','')
            for i2=1, #send_folders do
                send_folder_name = send_folders[i2].name
                if parent_name == send_folder_name then 
                    local parent_color = reaper.GetTrackColor(track)
                    local open_flag = send_folders[i2].open == 1 and reaper.ImGui_TreeNodeFlags_DefaultOpen() or 0
                    
                    local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
                    local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
                    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, min_x, max_y-10, min_x +w-17, max_y, col(parent_color,0.6))

                    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Text(),          col(parent_color,1))

                    if reaper.ImGui_TreeNode(ctx, parent_name, reaper.ImGui_TreeNodeFlags_SpanFullWidth() + open_flag) then
                        -- reaper.ImGui_PushID(ctx, i2)
                        children = get_children(track)
                        for i3=1, #children do 
                            reaper.ImGui_PushID(ctx, i3)
                            child = children[i3]
                            local _, mute = reaper.GetTrackUIMute(child) 
                            send_slot(child,sel_track)
                            reaper.ImGui_PopID(ctx)
                        end
                        reaper.ImGui_TreePop(ctx) 
                        
                    end
                    reaper.ImGui_Dummy(ctx, 4, 10)
                    reaper.ImGui_PopStyleColor(ctx)
                end 
            end
        end
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
        return name_w
    end
end

function count_active_sends(track)
    local sendnum = reaper.GetTrackNumSends(track, -1)
    local count = 0
    for i=0, sendnum-1 do 
        local _, mute = reaper.GetTrackReceiveUIMute(track, i)
        if not mute then count = count + 1 end 
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
        -- text_color = col_sat(color,0.2)
        text_color = rgba(255,255,255,1)
        val_color = col_sat(color,0.1)
    end
    
    vol = 0
    a = 0
    name_w = 100
    
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
        -- reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBg(),                 rgba(100,100,100,0.3))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBg(),              col(color,0.1))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgHovered(),       col(color,math.max(a-0.2,0.2)))
    end
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgActive(),            col(color,math.max(a-0.3,0)))
    
    -- slider_retval, slider_value = reaper.ImGui_SliderDouble(ctx, '##slider'..tostring(dest_track), vol, 0.005, 4,'',reaper.ImGui_SliderFlags_Logarithmic()+
    
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
    -- slider_retval, slider_value = HSlider_Filled(ctx, tostring(dest_track), w-17, 22, Convert_Val2Fader(vol), 0, 1, 2, col(color,0.2))

    if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) and found then 
        -- sx, sy = reaper.ImGui_GetWindowPos(ctx)
        -- reaper.ImGui_SetNextWindowPos(ctx, sx-w/2, sy-h/2 )
        reaper.ImGui_OpenPopup(ctx, 'fx_popup')    
    end

    if reaper.ImGui_BeginPopup(ctx, 'fx_popup',reaper.ImGui_WindowFlags_NoMove()) then 
        pw, ph = reaper.ImGui_GetWindowSize(ctx)
        px, py = reaper.ImGui_GetWindowPos(ctx)

        -- pmin_x, pmin_y = reaper.ImGui_GetItemRectMin(ctx)
        -- pmax_x, pmax_y = reaper.ImGui_GetItemRectMax(ctx)
        -- pdraw_list = reaper.ImGui_GetWindowDrawList(ctx)

        -- print(name_w)
        -- print(pw)

        reaper.ImGui_SetNextItemWidth( ctx, pw-16) 
        send_retval, send_pan = reaper.ImGui_SliderDouble(ctx, '##pan', pan, -1, 1, math.floor(trunc(pan,2)*100), reaper.ImGui_SliderFlags_NoInput())

         if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) then 
            reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_PAN', 0)
         end

        
        if send_retval then 
        -- print(reaper.ImGui_IsMouseDoubleClicked( ctx, button))
        -- if key_down()=='alt' then 
        -- else
        -- end
            reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_PAN', send_pan)
        end
        
        -- if reaper.ImGui_IsItemHovered(ctx) and key_down()='alt' then
        --     reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_PAN', 0)
        -- end
        reaper.ImGui_PushStyleVar(ctx,  reaper.ImGui_StyleVar_ItemSpacing(),2,2)

        local fx_count = reaper.TrackFX_GetCount(dest_track)
        if fx_count > 0 then 
            name_w = calculate_text_fxnames(dest_track)
            for fx=1,fx_count do 
                
                reaper.ImGui_PushID(ctx, fx-1)
                local _, fx_name = reaper.TrackFX_GetFXName(dest_track, fx-1)
                local fx_enabled = reaper.TrackFX_GetEnabled(dest_track, fx-1)

                if fx_enabled then fx_text_color = rgba(255,255,255,1) else fx_text_color = rgba(140,140,140,1) end

                reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Text(),          fx_text_color)

                fx_name =  fx_name:gsub('.-%:', ''):gsub('%(.-%)$', ''):gsub("^%s+", ''):gsub("%s+$", '')
                -- tw, _ = reaper.ImGui_CalcTextSize(ctx, fx_name)
                -- if tw > name_w then name_w = tw end

                local fx_button = reaper.ImGui_Button(ctx, fx_name,name_w+40)
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

            local scroll_to_button = reaper.ImGui_Button(ctx, 'Go to', (name_w/2)+19,24)
            if scroll_to_button then 
                pinned_mode = true
                pinned_track = sel_track
                scroll_to_track(dest_track)
            end
            reaper.ImGui_SameLine(ctx)
            local env_button = reaper.ImGui_Button(ctx, 'Env', (name_w/2)+19,24)
            if env_button then 
                -- env = get_env_dest(sel_track,dest_track)
                -- print(env)
                local env = reaper.GetTrackSendInfo_Value(sel_track, 0, id, "P_ENV:<VOLENV")
                OD_ToggleShowEnvelope(env,true)
                reaper.ImGui_CloseCurrentPopup(ctx)
            end 
        end
            reaper.ImGui_Dummy(ctx, 2, 2)

        local receives = get_receives(dest_track)
        reaper.ImGui_SeparatorText( ctx, "Receives" )
        for ir,r in ipairs(receives) do 
            -- print(reaper.ImGui_IsItemHovered(ctx))
                reaper.ImGui_PushID(ctx, ir-1)
                reaper.ImGui_SetNextItemWidth(ctx, name_w+40)

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

                rc = rgba(255, 255, 255, 1)
                
                -- reaper.ImGui_PopItemWidth(ctx)
                reaper.ImGui_PopStyleColor(ctx,5)
                -- reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Text(),rgba(255, 255, 255, 0.4))
                
                local draw_rslider_r = (pmax_x-pmin_x)-((pmax_x-pmin_x)*(rslider_value))
                ImGui.DrawList_AddRectFilled(pdraw_list, pmin_x, pmin_y, pmax_x - draw_rslider_r, pmax_y, col(r.color,0.2))
                reaper.ImGui_DrawList_AddText(pdraw_list, px+14, pmin_y+4, rc, r.name)
                
                r_text_value = tostring(trunc(VAL2DB(r.vol),1))
                r_text_w, _ = reaper.ImGui_CalcTextSize(ctx, r_text_value)
                reaper.ImGui_DrawList_AddText(pdraw_list, (px+pw-14)-r_text_w, pmin_y+4, col(r.color,1), r_text_value)

                -- reaper.ImGui_PopStyleColor(ctx)
                reaper.ImGui_PopID(ctx)
        end
                
        
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_EndPopup(ctx)
    end

    if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left()) and found then 
        if key_down() == 'alt' then 
            reaper.RemoveTrackSend(sel_track, 0, get_send_id_by_dest(sel_track,dest_track))
            -- sliders[tostring(dest_track)].value = 0.001
        elseif key_down() == 'shift' then 
            reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'B_MUTE', reaper.GetTrackSendInfo_Value(sel_track, 0, id, 'B_MUTE')==1 and 0 or 1)
        elseif key_down() == 'ctrl' then 
            if reaper.AnyTrackSolo(0) and not solo then reaper.Main_OnCommand(40340, 0) end
            reaper.SetMediaTrackInfo_Value(dest_track, 'I_SOLO', reaper.GetMediaTrackInfo_Value(dest_track, 'I_SOLO')==2 and 0 or 2)
        end
    end

    if slider_retval and (key_down() == nil or key_down() == 1) then 
        if found then 
            reaper.SetTrackSendInfo_Value(sel_track, 0, id, 'D_VOL', Convert_Fader2Val(slider_value))
        else 
            reaper.CreateTrackSend(sel_track, dest_track)
        end
    end
    
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    
    -- reaper.ImGui_PopItemWidth(ctx)
    -- reaper.ImGui_PopStyleColor(ctx,5)
    -- reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Text(),text_color)
    
    local draw_slider_r = (max_x-min_x)-((max_x-min_x)*(slider_value))
    ImGui.DrawList_AddRectFilled(draw_list, min_x, min_y, max_x - draw_slider_r, max_y, col(color,0.3))
    if sendnum > 0 then 
        sendnum_text_w = reaper.ImGui_CalcTextSize(ctx, sendnum)
        reaper.ImGui_DrawList_AddText(draw_list, x+14+sendnum_text_w, min_y+4, text_color, name)
        reaper.ImGui_DrawList_AddText(draw_list, x+10, min_y+4, val_color, sendnum)
    else 
        reaper.ImGui_DrawList_AddText(draw_list, x+14, min_y+4, text_color, name)
    end
    
    if found then 
        text_value = trunc(VAL2DB(vol),1)
        if VAL2DB(vol) < -50 then
            text_value = '-inf'
        end    
    else 
        text_value = '+'
    end
    text_w, _ = reaper.ImGui_CalcTextSize(ctx, text_value)
    reaper.ImGui_DrawList_AddText(draw_list, (x+w-14)-text_w, min_y+4, val_color, text_value)

    -- reaper.ImGui_PopStyleColor(ctx)

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
        
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_SliderGrab(),              col(target_color,0.4))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_SliderGrabActive(),        col(target_color,0.5))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBg(),                 col(target_color,0.2))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgHovered(),          col(target_color,0.4))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_FrameBgActive(),           col(target_color,0.5))
        
        reaper.ImGui_SetNextItemWidth( ctx, w-17)

        all_retval, all_adjust_slider = reaper.ImGui_SliderDouble(ctx, '##all', all_vol, -0.8, 0.8,'',reaper.ImGui_SliderFlags_None()+
        reaper.ImGui_SliderFlags_NoInput())

        -- print(reaper.ImGui_IsMouseDown( ctx,reaper.ImGui_MouseButton_Left()))

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
            -- reaper.ImGui_EndPopup(ctx)
        
        draw_send_folder_slots(target_track)
        -- reaper.ImGui_Dummy(ctx, 20, 20 )
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

function loop()
    reaper.ImGui_PushFont(ctx, font)

    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_WindowTitleAlign(),  0.5, 0.5)
    reaper.ImGui_PushStyleVar  (ctx,   reaper.ImGui_StyleVar_SeparatorTextAlign(),  0.5,0.5)
    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_IndentSpacing(),0)
    
    -- reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(title_colors.r, title_colors.g, title_colors.b, 1))
    reaper.ImGui_PushStyleColor(ctx,   reaper.ImGui_Col_Separator(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),           rgba(68, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_HeaderHovered(),           rgba(100, 100, 100, 1))

    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Button(),          rgba(80,80,80,1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonHovered(),    rgba(70,70,70,1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonActive(),     rgba(90,90,90,1))
    
    reaper.ImGui_SetNextFrameWantCaptureKeyboard( ctx, 1 )
    -- reaper.ImGui_SetNextWindowSize(ctx, 318, 40+(30*#data), reaper.ImGui_Cond_Always())

    local visible, open = reaper.ImGui_Begin(ctx, 'Sender', true,  window_flags)

    -- reaper.ImGui_SetConfigVar( ctx, 1, 
    -- reaper.ImGui_ConfigFlags_DockingEnable())
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