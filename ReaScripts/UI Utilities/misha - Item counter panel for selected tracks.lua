-- @description Item counter panel for selected track
-- @author Misha Oshkanov
-- @version 1.6
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

function col(col,a)
    r, g, b = reaper.ColorFromNative(col)
    result = rgba(r,g,b,a)
    return result
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
    
font_size = 26

local ctx = reaper.ImGui_CreateContext('MIDI Ghost Manager')
local font = reaper.ImGui_CreateFont('sans-serif')

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
        is_mute = reaper.GetMediaItemInfo_Value(item, 'B_MUTE') == 1
        local lane_plays = reaper.GetMediaItemInfo_Value(item, 'C_LANEPLAYS') > 0 
        if lane_plays then 
            if not is_mute then num = num + 1 end
        else 
            not_playing_num = not_playing_num + 1 
        end 
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

function frame()
    local first_track = reaper.GetSelectedTrack(0, 0)
    local num1 = 0
    local num2 = 0
    local num3 = 0
    local num4 = 0
    local send_mark    = false
    local receive_mark = false
    local num1_lanes_found  = false
    local num2_lanes_found  = false
    local color = '28290987' 
    local track_name = 'da'
    -- local dummy_spacing1 = 0
    -- local dummy_spacing2 = 0


    if first_track then 
        _, track_name = reaper.GetTrackName(first_track)
        color = reaper.GetTrackColor(first_track)
        if color == 0 then color = '28290987' end
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

        local child_playing, child_not_playing = count_child_playing_items(first_track)
        local playing, not_playing = count_playing_items_in_lanes(first_track)
        -- num1_lanes_found = true
        num1 = num1 + playing
        num2 = num2 + not_playing
        num3 = num3 + child_playing
        num4 = num4 + child_not_playing

    end
    local count = reaper.CountSelectedTracks(0)
    if count > 1 then 
        local folder_found = false
        for i2=0,count-2 do 
            local track = reaper.GetSelectedTrack(0, i2+1)
            local other_playing, other_not_playing = count_playing_items_in_lanes(track)
            local other_child_playing, other_child_not_playing = count_child_playing_items(track)
            
            num3 = num3 + other_playing + other_child_playing
            num4 = num4 + other_not_playing + other_child_not_playing
        end
    end

    w, h = reaper.ImGui_GetWindowSize( ctx )
    reaper.ImGui_PushStyleVar( ctx, reaper.ImGui_StyleVar_ItemSpacing(),0,2)

    -- reaper.ImGui_Dummy(ctx, 1, 1 )
    -- reaper.ImGui_SameLine(ctx)

    if send_mark then
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
        local size = 10 -- размер квадрата
        local padding = 0 -- отступ от краёв окна

        local x1 = win_x + win_w/6 - size
        local y1 = win_y - size/3
        local x2 = x1 + size
        local y2 = y1 + size
        reaper.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, rgba(111, 161, 194, 1))
    end

    if receive_mark then 
        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
        local size = 10 -- размер квадрата
        local padding = 0 -- отступ от краёв окна

        local x1 = win_x + win_w/6 - size +18
        local y1 = win_y - size/3 
        local x2 = x1 + size
        local y2 = y1 + size
        reaper.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, rgba(194, 134, 111, 1))
    end

    -- local dummy_name = 10
    -- reaper.ImGui_TextColored(ctx, col(color,1), track_name)
    -- reaper.ImGui_SameLine(ctx)
    --     reaper.ImGui_Dummy(ctx, dummy_name, 1 )
    -- reaper.ImGui_SameLine(ctx)


    reaper.ImGui_TextColored(ctx, rgba(220, 220, 220, 1), num1)
    reaper.ImGui_SameLine(ctx)
    local dummy_spacing1 = 10  -- после num1

    if 1 then 
        reaper.ImGui_TextColored(ctx, rgba(120, 120, 120, 1), '('..num2..')')
        reaper.ImGui_SameLine(ctx)
    end

    if num3 ~= '' then 
        dummy_spacing1 = 10  -- между группами
        reaper.ImGui_Dummy(ctx, dummy_spacing1, 1 )
        reaper.ImGui_SameLine(ctx)
    end 

    reaper.ImGui_TextColored(ctx, rgba(180, 180, 180, 1), num3)
    if 1 then 
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, rgba(120, 120, 120, 1), '('..num4..')')
    end
    
    reaper.ImGui_PopStyleVar( ctx, 1 )

    local num1_str = tostring(num1 or "")
    local num2_str = '('..tostring(num3)..')'
    local num3_str = tostring(num2 or "")
    local num4_str = '('..tostring(num4)..')'

    local width1, height1 = reaper.ImGui_CalcTextSize(ctx, num1_str)
    local width2, height2 = reaper.ImGui_CalcTextSize(ctx, num2_str)
    local width3, height3 = reaper.ImGui_CalcTextSize(ctx, num3_str)
    local width4, height4 = reaper.ImGui_CalcTextSize(ctx, num4_str)
    local width_name, height_name = reaper.ImGui_CalcTextSize(ctx, track_name)

    
    local spacing_x, spacing_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
    total_width =
    width1 +
    width2 +
    dummy_spacing1 +
    width3 +
    width4 +
    spacing_x * 4 
    -10           
    
    total_height = height1 + 16 
end 

function loop()
    
    reaper.ImGui_PushFont(ctx, nil, font_size)

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