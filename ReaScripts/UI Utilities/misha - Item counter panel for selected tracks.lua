-- @description Item counter panel for selected track
-- @author Misha Oshkanov
-- @version 1.4
-- @about
--  Small Ui panel with digits. Shows amount of items on first selected track(first number)
--  and number of items on other selected track and their child tracks(second number)
--  Blue dot os send indicator.
--  Brown dot is receive indicator.
--------------------------------------------------------------------- 
---------------------------------------------------------------------
---------------------------------------------------------------------
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
    

local ctx = reaper.ImGui_CreateContext('MIDI Ghost Manager')
local font = reaper.ImGui_CreateFont('sans-serif', 30)
reaper.ImGui_Attach(ctx, font)

title_colors = {r=30,g=30,b=30}

window_flags =  reaper.ImGui_WindowFlags_NoScrollWithMouse() +
reaper.ImGui_WindowFlags_NoFocusOnAppearing() +
reaper.ImGui_WindowFlags_NoNavFocus() +
reaper.ImGui_WindowFlags_NoNavInputs() +
reaper.ImGui_WindowFlags_NoScrollbar() + 
reaper.ImGui_WindowFlags_NoResize() +
reaper.ImGui_WindowFlags_NoTitleBar()

total_width = 80
total_height = 44

function count_child_items(track)
    local children = get_children(track)
    local num = 0
    for c=1,#children do 
        local child = children[c]
        if not reaper.IsTrackSelected(child) then 
            num = num + reaper.CountTrackMediaItems(child)
        end
    end 
    return num
end

function count_playing_items_in_lanes(track)
    local count_lanes = reaper.GetMediaTrackInfo_Value(track, 'I_NUMFIXEDLANES')
    local items = reaper.CountTrackMediaItems(track)
    num = 0
    not_playing_num = 0
    for i=0,items-1 do 
        local item = reaper.GetTrackMediaItem(track, i)
        local lane_plays = reaper.GetMediaItemInfo_Value(item, 'C_LANEPLAYS') > 0 
        if lane_plays then 
            num = num + 1
        else 
            not_playing_num = not_playing_num + 1 
        end 
    end
    return num, not_playing_num
end 

function frame()
    local first_track = reaper.GetSelectedTrack(0, 0)
    local num1 = 0
    local num2 = 0
    local send_mark    = false
    local receive_mark = false
    local num1_lanes_found  = false
    local num2_lanes_found  = false


    if first_track then 
        local is_folder = reaper.GetMediaTrackInfo_Value(first_track, 'I_FOLDERDEPTH')==1
        local has_sends =reaper.GetTrackNumSends(first_track, 0)
        if has_sends > 0 then 
            for s=0, has_sends-1 do 
                is_send_muted = reaper.GetTrackSendInfo_Value(first_track, 0, s, 'B_MUTE') == 1
                if not is_send_muted then send_mark = true end
            end
        end

        local has_receives =reaper.GetTrackNumSends(first_track, -1)
        if has_receives > 0 then 
            for r=0, has_receives-1 do 
                is_receive_muted = reaper.GetTrackSendInfo_Value(first_track, -1, r, 'B_MUTE') == 1
                if not is_receive_muted then receive_mark = true end
            end
        end

        if is_folder then num2 = num2 + count_child_items(first_track) end
        local count_lanes = reaper.GetMediaTrackInfo_Value(first_track, 'I_NUMFIXEDLANES')
        local items = reaper.CountTrackMediaItems(first_track)
        if count_lanes > 1 then 
            num1_lanes_found = true
            playing, not_playing = count_playing_items_in_lanes(first_track)
            num1 = num1 + playing
            num3 = num3 + not_playing
        else
            num1 = items
        end
    else
        num1 = ""
    end
    local count = reaper.CountSelectedTracks(0)
    if count > 1 then 
        local folder_found = false
        for i2=0,count-2 do 
            local track = reaper.GetSelectedTrack(0, i2+1)
            local count_lanes = reaper.GetMediaTrackInfo_Value(track, 'I_NUMFIXEDLANES')
            if count_lanes > 1 then 
                num2_lanes_found = true
                playing, not_playing = count_playing_items_in_lanes(track)
                num2 = num2 + playing
                num4 = num4 + not_playing
            else
                num2 = num2 + reaper.CountTrackMediaItems(track)
            end
            local is_folder = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')==1

            if is_folder then 
                local folder_found = true
                local children = get_children(track)
                for c=1,#children do 
                    local child = children[c]
                    if not reaper.IsTrackSelected(child) then 
                        local count_lanes = reaper.GetMediaTrackInfo_Value(first_track, 'I_NUMFIXEDLANES')
                        if count_lanes > 1 then 
                            num2_lanes_found = true
                            playing, not_playing = count_playing_items_in_lanes(track)
                            num2 = num2 + playing
                            num4 = num4 + not_playing
                        else
                            num2 = num2 + reaper.CountTrackMediaItems(track)
                        end
                    end
                end 
            end
        end
    end

    w, h = reaper.ImGui_GetWindowSize( ctx )

    reaper.ImGui_Dummy(ctx, 1, 1 )
    reaper.ImGui_SameLine(ctx)

    if send_mark or receive_mark then 
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)

        local size = 10 -- размер квадрата
        local padding = 0 -- отступ от краёв окна
    end 

    if send_mark then
        local x1 = win_x -4
        local y1 = win_y + win_h - size -28
        local x2 = x1 + size
        local y2 = y1 + size
        reaper.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, rgba(111, 161, 194, 1))
    end

    if num2 == 0 then num2 = '' end
    reaper.ImGui_TextColored(ctx, rgba(220, 220, 220, 1), num1)
    reaper.ImGui_SameLine(ctx)
    if num1_lanes_found then 
        reaper.ImGui_TextColored(ctx, rgba(180, 180, 180, 1), num3)
        reaper.ImGui_SameLine(ctx)
    end
    reaper.ImGui_TextColored(ctx, rgba(180, 180, 180, 1), num2)
    if num2_lanes_found then 
        reaper.ImGui_TextColored(ctx, rgba(180, 180, 180, 1), num4)
        reaper.ImGui_SameLine(ctx)
    end

    if receive_mark then 
        local x1 = win_x -4
        local y1 = win_y + win_h  -18
        local x2 = x1 + size
        local y2 = y1 + size
        reaper.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, rgba(194, 134, 111, 1))
    end

    local num1_str = tostring(num1)
    local num2_str = tostring(num2)
    local num3_str = tostring(num3)
    local num4_str = tostring(num4)
    local width1, height1 = reaper.ImGui_CalcTextSize(ctx, num1_str)
    local width2, height2 = reaper.ImGui_CalcTextSize(ctx, num2_str)
    local width3, height3 = reaper.ImGui_CalcTextSize(ctx, num2_str)
    local width4, height4 = reaper.ImGui_CalcTextSize(ctx, num2_str)

    local spacing_x, spacing_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
    total_width = width1 + spacing_x + width2 + width3 + spacing_x + width4 + 25  -- с запасом
    total_height = height1 + 16 -- с запасом  
end 

function loop()
    reaper.ImGui_PushFont(ctx, font)

    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_WindowTitleAlign(),  0.5, 0.5)
    reaper.ImGui_PushStyleVar  (ctx,   reaper.ImGui_StyleVar_SeparatorTextAlign(),  0.5,0.5)
    reaper.ImGui_PushStyleColor(ctx,   reaper.ImGui_Col_Separator(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(title_colors.r, title_colors.g, title_colors.b, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    
    -- reaper.ImGui_SetNextFrameWantCaptureKeyboard( ctx, 1 )
    -- reaper.ImGui_SetNextWindowSize(ctx, 88, 44, reaper.ImGui_Cond_Always())
    reaper.ImGui_SetNextWindowSize(ctx, total_width, total_height, reaper.ImGui_Cond_Always())


    local visible, open = reaper.ImGui_Begin(ctx, 'ReaReaRea', true,  window_flags)
    if visible then
        frame()
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx,4)
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopFont(ctx)
    
    if open then
        reaper.defer(loop)
    else
        reaper.ImGui_DestroyContext(ctx)
    end

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
  

reaper.defer(loop)