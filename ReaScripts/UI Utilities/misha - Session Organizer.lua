-- @description UI manager for session prepping
-- @author Misha Oshkanov
-- @version 2.0
-- @about
--  Add target tracks by clicking "Add Selected Tracks" to your session
--  Then type some kerwords
--  Select some tracks and click "Organise" to move selected tracks to target track based by their names and keywords
-- @changelog
--  collapse crush fixed, new partical match checkbox added
--  Added smart folder creator
--  Added smart pan group creator for double tracks
--  Added Check button to check if selected tracks match session rules

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


local ctx = reaper.ImGui_CreateContext('Session Organizer')
font = reaper.ImGui_CreateFont('sans-serif', font_size)
font_size = 16
local ext_key = "SESSION_DATA" -- Ключ для хранения в проекте
local session_data = {}
local match_partial = true -- Состояние чекбокса "Partial Match"
local folder_create = true -- Состояние чекбокса "Smart folder"
local pan_group = true -- Состояние чекбокса "Pan Groups"
local test_unmapped_result = nil -- Здесь будет храниться список нераспределенных треков после теста

local current_bpm = reaper.Master_GetTempo()

local function GetImGuiColor(track)
    local col = reaper.GetTrackColor(track)
    if col == 0 then return nil end -- Если цвет не назначен
    local r, g, b = reaper.ColorFromNative(col)
    -- Возвращаем HEX с прозрачностью (0xRRGGBBAA)
    return (r << 24) | (g << 16) | (b << 8) | 0x66 -- 0x44 это прозрачность фона
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

local function PushTrackStyles()
    local base_col  = 0x00000088 
    local hover_col = 0x444444FF -- Чуть светлее при наведении
    local active_col = 0x222222FF -- Совсем темный при клике

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        base_col)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), hover_col)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         base_col)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  hover_col)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   active_col)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),      0xFFFFFFFF) -- Белая галочка
    
    return true
end

local function sort_session_data()
    table.sort(session_data, function(a, b)
        if reaper.ValidatePtr(a.parent_ptr, "MediaTrack*") and reaper.ValidatePtr(b.parent_ptr, "MediaTrack*") then
            local idx_a = reaper.GetMediaTrackInfo_Value(a.parent_ptr, "IP_TRACKNUMBER")
            local idx_b = reaper.GetMediaTrackInfo_Value(b.parent_ptr, "IP_TRACKNUMBER")
            return idx_a < idx_b
        end
        return false
    end)
end

local function GetTrackDepth(track)
    local depth = 0
    local parent = reaper.GetParentTrack(track)
    while parent do
        depth = depth + 1
        parent = reaper.GetParentTrack(parent)
    end
    return depth
end

local function save_data()
    local serialized = ""
    for _, row in ipairs(session_data) do
        local guid = reaper.GetTrackGUID(row.parent_ptr)
        local mode = row.items_mode and "1" or "0"
        local kw = row.keywords or ""
        local fkw = row.folder_keywords or ""
        local n_on = row.norm_on and "1" or "0"
        local n_db = row.norm_db or -0.1
        local n_type = row.norm_type or 0
        serialized = serialized .. string.format("%s|%s|%s|%s|%s|%s|%s|%s\n", guid, row.name, kw, mode, fkw, n_on, n_db, n_type)
    end
    -- Сохраняем таблицу треков
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", ext_key, serialized)
    -- Сохраняем состояние чекбокса Partial Match
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", "PARTIAL_MATCH", match_partial and "1" or "0")
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", "FOLDER_CREATE", folder_create and "1" or "0")
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", "PAN_GROUP", pan_group and "1" or "0")


end

local function load_data()
    -- Загружаем таблицу (твой текущий код...)
    local _, serialized = reaper.GetProjExtState(0, "MISHA_SESSION_ORGANIZER", ext_key)
    if serialized and serialized ~= "" then
        session_data = {}
        for line in serialized:gmatch("[^\r\n]+") do
            local guid, name, keywords, mode, f_keywords = line:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")
            
            if guid and guid ~= "" then
                local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
                if tr then
                    table.insert(session_data, {
                        parent_ptr = tr,
                        name = name or "Unknown",
                        keywords = keywords or "",
                        items_mode = mode == "1",
                        folder_keywords = f_keywords or "",
                        norm_on = n_on == "1",
                        norm_db = tonumber(n_db) or -0.1,
                        norm_type = tonumber(n_type) or 0 -- 0: Peak, 1: RMS
                    })
                end
            end
        end
    end
    -- Загружаем состояние Partial Match
    local _, pm_state = reaper.GetProjExtState(0, "MISHA_SESSION_ORGANIZER", "PARTIAL_MATCH")
    if pm_state ~= "" then
        match_partial = (pm_state == "1")
    end
    local _, fc_state = reaper.GetProjExtState(0, "MISHA_SESSION_ORGANIZER", "FOLDER_CREATE")
    if fc_state ~= "" then
        folder_create = (fc_state == "1")
    end
        local _, pg_state = reaper.GetProjExtState(0, "MISHA_SESSION_ORGANIZER", "PAN_GROUP")
    if pg_state ~= "" then
        pan_group = (pg_state == "1")
    end
end

load_data()

-- Функция для обрезки пробелов
function string.trim(s) return s:match("^%s*(.-)%s*$") end

-- Функция для корректного перевода кириллицы в нижний регистр (UTF-8)
local function utf8_lower_custom(str)
    local upper = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
    local lower = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
    local res = str:lower() -- Латиницу обработает стандартно
    
    for i = 1, #upper/2 do -- В UTF-8 кириллица занимает 2 байта
        local u_char = upper:sub(i*2-1, i*2)
        local l_char = lower:sub(i*2-1, i*2)
        res = res:gsub(u_char, l_char)
    end
    return res
end

-- Вспомогательная функция для проверки границ слова (UTF-8 safe)
local function is_word_boundary(text, start_pos, end_pos)
    local function is_alphanumeric(pos)
        if pos < 1 or pos > #text then return false end
        local char_code = text:byte(pos)
        if not char_code then return false end
        -- Латиница и Цифры
        if (char_code >= 48 and char_code <= 57) or 
           (char_code >= 65 and char_code <= 90) or 
           (char_code >= 97 and char_code <= 122) then 
            return true 
        end
        -- Все символы UTF-8 (выше 127) считаем буквами
        if char_code > 127 then return true end
        -- Символ подчеркивания '_'
        if char_code == 95 then return true end 
        return false
    end
    return not is_alphanumeric(start_pos - 1) and not is_alphanumeric(end_pos + 1)
end

local function organize_session()
    reaper.Undo_BeginBlock()
    
    local rules = {}
    for _, row in ipairs(session_data) do
        if reaper.ValidatePtr(row.parent_ptr, "MediaTrack*") then
            for kw in row.keywords:gmatch("([^,]+)") do
                local clean_kw = kw:match("^%s*(.-)%s*$")
                if clean_kw and clean_kw ~= "" then
                    local f_keywords = {}
                    if row.folder_keywords then
                        for fkw in row.folder_keywords:gmatch("([^,]+)") do
                            local clean_fkw = fkw:match("^%s*(.-)%s*$")
                            if clean_fkw ~= "" then table.insert(f_keywords, clean_fkw) end
                        end
                    end

                    table.insert(rules, {
                        keyword = utf8_lower_custom(clean_kw),
                        parent = row.parent_ptr,
                        items_mode = row.items_mode,
                        length = #clean_kw,
                        folder_keywords = f_keywords,
                        norm_on = row.norm_on,
                        norm_db = row.norm_db,
                        norm_type = row.norm_type
                    })
                end
            end
        end
    end

    table.sort(rules, function(a, b) return a.length > b.length end)

    local selected_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        selected_tracks[i + 1] = reaper.GetSelectedTrack(0, i)
    end
    local auto_groups = {}
    for i = #selected_tracks, 1, -1 do
        local tr = selected_tracks[i]
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            local _, raw_name = reaper.GetTrackName(tr)
            local tr_name_norm = utf8_lower_custom(raw_name):gsub("_", " ")
            
            for _, rule in ipairs(rules) do
                if tr ~= rule.parent then
                    local start_pos, end_pos = tr_name_norm:find(rule.keyword, 1, true)
                    if start_pos and (match_partial or is_word_boundary(tr_name_norm, start_pos, end_pos)) then
                        local target_parent = rule.parent
                        for _, fkw in ipairs(rule.folder_keywords) do
                            if tr_name_norm:find(utf8_lower_custom(fkw), 1, true) then
                                target_parent = get_or_create_subfolder(rule.parent, fkw)
                                break
                            end
                        end
                        local clean_name = raw_name:lower() 
                        clean_name = clean_name:gsub("_([lr])%s*$", ""):gsub("%s*([lr])%s*$", "") -- 1. Удаляем суффиксы панорамирования (отдельно стоящие L и R)
                        clean_name = clean_name:gsub("%.%d+", "") -- 2. Удаляем точки вместе с дробными индексами (например, .1 или .42)
                        clean_name = clean_name:gsub("%.", " ") -- 3. Заменяем любые оставшиеся одиночные точки на пробелы
                        clean_name = clean_name:gsub("%d+", "") -- 4. Удаляем абсолютно все цифры из названия
                        clean_name = clean_name:gsub("_+", "_") -- 5. Схлопываем множественные подчеркивания в одно
                        clean_name = clean_name:match("^[%s_]*(.-)[%s_]*$") -- 6. Очищаем пробелы и подчеркивания по краям строки

                        -- [НОВАЯ ЛОГИКА] Оставляем только первые два слова
                        local base_name = ""
                        if clean_name and clean_name ~= "" then
                            local words = {}
                            -- Разбиваем строку по разделителям (подчеркивание или пробел)
                            for word in clean_name:gmatch("[^_%s]+") do
                                table.insert(words, word)
                            end
                            
                            -- Если слов 2 или больше — берем первые два. Если одно — берем одно.
                            if #words >= 2 then
                                base_name = words[1] .. "_" .. words[2]
                            elseif #words == 1 then
                                base_name = words[1]
                            end
                        end

                        if base_name and base_name ~= "" then
                            -- Регистрируем трек в группу для конкретного target_parent
                            if not auto_groups[target_parent] then auto_groups[target_parent] = {} end
                            if not auto_groups[target_parent][base_name] then auto_groups[target_parent][base_name] = {} end
                            table.insert(auto_groups[target_parent][base_name], tr)
                        end


                        if rule.items_mode then
                            local item_count = reaper.CountTrackMediaItems(tr)
                            for j = item_count - 1, 0, -1 do
                                local item = reaper.GetTrackMediaItem(tr, j)
                                reaper.MoveMediaItemToTrack(item, target_parent)
                            end
                            reaper.DeleteTrack(tr)
                        else
                            reaper.Main_OnCommand(40297, 0) -- Unselect all
                            reaper.SetTrackSelected(tr, true)
                            local p_idx = reaper.GetMediaTrackInfo_Value(target_parent, "IP_TRACKNUMBER")
                            reorder_idx = p_idx -- сохраняем индекс для последующего перемещения
                            reaper.ReorderSelectedTracks(p_idx, 1)
                        end
                        
                        found_match = true
                        break 
                    end
                end
            end
        end
    end

    for target_parent, groups in pairs(auto_groups) do
        for folder_name, tracks in pairs(groups) do
            if folder_create and #tracks >= 2 then
                local human_folder_name = folder_name:gsub("_", " ")
                human_folder_name = human_folder_name:gsub("%s+", " ")
                human_folder_name = human_folder_name:match("^%s*(.-)%s*$")
                local auto_folder_track = get_or_create_subfolder(target_parent, human_folder_name)
                
                if auto_folder_track then
                    local f_idx = reaper.GetMediaTrackInfo_Value(auto_folder_track, "IP_TRACKNUMBER")

                    reaper.Main_OnCommand(40297, 0) -- Снять выделение со всех
                    for _, tr in ipairs(tracks) do
                        if reaper.ValidatePtr(tr, "MediaTrack*") then
                            reaper.SetTrackSelected(tr, true)
                        end
                    end
                    -- Сдвигаем треки сразу за созданную авто-папку
                    reaper.ReorderSelectedTracks(f_idx, 1)
                end
            end -- Конец блока folder_create

            if pan_group and #tracks >= 2 then
                local linked_tracks = {} -- Таблица для отслеживания уже залинкованных треков

                for a = 1, #tracks do
                    local track1 = tracks[a]
                    
                    if reaper.ValidatePtr(track1, "MediaTrack*") and not linked_tracks[track1] then
                        local _, name1 = reaper.GetTrackName(track1)
                        local side1, val1 = name1:upper():match("[%s_%-]([LR])(%d*)$")
                        
                        if side1 then
                            local target_side = (side1 == "L") and "R" or "L"
                            
                            for b = a + 1, #tracks do
                                local track2 = tracks[b]
                                
                                if reaper.ValidatePtr(track2, "MediaTrack*") and not linked_tracks[track2] then
                                    local _, name2 = reaper.GetTrackName(track2)
                                    local side2, val2 = name2:upper():match("[%s_%-]([LR])(%d*)$")
                                    
                                    if side2 == target_side then
                                        
                                        local group_idx = -1
                                        for g = 0, 31 do
                                            local mask = 1 << g
                                            local is_used = false
                                            
                                            for t = 0, reaper.CountTracks(0) - 1 do
                                                local tr = reaper.GetTrack(0, t)
                                                local lead_m = reaper.GetSetTrackGroupMembership(tr, "PAN_LEAD", 0, 0)
                                                local follow_m = reaper.GetSetTrackGroupMembership(tr, "PAN_FOLLOW", 0, 0)
                                                if (lead_m & mask) ~= 0 or (follow_m & mask) ~= 0 then
                                                    is_used = true
                                                    break
                                                end
                                            end
                                            if not is_used then group_idx = g; break end
                                        end
                                        if group_idx ~= -1 then
                                            local mask = 1 << group_idx
                                            
                                            reaper.GetSetTrackGroupMembership(track1, "PAN_LEAD", mask, mask)
                                            reaper.GetSetTrackGroupMembership(track1, "PAN_FOLLOW", mask, mask)
                                            reaper.GetSetTrackGroupMembership(track2, "PAN_LEAD", mask, mask)
                                            reaper.GetSetTrackGroupMembership(track2, "PAN_FOLLOW", mask, mask)
                                            
                                            reaper.GetSetTrackGroupMembership(track1, "VOLUME_LEAD", mask, mask)
                                            reaper.GetSetTrackGroupMembership(track1, "VOLUME_FOLLOW", mask, mask)
                                            reaper.GetSetTrackGroupMembership(track2, "VOLUME_LEAD", mask, mask)
                                            reaper.GetSetTrackGroupMembership(track2, "VOLUME_FOLLOW", mask, mask)
                                            
                                            reaper.GetSetTrackGroupMembership(track2, "PAN_REVERSE", mask, mask)

                                            local pairs_to_pan = { {track1, side1, val1}, {track2, side2, val2} }
                                            for _, p_data in ipairs(pairs_to_pan) do
                                                local tr = p_data[1]
                                                local side = p_data[2]
                                                local val = p_data[3]
                                                
                                                local num = tonumber(val) or 100
                                                local pan_value = math.max(0, math.min(num, 100)) / 100
                                                
                                                if side == "L" then
                                                    reaper.SetMediaTrackInfo_Value(tr, "D_PAN", -pan_value)
                                                else
                                                    reaper.SetMediaTrackInfo_Value(tr, "D_PAN", pan_value)
                                                end
                                            end
                                            
                                            linked_tracks[track1] = true
                                            linked_tracks[track2] = true
                                            break 
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end -- Конец блока pan_group
            
        end
    end


    reaper.Undo_EndBlock("Organize Session", -1)
    reaper.TrackList_AdjustWindows(false)
end

function test_organize()
    local rules = {}
    for _, row in ipairs(session_data) do
        if reaper.ValidatePtr(row.parent_ptr, "MediaTrack*") then
            for kw in row.keywords:gmatch("([^,]+)") do
                local clean_kw = kw:match("^%s*(.-)%s*$")
                if clean_kw and clean_kw ~= "" then
                    local f_keywords = {}
                    if row.folder_keywords then
                        for fkw in row.folder_keywords:gmatch("([^,]+)") do
                            local clean_fkw = fkw:match("^%s*(.-)%s*$")
                            if clean_fkw ~= "" then table.insert(f_keywords, clean_fkw) end
                        end
                    end

                    table.insert(rules, {
                        keyword = utf8_lower_custom(clean_kw),
                        parent = row.parent_ptr,
                        items_mode = row.items_mode,
                        length = #clean_kw,
                        folder_keywords = f_keywords,
                        norm_on = row.norm_on,
                        norm_db = row.norm_db,
                        norm_type = row.norm_type
                    })
                end
            end
        end
    end

    table.sort(rules, function(a, b) return a.length > b.length end)

    local selected_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        selected_tracks[i + 1] = reaper.GetSelectedTrack(0, i)
    end
    
    -- Таблица, куда мы будем собирать треки без совпадений
    local unmoved_tracks = {}

    for i = #selected_tracks, 1, -1 do
        local tr = selected_tracks[i]
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            local _, raw_name = reaper.GetTrackName(tr)
            local tr_name_norm = utf8_lower_custom(raw_name):gsub("_", " ")
            
            -- Флаг совпадения для текущего трека
            local track_matched = false
            
            for _, rule in ipairs(rules) do
                if tr ~= rule.parent then
                    local start_pos, end_pos = tr_name_norm:find(rule.keyword, 1, true)
                    if start_pos and (match_partial or is_word_boundary(tr_name_norm, start_pos, end_pos)) then
                        
                        -- Скрипт нашел правило для трека! Маркируем его
                        track_matched = true

                        break -- Прерываем поиск правил для этого трека
                    end
                end
            end
            
            if not track_matched then
                table.insert(unmoved_tracks, {
                    ptr = tr,
                    name = raw_name
                })
            end
        end
    end
    return unmoved_tracks
end


function get_or_create_subfolder(parent_tr, folder_name)
    local parent_idx = reaper.GetMediaTrackInfo_Value(parent_tr, "IP_TRACKNUMBER")
    local depth = reaper.GetTrackDepth(parent_tr)

    for i = parent_idx, reaper.CountTracks(0) - 1 do
        local child = reaper.GetTrack(0, i)
        if reaper.GetTrackDepth(child) <= depth and i > parent_idx then break end
        
        local _, name = reaper.GetTrackName(child)
        if name:lower() == folder_name:lower() then return child end
    end
    
    reaper.InsertTrackAtIndex(parent_idx, true)
    local new_folder = reaper.GetTrack(0, parent_idx)
    reaper.GetSetMediaTrackInfo_String(new_folder, "P_NAME", folder_name, true)
    reaper.SetMediaTrackInfo_Value(parent_tr, "I_FOLDERDEPTH", 1)

    return new_folder
end


local function frame()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x5BBB5A88) -- 40% прозрачности (66)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x4C8A6E88) -- 50% прозрачности (80)0x4C8A6E88
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x55CF5488)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        0x5BBB5A88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x5BBB5A88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),      0xFFFFFFFF) -- Белая галочка


    if reaper.ImGui_Button(ctx, 'Add tracks to table', 160) then
        if reaper.CountSelectedTracks(0) > 0 then
            reaper.ImGui_OpenPopup(ctx, 'Confirm Add Tracks')
        end
    end

    -- 2. Логика самого модального окна (поместите этот блок ниже кнопки, в основном цикле отрисовки UI)
    -- Флаг ImGui_WindowFlags_AlwaysAutoResize сделает окно аккуратным по размеру текста
    if reaper.ImGui_BeginPopupModal(ctx, 'Confirm Add Tracks', nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        
        local sel_count = reaper.CountSelectedTracks(0)
        reaper.ImGui_Text(ctx, string.format("Are you sure you want to add %d selected track(s) to the table?", sel_count))
        reaper.ImGui_Separator(ctx)

        -- Кнопка YES (выполняет всю вашу логику)
        if reaper.ImGui_Button(ctx, 'Yes', 80) then
            for i = 0, sel_count - 1 do
                local tr = reaper.GetSelectedTrack(0, i)
                local exists = false
                for _, row in ipairs(session_data) do
                    if row.parent_ptr == tr then exists = true break end
                end
                if not exists then
                    local _, name = reaper.GetTrackName(tr)
                    table.insert(session_data, { parent_ptr = tr, name = name, keywords = "", items_mode = false })
                end
            end
            sort_session_data()
            save_data()
            
            reaper.ImGui_CloseCurrentPopup(ctx) -- Закрываем окно после выполнения
        end

        reaper.ImGui_SameLine(ctx)

        -- Кнопка NO (просто закрывает окно)
        if reaper.ImGui_Button(ctx, 'No', 80) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end

        reaper.ImGui_EndPopup(ctx)
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Dummy(ctx, 10, 1)

    -- 2. Чекбокс режима поиска
    reaper.ImGui_SameLine(ctx)
    local _, new_val = reaper.ImGui_Checkbox(ctx, "Partial Match  ", match_partial)
    if _ then match_partial = new_val end

    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "If enabled: 'vox' will match 'supervox'.\nIf disabled: matches whole words only.")
    end

        -- 3. Чекбокс для создания папок
    reaper.ImGui_SameLine(ctx)
    local _, new_val2 = reaper.ImGui_Checkbox(ctx, "Smart folders  ", folder_create)
    if _ then folder_create = new_val2 end

    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "If enabled: script will try to create folders using common parts of track names")
    end

            -- 4. Чекбокс для создания папок
    reaper.ImGui_SameLine(ctx)
    local _, new_val3 = reaper.ImGui_Checkbox(ctx, "Pan Groups  ", pan_group)
    if _ then pan_group = new_val3 end

    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "If enabled: script will add pairs of track to group and invert pan")
    end


    -- РАСЧЕТ ДЛЯ ПРАВОГО КРАЯ
    local bpm_input_w = 60 -- Ширина инпута
    local label_w = 35     -- Ширина текста "BPM:"
    local padding = 4      -- Отступ от правого края окна
    local total_w = bpm_input_w + label_w + padding

    -- Получаем ширину доступной области и ставим курсор
    local window_w = reaper.ImGui_GetContentRegionAvail(ctx)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, window_w - total_w)

    -- 2. Текст "BPM:"
    reaper.ImGui_AlignTextToFramePadding(ctx) -- Чтобы текст был на одной высоте с инпутом
    reaper.ImGui_Text(ctx, "BPM:")

    -- 3. Поле ввода BPM
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, bpm_input_w)
    local current_bpm = reaper.Master_GetTempo()
    local bpm_changed, new_bpm = reaper.ImGui_InputDouble(ctx, "##bpm", current_bpm, 0, 0, "%.2f")

    if bpm_changed then
        reaper.SetCurrentBPM(0, new_bpm, true)
    end

    reaper.ImGui_PopStyleColor(ctx, 6)
    reaper.ImGui_Separator(ctx)

    if #session_data > 0 then
        if reaper.ImGui_BeginTable(ctx, 'MainTable', 3, reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_Resizable()) then
            reaper.ImGui_TableSetupColumn(ctx, 'Target Tracks',reaper.ImGui_TableColumnFlags_WidthStretch(), 0.25)
            reaper.ImGui_TableSetupColumn(ctx, 'Keywords',reaper.ImGui_TableColumnFlags_WidthStretch(), 1)
            -- reaper.ImGui_TableSetupColumn(ctx, 'Folder Keywords',reaper.ImGui_TableColumnFlags_WidthStretch(), 0.20)

            -- reaper.ImGui_TableSetupColumn(ctx, 'Normalize',reaper.ImGui_TableColumnFlags_WidthStretch(), 0.10)

            -- reaper.ImGui_TableSetupColumn(ctx, 'Items', reaper.ImGui_TableColumnFlags_WidthFixed(), 40)
            reaper.ImGui_TableSetupColumn(ctx, 'Delete', reaper.ImGui_TableColumnFlags_WidthFixed(), 20)
            reaper.ImGui_TableHeadersRow(ctx)

            local row_to_remove = nil

            for i, row in ipairs(session_data) do
                reaper.ImGui_PushID(ctx, i)
                reaper.ImGui_TableNextRow(ctx)
                
                -- Установка цвета строки
                local color = GetImGuiColor(row.parent_ptr)
                if color then reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), color) end

                local styles_pushed = PushTrackStyles(row.parent_ptr)

                reaper.ImGui_TableSetColumnIndex(ctx, 0)

                local depth = GetTrackDepth(row.parent_ptr)
                local indent_step = 12 -- Ширина ступеньки
                local pad_x = 6        -- На сколько пикселей сдвинуть влево (компенсация Padding ячейки)

                if depth > 0 then
                    -- Получаем текущие координаты курсора и отступы таблицы
                    local cursor_x, cursor_y = reaper.ImGui_GetCursorScreenPos(ctx)
                    local row_h = reaper.ImGui_GetFrameHeightWithSpacing(ctx) -- Высота всей строки 
                    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                    
                    -- Координаты прямоугольника: 
                    -- Чуть выше и левее курсора, чтобы перекрыть отступы ячейки
                    local rect_x1 = cursor_x - pad_x
                    local rect_y1 = cursor_y - 2 -- Небольшой нахлест вверх
                    local rect_x2 = rect_x1 + (depth * indent_step)
                    local rect_y2 = rect_y1 + row_h
                    
                    -- Рисуем черный прямоугольник
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, 
                        rect_x1, rect_y1, 
                        rect_x2, rect_y2, 
                        0x00000088 ) -- Чистый черный
                        
                    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + (depth * indent_step))
                end

                reaper.ImGui_Text(ctx, row.name)
                reaper.ImGui_TableSetColumnIndex(ctx, 1)

                reaper.ImGui_SetNextItemWidth(ctx, -90) 
                local changed, k = reaper.ImGui_InputText(ctx, "##key", row.keywords)
                if changed then row.keywords = k save_data() end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, -15) 


                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "+##clip_" .. tostring(_), 25) then
                    local clip_text = reaper.ImGui_GetClipboardText(ctx)
                    
                    if clip_text and clip_text ~= "" then
                        local clean_clip = clip_text:match("^%s*(.-)%s*$")
                        
                        if clean_clip and clean_clip ~= "" then
                            if row.keywords == "" then
                                row.keywords = clean_clip
                            else
                                row.keywords = row.keywords .. ", " .. clean_clip
                            end
                            
                            save_data()
                        end
                    end
                end
                
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, row.name..': Paste keywords from clipboard with comma separator')
                end


                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "S", 25) then
                    local names = {}
                    for j = 0, reaper.CountSelectedTracks(0) - 1 do
                        local _, n = reaper.GetTrackName(reaper.GetSelectedTrack(0, j))
                        table.insert(names, n)
                    end
                    if #names > 0 then
                        local new_keys = table.concat(names, ", ")
                        row.keywords = row.keywords == "" and new_keys or row.keywords .. ", " .. new_keys
                        save_data()
                    end
                end

                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, row.name..': Add sel tracks names to keywords')
                end

                -- reaper.ImGui_SameLine(ctx)
                -- -- Кнопка Очистки
                -- if reaper.ImGui_Button(ctx, "C", 25) then
                --     row.keywords = ""
                --     save_data()
                -- end

                -- -- Всплывающая подсказка при наведении на "C"
                -- if reaper.ImGui_IsItemHovered(ctx) then
                --     reaper.ImGui_SetTooltip(ctx, row.name..": Clear Keywords")
                -- end


                -- 3. Режим айтемов
                reaper.ImGui_SameLine(ctx)

                local c_changed, c = reaper.ImGui_Checkbox(ctx, "##check", row.items_mode)
                if c_changed then row.items_mode = c save_data() end
                                    
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, row.name..": Move items to parent track")
                end

                -- reaper.ImGui_TableSetColumnIndex(ctx, 2)
                -- reaper.ImGui_SetNextItemWidth(ctx, -1.0)
                -- local changed, new_fkw = reaper.ImGui_InputText(ctx, "##fkw" .. i, row.folder_keywords)
                -- if changed then row.folder_keywords = new_fkw save_data()  end

                -- reaper.ImGui_TableSetColumnIndex(ctx, 3)
                -- -- 1. Чекбокс (виден всегда)
                -- local norm_changed, new_norm = reaper.ImGui_Checkbox(ctx, "##norm" .. i, row.norm_on or false)
                -- if norm_changed then 
                --     row.norm_on = new_norm 
                --     save_data() 
                -- end

                -- -- Показываем остальное только если чекбокс активен
                -- if row.norm_on then
                --     reaper.ImGui_SameLine(ctx)
                    
                --     -- 2. Кнопка типа (Peak/RMS)
                --     local type_name = (row.norm_type == 1) and "R" or "P"
                --     local btn_color = (row.norm_type == 1) and 0x4169E1FF or 0x2E8B57FF

                --     reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), btn_color)
                --     if reaper.ImGui_Button(ctx, type_name .. "##type" .. i, 20, 0) then
                --         row.norm_type = (row.norm_type == 1) and 0 or 1
                --         save_data()
                --     end
                --     reaper.ImGui_PopStyleColor(ctx)
                    
                --     reaper.ImGui_SameLine(ctx)

                --     -- 3. Инпут dB
                --     reaper.ImGui_SetNextItemWidth(ctx, -1)
                --     local db_val = math.floor(row.norm_db or -6)
                --     local db_changed, new_db = reaper.ImGui_InputInt(ctx, "##db" .. i, db_val, 0, 0)
                --     if db_changed then 
                --         row.norm_db = new_db 
                --         save_data() 
                --     end
                -- end

                                
                -- 4. Удаление
                reaper.ImGui_TableSetColumnIndex(ctx, 2)
                if reaper.ImGui_Button(ctx, "X", -1) then row_to_remove = i end

                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, row.name..": Delete row")
                end
                
                if styles_pushed then
                    reaper.ImGui_PopStyleColor(ctx, 6) -- Сбрасываем 6 запушенных цветов
                end

                reaper.ImGui_PopID(ctx)
            end
            
            if row_to_remove then 
                table.remove(session_data, row_to_remove) 
                save_data() 
            end
            
            reaper.ImGui_EndTable(ctx)
        end
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x203C20FF) -- 40% прозрачности (66)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE6894788) -- 50% прозрачности (80)0x4C8A6E88
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xDC9D7088)

        local avail_width = reaper.ImGui_GetContentRegionAvail(ctx)
        local style_spacing = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
        local total_button_width = avail_width - style_spacing
        
        local organize_w = total_button_width * 0.83
        local test_w     = total_button_width * 0.17

        if reaper.ImGui_Button(ctx, 'Organize Selected Tracks', organize_w, 40) then
            organize_session() 
            test_unmapped_result = nil
        end

        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Button(ctx, 'Check', test_w, 40) then
            test_unmapped_result = test_organize()
            show_test_window = true 
        end

        if test_unmapped_result then
            reaper.ImGui_SetNextWindowSize(ctx, 350, 250, reaper.ImGui_Cond_FirstUseEver())
            local open = true
            local visible, open_state = reaper.ImGui_Begin(ctx, "Check Organizer Results", open, reaper.ImGui_WindowFlags_None())

            if not open_state then
                test_unmapped_result = nil
                reaper.ImGui_End(ctx) -- Обязательно закрываем сессию Begin перед выходом
                visible = false       -- Блокируем дальнейшую отрисовку контента
            end

            if visible and test_unmapped_result then
                if #test_unmapped_result > 0 then
                    reaper.ImGui_TextColored(ctx, 0xFF5555FF, string.format("Unmapped tracks found: %d", #test_unmapped_result))
                    reaper.ImGui_Spacing(ctx)
                    reaper.ImGui_Separator(ctx)
                    reaper.ImGui_Spacing(ctx)

                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 2, 1)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x00000000)

                    for i, track in ipairs(test_unmapped_result) do
                        reaper.ImGui_Bullet(ctx)
                        reaper.ImGui_SameLine(ctx)
                        
                        local input_id = string.format("##track_test_win_%d", i)
                        local readable_name = track.name:gsub("_", " ")
                        
                        reaper.ImGui_SetNextItemWidth(ctx, -1)
                        reaper.ImGui_InputText(ctx, input_id, readable_name, reaper.ImGui_InputTextFlags_ReadOnly())
                    end

                    if reaper.ImGui_Button(ctx, "Close", -1, 30) then
                        test_unmapped_result = nil
                    end

                    reaper.ImGui_PopStyleColor(ctx)
                    reaper.ImGui_PopStyleVar(ctx)
                else
                    reaper.ImGui_Spacing(ctx)
                    reaper.ImGui_TextColored(ctx, 0x55FF55FF, "Success!")
                    reaper.ImGui_Text(ctx, "All selected tracks match your session rules.")
                    reaper.ImGui_Spacing(ctx)
                    
                    if reaper.ImGui_Button(ctx, "Close", -1, 30) then
                        test_unmapped_result = nil
                    end
                end

                reaper.ImGui_End(ctx)
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
    end
end


function loop()
    reaper.ImGui_PushFont(ctx, font, font_size)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 4, 4)    -- (X, Y) расстояние между кнопками/строками
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 3, 2)   -- (X, Y) внутренние отступы в кнопках/инпутах
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_CellPadding(), 2, 1)    -- отступы внутри ячеек таблицы

    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),           0x203C20FF)
    
    reaper.ImGui_SetNextWindowSize(ctx, 800, 700, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, 'Session Organizer', true)

    if visible then
        frame()
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx,2)
    reaper.ImGui_PopStyleVar(ctx, 3)

    reaper.ImGui_PopFont(ctx)
    
    if open then
        reaper.defer(loop)
    end

end

loop()