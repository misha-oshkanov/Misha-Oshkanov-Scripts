-- @description Track Noise Detector
-- @author Misha Oshkanov
-- @version 0.9
-- @about
--  Find that one noisy bastard!!!

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

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

function trunc(num, digits)
    local mult = 10^(digits)
    return math.modf(num*mult)/mult
end

local ctx = reaper.ImGui_CreateContext('Track Renamer')
local font = reaper.ImGui_CreateFont('sans-serif', 20)
reaper.ImGui_Attach(ctx, font)

active_type = {}
decode = {}
use_color = true
mode = 15
title_colors = {r=30,g=30,b=30}

window_flags =  
reaper.ImGui_WindowFlags_NoScrollWithMouse() +
reaper.ImGui_WindowFlags_NoFocusOnAppearing() +
reaper.ImGui_WindowFlags_NoNavFocus() +
reaper.ImGui_WindowFlags_NoNavInputs() +
reaper.ImGui_WindowFlags_NoScrollbar() 
-- reaper.ImGui_WindowFlags_NoResize()

function decode(encodedInt)
    local mask = 0xFFFF -- Mask to extract the lower 2 bytes
    local firstInteger = encodedInt & mask
    local secondInteger = (encodedInt >> 16) & mask
    local dec = {firstInteger,secondInteger}
    return dec
end 

function table.find(element,list) -- find element v of l satisfying f(v)
    for _, v in ipairs(list) do
      if element.track == v then
        return true
      end
    end
    return false
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
buttons = {}

slider_s=0
slider_e=0

function init_data()
    
    count = reaper.CountTracks(0)
    if count then 
        for i=1, count do 
            track_data = {}
            track = reaper.GetTrack(0, i-1)
            _, name = reaper.GetTrackName(track)
            solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO' ) ~= 0
            peakL = VAL2DB(reaper.Track_GetPeakInfo(track, 0))
            peakR = VAL2DB(reaper.Track_GetPeakInfo(track, 1))
            peak = trunc(math.max(peakL, peakR),2)

            track_data.track = track
            track_data.peak  = peak
            track_data.name  = name
            track_data.solo  = solo
        
            found = false
            -- if #data == 0 then table.insert(data, track_data) end 

            for k, v in ipairs(data) do    
                if v.track == track then
                    found = true
                    if v.peak < peak then v.peak = peak end
                    -- v.peak = peak
                    if v.name ~= name then v.name = name end
                    v.solo = solo 
                end 
            end

            if not found then 
                if peak > slider_floor then 
                    table.insert(data, track_data)
                end
            end
        end
    end
end

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
    local r, g, b = reaper.ColorFromNative(col)
    local h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)
    -- s = s*sat
    -- s =s-(s/4)
    local v = math.max(v,100)
    local v = math.min(v * vib,230)
    
    local r, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)

    result = rgba(r,g,b,1)
    return result
end

function col_vib_inv(col,vib,a)
    local r, g, b = reaper.ColorFromNative(col)
    local h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)

    if v < 100 then 
        local v = 255 - v
    end
    local v = math.min(v * vib,230)
    localr, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)

    result = rgba(r,g,b,a)
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
    reaper.ImGui_DrawList_AddRectFilled(draw_list, min_x, min_y, max_x, max_y, color)
end

slider_floor = -78

function frame()

    str_len = 0

    init_data()

    for k,t in ipairs(data) do 
        reaper.ImGui_PushID(ctx, k)
        if #t.name > str_len then str_len = #t.name end

        if k_retval then 
            _, _ = reaper.GetSetMediaTrackInfo_String(t.track, 'P_NAME', k_label, 1)
            t.name = k_label
        end

        reaper.ImGui_PopID(ctx)
    end

    reaper.ImGui_PushItemWidth( ctx, w-16 )
    slider_floor_retval, slider_floor = reaper.ImGui_SliderDouble( ctx, ' ', slider_floor, -100, -40, tostring(trunc(slider_floor,2)),  reaper.ImGui_SliderFlags_Logarithmic())
    reaper.ImGui_PopItemWidth( ctx )
    -- reaper.ImGui_PopStyleColor(ctx,2)


    if slider_floor_retval then data = {} end

    for k,t in ipairs(data) do 
        reaper.ImGui_PushID(ctx, k)
        
        _, current_name = reaper.GetTrackName(t.track)
        color = reaper.GetTrackColor(t.track)

        reaper.ImGui_BeginGroup(ctx)

        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Button(),        col(color,0.3))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonHovered(), col(color,0.5))
        reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonActive(),  col(color,0.5))

        if t.solo  then solostate = true else solostate = false end

        b_solostate = reaper.ImGui_RadioButton( ctx, '', solostate )
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_PushStyleVar(ctx,  reaper.ImGui_StyleVar_ButtonTextAlign(),  1, 1)

        button = reaper.ImGui_Button(ctx, t.peak, w-50, 26)
        
        reaper.ImGui_PopStyleColor(ctx,3)

        -- draw_color_fill(col(color,0.3))
        reaper.ImGui_SameLine(ctx, 36, 1)

        reaper.ImGui_Text(ctx, current_name)
        
        
        if button then
            reaper.SetOnlyTrackSelected( t.track )
            scroll_to_track(t.track)
        end

        if b_solostate then 
            reaper.SetTrackUISolo( t.track, -1, 0 )
        end
        reaper.ImGui_EndGroup(ctx)

        -- else table.remove(data, k) end
     
        -- reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_PopID(ctx)
    end 
end 

function loop()
    reaper.ImGui_PushFont(ctx, font)

    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_WindowTitleAlign(),  0.5, 0.5)
    reaper.ImGui_PushStyleVar  (ctx,   reaper.ImGui_StyleVar_SeparatorTextAlign(),  0.5,0.5)
    reaper.ImGui_PushStyleColor(ctx,   reaper.ImGui_Col_Separator(),           rgba(28, 29, 30, 1))
    -- reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(title_colors.r, title_colors.g, title_colors.b, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    
    reaper.ImGui_SetNextFrameWantCaptureKeyboard( ctx, 1 )
    -- reaper.ImGui_SetNextWindowSize(ctx, 318, 40+(30*#data), reaper.ImGui_Cond_Always())

    local visible, open = reaper.ImGui_Begin(ctx, 'Track Noise Detector', true,  window_flags)

    w, h = reaper.ImGui_GetWindowSize( ctx )

    if visible then
        frame()
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopFont(ctx)
    
    if open then
        reaper.defer(loop)
    end

end

reaper.defer(loop)