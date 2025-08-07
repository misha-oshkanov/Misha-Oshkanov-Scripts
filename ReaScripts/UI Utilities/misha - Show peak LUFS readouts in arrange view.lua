-- @description Show master peak lufs readouts in arrange view
-- @author Misha Oshkanov
-- @version 1.4
-- @about
--  Shows little text readout for master lufs and peak meters
--  Right click toggle to selected track meter readouts. Track mode adds rectangle around the text

--  Показывает текстовые значения LUFS и пика на мастер канале в углу окна аранжировки
--  Правый клик по значению вкючает режим трека, в этом режиме паказаны значеня выбранного трека. В этом режиме вокруг значений появляется прямоугольник

---------------------------------------------------------------------
---------------------------------------------------------------------
floating_window = false
only_master = true
font_size = 24

offset_x = 54
offset_y = 55

window_w = 150
h = 10
lufs_h = 16

------------------------------- COLORS -------------------------------
peak_col_master = {220,220,220,1} -- red, green, blue, alpha
peak_col_track  = {180,180,180,1} -- red, green, blue, alpha

lufs_col_1 = {147,171,226,1} -- red, green, blue, alpha
lufs_col_2 = {210,167,86,1}  -- red, green, blue, alpha
----------------------------------------------------------------------
----------------------------------------------------------------------

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

local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OSX') or os:match('macOS')
local is_linux = os:match('Other')

local ctx = reaper.ImGui_CreateContext('Meter')
local font = reaper.ImGui_CreateFont('sans-serif',reaper.ImGui_FontFlags_Bold())
-- reaper.ImGui_Attach(ctx, font)

proj = 0
active = 0

window_flags =  reaper.ImGui_WindowFlags_NoScrollbar() +
                reaper.ImGui_WindowFlags_NoTitleBar() +
                reaper.ImGui_WindowFlags_NoDocking()  +
                reaper.ImGui_WindowFlags_NoResize()  +
                reaper.ImGui_WindowFlags_NoBackground()
                
-- Initializing variables
last_time = reaper.time_precise() --for general update
ch1_last_peak_time = reaper.time_precise() --for peak hold
ch2_last_peak_time = reaper.time_precise() --for peak hold

padding = 14

update_frequency = 0.05 -- general update frequency in seconds
peak_hold_duration = 0.7 -- peak hold duration in seconds

ch1_max_peak = -150.0 --start with absolute silence
ch2_max_peak = -150.0 --start with absolute silence

hold1 = -150
hold2 = -150

ch1_peak_dB = -150
ch2_peak_dB = -150

function get_bounds(hwnd)
    local _, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
    -- Check voor MacOS
    if reaper.GetOS():match("^OSX") then
        local screen_height = reaper.ImGui_GetMainViewport(ctx).WorkSize.y
        top = screen_height - bottom
        bottom = screen_height - top
    end
    -- return left, top, right-left, bottom-top
    return left, top, right, bottom

    -- local _, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
    -- x, y = reaper.ImGui_PointConvertNative(ctx, x, y, false)
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

function col(col,a)
    r, g, b = reaper.ColorFromNative(col)
    result = rgba(r,g,b,a)
    return result
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

function log10(x)
    return math.log(x) / math.log(10)
end

function dbToLog(dB)
    return 1 - log10(-dB) / log10(1 / 10)
end

function dbToNormalized(dB)
    return 10 ^ (dB / 20)
end

function trunc(num, digits)
    local mult = 10^(digits)
    return math.modf(num*mult)/mult
end

function draw_color_fill(color)
    button_col = 0xaf1d70
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x+2, max_y,  color,2,0,2)
end

track_mode = false

function frame()
    master = reaper.GetMasterTrack(0)
    track = reaper.GetSelectedTrack(0, 0)
    w = reaper.ImGui_GetWindowWidth(ctx)

    if track_mode and track then target = track else target = master end

    ch1 = reaper.Track_GetPeakInfo(target, 0)
    ch2 = reaper.Track_GetPeakInfo(target, 1)

    lch1 = reaper.Track_GetPeakInfo(master, 1024)
    lch2 = reaper.Track_GetPeakInfo(master, 1025)

    ch1_peak_dB = VAL2DB(ch1)
    ch2_peak_dB = VAL2DB(ch2)
    
    hold1 = (reaper.Track_GetPeakHoldDB( master, 0, false ))
    hold2 = (reaper.Track_GetPeakHoldDB( master, 1, false ))

    ch1_current_time = reaper.time_precise()
    if ch1_peak_dB > ch1_max_peak or ch1_current_time - ch1_last_peak_time >= peak_hold_duration then 
        ch1_max_peak = ch1_peak_dB
        ch1_last_peak_time = ch1_current_time
    end

    ch2_current_time = reaper.time_precise()
    if ch2_peak_dB > ch2_max_peak or ch2_current_time - ch2_last_peak_time >= peak_hold_duration then 
        ch2_max_peak = ch2_peak_dB
        ch2_last_peak_time = ch2_current_time
    end
  
    current_peak = math.max(ch1_max_peak, ch2_max_peak)
    current_lufs = math.max(VAL2DB(lch1), VAL2DB(lch2))

    if current_peak>-50 then 
        text1 = tostring(trunc(current_peak,1))
        lufs = trunc(current_lufs,1)
    else text1 = '' lufs = ''
    end 
        
    reaper.ImGui_PushStyleVar( ctx,    reaper.ImGui_StyleVar_SeparatorTextPadding(), 0.1,0.1 ) 
    reaper.ImGui_PushStyleVar( ctx,    reaper.ImGui_StyleVar_SeparatorTextAlign(), 1, 0.5) 
    reaper.ImGui_PushStyleVar( ctx,    reaper.ImGui_StyleVar_SeparatorTextBorderSize(), 0) 

    if current_lufs < -9 then
        lufs_color =  rgba(lufs_col_1[1],lufs_col_1[2],lufs_col_1[3],lufs_col_1[4])
    else
        lufs_color =  rgba(lufs_col_2[1],lufs_col_2[2],lufs_col_2[3],lufs_col_2[4])
    end


    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), lufs_color)

    reaper.ImGui_SeparatorText( ctx, lufs )
    if track_mode then 
        if track then 
            draw_color_fill(rgba(230, 170, 145, 0.5)) 
        else 
            draw_color_fill(rgba(200, 200, 200, 0.5))
        end
    end

    clicked = reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_ButtonFlags_MouseButtonLeft())
    if clicked then 
        track_mode = not track_mode
    end

    reaper.ImGui_PopStyleColor(ctx,1)

    peak_color = rgba(140,140,140,1)
    
    if current_peak<-30 then 
        peak_color = rgba(114,178,255,0.7)
    elseif current_peak<-18 then 
        peak_color = rgba(90,219,149,0.7)
    elseif current_peak<-6 then 
        peak_color = rgba(220,218,217,1)
    elseif current_peak<-3 then 
        peak_color = rgba(232,204,132,0.8)
    elseif current_peak<-0 then 
        peak_color = rgba(219,172,90,1)
    elseif current_peak>-0 then 
        peak_color = rgba(209,105,105,1)
    end

    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), peak_color)

    reaper.ImGui_SeparatorText(ctx, text1)
    if track_mode then 
        if track then 
            draw_color_fill(rgba(230, 170, 145, 0.5)) 
        else 
            draw_color_fill(rgba(200, 200, 200, 0.5))
        end
    end

    reaper.ImGui_PopStyleColor(ctx,1)
    reaper.ImGui_PopStyleVar(ctx,3)
end

function loop()
    reaper.ImGui_PushFont(ctx, font, font_size)
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(36, 37, 38, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(52, 66, 54, 1))

    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_WindowPadding(), 3,4) 
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_ItemSpacing(),   0,0) 
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_WindowMinSize(), 2,14) 

    -- retval, left, top, right, bottom = reaper.JS_Window_GetClientRect( mainHWND )
    -- retval, ar_left, ar_top, ar_right, ar_bottom = reaper.JS_Window_GetClientRect(windowHWND)
    
    reaper.ImGui_SetNextWindowSize(ctx, 70, 70,  reaper.ImGui_Cond_Always())
    
    mainHWND = reaper.GetMainHwnd()
    windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
    left, top, right, bottom = get_bounds(windowHWND)



    -- x, y = reaper.ImGui_PointConvertNative(ctx, x, y, false)

    if not floating_window then 
            reaper.ImGui_SetNextWindowPos(ctx, right-offset_x, bottom-offset_y, condIn, 0.5, 0.5)

        -- if is_windows then 
        --     scale = reaper.ImGui_GetWindowDpiScale(ctx)
        --     reaper.ImGui_SetNextWindowPos(ctx, (ar_right-offset_x)*(1/scale), (ar_bottom-offset_y)*(1/scale), condIn, 0.5, 0.5)
        -- else 
        --     reaper.ImGui_SetNextWindowPos(ctx, ar_right-offset_x, ar_bottom-offset_y, condIn, 0.5, 0.5)
        -- end
    end
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Meter', true, window_flags)
    if visible then
      frame()
      reaper.ImGui_End(ctx)
    end

    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopFont(ctx)
    
    if open then
      reaper.defer(loop)
    end

end

loop()