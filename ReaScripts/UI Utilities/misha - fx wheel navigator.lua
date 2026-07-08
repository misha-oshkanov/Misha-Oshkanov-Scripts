-- @description FX Wheel Navigator
-- @author Misha Oshkanov
-- @version 1.2
-- @about
--   # FX Scroller
--   An interactive overlay utility for REAPER that simplifies plug-in chain management using ReaImGui.
--
--   ### Features:
--   - Centered Overlay Button: Automatically places a floating overlay button right in the center of the focused FX window's title bar.
--   - Mouse Wheel Navigation: Hover over the button and scroll the mouse wheel to cyclically switch between previous or next plug-ins in the track's FX chain (skips offline plugins).
--   - Bypass / Wet Toggles (Click): Left-click toggles full plugin Bypass. Right-click toggles Dry/Wet between 0% and 100%.
--   - Visual Feedback: The button dynamically updates its index number and color. It turns dark grey when active, red when Dry/Wet is set to 0%, and parks itself if no FX window is in focus.
--   - FX Chain Tooltip: Hovering over the button reveals a complete list of FX in the current track's chain, with the currently focused plug-in highlighted.
--
--   ### Requirements:
--   - REAPER v7.06 or higher
--   - ReaImGui extension (v0.10+)
--   - js_ReaScriptAPI extension

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local ctx = ImGui.CreateContext('FX Wheel Navigator')
local font = reaper.ImGui_CreateFont('arial')
local font_size_tooltip = 16
local font_size_main = 14

local last_win_x, last_win_y = 100, 100
local last_valid_x, last_valid_y = 100, 100
local last_fx_hwnd = nil

local target_fx_idx = nil
local should_reposition_window = false

local btn_w, btn_h = 100, 20

local INVERT_SCROLL = false

function rgb(r, g, b)
    a = 1
    local b = b/255
    local g = g/255 
    local r = r/255 
    local b = math.floor(b * 255) * 256
    local g = math.floor(g * 255) * 256 * 256
    local r = math.floor(r * 255) * 256 * 256 * 256
    local a = math.floor(a * 255)
    return r + g + b + a
end

local function round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    if num >= 0 then return math.floor(num * mult + 0.5) / mult
    else return math.ceil(num * mult - 0.5) / mult end
end

function clean_fx_name(name)
  name = tostring(name or "")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("^VST3i:%s*", "")
  name = name:gsub("^VSTi:%s*", "")
  name = name:gsub("^VST3:%s*", "")
  name = name:gsub("^VST:%s*", "")
  name = name:gsub("^CLAPi:%s*", "")
  name = name:gsub("^CLAP:%s*", "")
  name = name:gsub("^AUi:%s*", "")
  name = name:gsub("^LV2i:%s*", "")
  name = name:gsub("^AU:%s*", "")
  name = name:gsub("%s+%(.-%)%s*$", "")
  if name == "" then return "FX" end
  return name
end

function ToggleFXWet(track, fx_idx)
    if not track or not fx_idx then return end
    
    local wetparam = reaper.TrackFX_GetParamFromIdent(track, fx_idx, ":wet")
    if wetparam == -1 then return end -- Если плагин не поддерживает параметр wet
    
    local val = reaper.TrackFX_GetParam(track, fx_idx, wetparam)
    local fxguid = reaper.TrackFX_GetFXGUID(track, fx_idx)
    local _, name = reaper.TrackFX_GetFXName(track, fx_idx, "")
    local msg = ""

    if val > 0 then 
        reaper.SetProjExtState(0, "ToggleWet", fxguid, val)
        reaper.TrackFX_SetParam(track, fx_idx, wetparam, 0)
        reaper.Undo_OnStateChangeEx("Set " .. name .. " to 0% wet", 2, -1)
        msg = ({reaper.GetTrackName(track)})[2] .. "  |  ".. ({reaper.TrackFX_GetFXName(track, fx_idx)})[2] .. "  => 0%"
    else 
        local hasState, stored_val = reaper.GetProjExtState(0, "ToggleWet", fxguid)
        if hasState ~= 1 or not tonumber(stored_val) then
            stored_val = 1
        else
            stored_val = tonumber(stored_val)
        end
        reaper.TrackFX_SetParam(track, fx_idx, wetparam, stored_val)
        reaper.SetProjExtState(0, "ToggleWet", fxguid, "")
        
        local display_val = round(stored_val * 100)
        msg = ({reaper.GetTrackName(track)})[2] .. "  |  ".. ({reaper.TrackFX_GetFXName(track, fx_idx)})[2] .. "  => " .. math.tointeger(display_val) .. "%"
        reaper.Undo_OnStateChangeEx("Set " .. name .. " to " .. display_val .. "% wet", 2, -1)
    end
    
    local x, y = reaper.GetMousePosition()
    -- reaper.TrackCtl_SetToolTip(msg, x, y, true)
end

function Loop()
    if not ImGui.ValidatePtr(ctx, 'ImGui_Context*') then return end

    local fx_found = false
    local current_num = "-"
    local track, fx_idx, fx_count = nil, nil, 0
    local is_wet_zero = false 
     byp = nil
    local retval, track_idx, _, _fx_idx = reaper.GetFocusedFX()

    if retval == 1 then
        fx_idx = _fx_idx
        track = track_idx == 0 and reaper.GetMasterTrack(0) or reaper.GetTrack(0, track_idx-1)

        if track then
            fx_count = reaper.TrackFX_GetCount(track)
            current_num = tostring(fx_idx + 1).."/"..fx_count

            local wetparam = reaper.TrackFX_GetParamFromIdent(track, fx_idx, ":wet")
            byp = reaper.TrackFX_GetEnabled(track, fx_idx) == false
        
            if wetparam ~= -1 then
                local wet_val = reaper.TrackFX_GetParam(track, fx_idx, wetparam)
                if wet_val <= 0.001 then is_wet_zero = true end
            end

            local fx_hwnd = reaper.TrackFX_GetFloatingWindow(track, fx_idx)

            if fx_hwnd then
                local _, l, t, r, b = reaper.JS_Window_GetRect(fx_hwnd)
                if l then 
                    if should_reposition_window and fx_idx == target_fx_idx then
                        local new_w = r - l
                        local half_btn_w = math.floor(btn_w / 2)
                        local old_center_x, old_t_native = reaper.ImGui_PointConvertNative(ctx, last_valid_x + half_btn_w, last_valid_y - 5, true)
                        
                        local half_new_w = math.floor(new_w / 2)
                        local new_l = math.floor(old_center_x - half_new_w)
                        local new_t = math.floor(old_t_native)
                        
                        reaper.JS_Window_Move(fx_hwnd, new_l, new_t)
                        reaper.JS_Window_SetFocus(fx_hwnd)
                        
                        _, l, t, r, b = reaper.JS_Window_GetRect(fx_hwnd)
                        should_reposition_window = false
                        target_fx_idx = nil
                    end

                    local imgui_l, imgui_t = reaper.ImGui_PointConvertNative(ctx, l, t, false)
                    local imgui_r, _       = reaper.ImGui_PointConvertNative(ctx, r, b, false)
                    
                    local imgui_w = imgui_r - imgui_l
                    
                    local half_imgui_w = math.floor(imgui_w / 2)
                    local half_btn_w = math.floor(btn_w / 2)
                    
                    last_win_x = imgui_l + half_imgui_w - half_btn_w
                    last_win_y = imgui_t + 5

                    last_valid_x, last_valid_y = last_win_x, last_win_y
                    fx_found = true
                    last_fx_hwnd = fx_hwnd
                end
            end
        end
    else
        last_fx_hwnd = nil
    end

    if not fx_found then
        last_win_x = -100
        last_win_y = -100
    end
    
    ImGui.PushFont(ctx, font, font_size_main)

    ImGui.SetNextWindowPos(ctx, last_win_x, last_win_y, ImGui.Cond_Always)
    ImGui.SetNextWindowSize(ctx, btn_w, btn_h)

    local window_flags = ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoResize |
                         ImGui.WindowFlags_NoMove | ImGui.WindowFlags_NoBackground |
                         ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_TopMost

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
    local visible, _ = ImGui.Begin(ctx, '##FX_Wheel_Btn', true, window_flags)
    ImGui.PopStyleVar(ctx)

    if visible then
        local btn_color = rgb(100, 100, 100)
        if fx_found then
            if is_wet_zero then
                btn_color = rgb(140, 50, 50)
            elseif byp then 
                btn_color = rgb(51, 68, 114)
            else
                btn_color = rgb(94, 94, 94)
            end
        end

        ImGui.PushStyleColor(ctx, ImGui.Col_Button, btn_color)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, btn_color)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, btn_color)

        ImGui.Button(ctx, current_num, btn_w, btn_h)
        
        if fx_found then
            if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
                local current_state = reaper.TrackFX_GetEnabled(track, fx_idx)
                reaper.TrackFX_SetEnabled(track, fx_idx, not current_state)
                local _, fx_name = reaper.TrackFX_GetFXName(track, fx_idx, "")
                local status_msg = current_state and "Bypassed" or "Enabled"
                reaper.Undo_OnStateChangeEx("Toggle Bypass for " .. fx_name, 2, -1)
                
                local x, y = reaper.GetMousePosition()
                -- reaper.TrackCtl_SetToolTip(clean_fx_name(fx_name) .. " => " .. status_msg, x, y, true)
            end
            
            if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
                ToggleFXWet(track, fx_idx)
            end
        end

        if fx_found and ImGui.IsItemHovered(ctx) then
            ImGui.PushFont(ctx, font, font_size_tooltip)

            ImGui.BeginTooltip(ctx)
            
            local _, track_name = reaper.GetTrackName(track)
            if track_name == "" then track_name = (track == reaper.GetMasterTrack(0)) and "MASTER" or "Track " .. track_idx end
            ImGui.TextDisabled(ctx, track_name)
            ImGui.Separator(ctx)
            
            for i = 0, fx_count - 1 do
                local _, fx_name = reaper.TrackFX_GetFXName(track, i, "")
                local is_byp = reaper.TrackFX_GetEnabled(track, i) == false
                local is_off = reaper.TrackFX_GetOffline(track, i) == true

                fx_name = clean_fx_name(fx_name)
                local line_text = string.format("%d. %s", i + 1, fx_name)
                if not is_off then 
                    if i == fx_idx then
                        if is_byp then c = rgb(132, 150, 255) else c = rgb(255, 227, 11) end
                        if is_wet_zero then c = rgb(207, 74, 74) end
                        ImGui.TextColored(ctx, c, line_text)
                    else
                        if is_byp then c = rgb(93, 93, 93) else c = rgb(238, 238, 238) end
                        ImGui.TextColored(ctx, c, line_text)
                    end
                end
            end
            ImGui.PopFont(ctx)
            ImGui.EndTooltip(ctx)

            local vertical = reaper.ImGui_GetMouseWheel(ctx)
            if INVERT_SCROLL then
                vertical = vertical * -1
            end
            if vertical ~= 0 and fx_count > 1 then
                local next_idx = fx_idx
                local loops = 0
                
                while loops < fx_count do
                    if vertical > 0 then
                        next_idx = (next_idx + 1) % fx_count
                    else
                        next_idx = (next_idx - 1 + fx_count) % fx_count
                    end
                    
                    loops = loops + 1
                    
                    if not reaper.TrackFX_GetOffline(track, next_idx) then
                        target_fx_idx = next_idx
                        break
                    end
                end

                if target_fx_idx and target_fx_idx ~= fx_idx then
                    last_valid_x, last_valid_y = last_win_x, last_win_y
                    should_reposition_window = true
                    
                    reaper.TrackFX_Show(track, fx_idx, 2)
                    reaper.TrackFX_Show(track, target_fx_idx, 3)
                end
            end
        end

        ImGui.PopStyleColor(ctx, 3)
        ImGui.PopFont(ctx)
        ImGui.End(ctx)
    end
    reaper.defer(Loop)
end

reaper.defer(Loop)