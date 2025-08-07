-- @description Master FX Inverter Panel
-- @author Misha Oshkanov
-- @version 1.6
-- @about
--  Manages bypass states of effects in master fx chain
--  use activate and deactivate toggle scripts to switch bypass states 

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


font_size = 20
local ctx = reaper.ImGui_CreateContext('BM')
local font = reaper.ImGui_CreateFont('sans-serif', 0)
-- reaper.ImGui_Attach(ctx, font)

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

list_window_flags =  
                reaper.ImGui_WindowFlags_NoTitleBar() +  
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

master_active = true
mark = false
def_w = 80
-- fx_list = {}


function table_find(list,element) -- find element v of l satisfying f(v)
    for _, v in ipairs(fx_list) do
        if v.guid == element then
          return true
        end
    end
    return false
end

function frame()

    fx_list = {}
    mode_label = "master"
    -- master_mode = reaper.ImGui_RadioButton(ctx, mode_label, master_active)
    -- reaper.ImGui_Button(ctx, mode_label, 0, size_hIn )

    if master_mode then master_active = not master_active end 

    if master_active then 
        track = reaper.GetMasterTrack(0)

        count_fx = reaper.TrackFX_GetCount(track)
        for i=1,count_fx do 
            fx_data = {id=nil, active = nil, name = nil}
            fx_active = reaper.TrackFX_GetEnabled(track, i-1)
            -- retval, fx_name = reaper.TrackFX_GetFXName(track, i-1)
            retval, fx_type = reaper.TrackFX_GetNamedConfigParm(track, i-1, 'fx_type')
            retval, fx_name = reaper.TrackFX_GetNamedConfigParm(track, i-1, 'fx_name')
            off = reaper.TrackFX_GetOffline( track, i-1 )
            guid = reaper.TrackFX_GetFXGUID(track, i-1)
            fx_name = string.gsub(fx_name,fx_type..': ','')
            fx_name = string.gsub(fx_name,'%b()', '')
            fx_data.guid = guid
            fx_data.active = fx_active
            fx_data.name = fx_name
            fx_data.mark = false

            if not off then table.insert(fx_list, fx_data) end
            -- if table_find(fx_list,guid) == false then 
            --     table.insert(fx_list, fx_data)
            -- end
        end

        for id,fx in ipairs(fx_list) do 
            reaper.ImGui_PushID(ctx, id)

            if toggle_state == '1' then 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),           rgba(230, 90, 85, 1))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),              rgba(152, 52, 52, 1))
            else 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),           rgba(85, 135, 230, 1))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),              rgba(100, 100, 100, 1))

            end

            if fx.active then 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               rgba(240,240,240,1))
            else 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               rgba(150,150,150,1))
            end

            retval, val = reaper.GetProjExtState(0, 'INEED_BYPASS_MANAGER', fx.guid)
            -- print(val:find('1'))
            if val:find('1') then mark = true  else mark = false end
            fx_state = fx.active == false and 'b' or 'a'


            b = reaper.ImGui_RadioButton(ctx, fx.name, mark)

            w, h = reaper.ImGui_CalcTextSize(ctx, fx.name)
            if w > def_w then def_w = w end 

            if set_all then 
                reaper.SetProjExtState(0, 'INEED_BYPASS_MANAGER', fx.guid, '1'..fx_state)
                if id == #fx_list then set_all = false end
            end

            if set_none then 
                reaper.SetProjExtState(0, 'INEED_BYPASS_MANAGER', fx.guid, '0'..fx_state)
                if id == #fx_list then set_none = false end
            end

            if b then 
                if val:find('1') then val = '0'  else val = '1' end
                reaper.SetProjExtState(0, 'INEED_BYPASS_MANAGER', fx.guid, val..fx_state)
            end

            reaper.ImGui_PopStyleColor(ctx, 3)
            reaper.ImGui_PopID(ctx)
        end

        width = reaper.ImGui_GetWindowWidth(ctx)
        if not b_toggle then toggle_text = 'Invert State' end

        reaper.ImGui_Dummy( ctx, width, 5 )

        b_all = reaper.ImGui_Button(ctx, 'All', (width-23)/2, 26)
        reaper.ImGui_SameLine(ctx)
        b_none = reaper.ImGui_Button(ctx, 'None', (width-23)/2, 26)
        b_toggle = reaper.ImGui_Button(ctx, toggle_text, width-15, 26)


        if b_all then 
            set_all = true 
        elseif b_none then 
            set_none = true 
        elseif b_toggle then  
            toggle_text = 'Inverted'   

            reaper.Undo_BeginBlock()

            i=-1
            enum, key, val = reaper.EnumProjExtState(0, "INEED_BYPASS_MANAGER", 0)
            while enum ~= false do
                i = i + 1
                enum, key, val = reaper.EnumProjExtState(0, "INEED_BYPASS_MANAGER", i)
                for i=1,count_fx do 
                    guid = reaper.TrackFX_GetFXGUID(track, i-1)
                    if key == guid then 
                        if val:find('1') then 
                            if val:find('b') then 
                                reaper.TrackFX_SetEnabled(track, i-1, toggle_state == '0' and true or false)
                            
                            elseif val:find('a') then 
                                -- print(toggle_state)
                                reaper.TrackFX_SetEnabled(track, i-1, toggle_state == '1' and true or false)
                            end
                        end
                            -- enabled = reaper.TrackFX_GetEnabled(track, i-1)
                            -- reaper.TrackFX_SetEnabled(track, i-1, not enabled)

                    end
                end
            end
            reaper.Undo_EndBlock("Master FX Invert", -1)
        end
    end



end 

function loop()
    reaper.ImGui_PushFont(ctx, nil, font_size)

    _, toggle_state = reaper.GetProjExtState(proj, 'INEED_BYPASS_STATE', "STATE" )

    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_WindowTitleAlign(),  0.5, 0.5)
    reaper.ImGui_PushStyleVar  (ctx,   reaper.ImGui_StyleVar_SeparatorTextAlign(),  0.5,0.5)
    reaper.ImGui_PushStyleColor(ctx,   reaper.ImGui_Col_Separator(),           rgba(28, 29, 30, 1))

    if toggle_state == "1" then 
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(38, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(152, 52, 52, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(152, 52, 52, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),              rgba(152, 52, 52, 1))
    else 
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(title_colors.r, title_colors.g, title_colors.b, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),              rgba(80, 80, 80, 1))
    end
    
    reaper.ImGui_SetNextFrameWantCaptureKeyboard( ctx, 1 )
    if fx_list then reaper.ImGui_SetNextWindowSize(ctx, 58+def_w, 70+36+(30*#fx_list), reaper.ImGui_Cond_Always()) end

    local visible, open = reaper.ImGui_Begin(ctx, 'Master FX Inverter', true,  window_flags)
    if visible then
        frame()
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx,5)
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopFont(ctx)
    
    if open then
        reaper.defer(loop)
    end

end


loop()