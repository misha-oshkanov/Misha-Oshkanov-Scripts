-- @description Track Renamer
-- @author Misha Oshkanov
-- @version 1.3
-- @about
-- UI panel to quickly rename track with sliders. Work in progress


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

local ctx = reaper.ImGui_CreateContext('MIDI Ghost Manager')
local font = reaper.ImGui_CreateFont('sans-serif', 20)
reaper.ImGui_Attach(ctx, font)

active_type = {}
decode = {}
use_color = true
mode = 15
title_colors = {r=30,g=30,b=30}

window_flags =  reaper.ImGui_WindowFlags_NoScrollWithMouse() +
reaper.ImGui_WindowFlags_NoFocusOnAppearing() +
reaper.ImGui_WindowFlags_NoNavFocus() +
reaper.ImGui_WindowFlags_NoNavInputs() +
reaper.ImGui_WindowFlags_NoScrollbar() + 
reaper.ImGui_WindowFlags_NoResize()

list_window_flags =  reaper.ImGui_WindowFlags_NoTitleBar() +  
                reaper.ImGui_WindowFlags_NoDocking() +
                reaper.ImGui_WindowFlags_NoResize() +
                reaper.ImGui_WindowFlags_NoBackground()  +
                reaper.ImGui_WindowFlags_NoScrollWithMouse() +
                reaper.ImGui_WindowFlags_NoScrollbar()

                -- reaper.ImGui_WindowFlags_TopMost()


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

data = {}
buttons = {}
default_input_text = 'type text to remove'

slider_s=0
slider_e=0


function init_data()
    count = reaper.CountSelectedTracks(0)
    if count then 
        for i=0, count-1 do 
            track_data = {}
            track = reaper.GetSelectedTrack(0, i)
            _, name = reaper.GetTrackName(track)
            state = 0

            track_data.track = track
            track_data.state = state
            track_data.name  = name
        
            found = false
            if #data == 0 then table.insert(data, track_data) end 

            for k, v in ipairs(data) do    
                if v.track == track then
                    found = true
                end 
            end

            if not found then 
                table.insert(data, track_data)
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

        if slider_retval or input_retval then 
            new_name = string.sub(t.name, slider_s+1, #t.name - slider_e)
            new_name = string.gsub(new_name, input_string, '')
            _, _ = reaper.GetSetMediaTrackInfo_String(t.track, 'P_NAME', new_name, 1)
        end

        reaper.ImGui_PopID(ctx)
    end


    if #data > 0 then 
        reaper.ImGui_SetNextItemWidth( ctx, 302 )
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),          rgba(90,90,90,0.6))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),    rgba(184,170,112,0.4))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),   rgba(120,120,120,0.6))

        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(),       rgba(150,150,150,0.8))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), rgba(212,201,120,0.8))

        slider_retval, trim_s, trim_e = reaper.ImGui_SliderInt2( ctx, label, slider_s, slider_e, 0, str_len, formatIn, flagsIn )
        reaper.ImGui_PopStyleColor(ctx,2)

        reaper.ImGui_SetNextItemWidth( ctx, 302 )
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), rgba(90,90,90,0.3))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),    rgba(220,220,220,0.6))

        input_retval, input_string = reaper.ImGui_InputText(ctx, 'input_label', default_input_text,  reaper.ImGui_InputTextFlags_AutoSelectAll(), callbackIn)
        reaper.ImGui_PopStyleColor(ctx,5)
    end


    for k,t in ipairs(data) do 
        reaper.ImGui_PushID(ctx, k)
        
        _, current_name = reaper.GetTrackName(t.track)
        color = reaper.GetTrackColor(t.track)
        -- r, g, b = reaper.ColorFromNative(color)

        if current_name:sub(#current_name) == ' ' or current_name:sub(0,1) == ' '  then 
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), rgba(250, 102, 102, 1))
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), rgba(255, 255, 255, 1))
        end

        if reaper.IsTrackSelected(t.track) then
            reaper.ImGui_BeginGroup(ctx)

            if t.state == 1 then 
                reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Button(),        col(color,0.4))
            else

                reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Button(),        col(color,0.3))
            end

            if show_input then 
                reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Button(),        col(color,0))
                reaper.ImGui_PopStyleColor(ctx)

            end


            reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonHovered(), col(color,0.5))
            reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ButtonActive(),  col(color,0.5))


            reaper.ImGui_PushStyleColor(ctx,   reaper.ImGui_Col_Text(),  rgba(0,0,0,0))

            button = reaper.ImGui_Button(ctx, k, 302, 26)
            
            reaper.ImGui_PopStyleColor(ctx,4)


            -- draw_color_fill(col(color,0.3))
            reaper.ImGui_SameLine(ctx, 1, 1)

            if slider_s > 0 then 
                reaper.ImGui_PushStyleColor(ctx,   reaper.ImGui_Col_FrameBg(), rgba(0,0,0,0))
                reaper.ImGui_TextColored(ctx, rgba(150,150,150,1), string.sub(t.name, 1, slider_s))
                reaper.ImGui_SameLine(ctx, 0, 0)
                reaper.ImGui_PopStyleColor(ctx)
            end

            reaper.ImGui_Text(ctx, current_name)
            
            if slider_e > 0 then 
                reaper.ImGui_SameLine(ctx, 0, 0)
                reaper.ImGui_PushStyleColor(ctx,   reaper.ImGui_Col_FrameBg(), rgba(0,0,0,0))
                reaper.ImGui_TextColored(ctx, rgba(150,150,150,1), string.sub(t.name, #t.name-slider_e+1, #t.name))
                reaper.ImGui_PopStyleColor(ctx)
            end
            
            if button then

                i_clicked_button_x, i_clicked_button_y     = reaper.ImGui_GetItemRectMin(ctx)
                i_clicked_button_x_m, i_clicked_button_y_m = reaper.ImGui_GetItemRectMax(ctx)
                i_clicked_w, i_clicked_h = reaper.ImGui_GetItemRectSize(ctx)

                -- draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                -- reaper.ImGui_DrawList_AddRectFilled(draw_list, i_clicked_button_x, i_clicked_button_y, i_clicked_button_x_m, i_clicked_button_y_m, rgba(255,255,255,1))

                input_str = current_name
                input_track = t.track
                input_trackname = t.name
                input_color = color
                data_id = k

                t.state = 1

                show_input = true

                -- print(current_name)
            end
            reaper.ImGui_EndGroup(ctx)

        else table.remove(data, k) end

        if show_input then
            draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            reaper.ImGui_DrawList_AddRectFilled(draw_list, i_clicked_button_x, i_clicked_button_y, i_clicked_button_x_m, i_clicked_button_y_m, col_sat(color,-0.7))
        end
        
        -- if #t.name > str_len then str_len = #t.name end

        -- if k_retval then 
        --     _, _ = reaper.GetSetMediaTrackInfo_String(t.track, 'P_NAME', k_label, 1)
        --     t.name = k_label
        -- end

        -- if slider_retval or input_retval then 
        --     new_name = string.sub(t.name, s+1, #t.name - e)
        --     new_name = string.gsub(new_name, input_string, '')
        --     _, _ = reaper.GetSetMediaTrackInfo_String(t.track, 'P_NAME', new_name, 1)
        -- end

        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_PopID(ctx)
    end 

    -- if input_activate then 
    --     reaper.ImGui_SetNextItemWidth( ctx, 402 )
    --     k_retval, k_label = reaper.ImGui_InputText( ctx, 0, current_name,  reaper.ImGui_InputTextFlags_EnterReturnsTrue(), callbackIn ) -- reaper.ImGui_InputTextFlags_ReadOnly()
    -- elseif k_retval then input_activate = false end
    
    if slider_retval then
        slider_s = trim_s
        slider_e = trim_e
    elseif input_retval then 
        default_input_text = input_string
    end

    if show_input then 
        reaper.ImGui_PushStyleVar( ctx, reaper.ImGui_StyleVar_WindowMinSize(), 10,10 )
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), rgba(0,0,0,0))

        reaper.ImGui_SetNextWindowPos( ctx, i_clicked_button_x-12,i_clicked_button_y+25, condIn, 0, 1 ) -- h = 1400
        reaper.ImGui_SetNextWindowSize(ctx, 468 - (slider_s*20), 36,  reaper.ImGui_Cond_Always()) 

        input_rv, i_open = reaper.ImGui_Begin( ctx, "input", true, list_window_flags)
        if not input_rv then return i_open end 

        enter_rv, new_name = reaper.ImGui_InputText( ctx, ' ', input_str,  reaper.ImGui_InputTextFlags_EnterReturnsTrue() +  reaper.ImGui_InputTextFlags_NoHorizontalScroll() )
        if enter_rv then 

            _, _ = reaper.GetSetMediaTrackInfo_String( input_track, 'P_NAME', new_name, 1 )

            data[data_id].name = new_name
            data[data_id].state = 0

            slider_s = 0
            slider_e = 0

            show_input = false 
            enter_rv = false
        end

        if not reaper.ImGui_IsWindowFocused(ctx, flagsIn) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), repeatIn) then 
            show_input = false
            enter_rv = false
            data[data_id].state = 0
        end
        
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_End(ctx)
    end  

    -- print(current_name)
end 

function loop()
    reaper.ImGui_PushFont(ctx, font)

    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_WindowTitleAlign(),  0.5, 0.5)
    reaper.ImGui_PushStyleVar  (ctx,   reaper.ImGui_StyleVar_SeparatorTextAlign(),  0.5,0.5)
    reaper.ImGui_PushStyleColor(ctx,   reaper.ImGui_Col_Separator(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(title_colors.r, title_colors.g, title_colors.b, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    
    reaper.ImGui_SetNextFrameWantCaptureKeyboard( ctx, 1 )
    reaper.ImGui_SetNextWindowSize(ctx, 318, 40+59+(30*#data), reaper.ImGui_Cond_Always())

    local visible, open = reaper.ImGui_Begin(ctx, 'Track Renamer', true,  window_flags)
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



reaper.defer(loop)