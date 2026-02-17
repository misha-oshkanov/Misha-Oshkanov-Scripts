-- @description UI manager for session prepping
-- @author Misha Oshkanov
-- @version 1.4
-- @about
--  Add target tracks by clicking "Add Selected Tracks" to your session
--  Then type some kerwords
--  Select some tracks and click "Organise" to move selected tracks to target track based by their names and keywords
-- @changelog
--  collapse crush fixed, new partical match checkbox added

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
        serialized = serialized .. string.format("%s|%s|%s|%s\n", guid, row.name, kw, mode)
    end
    -- Сохраняем таблицу треков
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", ext_key, serialized)
    -- Сохраняем состояние чекбокса Partial Match
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", "PARTIAL_MATCH", match_partial and "1" or "0")
end

local function load_data()
    -- Загружаем таблицу (твой текущий код...)
    local _, serialized = reaper.GetProjExtState(0, "MISHA_SESSION_ORGANIZER", ext_key)
    if serialized and serialized ~= "" then
        session_data = {}
        for line in serialized:gmatch("[^\r\n]+") do
            local guid, name, keywords, mode = line:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)")
            if guid and guid ~= "" then
                local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
                if tr then
                    table.insert(session_data, {
                        parent_ptr = tr,
                        name = name or "Unknown",
                        keywords = keywords or "",
                        items_mode = mode == "1"
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
                    table.insert(rules, {
                        keyword = utf8_lower_custom(clean_kw),
                        parent = row.parent_ptr,
                        items_mode = row.items_mode,
                        length = #clean_kw
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

    for _, tr in ipairs(selected_tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            local _, raw_name = reaper.GetTrackName(tr)
            -- Приводим имя трека к нижнему регистру и меняем _ на пробел
            local tr_name_norm = utf8_lower_custom(raw_name):gsub("_", " ")
            
            for _, rule in ipairs(rules) do
                if tr ~= rule.parent then
                    -- Поиск подстроки (plain = true)

                    local start_pos, end_pos = tr_name_norm:find(rule.keyword, 1, true)
                    
                    if start_pos then
                        -- Если включен Partial Match, то проверка границ не нужна.
                        -- Если выключен, то вызываем is_word_boundary.
                        if match_partial or is_word_boundary(tr_name_norm, start_pos, end_pos) then
                            
                            if rule.items_mode then
                                -- (код перемещения айтемов...)
                                local item_count = reaper.CountTrackMediaItems(tr)
                                for j = item_count - 1, 0, -1 do
                                    local item = reaper.GetTrackMediaItem(tr, j)
                                    reaper.MoveMediaItemToTrack(item, rule.parent)
                                end
                                reaper.DeleteTrack(tr)
                            else
                                -- (код перемещения трека...)
                                reaper.Main_OnCommand(40297, 0)
                                reaper.SetTrackSelected(tr, true)
                                local p_idx = reaper.GetMediaTrackInfo_Value(rule.parent, "IP_TRACKNUMBER")
                                reaper.ReorderSelectedTracks(p_idx, 1)
                            end
                            
                            found_match = true
                            break 
                        end
                    end

                    -- local start_pos, end_pos = tr_name_norm:find(rule.keyword, 1, true)
                    
                    -- if start_pos then
                    --     if is_word_boundary(tr_name_norm, start_pos, end_pos) then
                    --         if rule.items_mode then
                    --             for j = reaper.CountTrackMediaItems(tr) - 1, 0, -1 do
                    --                 local item = reaper.GetTrackMediaItem(tr, j)
                    --                 reaper.MoveMediaItemToTrack(item, rule.parent)
                    --             end
                    --             reaper.DeleteTrack(tr)
                    --         else
                    --             reaper.Main_OnCommand(40297, 0)
                    --             reaper.SetTrackSelected(tr, true)
                    --             local p_idx = reaper.GetMediaTrackInfo_Value(rule.parent, "IP_TRACKNUMBER")
                    --             reaper.ReorderSelectedTracks(p_idx, 1)
                    --         end
                    --         break 
                    --     end
                    -- end
                end
            end
        end
    end

    reaper.Undo_EndBlock("Organize Session (Smart UTF8)", -1)
    reaper.TrackList_AdjustWindows(false)
end


local function frame()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x5BBB5A88) -- 40% прозрачности (66)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x4C8A6E88) -- 50% прозрачности (80)0x4C8A6E88
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x55CF5488)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        0x5BBB5A88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x5BBB5A88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),      0xFFFFFFFF) -- Белая галочка

    -- 1. Кнопка добавления (делаем ее не на всю ширину, чтобы влез BPM)
    if reaper.ImGui_Button(ctx, 'Add selected tracks to session table', 320) then
        for i = 0, reaper.CountSelectedTracks(0) - 1 do
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
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Dummy(ctx, 10, 1) -- Небольшой отступ

    reaper.ImGui_SameLine(ctx)
    -- 2. Чекбокс режима поиска
    local _, new_val = reaper.ImGui_Checkbox(ctx, "Partial Match", match_partial)
    if _ then match_partial = new_val end

    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "If enabled: 'vox' will match 'supervox'.\nIf disabled: matches whole words only.")
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
            -- reaper.ImGui_TableSetupColumn(ctx, 'Items', reaper.ImGui_TableColumnFlags_WidthFixed(), 40)
            reaper.ImGui_TableSetupColumn(ctx, 'Delete', reaper.ImGui_TableColumnFlags_WidthFixed(), 20)
            reaper.ImGui_TableHeadersRow(ctx)

            local row_to_remove = nil

            for i, row in ipairs(session_data) do
                reaper.ImGui_PushID(ctx, i)
                reaper.ImGui_TableNextRow(ctx)
                
                -- Установка цвета строки
                local color = GetImGuiColor(row.parent_ptr)
                if color then
                    reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), color)
                end

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
                        
                    -- Сдвигаем курсор для текста (относительно начала ячейки)
                    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + (depth * indent_step))
                end

                reaper.ImGui_Text(ctx, row.name)
                -- Столбец 2: Input + Кнопки (Clear и Grab)
                reaper.ImGui_TableSetColumnIndex(ctx, 1)

                -- Рассчитываем ширину, чтобы влезли две кнопки (примерно по 25px каждая + отступы)
                reaper.ImGui_SetNextItemWidth(ctx, -85) 
                local changed, k = reaper.ImGui_InputText(ctx, "##key", row.keywords)
                if changed then row.keywords = k save_data() end

                reaper.ImGui_SameLine(ctx)
                -- Кнопка Очистки
                if reaper.ImGui_Button(ctx, "C", 25) then
                    row.keywords = ""
                    save_data()
                end

                -- Всплывающая подсказка при наведении на "C"
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, row.name..": Clear Keywords")
                end

                reaper.ImGui_SameLine(ctx)
                -- Кнопка Захвата имен
                if reaper.ImGui_Button(ctx, "+", 25) then
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

                -- 3. Режим айтемов
                reaper.ImGui_SameLine(ctx)

                local c_changed, c = reaper.ImGui_Checkbox(ctx, "##check", row.items_mode)
                if c_changed then row.items_mode = c save_data() end
                                    
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, row.name..": Move items to parent track")
                end
                
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

        if reaper.ImGui_Button(ctx, 'Organize Selected Tracks', -1, 40) then
            organize_session() 
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