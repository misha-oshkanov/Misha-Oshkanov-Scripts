-- @description Project Work Timer: Smart time tracker with tags, afk and focus detection and alarms
-- @author Misha Oshkanov
-- @version 3.0
-- @about
--  Tracks active work time per project tab in REAPER.
--  Switches timers between tabs automatically.
--  Saves time to ExtState only once per minute or on save/exit.
--  Create and color code tags to mark time
--  Right click to open tag window and alarm settings
--  Left click to open statistics

--------------------------------------------------------------------- 
---------------------------------------------------------------------
---------------------------------------------------------------------
function print(msg) 
    if msg==nil then msg="da" end
    reaper.ShowConsoleMsg(tostring(msg) .. '\n') 

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

local total_time = 0
local last_save = reaper.time_precise()
local last_check = reaper.time_precise()
local last_project_ptr = 0 
local last_date_key = "" 
local last_project_path = "" -- Хранит путь к файлу текущего проекта

local alert_time_left = 0    -- Сколько секунд осталось до срабатывания алерта
local alert_duration = 0     -- Общая длительность выбранного таймера
local alert_active = false   

local current_tag = "no tag" -- Тег по умолчанию
local available_tags = {"no tag"} -- Базовый список
local new_tag_buf = "" -- Буфер для ввода имени нового тега
local is_popup_open = false

local move_tag_from = "no tag"
local move_tag_to = "no tag"
local move_minutes_buf = "0"

local move_hours_buf = "0"
local move_mins_buf = "0"
local move_secs_buf = "0"

local AFK_THRESHOLD = 10 
local last_input_time = reaper.time_precise()

local last_mouse_x, last_mouse_y = reaper.GetMousePosition()
local prev_dirty = false

local ctx = reaper.ImGui_CreateContext('Project Work Timer')
local EXT_SECTION = "PROJECT_TIMER_SETTINGS"

local font = reaper.ImGui_CreateFont('arial')
local font_size_ui = 18
local font_size_timer = 24
local font_size_alarm = 22
local button_h = 34

local blink_check = false
local notag_nocoutn_check = false
local day_or_all_check = false
local rendertime_check = false
local afktime_check = false
local is_rendering = false
local is_untitled = false
local minimize_check = false
-- local enlarge_check = false

local edit_mode = "transfer"     -- Режимы: "transfer" (перенос), "change" (изменение), "remove" (удаление)
local change_action = "increase" -- Действия для change: "increase" (добавить), "decrease" (вычесть)
local move_hours_buf = "0"       -- Буфер ввода часов
local move_mins_buf = "0"        -- Буфер ввода минут
local move_secs_buf = "0"        -- Буфер ввода секунд
local move_date_context = ""     -- Хранит дату редактируемого дня


window_flags =  reaper.ImGui_WindowFlags_NoScrollbar() +
                reaper.ImGui_WindowFlags_NoTitleBar() +
                reaper.ImGui_WindowFlags_NoDocking()  +
                reaper.ImGui_WindowFlags_NoResize()  


function col(col,a)
    r, g, b = reaper.ColorFromNative(col)
    result = rgba(r,g,b,a)
    return result
end

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

function draw_color(color,px)
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x, max_y,  color,6,0,px)
end

function save_settings()
    local blink_str      = blink_check          and "1" or "0"
    local nocount_str    = notag_nocoutn_check  and "1" or "0"
    local day_or_all_str = day_or_all_check     and "1" or "0"
    local rendertime_str = rendertime_check     and "1" or "0"
    local afktime_str    = afktime_check        and "1" or "0"
    local minimize_str   = minimize_check       and "1" or "0"
    -- local enlarge_str    = enlarge_check        and "1" or "0"


    reaper.SetExtState(EXT_SECTION, "blink_check",          blink_str,       true)
    reaper.SetExtState(EXT_SECTION, "notag_nocoutn_check",  nocount_str,     true)
    reaper.SetExtState(EXT_SECTION, "day_or_all_check",     day_or_all_str,  true)
    reaper.SetExtState(EXT_SECTION, "rendertime_check",     rendertime_str,  true)
    reaper.SetExtState(EXT_SECTION, "afktime_check",        afktime_str,     true)
    reaper.SetExtState(EXT_SECTION, "minimize_check",       minimize_str,    true)
    -- reaper.SetExtState(EXT_SECTION, "enlarge_check",        enlarge_str,     true)

    reaper.SetExtState(EXT_SECTION, "font_size_ui",    font_size_ui,     true)
    reaper.SetExtState(EXT_SECTION, "font_size_alarm", font_size_alarm,  true)
    reaper.SetExtState(EXT_SECTION, "font_size_timer", font_size_timer,  true)
end 



function load_settings()
    local saved_font_size_ui      = reaper.GetExtState(EXT_SECTION, "font_size_ui")
    local saved_font_size_alarm   = reaper.GetExtState(EXT_SECTION, "font_size_alarm")
    local saved_font_size_timer   = reaper.GetExtState(EXT_SECTION, "font_size_timer")

    blink_check_setting           = reaper.GetExtState(EXT_SECTION, "blink_check")
    notag_nocoutn_check_setting   = reaper.GetExtState(EXT_SECTION, "notag_nocoutn_check")
    day_or_all_check_setting      = reaper.GetExtState(EXT_SECTION, "day_or_all_check")
    rendertime_setting            = reaper.GetExtState(EXT_SECTION, "rendertime_check")
    afktime_setting               = reaper.GetExtState(EXT_SECTION, "afktime_check")
    minimize_setting              = reaper.GetExtState(EXT_SECTION, "minimize_check")
    -- enlarge_setting               = reaper.GetExtState(EXT_SECTION, "enlarge_check")

    if blink_check_setting           and blink_check_setting           ~= "" then blink_check          = (blink_check_setting   == "1")         end
    if notag_nocoutn_check_setting   and notag_nocoutn_check_setting   ~= "" then notag_nocoutn_check  = (notag_nocoutn_check_setting   == "1") end
    if day_or_all_check_setting      and day_or_all_check_setting      ~= "" then day_or_all_check     = (day_or_all_check_setting   == "1")    end
    if rendertime_setting            and rendertime_setting            ~= "" then rendertime_check     = (rendertime_setting   == "1")          end
    if afktime_setting               and afktime_setting               ~= "" then afktime_check        = (afktime_setting   == "1")             end
    if minimize_setting              and minimize_setting              ~= "" then minimize_check       = (minimize_setting   == "1")            end
    -- if enlarge_setting               and enlarge_setting               ~= "" then enlarge_check        = (enlarge_setting   == "1")             end


    if saved_font_size_ui    and saved_font_size_ui    ~= "" then font_size_ui = tonumber(saved_font_size_ui) end 
    if saved_font_size_alarm and saved_font_size_alarm ~= "" then saved_font_size_alarm = tonumber(saved_font_size_alarm) end 
    if saved_font_size_timer and saved_font_size_timer ~= "" then font_size_timer = tonumber(saved_font_size_timer) end 
end 

function save_global_tags()
    local export_table = {}
    for _, t in ipairs(available_tags) do 
        if t and t.name then
            local safe_color = t.color or 0xFFFFFFFF
            table.insert(export_table, string.format("%s:%08X", t.name, safe_color)) 
        end
    end
    local tags_string = table.concat(export_table, ",")
    reaper.SetExtState(EXT_SECTION, "USER_TAGS_V2", tags_string, true)
end

function load_global_tags()
    local loaded_tags = {
        { name = "no tag", color = 0xE8E8E8FF }
    }

    if reaper.HasExtState(EXT_SECTION, "USER_TAGS_V2") then
        local tags_string = reaper.GetExtState(EXT_SECTION, "USER_TAGS_V2")
        if tags_string ~= "" then
            for pair in string.gmatch(tags_string, "([^,]+)") do
                local name = ""
                local color_val = 0xFFFFFFFF
                
                if pair:find(":") then
                    local t_name, color_str = pair:match("([^:]+):([0-9A-Fa-f]+)")
                    if t_name then 
                        name = string.lower(t_name)
                        color_val = tonumber(color_str, 16) or 0xFFFFFFFF
                    end
                else
                    if pair ~= "" then name = string.lower(pair) end
                end
                
                if name ~= "" and name ~= "no tag" then
                    table.insert(loaded_tags, { name = name, color = color_val })
                end
            end
        end
    end
    
    available_tags = loaded_tags
end


function GetTagColor(tag_name, is_afk)
    if is_afk then return 0x808080FF end
    
    local safe_name = tostring(tag_name or "unknown"):lower():gsub("^%s*(.-)%s*$", "%1")

    if safe_name == "rendering" then return 0xFF9900FF end
    if safe_name == "afk" then return 0x888888FF end  -- Серый для простоя
    
    for _, t in ipairs(available_tags) do 
        if type(t) == "table" and t.name then
            local check_name = t.name:lower():gsub("^%s*(.-)%s*$", "%1")
            if check_name == safe_name then 
                return t.color or 0xFFFFFFFF 
            end 
        end 
    end
    
    return 0xE8E8E899
end

function GetCurrentDateKey() return os.date("%Y-%m-%d") end


function key_down()
    local key = reaper.JS_Mouse_GetState(95)
    if key == 4 or key == 5 then return 'ctrl'
    elseif key == 8 or key == 9 then return 'shift'
    elseif key == 16 or key == 17 then return 'alt'
    else return nil 
    end
end

function load_proj_time(proj_ptr, date_key, tag)
    if not proj_ptr then return 0 end
    local key = "TOTAL_TIME_" .. date_key .. "_" .. tag
    local retval, saved_time = reaper.GetProjExtState(proj_ptr, "TIME_TRACKER", key)
    return tonumber(saved_time) or 0
end

function FormatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

function IsReaperRendering()
  local A,B=reaper.EnumProjects(0x40000000,"")  
  if A~=nil then 
    return true, reaper.GetPlayPositionEx(A), reaper.GetProjectLength(A), A
  else return false 
  end
end

function ImportHistoryFromRPP(target_proj_ptr)
    if not target_proj_ptr then return end
    
    if not reaper.JS_Dialog_BrowseForOpenFiles then
        reaper.MB("Для выбора файла через проводник необходимо установить расширение js_ReaScriptAPI через ReaPack!", "Ошибка", 0)
        return
    end
    
    local retval, file_path = reaper.JS_Dialog_BrowseForOpenFiles(
        "Выберите .RPP файл для импорта истории времени",
        "", 
        "", 
        "REAPER Project Files (*.rpp)\0*.rpp\0All Files (*.*)\0*.*\0", 
        false 
    )
    
    if retval == 0 or file_path == "" then return end
    
    local file = io.open(file_path, "r")
    if not file then
        reaper.MB("Не удалось прочитать выбранный файл.", "Ошибка импорта", 0)
        return
    end
    
    local idx = 0
    local keys_to_delete = {}
    while true do
        local r_ok, key, _ = reaper.EnumProjExtState(target_proj_ptr, "TIME_TRACKER", idx)
        if not r_ok then break end
        if key and key:match("^TOTAL_TIME_") then table.insert(keys_to_delete, key) end
        idx = idx + 1
    end
    for _, k in ipairs(keys_to_delete) do
        reaper.SetProjExtState(target_proj_ptr, "TIME_TRACKER", k, "")
    end
    
    local imported_count = 0
    local is_inside_time_tracker = false
    
    for line in file:lines() do
        local clean_line = line:gsub("^%s*(.-)%s*$", "%1")
        
        if clean_line:match("^<TIME_TRACKER") then
            is_inside_time_tracker = true
        elseif clean_line:match("^>") and is_inside_time_tracker then
            is_inside_time_tracker = false
        end
        
        if is_inside_time_tracker and clean_line:match("TOTAL_TIME_") then
            local key, val = clean_line:match('^"?TOTAL_TIME_([^"]+)"?%s+(%d+%.?%d*)')
            
            if key and val then
                local full_key = "TOTAL_TIME_" .. key
                
                reaper.SetProjExtState(target_proj_ptr, "TIME_TRACKER", full_key, val)
                imported_count = imported_count + 1
            end
        end
    end
    file:close()
    
    local current_date_key = GetCurrentDateKey()
    total_time = load_proj_time(target_proj_ptr, current_date_key, current_tag)
    -- if day_or_all_check then 
    -- total_time = load_proj_time(current_proj_ptr, current_date_key, current_tag)
    -- else 
    -- total_time = load_total_tag_time(current_proj_ptr, current_tag)
    -- end
    -- reaper.MarkProjectDirty(target_proj_ptr)
    
    reaper.MB(string.format("Successful import!\nData loaded: %d", imported_count), "Done", 0)
end

function ClearProjectHistory(target_proj_ptr)
    if not target_proj_ptr then return end
    
    local answer = reaper.MB(
        "Are you sure you want to COMPLETELY DELETE the entire time history for this project?\nThis action cannot be undone!",
        "Warning: Clearing history",
        4 -- Флаг 4 означает кнопки "Да / Нет" (Yes / No)
    )
    
    if answer == 7 then return end
    
    local idx = 0
    local keys_to_delete = {}
    
    while true do
        local r_ok, key, _ = reaper.EnumProjExtState(target_proj_ptr, "TIME_TRACKER", idx)
        if not r_ok then break end
        if key and key:match("^TOTAL_TIME_") then 
            table.insert(keys_to_delete, key) 
        end
        idx = idx + 1
    end
    
    for _, k in ipairs(keys_to_delete) do
        reaper.SetProjExtState(target_proj_ptr, "TIME_TRACKER", k, "")
    end
    
    total_time = 0
    last_save = reaper.time_precise()
    
    -- reaper.MarkProjectDirty(target_proj_ptr)
    
    reaper.MB("The entire time history for the current project has been successfully deleted!", "Done", 0)
end

function SortTagsCustom(a, b)
    local tag_a = tostring(a):lower():gsub("^%s*(.-)%s*$", "%1")
    local tag_b = tostring(b):lower():gsub("^%s*(.-)%s*$", "%1")
    
    if tag_a == "no tag" then return true end
    if tag_b == "no tag" then return false end
    if tag_a == "rendering" then return false end
    if tag_b == "rendering" then return true end
    if tag_a == "afk" then return false end
    if tag_b == "afk" then return true end
    
    return tag_a < tag_b
end


function DrawStatsWindow(proj_ptr)
    if not show_stats_window or not proj_ptr then return end
    
    reaper.ImGui_SetNextWindowSize(ctx, 340, 450, reaper.ImGui_Cond_FirstUseEver())
    
    local visible, open = reaper.ImGui_Begin(ctx, "Project Time Statistics", true, reaper.ImGui_WindowFlags_NoCollapse())
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 8, 8) 
    if not open then show_stats_window = false end
    
    if visible then
        local idx = 0
        local history = {}
        local dates_order = {}
        local dates_set = {}
        
        local total_project_time = 0
        local total_per_tag = {}
        local daily_totals = {}

        -- 1. СБОР И АГРЕГАЦИЯ ДАННЫХ ИЗ БАЗЫ ПРОЕКТА
        while true do
            local retval, key, val = reaper.EnumProjExtState(proj_ptr, "TIME_TRACKER", idx)
            if not retval then break end
            
            if key and key:match("^TOTAL_TIME_") then
                local date, tag = key:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)_(.+)$")
                if not date then
                    date = key:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)$")
                    if date then tag = "no tag" end
                end
                
                if date and tag then
                    local clean_tag = tag:lower():gsub("^%s*(.-)%s*$", "%1")
                    local sec = tonumber(val) or 0
                    
                    if date == GetCurrentDateKey() and clean_tag == current_tag then
                        local past_days_time = 0
                        local sub_idx = 0
                        while true do
                            local r_sub, k_sub, v_sub = reaper.EnumProjExtState(proj_ptr, "TIME_TRACKER", sub_idx)
                            if not r_sub then break end
                            if k_sub and k_sub:match("^TOTAL_TIME_") then
                                local d_sub, t_sub = k_sub:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)_(.+)$")
                                if d_sub and t_sub and d_sub ~= GetCurrentDateKey() and t_sub:lower():gsub("^%s*(.-)%s*$", "%1") == clean_tag then
                                    past_days_time = past_days_time + (tonumber(v_sub) or 0)
                                end
                            end
                            sub_idx = sub_idx + 1
                        end
                        sec = math.max(0, total_time - past_days_time)
                    end
                    
                    if not history[date] then history[date] = {} end
                    history[date][clean_tag] = sec
                    
                    if not dates_set[date] then
                        dates_set[date] = true
                        table.insert(dates_order, date)
                    end

                    total_per_tag[clean_tag] = (total_per_tag[clean_tag] or 0) + sec
                end
            end
            idx = idx + 1
        end
        
        local cur_date = GetCurrentDateKey()
        if not history[cur_date] or not history[cur_date][current_tag] then
            if not history[cur_date] then history[cur_date] = {} end
            
            local past_days_time = 0
            local sub_idx = 0
            while true do
                local r_sub, k_sub, v_sub = reaper.EnumProjExtState(proj_ptr, "TIME_TRACKER", sub_idx)
                if not r_sub then break end
                if k_sub and k_sub:match("^TOTAL_TIME_") then
                    local d_sub, t_sub = k_sub:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)_(.+)$")
                    if d_sub and t_sub and d_sub ~= cur_date and t_sub:lower():gsub("^%s*(.-)%s*$", "%1") == current_tag then
                        past_days_time = past_days_time + (tonumber(v_sub) or 0)
                    end
                end
                sub_idx = sub_idx + 1
            end
            
            local live_today_sec = math.max(0, total_time - past_days_time)
            history[cur_date][current_tag] = live_today_sec
            
            if not dates_set[cur_date] then table.insert(dates_order, cur_date) end
            
            total_per_tag[current_tag] = live_today_sec
        end

        for _, d_key in ipairs(dates_order) do
            daily_totals[d_key] = 0
            for t_name, s_val in pairs(history[d_key]) do
                if t_name ~= "rendering" or rendertime_check then
                    if t_name ~= "afk" then
                        daily_totals[d_key] = daily_totals[d_key] + s_val
                    end
                end
            end
        end

        total_project_time = 0
        
        for t_name, total_sec in pairs(total_per_tag) do
            if t_name ~= "afk" then
                if t_name ~= "rendering" or rendertime_check then
                    total_project_time = total_project_time + total_sec
                end
            end
        end
        
        reaper.ImGui_Spacing(ctx)

        local total_tags_order = {}
        for tag_name, _ in pairs(total_per_tag) do
            table.insert(total_tags_order, tag_name)
        end
        table.sort(total_tags_order, SortTagsCustom)

        -- for _, tag_name in ipairs(total_tags_order) do
        --     local total_sec = total_per_tag[tag_name] or 0
        --     local should_hide_render = (tag_name == "rendering" and not rendertime_check)
            
        --     if total_sec > 0 and not should_hide_render then
        --         local tag_color = GetTagColor(tag_name, false)
        --         reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), tag_color) 
        --         reaper.ImGui_ColorButton(ctx, "##ico_" .. tag_name, tag_color, 0, 10, 20)
        --         reaper.ImGui_PopStyleColor(ctx, 1)
        --         reaper.ImGui_SameLine(ctx)
        --         reaper.ImGui_TextColored(ctx, tag_color, string.format("%s: %s", FormatTime(total_sec), tag_name)) 
        --         reaper.ImGui_SameLine(ctx)
        --     end
        -- end

                -- Вывод кнопок-иконок и интерактивных названий тегов
        for _, tag_name in ipairs(total_tags_order) do
            local total_sec = total_per_tag[tag_name] or 0
            local should_hide_render = (tag_name == "rendering" and not rendertime_check)
            local should_hide_afk    = (tag_name == "afk" and not afktime_check)

            if total_sec > 0 and not should_hide_render and not should_hide_afk then
                local tag_color = GetTagColor(tag_name, false)
                
                local is_currently_active = (current_tag == tag_name)

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), tag_color) 
                reaper.ImGui_ColorButton(ctx, "##ico_" .. tag_name, tag_color, 0, 10, 20)
                reaper.ImGui_PopStyleColor(ctx, 1)
                
                reaper.ImGui_SameLine(ctx)
                
                local r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(tag_color)
                local bg_active_color = reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 0.20)  -- 20% яркости для активного
                local bg_hover_color  = reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 0.35)  -- 35% яркости при наведении
                
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), bg_active_color)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), bg_hover_color)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(),  bg_hover_color)

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), tag_color)

                
                local label_text = string.format("%s: %s##sel_%s",FormatTime(total_sec), tag_name, tag_name)
                
                local tag_clicked = reaper.ImGui_Selectable(ctx, label_text, is_currently_active)
                
                reaper.ImGui_PopStyleColor(ctx, 4)
                
                if tag_clicked and tag_name ~= "rendering" and tag_name ~= "afk" then
                    local current_date_key = GetCurrentDateKey()
                    save_proj_time(proj_ptr, current_date_key, current_tag, total_time)
                    
                    current_tag = tag_name
                    
                    total_time = load_total_tag_time(proj_ptr, current_tag)
                    
                    reaper.SetProjExtState(proj_ptr, "TIME_TRACKER", "LAST_ACTIVE_TAG", current_tag)
                    reaper.MarkProjectDirty(proj_ptr)
                end
            end
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_Text(ctx, string.format("Total: %s", FormatTime(total_project_time)))

        -- reaper.ImGui_TextColored(ctx, 0x888888FF, string.format("AFK: %s", FormatTime(global_afk_total)))

        local window_width, _ = reaper.ImGui_GetContentRegionAvail(ctx)
        window_width = window_width - 8

        reaper.ImGui_Spacing(ctx)
        
        if reaper.ImGui_Button(ctx, "Save", window_width/3, 24) then
            local current_date_key = GetCurrentDateKey()
            save_proj_time(proj_ptr, current_date_key, current_tag, total_time)
            last_save = reaper.time_precise()
        end

        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Button(ctx, "Import", window_width/3, 24) then ImportHistoryFromRPP(proj_ptr) end 
        reaper.ImGui_SameLine(ctx)
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF333340)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF333366)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF8888FF)
        
        if reaper.ImGui_Button(ctx, "Clear", window_width/3, 24) then ClearProjectHistory(proj_ptr) end
        
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_TextDisabled(ctx, "Daily stats:")
        reaper.ImGui_Spacing(ctx)
        
        table.sort(dates_order, function(a, b) return a > b end)
        
        local open_move_popup = false
        local target_move_date = ""

        for _, date in ipairs(dates_order) do
            local day_sec = daily_totals[date] or 0
            local avail_width, _ = reaper.ImGui_GetContentRegionAvail(ctx)
            local cursor_start_x = reaper.ImGui_GetCursorPosX(ctx)
            local absolute_right_edge = cursor_start_x + avail_width

            local node_id = "##node_" .. date
            local is_node_open = reaper.ImGui_TreeNode(ctx, node_id,reaper.ImGui_TreeNodeFlags_AllowOverlap()+reaper.ImGui_TreeNodeFlags_SpanAvailWidth())

            local date_start_x = reaper.ImGui_GetCursorPosX(ctx)

            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_Text(ctx, date)

            local date_w, _ = reaper.ImGui_CalcTextSize(ctx, date)
            local date_right_edge = date_start_x + date_w -- Конец текста даты
            local time_string = FormatTime(day_sec)
            local text_w, _ = reaper.ImGui_CalcTextSize(ctx, time_string)
            local is_overlapping = false
            local x_btn_width = 24  -- space reserved for X button on the right
            local target_same_line_x = absolute_right_edge - x_btn_width - text_w - 10

            if is_node_open then
                is_overlapping = (target_same_line_x < date_right_edge + 13)
            else 
                is_overlapping = (target_same_line_x < date_right_edge + 34) -- +10 пикселей безопасного зазора
            end

            if not is_overlapping then
                reaper.ImGui_SameLine(ctx, target_same_line_x)
                edit_button = reaper.ImGui_Button(ctx, time_string, text_w+10, 22 )
                reaper.ImGui_SetItemTooltip( ctx, "Click to edit time" )
                if edit_button then 
                    target_move_date = date
                    open_move_popup = true
                end
            end
            -- Remove all button (X) - always visible on right edge
            do
                local x_btn_x = absolute_right_edge - x_btn_width
                reaper.ImGui_SameLine(ctx, x_btn_x)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF333340)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF333366)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF8888FF)
                if reaper.ImGui_Button(ctx, "X##del_" .. date, 20, 22) then
                    -- Collect all tags for this date and remove them
                    local del_idx = 0
                    local keys_to_delete = {}
                    local prefix = "TOTAL_TIME_" .. date .. "_"
                    local exact_key = "TOTAL_TIME_" .. date
                    while true do
                        local d_r, d_key, d_val = reaper.EnumProjExtState(proj_ptr, "TIME_TRACKER", del_idx)
                        if not d_r then break end
                        if d_key and (d_key:find(prefix, 1, true) == 1 or d_key == exact_key) then
                            table.insert(keys_to_delete, d_key)
                        end
                        del_idx = del_idx + 1
                    end
                    for _, dk in ipairs(keys_to_delete) do
                        reaper.SetProjExtState(proj_ptr, "TIME_TRACKER", dk, "")
                    end
                    total_time = load_total_tag_time(proj_ptr, current_tag)
                    reaper.MarkProjectDirty(proj_ptr)
                end
                reaper.ImGui_PopStyleColor(ctx, 3)
                reaper.ImGui_SetItemTooltip( ctx, "Remove all time for this day" )
            end

            if is_node_open then
                local day_tags_order = {}
                for tag_name, _ in pairs(history[date]) do
                    table.insert(day_tags_order, tag_name)
                end
                table.sort(day_tags_order, SortTagsCustom)

                for _, tag_name in ipairs(day_tags_order) do
                    local sec = history[date][tag_name] or 0
                    local should_hide_render = (tag_name == "rendering" and not rendertime_check)
                    local should_hide_afk    = (tag_name == "afk" and not afktime_check)

                    if sec > 0 and not should_hide_render and not should_hide_afk then
                        local tag_color = GetTagColor(tag_name, false)
                        reaper.ImGui_TextColored(ctx, tag_color, string.format("    %s: %s", FormatTime(sec),  tag_name or "unknown"))
                    end
                end
                
                -- reaper.ImGui_Spacing(ctx)
                -- reaper.ImGui_Dummy(ctx,0,10)
                -- reaper.ImGui_SameLine(ctx)
                -- if reaper.ImGui_Button(ctx, "Edit##btn_" .. date, 86, 22) then
                --     target_move_date = date
                --     open_move_popup = true
                -- end
                
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Dummy(ctx,0,4)

                reaper.ImGui_TreePop(ctx)
            end
        end

        if open_move_popup then
            reaper.ImGui_OpenPopup(ctx, "Edit Time Popup")
            move_date_context = target_move_date
        end

        if reaper.ImGui_BeginPopupModal(ctx, "Edit Time Popup", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_Text(ctx, "Date context: " .. tostring(move_date_context))
            reaper.ImGui_Spacing(ctx)
            
            reaper.ImGui_SetNextItemWidth(ctx, 150)
            if reaper.ImGui_BeginCombo(ctx, "Function", edit_mode) then
                if reaper.ImGui_Selectable(ctx, "transfer", edit_mode == "transfer") then edit_mode = "transfer" end
                if reaper.ImGui_Selectable(ctx, "change", edit_mode == "change") then edit_mode = "change" end
                if reaper.ImGui_Selectable(ctx, "remove", edit_mode == "remove") then edit_mode = "remove" end
                reaper.ImGui_EndCombo(ctx)
            end
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            -- [РЕЖИМ 1: TRANSFER] Перенос из одного тега в другой
            if edit_mode == "transfer" then
                local current_from_day_sec = load_proj_time(proj_ptr, move_date_context, move_tag_from)
                local combo_from_label = string.format("%s  (%s)", move_tag_from, FormatTime(current_from_day_sec))
                
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTagColor(move_tag_from, false))
                local begin_from = reaper.ImGui_BeginCombo(ctx, "From", combo_from_label)
                reaper.ImGui_PopStyleColor(ctx)

                if begin_from then
                    for _, t in ipairs(available_tags) do
                        if type(t) == "table" and t.name then
                            local tag_day_sec = load_proj_time(proj_ptr, move_date_context, t.name)
                            local item_label = string.format("%s  [%s]", t.name, FormatTime(tag_day_sec))
                            
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTagColor(t.name, false))
                            local selected = reaper.ImGui_Selectable(ctx, item_label, move_tag_from == t.name)
                            reaper.ImGui_PopStyleColor(ctx)
                            if selected then move_tag_from = t.name end
                        end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end

                local current_to_day_sec = load_proj_time(proj_ptr, move_date_context, move_tag_to)
                local combo_to_label = string.format("%s  (%s)", move_tag_to, FormatTime(current_to_day_sec))

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTagColor(move_tag_to, false))
                local begin_to = reaper.ImGui_BeginCombo(ctx, "To", combo_to_label)
                reaper.ImGui_PopStyleColor(ctx)

                if begin_to then
                    for _, t in ipairs(available_tags) do
                        if type(t) == "table" and t.name then
                            local tag_day_sec = load_proj_time(proj_ptr, move_date_context, t.name)
                            local item_label = string.format("%s  [%s]", t.name, FormatTime(tag_day_sec))
                            
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTagColor(t.name, false))
                            local selected = reaper.ImGui_Selectable(ctx, item_label, move_tag_to == t.name)
                            reaper.ImGui_PopStyleColor(ctx)
                            if selected then move_tag_to = t.name end
                        end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end

                reaper.ImGui_Text(ctx, "Time to transfer:")
                
                reaper.ImGui_SetNextItemWidth(ctx, 35)
                local rc_h, txt_h = reaper.ImGui_InputText(ctx, "h##move_h", move_hours_buf)
                if rc_h then move_hours_buf = txt_h end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Dummy(ctx,10,10)
                reaper.ImGui_SameLine(ctx)
                
                reaper.ImGui_SetNextItemWidth(ctx, 35)
                local rc_m, txt_m = reaper.ImGui_InputText(ctx, "m##move_m", move_mins_buf)
                if rc_m then move_mins_buf = txt_m end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Dummy(ctx,10,10)
                reaper.ImGui_SameLine(ctx)
                
                reaper.ImGui_SetNextItemWidth(ctx, 35)
                local rc_s, txt_s = reaper.ImGui_InputText(ctx, "s##move_s", move_secs_buf)
                if rc_s then move_secs_buf = txt_s end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Dummy(ctx,10,10)
                reaper.ImGui_SameLine(ctx)

                if reaper.ImGui_Button(ctx, "All##all_transfer", 45, 0) then
                    if current_from_day_sec > 0 then
                        move_hours_buf = tostring(math.floor(current_from_day_sec / 3600))
                        move_mins_buf = tostring(math.floor((current_from_day_sec % 3600) / 60))
                        move_secs_buf = tostring(math.floor(current_from_day_sec % 60))
                    else
                        move_hours_buf, move_mins_buf, move_secs_buf = "0", "0", "0"
                    end
                end

            -- [РЕЖИМ 2: CHANGE] Добавление или вычитание времени у выбранного тега
            elseif edit_mode == "change" then
                local current_from_day_sec = load_proj_time(proj_ptr, move_date_context, move_tag_from)
                local combo_from_label = string.format("%s  (%s)", move_tag_from, FormatTime(current_from_day_sec))

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTagColor(move_tag_from, false))
                local begin_change = reaper.ImGui_BeginCombo(ctx, "Select Tag", combo_from_label)
                reaper.ImGui_PopStyleColor(ctx)

                if begin_change then
                    for _, t in ipairs(available_tags) do
                        if type(t) == "table" and t.name then
                            local tag_day_sec = load_proj_time(proj_ptr, move_date_context, t.name)
                            local item_label = string.format("%s  [%s]", t.name, FormatTime(tag_day_sec))
                            
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTagColor(t.name, false))
                            local selected = reaper.ImGui_Selectable(ctx, item_label, move_tag_from == t.name)
                            reaper.ImGui_PopStyleColor(ctx)
                            if selected then move_tag_from = t.name end
                        end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end

                reaper.ImGui_SetNextItemWidth(ctx, 120)
                if reaper.ImGui_BeginCombo(ctx, "Action", change_action) then
                    if reaper.ImGui_Selectable(ctx, "increase", change_action == "increase") then change_action = "increase" end
                    if reaper.ImGui_Selectable(ctx, "decrease", change_action == "decrease") then change_action = "decrease" end
                    reaper.ImGui_EndCombo(ctx)
                end

                reaper.ImGui_Text(ctx, "Time to increase/decrese:")
                
                reaper.ImGui_SetNextItemWidth(ctx, 35)
                local rc_h, txt_h = reaper.ImGui_InputText(ctx, "h##change_h", move_hours_buf)
                if rc_h then move_hours_buf = txt_h end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Dummy(ctx,10,10)
                reaper.ImGui_SameLine(ctx)
                
                reaper.ImGui_SetNextItemWidth(ctx, 35)
                local rc_m, txt_m = reaper.ImGui_InputText(ctx, "m##change_m", move_mins_buf)
                if rc_m then move_mins_buf = txt_m end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Dummy(ctx,10,10)
                reaper.ImGui_SameLine(ctx)
                
                reaper.ImGui_SetNextItemWidth(ctx, 35)
                local rc_s, txt_s = reaper.ImGui_InputText(ctx, "s##change_s", move_secs_buf)
                if rc_s then move_secs_buf = txt_s end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Dummy(ctx,10,10)
                reaper.ImGui_SameLine(ctx)

                if reaper.ImGui_Button(ctx, "All##all_change", 45, 0) then
                    if current_from_day_sec > 0 then
                        move_hours_buf = tostring(math.floor(current_from_day_sec / 3600))
                        move_mins_buf = tostring(math.floor((current_from_day_sec % 3600) / 60))
                        move_secs_buf = tostring(math.floor(current_from_day_sec % 60))
                    else
                        move_hours_buf, move_mins_buf, move_secs_buf = "0", "0", "0"
                    end
                end

            -- [РЕЖИМ 3: REMOVE] Очистка тега за выбранные сутки
            elseif edit_mode == "remove" then
                local current_from_day_sec = load_proj_time(proj_ptr, move_date_context, move_tag_from)
                local combo_from_label = string.format("%s  (%s)", move_tag_from, FormatTime(current_from_day_sec))

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTagColor(move_tag_from, false))
                local begin_remove = reaper.ImGui_BeginCombo(ctx, "Tag to reset", combo_from_label)
                reaper.ImGui_PopStyleColor(ctx)

                if begin_remove then
                    for _, t in ipairs(available_tags) do
                        if type(t) == "table" and t.name then
                            local tag_day_sec = load_proj_time(proj_ptr, move_date_context, t.name)
                            local item_label = string.format("%s  [%s]", t.name, FormatTime(tag_day_sec))
                            
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTagColor(t.name, false))
                            local selected = reaper.ImGui_Selectable(ctx, item_label, move_tag_from == t.name)
                            reaper.ImGui_PopStyleColor(ctx)
                            if selected then move_tag_from = t.name end
                        end 
                    end 
                    reaper.ImGui_EndCombo(ctx)
                end
                reaper.ImGui_TextColored(ctx, 0xFF3333FF, "Warning: OK will delete all time for this tag on this day.")
            end
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF333340)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF333366)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF8888FF)
            if reaper.ImGui_Button(ctx, "Remove All##rmv_all", 120, 24) then
                local del_idx = 0
                local keys_to_delete = {}
                local prefix = "TOTAL_TIME_" .. move_date_context .. "_"
                local exact_key = "TOTAL_TIME_" .. move_date_context
                while true do
                    local d_r, d_key, d_val = reaper.EnumProjExtState(proj_ptr, "TIME_TRACKER", del_idx)
                    if not d_r then break end
                    if d_key and (d_key:find(prefix, 1, true) == 1 or d_key == exact_key) then
                        table.insert(keys_to_delete, d_key)
                    end
                    del_idx = del_idx + 1
                end
                for _, dk in ipairs(keys_to_delete) do
                    reaper.SetProjExtState(proj_ptr, "TIME_TRACKER", dk, "")
                end
                total_time = load_total_tag_time(proj_ptr, current_tag)
                reaper.MarkProjectDirty(proj_ptr)
                move_hours_buf, move_mins_buf, move_secs_buf = "0", "0", "0"
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx, 3)
            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_Button(ctx, "OK", 80, 24) then
                local input_hours = tonumber(move_hours_buf) or 0
                local input_mins  = tonumber(move_mins_buf) or 0
                local input_secs  = tonumber(move_secs_buf) or 0
                local delta_secs  = (input_hours * 3600) + (input_mins * 60) + input_secs

                if edit_mode == "transfer" then 
                    if delta_secs > 0 and move_tag_from ~= move_tag_to then
                        local current_from_time = load_proj_time(proj_ptr, move_date_context, move_tag_from)
                        local actual_move = math.min(delta_secs, current_from_time)
                        if actual_move > 0 then
                            local current_to_time = load_proj_time(proj_ptr, move_date_context, move_tag_to)
                            reaper.SetProjExtState(proj_ptr, "TIME_TRACKER", "TOTAL_TIME_" .. move_date_context .. "_" .. move_tag_from, tostring(current_from_time - actual_move))
                            reaper.SetProjExtState(proj_ptr, "TIME_TRACKER", "TOTAL_TIME_" .. move_date_context .. "_" .. move_tag_to, tostring(current_to_time + actual_move))
                        end 
                    end
                elseif edit_mode == "change" then
                    if delta_secs > 0 then
                        local current_time = load_proj_time(proj_ptr, move_date_context, move_tag_from)
                        local new_time = current_time
                        if change_action == "increase" then
                            new_time = current_time + delta_secs
                        elseif change_action == "decrease" then
                            new_time = math.max(0, current_time - delta_secs)
                        end
                        reaper.SetProjExtState(proj_ptr, "TIME_TRACKER", "TOTAL_TIME_" .. move_date_context .. "_" .. move_tag_from, tostring(new_time))
                    end
                elseif edit_mode == "remove" then
                    reaper.SetProjExtState(proj_ptr, "TIME_TRACKER", "TOTAL_TIME_" .. move_date_context .. "_" .. move_tag_from, "")
                end

                total_time = load_total_tag_time(proj_ptr, current_tag)
                reaper.MarkProjectDirty(proj_ptr)

                move_hours_buf, move_mins_buf, move_secs_buf = "0", "0", "0"reaper.ImGui_CloseCurrentPopup(ctx) 

            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Cancel", 80, 24) then
                move_hours_buf, move_mins_buf, move_secs_buf = "0", "0", "0"
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                move_hours_buf, move_mins_buf, move_secs_buf = "0", "0", "0"
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
        end
        local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        local btn_height = 22
        local dummy_height = avail_h - btn_height - 5
        
        if dummy_height > 0 then
            reaper.ImGui_Dummy(ctx, 1, dummy_height)
        end

        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),          0xFFFFFF66)   -- Серый цвет иконки
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        0x00000000)   -- Прозрачный фон
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x44444488)   -- Легкая полупрозрачная подложка при наведении
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  0x666666AA)   -- Чуть плотнее при клике
        
        if reaper.ImGui_Button(ctx, "⛭ Settings ##settings_btn", avail_w, btn_height) then
            reaper.ImGui_OpenPopup(ctx, "settings_popup")
        end
        reaper.ImGui_PopStyleColor(ctx, 4)
        
        if reaper.ImGui_BeginPopup( ctx, "settings_popup", flagsIn ) then 

            blink_check_r,         blink_check         = reaper.ImGui_Checkbox(ctx, "Button blinks if no tag", blink_check)
            notag_nocoutn_check_r, notag_nocoutn_check = reaper.ImGui_Checkbox(ctx, "Do not start timer if no tag",  notag_nocoutn_check)
            day_or_all_check_r,    day_or_all_check    = reaper.ImGui_Checkbox(ctx, "Show only Today time on timer",  day_or_all_check)
            rendertime_check_r,    rendertime_check    = reaper.ImGui_Checkbox(ctx, "Capture rendering time",  rendertime_check)
            afktime_check_r,       afktime_check       = reaper.ImGui_Checkbox(ctx, "Capture afk time",  afktime_check)
            -- enlagre_check_r,       enlagre_check       = reaper.ImGui_Checkbox(ctx, "Enlarge on hover in minimized view",  enlagre_check)

            reaper.ImGui_Spacing( ctx )

            font_size_timer_r,  font_size_timer = reaper.ImGui_SliderInt(ctx, "Timer size",      font_size_timer ,  7, 35)
            font_size_ui_r,     font_size_ui_sl = reaper.ImGui_SliderInt(ctx, "Font size UI",    font_size_ui_sl ,  7, 35)
            font_size_alarm_r,  font_size_alarm = reaper.ImGui_SliderInt(ctx, "Font size Alarm", font_size_alarm ,  7, 35)

            if font_size_ui_sl then 
                if reaper.ImGui_IsMouseReleased( ctx, reaper.ImGui_MouseButton_Left()) then 
                    if font_size_ui_sl == 0 then 
                        font_size_ui_sl = font_size_ui
                    else
                        font_size_ui = font_size_ui_sl
                    end
                end
            end
            

            if blink_check_r or notag_nocoutn_check_r or font_size_timer_r or font_size_ui_r or 
            font_size_alarm_r or day_or_all_check_r or rendertime_check_r or afktime_check_r or enlagre_check_r then 
                if reaper.ImGui_IsMouseReleased( ctx, reaper.ImGui_MouseButton_Left() ) then 
                    save_settings()
                end
            end
            reaper.ImGui_Dummy(ctx,4,4)
            reaper.ImGui_TextDisabled( ctx, "Hotkeys and info:" )
            reaper.ImGui_TextDisabled( ctx, "Ctrl + click on timer to toggle show only today timer" )
            reaper.ImGui_TextDisabled( ctx, "Shift + click on timer to toggle minimize" )
            reaper.ImGui_TextDisabled( ctx, "Esc to close popups" )
            reaper.ImGui_TextDisabled( ctx, "Dot in the corner means that only today time will be shown" )

            reaper.ImGui_EndPopup( ctx )
        end 
        

        reaper.ImGui_PopStyleVar(ctx, 1)

        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            show_stats_window = false
        end

        reaper.ImGui_End(ctx)
    end
end



function GetCurrentDateKey()
    return os.date("%Y-%m-%d")
end

function load_proj_time(proj_ptr, date_key, tag)
    if not proj_ptr then return 0 end
    local key = "TOTAL_TIME_" .. date_key .. "_" .. tag
    local retval, saved_time = reaper.GetProjExtState(proj_ptr, "TIME_TRACKER", key)
    return tonumber(saved_time) or 0
end

function save_proj_time(proj_ptr, date_key, tag, current_total_time)
    if not proj_ptr or date_key == "" or tag == "" then return end
    if not reaper.ValidatePtr(proj_ptr, "ReaProject*") then return end
    
    local past_days_time = 0
    local idx = 0
    local target_tag = tostring(tag):lower():gsub("^%s*(.-)%s*$", "%1")
    
    while true do
        local retval, key, val = reaper.EnumProjExtState(proj_ptr, "TIME_TRACKER", idx)
        if not retval then break end
        
        if key and key:match("^TOTAL_TIME_") then
            local d, t = key:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)_(.+)$")
            if not d and target_tag == "no tag" then
                d = key:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)$")
                if d then t = "no tag" end
            end
            
            if d and t and d ~= date_key and t:lower():gsub("^%s*(.-)%s*$", "%1") == target_tag then
                past_days_time = past_days_time + (tonumber(val) or 0)
            end
        end
        idx = idx + 1
    end
    
    local today_only_time = math.max(0, current_total_time - past_days_time)
    
    local key = "TOTAL_TIME_" .. date_key .. "_" .. target_tag
    reaper.SetProjExtState(proj_ptr, "TIME_TRACKER", key, tostring(today_only_time))
    reaper.SetProjExtState(proj_ptr, "TIME_TRACKER", "LAST_ACTIVE_TAG", target_tag)
    -- reaper.MarkProjectDirty(proj_ptr) 
end

function load_total_tag_time(proj_ptr, current_tag_name)
    if not proj_ptr then return 0 end
    
    local total_accumulated_seconds = 0
    local idx = 0
    local target_tag = tostring(current_tag_name or ""):lower():gsub("^%s*(.-)%s*$", "%1")
    
    while true do
        local retval, key, val = reaper.EnumProjExtState(proj_ptr, "TIME_TRACKER", idx)
        if not retval then break end
        
        if key and key:match("^TOTAL_TIME_") then
            local date, tag = key:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)_(.+)$")
            
            if not date and target_tag == "no tag" then
                date = key:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)$")
                if date then tag = "no tag" end
            end
            
            if date and tag then
                local clean_tag = tag:lower():gsub("^%s*(.-)%s*$", "%1")
                if clean_tag == target_tag then
                    total_accumulated_seconds = total_accumulated_seconds + (tonumber(val) or 0)
                end
            end
        end
        idx = idx + 1
    end
    
    return total_accumulated_seconds
end

function FormatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

function rgba(r, g, b, a)
    return reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, a or 1.0)
end

function get_bounds(hwnd)
    if not hwnd then return 0, 0, 300, 200 end
    local _, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
    if reaper.GetOS():match("^OSX") then
        local screen_height = reaper.ImGui_GetMainViewport(ctx).WorkSize.y
        top = screen_height - bottom
        bottom = screen_height - top
    end
    return left, top, right, bottom
end

function IsReaperFocused()
    if not reaper.JS_Window_GetFocus then return true end
    local focusHwnd = reaper.JS_Window_GetFocus()
    local mainHwnd = reaper.GetMainHwnd()
    local parent = focusHwnd
    while true do
        local nextParent = reaper.JS_Window_GetParent(parent)
        if not nextParent or nextParent == parent then break end
        parent = nextParent
    end
    return parent == mainHwnd
end

function IsPlayingOrRecording()
    local transportState = reaper.GetPlayState()
    return (transportState & 1 == 1) or (transportState & 4 == 4)
end

function atexit()
    local current_proj_ptr, _ = reaper.EnumProjects(-1)
    if current_proj_ptr and reaper.ValidatePtr(current_proj_ptr, "ReaProject*") and last_date_key ~= "" then
        save_proj_time(current_proj_ptr, last_date_key, current_tag, total_time)
    end
end


function delete_tag(tag_name)
    if tag_name == "no tag" then return end
    local delete_idx = nil
    for idx, t in ipairs(available_tags) do
        if type(t) == "table" and t.name == tag_name then
            delete_idx = idx
            break
        end
    end
    
    if delete_idx then
        table.remove(available_tags, delete_idx)
        save_global_tags()
        
        if current_tag == tag_name then
            local current_proj_ptr, _ = reaper.EnumProjects(-1)
            if #available_tags > 0 then
                current_tag = available_tags[1].name
            else
                table.insert(available_tags, { name = "no tag", color = 0xFF6B6BFF })
                current_tag = "no tag"
                save_global_tags()
            end
            
            if current_proj_ptr then
                total_time = load_total_tag_time(current_proj_ptr, current_tag)
            end
        end
    end
end 


function frame()
    local now = reaper.time_precise()
    local delta = now - last_check
    last_check = now
    local button_label = "  Timer  "

    local current_proj_ptr, _ = reaper.EnumProjects(-1)
    local current_date_key = GetCurrentDateKey()

    local proj_name = reaper.GetProjectName(0)
    is_untitled = (proj_name == "")

    if rendertime_check then is_rendering = IsReaperRendering() else is_rendering = false end 

    if current_proj_ptr and not is_untitled then
        local current_proj_path = reaper.GetProjectPath()

        if current_proj_ptr ~= last_project_ptr or current_date_key ~= last_date_key or current_proj_path ~= last_project_path then
            
            if last_project_ptr and last_date_key ~= "" and current_proj_path == last_project_path then
                save_proj_time(last_project_ptr, last_date_key, current_tag, total_time)
            end

            local has_last_tag, last_tag_val = reaper.GetProjExtState(current_proj_ptr, "TIME_TRACKER", "LAST_ACTIVE_TAG")
            if has_last_tag and last_tag_val ~= "" then
                current_tag = last_tag_val:lower():gsub("^%s*(.-)%s*$", "%1")
            else
                current_tag = "no tag"
            end
            
            total_time = load_total_tag_time(current_proj_ptr, current_tag)
            
            last_project_ptr = current_proj_ptr
            last_date_key = current_date_key
            last_project_path = current_proj_path
            last_save = now 
        end

        local is_afk = false
        if IsReaperFocused() or IsPlayingOrRecording() and not notag_nocoutn_check then
            local mouse_x, mouse_y = reaper.GetMousePosition()
            local mouse_state = reaper.JS_Mouse_GetState and reaper.JS_Mouse_GetState(0xFFFF) or 0

            if mouse_x ~= last_mouse_x or mouse_y ~= last_mouse_y or mouse_state ~= 0 then
                last_input_time = now
                last_mouse_x, last_mouse_y = mouse_x, mouse_y
            end

            if IsPlayingOrRecording() or (rendertime_check and is_rendering) then 
                last_input_time = now 
            end

            is_afk = (now - last_input_time) > AFK_THRESHOLD
            
            if delta < 60 and not is_afk then 
                 if rendertime_check and is_rendering then
                    local render_day_sec = load_proj_time(current_proj_ptr, current_date_key, "rendering")
                    render_day_sec = render_day_sec + delta
                    
                    local r_key = "TOTAL_TIME_" .. current_date_key .. "_rendering"
                    reaper.SetProjExtState(current_proj_ptr, "TIME_TRACKER", r_key, tostring(render_day_sec))
                else
                    total_time = total_time + delta 
                end
                if rendertime_check then
                    if not is_rendering and oldrender==true then
                        reaper.MarkProjectDirty(current_proj_ptr)
                    end
                    oldrender=is_rendering
                end
            end
        else 
            is_afk = true 
            if delta < 6 and afktime_check then
                local afk_day_sec = load_proj_time(current_proj_ptr, current_date_key, "afk")
                afk_day_sec = afk_day_sec + delta
                reaper.SetProjExtState(current_proj_ptr, "TIME_TRACKER", "TOTAL_TIME_" .. current_date_key .. "_afk", tostring(afk_day_sec))
                reaper.MarkProjectDirty(current_proj_ptr)
            end
        end
        
        if now - last_save >= 60 then
            save_proj_time(current_proj_ptr, last_date_key, current_tag, total_time)
            last_save = now
        end

        local display_seconds = total_time

        if day_or_all_check then
            local past_days_time = 0
            local idx = 0
            local target_tag = current_tag:lower():gsub("^%s*(.-)%s*$", "%1")
            
            while true do
                local retval, key, val = reaper.EnumProjExtState(current_proj_ptr, "TIME_TRACKER", idx)
                if not retval then break end
                
                if key and key:match("^TOTAL_TIME_") then
                    local d, t = key:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)_(.+)$")
                    if not d and target_tag == "no tag" then
                        d = key:match("^TOTAL_TIME_(%d%d%d%d%-%d%d%-%d%d)$")
                        if d then t = "no tag" end
                    end
                    
                    -- Складываем время ВСЕХ дней, кроме СЕГОДНЯШНЕГО
                    if d and t and d ~= current_date_key and t:lower():gsub("^%s*(.-)%s*$", "%1") == target_tag then
                        past_days_time = past_days_time + (tonumber(val) or 0)
                    end
                end
                idx = idx + 1
            end
            
            display_seconds = math.max(0, total_time - past_days_time)
        end

        local text_color = GetTagColor(current_tag, is_afk)
        local r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(text_color)
        
        local text_a = 1.0
        local bg_a = 0.15

        if blink_check and not is_afk then 
            if current_tag == "no tag" then
                local time_now = reaper.time_precise()
                local pulse = 0.65 + math.sin(time_now * math.pi * 2) * 0.35
                text_a = pulse
                bg_a = 0.15 * pulse
            end
        end
        
        local final_text_color = reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, text_a)
        local bg_color = reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, bg_a)
        local hover_color = reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 0.40)
        local active_color = reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, 0.70)

        local target_font = font_timer or font
        if target_font then reaper.ImGui_PushFont(ctx, target_font, font_size_timer) end
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), final_text_color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), bg_color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hover_color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), active_color)
        
        
        if is_rendering then 
            button_label = " Render "
        elseif minimize_check then 
            button_label = "|##button"
        else
            button_label = FormatTime(display_seconds)
        end
        if minimize_check then button_h = 22 else button_h = 34 end
        local clicked = reaper.ImGui_Button(ctx, button_label, 0, button_h)

        local item_min_x, item_min_y = reaper.ImGui_GetItemRectMin(ctx)
        local item_max_x, item_max_y = reaper.ImGui_GetItemRectMax(ctx)
        if not minimize_check then
        DrawAlertProgressBar(item_min_x, item_min_y, item_max_x, item_max_y)
        end

         if day_or_all_check and not minimize_check then
            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            
            local circle_x = item_min_x + 1
            local circle_y = item_min_y + 5
            local circle_radius = 2.5 -- Радиус точки
            
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, circle_x, circle_y, circle_radius, text_color)
        end
        
        if alert_active and alert_time_left > 0 and reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_BeginTooltip(ctx)
            reaper.ImGui_PushFont(ctx, font, font_size_alarm )
            reaper.ImGui_TextColored(ctx, 0xFFCC00FF, "Alarm:  ")
            reaper.ImGui_TextColored(ctx, 0xFFCC00FF,  FormatTime(alert_time_left))
            reaper.ImGui_PopFont(ctx)
            reaper.ImGui_EndTooltip(ctx)
        end
        
        reaper.ImGui_PopStyleColor(ctx, 4)
        if target_font then reaper.ImGui_PopFont(ctx) end
        
        if clicked then 
            if key_down()=="ctrl" and not minimize_check then 
                day_or_all_check = not day_or_all_check
            elseif key_down()=="shift" then 
                minimize_check = not minimize_check
                save_settings()
            else
                show_stats_window = not show_stats_window
            end
        end
        if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) then reaper.ImGui_OpenPopup(ctx, 'TimerContextMenu') end
        
        local should_open_manage_modal = false
        
        if reaper.ImGui_BeginPopup(ctx, 'TimerContextMenu') then
    
            reaper.ImGui_TextDisabled(ctx, "Choose tag:")
            reaper.ImGui_Separator(ctx)
            
            for _, tag_obj in ipairs(available_tags) do
                local tag_name = "unknown"
                local tag_color = 0xFFFFFFFF
                
                if type(tag_obj) == "table" then
                    tag_name = tag_obj.name or "unknown"
                    tag_color = tag_obj.color or 0xFFFFFFFF
                elseif type(tag_obj) == "string" then
                    tag_name = tag_obj
                end
                
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), tag_color) 
                reaper.ImGui_ColorButton(ctx, "##ico_" .. tag_name, tag_color, 0, 10, 22)
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_MenuItem(ctx, tag_name, nil, (current_tag == tag_name)) then
                    save_proj_time(current_proj_ptr, last_date_key, current_tag, total_time)
                    current_tag = tag_name
                    total_time = load_total_tag_time(current_proj_ptr, current_tag)
                end
                reaper.ImGui_PopStyleColor(ctx,1)
            end
            
            reaper.ImGui_Dummy(ctx,5,5)
            reaper.ImGui_Separator(ctx)
            
            reaper.ImGui_PushFont(ctx, nil, 14 )

            if reaper.ImGui_MenuItem(ctx, "        + Add / Modify") then 
                should_open_manage_modal = true 
            end

            reaper.ImGui_PopFont(ctx)

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            
            reaper.ImGui_TextDisabled(ctx, "Set alarm:")
            
            local function set_alert(minutes)
                alert_duration = minutes * 60
                alert_time_left = alert_duration
                alert_active = true
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            if reaper.ImGui_Button(ctx, "15m", 40, 22) then set_alert(15) end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "30m", 40, 22) then set_alert(30) end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "1h", 40, 22) then set_alert(60) end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "2h", 40, 22) then set_alert(120) end
            
            if alert_active and alert_time_left > 0 then
                reaper.ImGui_Dummy( ctx, 10, 10 )
                local status_text = string.format("Alarm in: %s", FormatTime(alert_time_left))
                local reset_text = "Clear alarm"
                
                local popup_width = reaper.ImGui_GetWindowWidth(ctx)
                
                local text_w, _ = reaper.ImGui_CalcTextSize(ctx, status_text)
                local start_x1 = (popup_width - text_w) * 0.5
                reaper.ImGui_SetCursorPosX(ctx, start_x1)
                reaper.ImGui_TextColored(ctx, 0xFFCC00FF, status_text)
                
                -- reaper.ImGui_Spacing(ctx)
                
                local btn_w, _ = reaper.ImGui_CalcTextSize(ctx, reset_text)
                local start_x2 = (popup_width - btn_w) * 0.5
                reaper.ImGui_SetCursorPosX(ctx, start_x2)
                
                if reaper.ImGui_Selectable(ctx, reset_text, false, 0, btn_w) then
                    alert_active = false
                    alert_time_left = 0
                    alert_duration = 0
                end
                reaper.ImGui_Separator(ctx)
            end

            reaper.ImGui_Dummy( ctx, 10, 10 )
            reaper.ImGui_PushFont(ctx, nil, 14 )

            if reaper.ImGui_Button(ctx, "Minimize", -1, 0 ) then
                minimize_check = not minimize_check
                save_settings()
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            reaper.ImGui_PopFont(ctx)
            reaper.ImGui_EndPopup(ctx)
        end
        
        if should_open_manage_modal then
            reaper.ImGui_OpenPopup(ctx, 'Tags')
        end
        
        if reaper.ImGui_BeginPopupModal(ctx, 'Tags', true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            
            for idx, tag_obj in ipairs(available_tags) do
                if type(tag_obj) == "table" then
                    local t_name = tag_obj.name or "unknown"
                    local t_color = tag_obj.color or 0xFFFFFFFF
                    
                    reaper.ImGui_SetNextItemWidth(ctx, 30)
                    local r_ok, new_color = reaper.ImGui_ColorEdit4(ctx, "##cp_" .. t_name, t_color, reaper.ImGui_ColorEditFlags_NoInputs())
                    if r_ok then
                        available_tags[idx].color = new_color
                        save_global_tags() -- Сразу сохраняем новый цвет в память REAPER
                    end
                    
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_TextColored(ctx, t_color, " " .. t_name)
                    reaper.ImGui_SameLine(ctx, 180)
                    
                    if reaper.ImGui_Button(ctx, "Ред.##ed_" .. t_name) then
                        new_tag_buf = t_name
                    end
                    
                    reaper.ImGui_SameLine(ctx)
                    
                    if t_name ~= "no tag" then
                        if reaper.ImGui_Button(ctx, "Удалить##del_" .. t_name) then
                            delete_tag(t_name)
                        end
                    else
                        reaper.ImGui_TextDisabled(ctx, " ")
                    end
                                        
                    reaper.ImGui_Spacing(ctx)
                end
            end
            
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            -- local r_iok, new_color_input = reaper.ImGui_ColorEdit4(ctx, "##cp_" .. t_name, t_color, reaper.ImGui_ColorEditFlags_NoInputs())
            
            reaper.ImGui_SetNextItemWidth(ctx, 160)
            local retval, text = reaper.ImGui_InputText(ctx, "##tag_name_field", new_tag_buf)
            
            if retval then new_tag_buf = text end
            
            reaper.ImGui_SameLine(ctx)
            
            if reaper.ImGui_Button(ctx, "+", 80) then
                if new_tag_buf ~= "" then
                    local cleaned_tag_name = string.lower(new_tag_buf)
                    
                    local exists_idx = nil
                    for idx, t in ipairs(available_tags) do 
                        if type(t) == "table" and t.name == cleaned_tag_name then 
                            exists_idx = idx 
                            break 
                        end 
                    end
                    
                    if not exists_idx then 
                        table.insert(available_tags, { name = cleaned_tag_name, color = 0xFFFFFFFF }) 
                        save_global_tags()
                    end
                    
                    new_tag_buf = "" -- очищаем текстовое поле
                end
            end
            
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_Button(ctx, "Close", -1) then 
                new_tag_buf = ""
                reaper.ImGui_CloseCurrentPopup(ctx) 
            end

            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                new_tag_buf = ""
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            
            reaper.ImGui_EndPopup(ctx)
        end

        if alert_active and alert_time_left <= 0 then
            local format_minutes = math.floor(alert_duration / 60)
            
            alert_active = false
            alert_time_left = 0
            
            reaper.MB(string.format("Таймер на %d мин. завершен! Время вышло.", format_minutes), "Напоминание", 0)
            alert_duration = 0
        end

        DrawStatsWindow(current_proj_ptr)
    end
end


function DrawAlertProgressBar(item_min_x, item_min_y, item_max_x, item_max_y)
    if not alert_active or alert_time_left <= 0 or alert_duration <= 0 then return end

    local time_passed = alert_duration - alert_time_left
    local progress = math.max(0.0, math.min(1.0, time_passed / alert_duration))

    local bar_h = 3
    local bar_min_x = item_min_x
    local bar_max_x = item_min_x + ((item_max_x - item_min_x) * progress)
    local bar_min_y = item_max_y - bar_h
    local bar_max_y = item_max_y

    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local yellow_color = 0xFFCC00C8
    local draw_flags = reaper.ImGui_DrawFlags_RoundCornersBottom()
    local rounding = 6.0 

    reaper.ImGui_DrawList_AddRectFilled(draw_list, bar_min_x, bar_min_y, bar_max_x, bar_max_y, yellow_color, rounding, draw_flags)
end


function loop()
    reaper.ImGui_PushFont(ctx, font, font_size_ui)

    local bg_color = rgb(31,30,30)       -- Обычный цвет фона (непрозрачный)
    local title_bg = 0x1C1D1EFF
    local title_active = 0x344236FF
    local border_color = 0x1C1D1EFF

    if is_untitled then
        bg_color = 0x00000000         -- Полностью прозрачный фон, если проект пустой
        title_bg = 0x00000000
        title_active = 0x00000000
        border_color = 0x00000000
    end

    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          bg_color)

    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           title_bg)
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     title_active)
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_Border(),            border_color)

    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_WindowPadding(), 4, 4) 
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_ItemSpacing(),   4, 4) 
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_WindowMinSize(), 2, 14) 
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_FrameRounding(), 6.0)
    reaper.ImGui_PushStyleVar(ctx,    reaper.ImGui_StyleVar_WindowRounding(), 6.0)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), rgb(70, 70, 70))       -- Фон приглушенный
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), rgb(70, 70, 70))       -- Фон приглушенный
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), rgb(70, 70, 70))       -- Фон приглушенный

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), rgb(81, 80, 80)) -- При наведении
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), rgb(88, 87, 87)) -- При наведении
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), rgb(98, 97, 97)) -- При наведении

    reaper.ImGui_SetNextWindowSize(ctx, 0, button_h+8,  reaper.ImGui_Cond_Always())

    local visible, open = reaper.ImGui_Begin(ctx, 'Project Work Timer', true, window_flags)
    if visible then frame() reaper.ImGui_End(ctx) end

    reaper.ImGui_PopStyleColor(ctx, 10)
    reaper.ImGui_PopStyleVar(ctx, 5)
    reaper.ImGui_PopFont(ctx)
    if open then reaper.defer(loop) end
end

load_global_tags()
local start_proj, _ = reaper.EnumProjects(-1)
if start_proj then
    last_project_ptr = start_proj
    last_date_key = GetCurrentDateKey()
    
    local start_path = reaper.GetProjectPath()
    last_project_path = start_path or ""
    
    local has_last_tag, last_tag_val = reaper.GetProjExtState(start_proj, "TIME_TRACKER", "LAST_ACTIVE_TAG")
    if has_last_tag and last_tag_val ~= "" then
        current_tag = last_tag_val:lower():gsub("^%s*(.-)%s*$", "%1")
    else
        current_tag = "no tag"
    end
    
    total_time = load_total_tag_time(last_project_ptr, current_tag)
end


load_settings()
loop()
reaper.atexit(atexit)