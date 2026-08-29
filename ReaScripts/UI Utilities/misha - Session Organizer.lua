-- @description Session Organizer
-- @author Misha Oshkanov
-- @version 3.0
-- @about
--  Create your naming rules
--  Add target tracks by clicking "Add Selected Tracks" to your session
--  Then type some keywords
--  Customize processing (silence remove, normalization, folder creation)
--  Select some tracks and click "Organise" to move selected tracks to target track based by their names and keywords
-- @changelog
--  New big auto rename system with custom rules
--  Peak lufs normalization support
--  Auto silence remover
--  Auto add section names to track names
--  Smart folder overhaul, now it has nested logic with rules priorites
--  New check system. Check if track will be moved to its target track in template

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

function print_name(track)
    _, str = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false )
    return srt
end 


local ctx = reaper.ImGui_CreateContext('Session Organizer')
font_size = 15
font = reaper.ImGui_CreateFont('sans-serif', font_size)
local ext_key = "SESSION_DATA" -- Ключ для хранения в проекте
local session_data = {}
local match_partial = true -- Состояние чекбокса "Partial Match"
local folder_create = true -- Состояние чекбокса "Smart folder"
local pan_group = true -- Состояние чекбокса "Pan Groups"
local region_sections = true -- Состояние чекбокса "Region Sections" (имена регионов в названиях треков)
local norm_enabled = true -- Мастер-выключатель нормализации (чекбоксы в таблице сохраняются)
local clean_names_snapshot = nil -- Кэш: зафиксированный список дорожек с рассчитанными именами
local clean_names_sorted = false -- Тоггл: сортировать таблицу по новым именам
local clean_names_sel = {} -- Множество выделенных строк (ключ - ссылка на строку)
local clean_names_sel_count = 0 -- Кол-во выделенных строк
local clean_names_anchor = nil -- Якорная строка для shift-выделения
local clean_names_sel_mode = "items" -- "range" для shift-выделения, "items" для ctrl/одиночного
local clean_names_display_cache = nil -- Кэш отсортированных строк (пересобирается при изменении имён)
local clean_names_display_dirty = false -- Нужна ли пересборка кэша сортировки
local clean_names_solo_tick = 0 -- Счётчик для периодического обновления кэша соло
local clean_edit_active = false -- Открыт ли правокликовый попап (для сохранения базовых имён)
local clean_popup_open = false -- Был ли попап открыт в этом кадре
local clean_remove_str = "" -- Подстрока для удаления из новых имён (попап)

-- local current_bpm = reaper.Master_GetTempo()

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
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),      0xB2B2B2FF) -- Белая галочка
    
    return true
end

local function unselect_all_tracks()
  for i = 0, reaper.GetNumTracks() - 1 do
    reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
  end
  reaper.UpdateArrange()
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

local function IsTrackDescendant(track, parent)
    local p = reaper.GetParentTrack(track)
    while p do
        if p == parent then return true end
        p = reaper.GetParentTrack(p)
    end
    return false
end


function get_parent(track)
    depth = reaper.GetTrackDepth( track )
    for d=1,depth do 
        track =  reaper.GetParentTrack(track)
    end 
    return track
end

function get_parentnames_table(track)
    local parentlist = {}
    local oldparent
    local parent = get_parent(track)
    if parent ~= oldparent then
        local _, name = reaper.GetTrackName(parent)
        local name = remove_arch_prefix(name)
        table.insert(parentlist, name)
    end
        oldparent = parent
    return parentlist
end

-- function get_children(parent)
--     if parent then 
--         local parentdepth = reaper.GetTrackDepth(parent)
--         local parentnumber = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
--         print(parentnumber)
--         local children = {}
--         for i=parentnumber, reaper.CountTracks(0)-1 do
--                 local track = reaper.GetTrack(0,i)
--                 local depth = reaper.GetTrackDepth(track)
--                 if depth == parentdepth+1 then
--                     table.insert(children, track)
--                 else
--                     break
--                 end
--         end
--         return children
--     end
-- end


local function get_children_contain_folders_as_well(track)
  local children = {}
  if not track then return children end

  local parent_depth = reaper.GetTrackDepth(track)
  local parent_idx   = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  local total        = reaper.GetNumTracks()

  for i = parent_idx + 1, total do
    local t    = reaper.GetTrack(0, i - 1)
    local d    = reaper.GetTrackDepth(t)
    -- print(reaper.GetMediaTrackInfo_Value( t, "I_FOLDERDEPTH" ))
    if d <= parent_depth then break end          -- вышли за пределы папки
    if d == parent_depth + 1 then        
      children[#children + 1] = t
    end
  end

  return children
end

local function get_children_contain_only_single(track)
  local children = {}
  if not track then return children end

  local parent_depth = reaper.GetTrackDepth(track)
  local parent_idx   = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  local total        = reaper.GetNumTracks()

  for i = parent_idx + 1, total do
    local t    = reaper.GetTrack(0, i - 1)
    local d    = reaper.GetTrackDepth(t)
    -- print(reaper.GetMediaTrackInfo_Value( t, "I_FOLDERDEPTH" ))
    if d <= parent_depth then break end          -- вышли за пределы папки
    if d == parent_depth + 1 and reaper.GetMediaTrackInfo_Value( t, "I_FOLDERDEPTH" )~=1  then                -- только прямые дети
      children[#children + 1] = t
    end
  end

  return children
end

local function has_nested_folder(track)
  if not track then return false end

  local parent_depth = reaper.GetTrackDepth(track)
  local parent_idx   = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  local total        = reaper.GetNumTracks()

  for i = parent_idx + 1, total do
    local t = reaper.GetTrack(0, i - 1)
    local d = reaper.GetTrackDepth(t)
    if d <= parent_depth then break end        -- папка закончилась
    if d == parent_depth + 1 then              -- только прямые дети
      if reaper.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") == 1 then
        return true
      end
    end
  end

  return false
end

-- Уровень нормализации по умолчанию для режима (Peak: -6 dB, LUFS-S: -23 LUFS)
local function default_norm_db(norm_type)
    return (norm_type == 1) and -23 or -6
end

local function save_data()
    local serialized = ""
    for _, row in ipairs(session_data) do
        local guid = reaper.GetTrackGUID(row.parent_ptr)
        local mode = row.items_mode and "1" or "0"
        local kw = row.keywords or ""
        local fkw = row.folder_keywords or ""
        local n_on = row.norm_on and "1" or "0"
        local n_db = row.norm_db or default_norm_db(row.norm_type or 0)
        local n_type = row.norm_type or 0
        local rs = row.remove_silence and "1" or "0"
        local rr = row.remove_row and "1" or "0"
        serialized = serialized .. string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n", guid, row.name, kw, mode, fkw, n_on, n_db, n_type, rs, rr)
    end
    -- Сохраняем таблицу треков
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", ext_key, serialized)
    -- Сохраняем состояние чекбокса Partial Match
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", "PARTIAL_MATCH", match_partial and "1" or "0")
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", "FOLDER_CREATE", folder_create and "1" or "0")
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", "PAN_GROUP", pan_group and "1" or "0")
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", "REGION_SECTIONS", region_sections and "1" or "0")
    reaper.SetProjExtState(0, "MISHA_SESSION_ORGANIZER", "NORM_ENABLED", norm_enabled and "1" or "0")


end

local function load_data()
    -- Загружаем таблицу (твой текущий код...)
    local _, serialized = reaper.GetProjExtState(0, "MISHA_SESSION_ORGANIZER", ext_key)
    if serialized and serialized ~= "" then
        session_data = {}
        for line in serialized:gmatch("[^\r\n]+") do
            local guid, name, keywords, mode, f_keywords, n_on, n_db, n_type, remove_silence, remove_row =
                line:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")

            if guid and guid ~= "" then
                local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
                if tr then
                    local db_val = tonumber(n_db)
                    -- старые сохранения писали -0.1 как заглушку — заменяем на дефолт режима
                    if not db_val or db_val == -0.1 then db_val = default_norm_db(tonumber(n_type) or 0) end
                    table.insert(session_data, {
                        parent_ptr = tr,
                        name = name or "Unknown",
                        keywords = keywords or "",
                        items_mode = mode == "1",
                        folder_keywords = f_keywords or "",
                        norm_on = n_on == "1",
                        norm_db = db_val,
                        norm_type = tonumber(n_type) or 0, -- 0: Peak, 1: LUFS-S
                        remove_silence = remove_silence == "1",
                        remove_row = remove_row == "1"
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
    local _, rs_state = reaper.GetProjExtState(0, "MISHA_SESSION_ORGANIZER", "REGION_SECTIONS")
    if rs_state ~= "" then
        region_sections = (rs_state == "1")
    end
    local _, ne_state = reaper.GetProjExtState(0, "MISHA_SESSION_ORGANIZER", "NORM_ENABLED")
    if ne_state ~= "" then
        norm_enabled = (ne_state == "1")
    end
end

load_data()

-- Возвращает список треков: из снапшота, собранного кнопкой "Get session tracks",
-- либо (если снапшот пуст) — из текущего выделения
local function get_session_tracks()
    local tracks = {}
    if clean_names_snapshot and #clean_names_snapshot.rows > 0 then
        for _, r in ipairs(clean_names_snapshot.rows) do
            if reaper.ValidatePtr(r.ptr, "MediaTrack*") then
                tracks[#tracks + 1] = r.ptr
            end
        end
        if #tracks > 0 then return tracks end
    end
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        tracks[#tracks + 1] = reaper.GetSelectedTrack(0, i)
    end
    return tracks
end

-- ============================================================
-- REMOVE SILENCE ENGINE (ported from Arc_Function_lua.lua)
-- ============================================================
local function GetSampleNumberPosValue(take, SkipNumberOfSamplesPerChannel, FeelVolumeOfItem, FeelVolumeOfTake, FeelVolumeOfEnvelopeItem)
    if not take or reaper.TakeIsMIDI(take) then return false, false, false, false, false, false, false end
    if not tonumber(SkipNumberOfSamplesPerChannel) then SkipNumberOfSamplesPerChannel = 0 end
    SkipNumberOfSamplesPerChannel = math.floor(SkipNumberOfSamplesPerChannel + 0.5)

    local item = reaper.GetMediaItemTake_Item(take)
    local PlayRate_Original = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    local Item_len_Original = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", Item_len_Original * PlayRate_Original)
    reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1)

    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local accessor = reaper.CreateTakeAudioAccessor(take)
    local source = reaper.GetMediaItemTake_Source(take)
    local samplerate = reaper.GetMediaSourceSampleRate(source)
    local numchannels = reaper.GetMediaSourceNumChannels(source)
    if not numchannels or numchannels <= 0 then
        reaper.DestroyAudioAccessor(accessor)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", item_len / PlayRate_Original)
        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", PlayRate_Original)
        return false, false, false, false, false, false, false
    end
    local item_len_idx = math.ceil(item_len)

    local CountSamples_OneChannel = math.floor(item_len * samplerate + 2)
    local CountSamples_AllChannels = math.floor(item_len * samplerate + 2) * numchannels

    local NumberSamplesOneChan = {}
    local NumberSamplesAllChan = {}
    local Sample_min = {}
    local Sample_max = {}
    local TimeSample = {}

    local breakX, multi

    for i1 = 1, item_len_idx do
        local buffer = reaper.new_array(samplerate * numchannels)
        local Accessor_Samples = reaper.GetAudioAccessorSamples(accessor, samplerate, numchannels, i1 - 1, samplerate, buffer)
        local ContinueCounting = (i1 - 1) * samplerate
        for i2 = 1, samplerate * numchannels, numchannels * (SkipNumberOfSamplesPerChannel + 1) do
            local SamplePointNumb = (i2 - 1) / numchannels + ContinueCounting
            local Sample_min_all_channels = 9 ^ 99
            local Sample_max_all_channels = 0
            for i3 = 1, numchannels do
                local Sample = math.abs(buffer[i2 + (i3 - 1)])
                Sample_min_all_channels = math.min(Sample, Sample_min_all_channels)
                Sample_max_all_channels = math.max(Sample, Sample_max_all_channels)
            end
            if FeelVolumeOfTake == true then
                Sample_min_all_channels = Sample_min_all_channels * reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
                Sample_max_all_channels = Sample_max_all_channels * reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
            end
            if FeelVolumeOfItem == true then
                Sample_min_all_channels = Sample_min_all_channels * reaper.GetMediaItemInfo_Value(item, "D_VOL")
                Sample_max_all_channels = Sample_max_all_channels * reaper.GetMediaItemInfo_Value(item, "D_VOL")
            end
            if FeelVolumeOfEnvelopeItem == true then
                local Envelope = reaper.GetTakeEnvelopeByName(take, "Volume")
                if Envelope then
                    local retval, value, _, _, _ = reaper.Envelope_Evaluate(Envelope, SamplePointNumb / samplerate, samplerate, 0)
                    if retval > 0 then
                        Sample_min_all_channels = Sample_min_all_channels * value
                        Sample_max_all_channels = Sample_max_all_channels * value
                    end
                end
            end

            Sample_min[#Sample_min + 1] = Sample_min_all_channels
            Sample_max[#Sample_max + 1] = Sample_max_all_channels

            NumberSamplesAllChan[#NumberSamplesAllChan + 1] = (i2 + ContinueCounting)
            if numchannels > 2 then multi = 1 else multi = 0 end
            NumberSamplesOneChan[#NumberSamplesOneChan + 1] = math.floor(((i2 + ContinueCounting) / numchannels) + 0.5) + multi

            TimeSample[#TimeSample + 1] = SamplePointNumb / samplerate / PlayRate_Original + item_pos

            if TimeSample[#TimeSample] > Item_len_Original + item_pos then breakX = 1 break end
        end
        buffer.clear()
        if breakX == 1 then break end
    end
    reaper.DestroyAudioAccessor(accessor)

    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", item_len / PlayRate_Original)
    reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", PlayRate_Original)

    TimeSample[1] = item_pos
    TimeSample[#TimeSample] = item_pos + Item_len_Original

    return CountSamples_AllChannels, CountSamples_OneChannel, NumberSamplesAllChan, NumberSamplesOneChan, Sample_min, Sample_max, TimeSample
end

local function DeleteMediaItem(item)
    if item then
        local tr = reaper.GetMediaItem_Track(item)
        reaper.DeleteTrackMediaItem(tr, item)
    end
end

-- Removes silent regions inside items. All resulting item edges are snapped
-- to the measure grid, so only whole measures of silence are ever cut away
-- and no audio can be lost. Fully silent items are deleted.
local function remove_silence(clean_items)
    if not clean_items or #clean_items == 0 then return end

    local Thresh_dB = -60
    local MinSilentChunks = 5 -- chunks are ~10 ms each (samplerate/100)
    local ValInDB = 10 ^ (Thresh_dB / 20)
    local EPS = 1e-6

    local function measure_start(t)
        local _, measures = reaper.TimeMap2_timeToBeats(0, t)
        return reaper.TimeMap2_beatsToTime(0, 0, measures)
    end

    local function measure_end(t)
        local _, measures = reaper.TimeMap2_timeToBeats(0, t)
        return reaper.TimeMap2_beatsToTime(0, 0, measures + 1)
    end

    for idx = #clean_items, 1, -1 do
        local Selitem = clean_items[idx]
        if reaper.ValidatePtr(Selitem, "MediaItem*") then
            local take = reaper.GetActiveTake(Selitem)
            if take and not reaper.TakeIsMIDI(take) then
                local source = reaper.GetMediaItemTake_Source(take)
                local samples_skip = reaper.GetMediaSourceSampleRate(source) / 100
                local _, _, _, _, _, Sample_max, TimeSample =
                    GetSampleNumberPosValue(take, samples_skip, true, true, true)

                if TimeSample and #TimeSample > 0 then
                    local last = #TimeSample

                    -- collect silent runs as index pairs {first, last}
                    local runs = {}
                    local run_start
                    for i = 1, last do
                        local silent = Sample_max[i] < ValInDB
                        if silent and not run_start then run_start = i end
                        if run_start and (not silent or i == last) then
                            local run_end = silent and i or i - 1
                            if run_end - run_start + 1 >= MinSilentChunks then
                                runs[#runs + 1] = { run_start, run_end }
                            end
                            run_start = nil
                        end
                    end

                    -- process runs right-to-left so earlier positions stay valid on the item
                    for r = #runs, 1, -1 do
                        if not reaper.ValidatePtr(Selitem, "MediaItem*") then break end
                        local pos = reaper.GetMediaItemInfo_Value(Selitem, "D_POSITION")
                        local fin = pos + reaper.GetMediaItemInfo_Value(Selitem, "D_LENGTH")
                        local s_i, e_i = runs[r][1], runs[r][2]
                        local sil_start = TimeSample[s_i]
                        local sil_end = (e_i < last) and TimeSample[e_i + 1] or fin

                        if s_i == 1 and e_i == last then
                            -- item is completely silent
                            DeleteMediaItem(Selitem)
                        elseif s_i == 1 then
                            -- leading silence: trim head to the measure line at/before first sound
                            local new_pos = measure_start(sil_end)
                            if new_pos > pos + EPS and new_pos < fin - EPS then
                                local keep = reaper.SplitMediaItem(Selitem, new_pos)
                                if keep then DeleteMediaItem(Selitem) end
                            end
                        elseif e_i == last then
                            -- trailing silence: trim tail to the measure line at/after last sound
                            local new_fin = measure_end(sil_start)
                            if new_fin > pos + EPS and new_fin < fin - EPS then
                                local tail = reaper.SplitMediaItem(Selitem, new_fin)
                                if tail then DeleteMediaItem(tail) end
                            end
                        else
                            -- middle silence: cut out a whole number of measures between grid lines
                            local cut_l = measure_end(sil_start)
                            local cut_r = measure_start(sil_end)
                            if cut_r > cut_l + EPS then
                                local mid = reaper.SplitMediaItem(Selitem, cut_l)
                                if mid then
                                    local tail = reaper.SplitMediaItem(mid, cut_r)
                                    if tail then DeleteMediaItem(mid) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    reaper.UpdateArrange()
end


-- ============================================================
-- NORMALIZATION ENGINE (Peak/RMS ported from RAPID.lua,
-- LUFS-S через SWS NF_AnalyzeTakeLoudness, как в nofish-скрипте)
-- Group-based: измеряется самый громкий итем группы, один и тот же
-- гейн применяется ко всем итемам группы.
-- ============================================================

-- Сбрасывает гейны итемов и тейков в 0 dB перед измерением (как в RAPID)
local function reset_item_gains(items)
    for _, item in ipairs(items) do
        reaper.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
        local take = reaper.GetActiveTake(item)
        if take then reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", 1.0) end
    end
end

-- Возвращает самый громкий уровень (линейный) среди итемов и сам итем
local function measure_loudest_item(items, measure_type)
    local loudest_value = nil
    local loudest_item = nil

    for _, item in ipairs(items) do
        local take = reaper.GetActiveTake(item)
        if take and not reaper.TakeIsMIDI(take) then
            local source = reaper.GetMediaItemTake_Source(take)
            if source then
                local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local samplerate = reaper.GetMediaSourceSampleRate(source)
                local n_ch = reaper.GetMediaSourceNumChannels(source)

                if samplerate and samplerate > 0 and n_ch and n_ch > 0 then
                    local total_samples = math.floor(item_len * samplerate)
                    local max_peak = 0
                    local sum_squared = 0
                    local num_samples = 0
                    local buffer_size = 65536
                    local buffer = reaper.new_array(n_ch * buffer_size)
                    local accessor = reaper.CreateTakeAudioAccessor(take)
                    local pos = 0

                    while pos < total_samples do
                        local to_read = math.min(buffer_size, total_samples - pos)
                        reaper.GetAudioAccessorSamples(accessor, samplerate, n_ch, pos / samplerate, to_read, buffer)

                        for i = 1, to_read * n_ch do
                            local val = math.abs(buffer[i])
                            if val > max_peak then max_peak = val end
                            if measure_type == "RMS" then
                                sum_squared = sum_squared + (val * val)
                                num_samples = num_samples + 1
                            end
                        end

                        pos = pos + to_read
                    end

                    reaper.DestroyAudioAccessor(accessor)
                    buffer.clear()

                    local current_value
                    if measure_type == "Peak" then
                        current_value = max_peak
                    elseif num_samples > 0 then
                        current_value = math.sqrt(sum_squared / num_samples)
                    end

                    if current_value and (not loudest_value or current_value > loudest_value) then
                        loudest_value = current_value
                        loudest_item = item
                    end
                end
            end
        end
    end

    return loudest_value, loudest_item
end

-- Применяет гейн (dB) ко всем итемам через громкость тейка
local function apply_gain_to_items(items, gain_db)
    local gain_linear = 10 ^ (gain_db / 20)
    for _, item in ipairs(items) do
        local current_vol = reaper.GetMediaItemInfo_Value( item, "D_VOL")
        reaper.SetMediaItemInfo_Value(item, "D_VOL",  current_vol * gain_linear)
        reaper.UpdateItemInProject(item)

        -- local take = reaper.GetActiveTake(item)
        -- if take then
        --     local current_vol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
        --     reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", current_vol * gain_linear)
        --     reaper.UpdateItemInProject(item)
        -- end
    end
end

-- LUFS-S (short term max) измерение самого громкого итема через SWS NF_AnalyzeTakeLoudness.
-- Возвращает значение в LUFS (dB). Итемы короче окна анализа (3 сек) дают < -100 и пропускаются,
-- как в nofish_Normalize loudness of selected items active take to X LUFS max short term.
local function measure_loudest_item_lufs(items)
    local loudest_value = nil
    local loudest_item = nil

    for _, item in ipairs(items) do
        local take = reaper.GetActiveTake(item)
        if take and not reaper.TakeIsMIDI(take) then
            local success, _, _, _, _, short_term_max = reaper.NF_AnalyzeTakeLoudness(take, false)
            if success and short_term_max and short_term_max > -100.0 then
                if not loudest_value or short_term_max > loudest_value then
                    loudest_value = short_term_max
                    loudest_item = item
                end
            end
        end
    end

    return loudest_value, loudest_item
end

-- Групповая нормализация Peak/LUFS-S: ищем самый громкий итем, общий гейн на всех
local lufs_fallback_warned = false

local function normalize_items_group(items, target_db, norm_type)
    if not items or #items == 0 then return false end

    reset_item_gains(items)

    if norm_type == 1 then -- LUFS-S (short term max)
        if reaper.NF_AnalyzeTakeLoudness then
            local lufs_value = measure_loudest_item_lufs(items)
            if lufs_value then
                apply_gain_to_items(items, target_db - lufs_value)
                return true
            end
            return false -- ни один итем не поддался анализу (слишком короткие)
        end
        -- Нет SWS/NF расширения: одно предупреждение и откат к RMS-детектору
        if not lufs_fallback_warned then
            lufs_fallback_warned = true
            print("NF_AnalyzeTakeLoudness not available (needs REAPER v5.21+ / SWS v2.9.6+), falling back to RMS detection")
        end
    end

    -- Peak / RMS (RAPID-детектор), также используется как фолбэк для LUFS-S
    local measure_type = (norm_type == 1) and "RMS" or "Peak"
    local loudest_value = measure_loudest_item(items, measure_type)

    if not loudest_value or loudest_value <= 0 then return false end

    local current_db = 20 * math.log(loudest_value, 10)
    apply_gain_to_items(items, target_db - current_db)
    return true
end



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

local backup_status = ""
local backup_file_path = nil

local function get_backup_path()
    if backup_file_path then return backup_file_path end
    local _, script = reaper.get_action_context()
    local script_dir = script:match("^(.*)[\\/][^\\/]+$") or "."
    backup_file_path = script_dir .. "/session_organizer_backup.txt"
    return backup_file_path
end

local function save_backup()
    local path = get_backup_path()
    local lines = {}
    for _, row in ipairs(session_data) do
        local name = row.name or ""
        local kw = row.keywords or ""
        table.insert(lines, name .. "|" .. kw)
    end
    local f = io.open(path, "w")
    if not f then return "Error: cannot write " .. path end
    f:write(table.concat(lines, "\n"))
    f:close()
    return "Saved " .. #lines .. " rows -> " .. path
end

local function load_backup()
    local path = get_backup_path()
    local f = io.open(path, "r")
    if not f then return "No backup file: " .. path end
    local content = f:read("*a")
    f:close()
    local applied = 0
    for line in content:gmatch("[^\r\n]+") do
        local name, kw = line:match("^([^|]*)|(.*)$")
        if name and name ~= "" then
            local tl_name = utf8_lower_custom(name)
            local found = false
            for _, row in ipairs(session_data) do
                if (row.name or "") == name then
                    row.keywords = kw or ""
                    applied = applied + 1
                    found = true
                    break
                end
            end
            if not found then
                for _, row in ipairs(session_data) do
                    if utf8_lower_custom(row.name or "") == tl_name then
                        row.keywords = kw or ""
                        applied = applied + 1
                        break
                    end
                end
            end
        end
    end
    save_data()
    return "Applied keywords to " .. applied .. " rows"
end

-- ============================================================
-- SMART FOLDERS ENGINE (folder_create)
-- ============================================================
local SIDE_WORDS = { l = true, r = true, left = true, right = true }

-- Разбивает имя на "значимые" токены для группировки:
-- нижний регистр, L/R/left/right в конце отбрасываются,
-- подряд идущие числа склеиваются через точку (1 1 -> 1.1)
local function smart_tokens(raw_name)
    local toks = {}
    for w in (utf8_lower_custom(raw_name):gsub("_", " ")):gmatch("[^%s]+") do
        toks[#toks + 1] = w
    end
    while #toks > 0 and SIDE_WORDS[toks[#toks]] do
        toks[#toks] = nil
    end
    local merged = {}
    local i = 1
    while i <= #toks do
        if toks[i]:match("^%d+$") then
            local num = toks[i]
            local j = i + 1
            while j <= #toks and toks[j]:match("^%d+$") do
                num = num .. "." .. toks[j]
                j = j + 1
            end
            merged[#merged + 1] = num
            i = j
        else
            merged[#merged + 1] = toks[i]
            i = i + 1
        end
    end
    return merged
end

-- Перемещает группу треков сразу за папкой folder
local function move_tracks_after(tracks, folder, makefolder)
    local f_idx = reaper.GetMediaTrackInfo_Value(folder, "IP_TRACKNUMBER")
    -- local children = get_children_contain_only_single(folder)
    retval, p_name = reaper.GetSetMediaTrackInfo_String( folder, "P_NAME", "", false )
    -- local ch = get_children_contain_folders_as_well(folder)

    -- print(p_name.. " - " )
    -- print(#ch)
    -- print("--------------- " )
    -- printt(tracks)
    -- print("--------------- " )


    reaper.Main_OnCommand(40297, 0) -- Unselect all
    for _, t in ipairs(tracks) do
        if reaper.ValidatePtr(t.tr, "MediaTrack*") then
            reaper.SetTrackSelected(t.tr, true)
        end
    end
    reaper.ReorderSelectedTracks(f_idx, makefolder)
end



-- Делает первую букву слова заглавной (латиница + кириллица)
local function cap_smart_word(w)
    local b1 = w:byte(1)
    if not b1 then return w end
    if b1 >= 97 and b1 <= 122 then return w:sub(1, 1):upper() .. w:sub(2) end
    if b1 == 0xD0 and w:byte(2) and w:byte(2) >= 0xB0 and w:byte(2) <= 0xBF then
        return string.char(0xD0, w:byte(2) - 0x20) .. w:sub(3)
    end
    if b1 == 0xD1 and w:byte(2) and w:byte(2) >= 0x80 and w:byte(2) <= 0x8F then
        return string.char(0xD1, w:byte(2) - 0x20) .. w:sub(3)
    end
    return w
end

-- Читаемое имя папки: "voc back chorus 1.1" -> "Voc Back Chorus 1.1"
local function humanize_folder_name(name)
    local out = {}
    for w in name:gmatch("[^%s]+") do
        out[#out + 1] = cap_smart_word(w)
    end
    return table.concat(out, " ")
end

-- Если имя папки содержит 3+ слов/цифр, оставляем только последнее:
-- "Voc Back 4.1" -> "4.1", "Voc Back 4.1 Verse" -> "Verse", "Piano Bells" -> "Piano Bells"
local function shorten_folder_name(name)
    local words = {}
    for w in name:gmatch("%S+") do words[#words + 1] = w end
    if #words > 2 then return words[#words] end
    return name
end

-- Рекурсивная группировка по общим словам в названиях:
--  - общий ведущий токен у ВСЕХ треков (например "gtr", "voc") поглощается без папки
--  - группы из 2+ треков получают свою папку (вложенно, рекурсией)
--  - одиночные треки остаются прямо в контейнере
--  - get_or_create_subfolder переиспользует уже существующую папку с тем же именем,
--    поэтому дубликаты папок не создаются
-- Затемняет цвет в зависимости от глубины smart-папки (уровень 1 = родительский цвет без изменений)
local SMART_DARKEN_FACTOR = 0.8
-- Внутренний выключатель: false = умные папки создаются БЕЗ цвета
local SMART_FOLDERS_COLORED = false
local function darken_track_color(col, depth)
    local r, g, b = reaper.ColorFromNative(col)
    local f = SMART_DARKEN_FACTOR ^ (depth - 1)
    return reaper.ColorToNative(math.floor(r * f), math.floor(g * f), math.floor(b * f))
end

local function smart_folder_cluster(container, tracks, prefix, depth)
    local groups = {}
    local flat_count = 0
    for _, t in ipairs(tracks) do
        if #t.toks == 0 then
            flat_count = flat_count + 1
        else
            local key = t.toks[1]
            local rem = {}
            for k = 2, #t.toks do rem[#rem + 1] = t.toks[k] end
            local g = groups[key]
            if not g then g = {}; groups[key] = g end
            g[#g + 1] = { tr = t.tr, toks = rem }
        end
    end

    local keys = {}
    for k in pairs(groups) do keys[#keys + 1] = k end
    table.sort(keys)

    -- Общий токен у ВСЕХ треков: папку не создаём, просто углубляемся
    if #keys == 1 and flat_count == 0 then
        local new_prefix = {}
        for _, w in ipairs(prefix) do new_prefix[#new_prefix + 1] = w end
        new_prefix[#new_prefix + 1] = keys[1]
        smart_folder_cluster(container, groups[keys[1]], new_prefix, depth)
        return
    end

    for _, key in ipairs(keys) do
        local g = groups[key]
        if #g >= 2 then
            local folder_name = key
            if #prefix > 0 then
                folder_name = table.concat(prefix, " ") .. " " .. key
            end
            local parent_col = reaper.GetTrackColor(container)
            local color = nil
            if SMART_FOLDERS_COLORED and parent_col ~= 0 then
                color = darken_track_color(parent_col, depth)
            end
            local folder = get_or_create_subfolder(container, humanize_folder_name(shorten_folder_name(folder_name)), color)
            if folder then
                move_tracks_after(g, folder,1)
                local new_prefix = {}
                for _, w in ipairs(prefix) do new_prefix[#new_prefix + 1] = w end
                new_prefix[#new_prefix + 1] = key
                smart_folder_cluster(folder, g, new_prefix, depth + 1)
            end
        end
    end
end

-- Группирует парные треки (L/R в конце имени) в pan-группы:
-- линкует PAN и VOLUME, на одном треке ставит PAN_REVERSE, панорамирует стороны.
local function apply_pan_groups(tracks)
    if not pan_group or not tracks or #tracks < 2 then return end

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

                                -- reaper.GetSetTrackGroupMembership(track1, "VOLUME_LEAD", mask, mask)
                                -- reaper.GetSetTrackGroupMembership(track1, "VOLUME_FOLLOW", mask, mask)
                                -- reaper.GetSetTrackGroupMembership(track2, "VOLUME_LEAD", mask, mask)
                                -- reaper.GetSetTrackGroupMembership(track2, "VOLUME_FOLLOW", mask, mask)

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
end

-- Собирает правила из таблицы Move Tracks (общие для organize и проверки)
local function build_organize_rules()
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
                        norm_type = row.norm_type,
                        remove_silence = row.remove_silence
                    })
                end
            end
        end
    end

    table.sort(rules, function(a, b) return a.length > b.length end)
    return rules
end

-- Совпадает ли имя трека с каким-либо правилом
local function track_matches_rules(name_raw, rules)
    local name_norm = utf8_lower_custom(name_raw or ""):gsub("_", " ")
    for _, rule in ipairs(rules) do
        local s, e = name_norm:find(rule.keyword, 1, true)
        if s and (match_partial or is_word_boundary(name_norm, s, e)) then
            return true
        end
    end
    return false
end

-- Сколько треков из снапшота/выделения совпадёт с ключевыми словами ряда
-- (та же логика маппинга, что и в organize_session / run_clean_check)
local function count_row_matches(keywords_str, exclude_track, tracks)
    local kws = {}
    for kw in (keywords_str or ""):gmatch("([^,]+)") do
        local clean_kw = kw:match("^%s*(.-)%s*$")
        if clean_kw and clean_kw ~= "" then
            kws[#kws + 1] = utf8_lower_custom(clean_kw)
        end
    end
    if #kws == 0 then return 0 end

    local count = 0
    local matched_names = {}
    local matched_ptrs = {}
    for _, tr in ipairs(tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") and tr ~= exclude_track then
            local _, raw_name = reaper.GetTrackName(tr)
            local name_norm = utf8_lower_custom(raw_name):gsub("_", " ")
            for _, kw in ipairs(kws) do
                local s, e = name_norm:find(kw, 1, true)
                if s and (match_partial or is_word_boundary(name_norm, s, e)) then
                    count = count + 1
                    matched_names[#matched_names + 1] = raw_name
                    matched_ptrs[#matched_ptrs + 1] = tr
                    break
                end
            end
        end
    end
    return count, matched_names, matched_ptrs
end

-- Удаление треков без поломки структуры папок.
-- Прямой DeleteTrack на месте может оставить незакрытую папку выше по списку
-- (если удаляемый трек закрывал её с I_FOLDERDEPTH = -1).
-- Вместо этого: создаём временный трек в самом конце списка, выделяем все
-- удаляемые треки и одним блоком переносим их под временный через
-- ReorderSelectedTracks (REAPER сам компенсирует глубину в местах, откуда
-- треки ушли), затем выравниваем их I_FOLDERDEPTH в 0 и удаляем блок
-- вместе с временным треком.
local function delete_tracks_preserving_structure(tracks)
    local valid = {}
    for _, tr in ipairs(tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            valid[#valid + 1] = tr
        end
    end
    if #valid == 0 then return 0 end

    reaper.PreventUIRefresh(1)

    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    local tmp_tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)

    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    for _, tr in ipairs(valid) do
        reaper.SetTrackSelected(tr, true)
    end
    local tmp_num = reaper.GetMediaTrackInfo_Value(tmp_tr, "IP_TRACKNUMBER")
    reaper.ReorderSelectedTracks(tmp_num, 0) -- блок встаёт прямо перед временным треком

    local removed = 0
    for _, tr in ipairs(valid) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            -- треки уже внизу проекта: обнуляем глубину, чтобы они не тянули
            -- за собой открытие/закрытие папок при удалении
            reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
            reaper.DeleteTrack(tr)
            removed = removed + 1
        end
    end
    if reaper.ValidatePtr(tmp_tr, "MediaTrack*") then
        reaper.DeleteTrack(tmp_tr)
    end

    reaper.PreventUIRefresh(-1)
    return removed
end

local function organize_session()
    reaper.Undo_BeginBlock()

    local rules = build_organize_rules()

    -- Удаление неиспользуемых треков, помеченных галочкой Remove Row.
    -- Безопасность: трек удаляется только если он пуст и без дочерних треков,
    -- иначе строка остаётся с предупреждением в консоль.
    -- Сами удаления идут одним блоком через delete_tracks_preserving_structure,
    -- чтобы не ломать глубину вложенности папок.
    local removed_unused = 0
    local doomed_rows = {} -- { idx (в session_data), tr }
    for i = #session_data, 1, -1 do
        local row = session_data[i]
        if row.remove_row then
            local tr = row.parent_ptr
            if reaper.ValidatePtr(tr, "MediaTrack*") then
                if reaper.CountTrackMediaItems(tr) == 0
                    and #get_children_contain_folders_as_well(tr) == 0 then
                    doomed_rows[#doomed_rows + 1] = { idx = i, tr = tr }
                else
                    print("Remove Unused: skipped '" .. (row.name or "?") ..
                        "' - track is not empty or has child tracks")
                    row.remove_row = false
                end
            else
                row.remove_row = false -- трек уже не существует в проекте
            end
        end
    end

    if #doomed_rows > 0 then
        local doomed_tracks = {}
        for _, d in ipairs(doomed_rows) do
            doomed_tracks[#doomed_tracks + 1] = d.tr
        end
        removed_unused = delete_tracks_preserving_structure(doomed_tracks)

        -- doomed_rows собраны в обратном порядке индексов: убираем сверху вниз,
        -- чтобы индексы не съезжали
        for _, d in ipairs(doomed_rows) do
            table.remove(session_data, d.idx)
        end

        if removed_unused > 0 then
            save_data()
            print(string.format("Remove Unused: deleted %d track(s)", removed_unused))
        end
    end

    local selected_tracks = get_session_tracks()

    -- PHASE 1: определяем соответствия без перемещений.
    -- (get_or_create_subfolder идемпотентна, папки создаются сразу - это ок)
    local matches = {} -- { tr, parent, rule } в порядке обработки (с конца)
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
                        matches[#matches + 1] = { tr = tr, parent = target_parent, rule = rule }
                        break
                    end
                end
            end
        end
    end

    if #matches > 0 then
        -- PHASE 2: удаление тишины ДО перемещений (итемы ещё на своих местах,
        -- разрезы наследуют громкость тейка и переезд переносят с собой)
        local pre_silence_items = {}
        for _, m in ipairs(matches) do
            if m.rule.remove_silence and reaper.ValidatePtr(m.tr, "MediaTrack*") then
                local n = reaper.CountTrackMediaItems(m.tr)
                for j = 0, n - 1 do
                    pre_silence_items[#pre_silence_items + 1] = reaper.GetTrackMediaItem(m.tr, j)
                end
            end
        end
        if #pre_silence_items > 0 then
            remove_silence(pre_silence_items)
        end

        -- PHASE 3: нормализация по исходным трекам - читаем свежие списки итемов,
        -- поэтому хвосты после разрезов тишины тоже попадают в группу.
        -- Выполняется только при включённом мастере norm_enabled
        if norm_enabled then
            for _, m in ipairs(matches) do
                if m.rule.norm_on and reaper.ValidatePtr(m.tr, "MediaTrack*") then
                    local norm_items = {}
                    local n = reaper.CountTrackMediaItems(m.tr)
                    for j = 0, n - 1 do
                        norm_items[#norm_items + 1] = reaper.GetTrackMediaItem(m.tr, j)
                    end
                    if #norm_items > 0 then
                        normalize_items_group(norm_items,
                            m.rule.norm_db or default_norm_db(m.rule.norm_type or 0),
                            m.rule.norm_type or 0)
                    end
                end
            end
        end

        -- PHASE 4: SECTION из регионов - переименовываем исходные треки,
        -- пока они живы и позиции итемов уже финальные (после чистки тишины).
        -- Умные папки ниже создаются уже по обновлённым именам.
        if region_sections then
            local region_candidates = {}
            for _, m in ipairs(matches) do
                region_candidates[#region_candidates + 1] = m.tr
            end
            apply_region_sections(region_candidates)
        end
    end

    -- PHASE 5: перемещения
    local auto_groups = {}
    local moved_parents = {} -- родители-приёмники итемов (для Region Sections после переезда)
    local merged_tracks = {} -- исходники items_mode, удаляем одним блоком после цикла
    for _, m in ipairs(matches) do
        local tr, target_parent, rule = m.tr, m.parent, m.rule
        if reaper.ValidatePtr(tr, "MediaTrack*") and reaper.ValidatePtr(target_parent, "MediaTrack*") then
            -- Регистрируем трек в группу для конкретного target_parent
            if not auto_groups[target_parent] then auto_groups[target_parent] = {} end
            table.insert(auto_groups[target_parent], tr)

            if rule.items_mode then
                local item_count = reaper.CountTrackMediaItems(tr)
                for j = item_count - 1, 0, -1 do
                    local item = reaper.GetTrackMediaItem(tr, j)
                    reaper.MoveMediaItemToTrack(item, target_parent)
                end
                merged_tracks[#merged_tracks + 1] = tr
                moved_parents[target_parent] = true
            else
                reaper.Main_OnCommand(40297, 0) -- Unselect all
                reaper.SetTrackSelected(tr, true)
                local p_idx = reaper.GetMediaTrackInfo_Value(target_parent, "IP_TRACKNUMBER")
                reorder_idx = p_idx -- сохраняем индекс для последующего перемещения
                reaper.ReorderSelectedTracks(p_idx, 1)
            end

            found_match = true
        end
    end

    -- исходники items_mode пусты: удаляем одним безопасным блоком,
    -- чтобы не сломать глубину папок прямым DeleteTrack на месте
    if #merged_tracks > 0 then
        delete_tracks_preserving_structure(merged_tracks)
    end

    if folder_create then
        for target_parent, trs in pairs(auto_groups) do
            if reaper.ValidatePtr(target_parent, "MediaTrack*") then
                local list = {}
                local seen = {}
                -- trs собирается в обратном порядке, поэтому обходим с конца,
                -- чтобы внутри папок треки шли в правильной последовательности
                for k = #trs, 1, -1 do
                    local tr = trs[k]
                    if reaper.ValidatePtr(tr, "MediaTrack*")
                        and reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") ~= 1
                        and not seen[tr] then
                        seen[tr] = true
                        local _, rn = reaper.GetTrackName(tr)
                        list[#list + 1] = { tr = tr, toks = smart_tokens(rn) }
                    end
                end
                if #list >= 2 then
                    smart_folder_cluster(target_parent, list, {}, 1)
                end

                local function get_all_folders(track, result)
                    result = result or {}
                    for _, child in ipairs(get_children_contain_folders_as_well(track)) do
                        if reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH") == 1 then
                            result[#result + 1] = child
                            get_all_folders(child, result)
                        end
                    end
                    return result
                end
                
                local function move_plain_tracks_to_own_top(folder)
                    local plain = {}
                    for _, child in ipairs(get_children_contain_folders_as_well(folder)) do
                        if reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH") ~= 1 then
                        plain[#plain + 1] = child
                        end
                    end
                if #plain == 0 then return end

                unselect_all_tracks()
                for _, t in ipairs(plain) do reaper.SetTrackSelected(t, true) end

                    local parent_pos = reaper.GetMediaTrackInfo_Value(folder, "IP_TRACKNUMBER")
                    reaper.ReorderSelectedTracks(parent_pos, 0)
                end

                local folders = get_all_folders(target_parent)
                table.insert(folders, target_parent)
                table.sort(folders, function(a, b)
                return reaper.GetTrackDepth(a) > reaper.GetTrackDepth(b)  -- сначала глубокие
                end)

                for _, folder in ipairs(folders) do
                    move_plain_tracks_to_own_top(folder)
                end
                reaper.UpdateArrange()
                
                -- retval, p_name = reaper.GetSetMediaTrackInfo_String(target_parent, "P_NAME", "", false )
                -- print(p_name)
                
                -- print(#children)
                -- local children = get_children_contain_folders_as_well(target_parent)
                -- if #children > 0 then 
                --     for _,child in ipairs(children) do 
                --         if reaper.GetMediaTrackInfo_Value( child, "I_FOLDERDEPTH" )==1 then 
                --             local ch_children = get_children_contain_only_single(child)
                --             for _,ch_child in ipairs(ch_children) do 
                --                 if reaper.GetMediaTrackInfo_Value( ch_child, "I_FOLDERDEPTH" )==1 then 
                --                     local ch_ch_children = get_children_contain_only_single(ch_child)
                --                         for _,ch_ch_child in ipairs(ch_ch_children) do 

                --                         end

                --                 else
                --                     unselect_all_tracks()
                --                     reaper.SetTrackSelected(child, true)
                --                 end
                --             end
                --         else
                --             unselect_all_tracks()
                --             reaper.SetTrackSelected(child, true)
                --         end
                --         --     print(#ch_children)
                            
                            
                --         -- else
                --         --     retval, p_name = reaper.GetSetMediaTrackInfo_String(target_parent, "P_NAME", "", false )
                --         --     print(p_name)
                --         end
                --         -- local id = reaper.GetMediaTrackInfo_Value(target_parent, "IP_TRACKNUMBER" )
                --         -- retval, single_name = reaper.GetSetMediaTrackInfo_String(child, "P_NAME", "", false )
                --         -- print(single_name)
                --         -- unselect_all_tracks()
                --         -- reaper.SetTrackSelected(child, true)

                        
                --         -- if reaper.GetMediaTrackInfo_Value( child, "I_FOLDERDEPTH" )~=1 then 

                --         -- end 
                --     end 
                --     -- reaper.ReorderSelectedTracks(reaper.GetMediaTrackInfo_Value(target_parent, "IP_TRACKNUMBER" ), 0 )
                --     -- unselect_all_tracks()
                -- end
            end
        end
    end

    -- SECTION из регионов для родителей-приёмников итемов (items mode):
    -- консенсус по итоговому контенту родителя, ДО создания умных папок.
    if region_sections and next(moved_parents) then
        local parent_candidates = {}
        for tp in pairs(moved_parents) do
            if reaper.ValidatePtr(tp, "MediaTrack*") then
                parent_candidates[#parent_candidates + 1] = tp
            end
        end
        apply_region_sections(parent_candidates)
    end

    if pan_group then
        local moved_tracks = {}
        for _, trs in pairs(auto_groups) do
            for _, tr in ipairs(trs) do
                if reaper.ValidatePtr(tr, "MediaTrack*") then
                    moved_tracks[#moved_tracks + 1] = tr
                end
            end
        end
        apply_pan_groups(moved_tracks)
    end

    reaper.Undo_EndBlock("Organize Session", -1)
    reaper.TrackList_AdjustWindows(false)
end

-- Проверка треков из снапшота Clean Names по правилам Move Tracks.
-- Строки, чьё новое имя не совпадёт ни с одним правилом, помечаются check_failed
-- (красный тинт в таблице).
-- Заодно пересчитывает кэш счётчиков для кнопок в таблице Move Tracks.
-- Всё это выполняется только при вызове Check (кнопка или авто-триггеры).
local match_counts = {} -- [row] = количество совпавших треков
local match_names = {}  -- [row] = { имена }
local match_ptrs = {}   -- [row] = { указатели треков }

local function run_clean_check()
    -- Пересчёт счётчиков совпадений для рядов Move Tracks
    local check_tracks = get_session_tracks()
    match_counts = {}
    match_names = {}
    match_ptrs = {}
    for _, r in ipairs(session_data) do
        local c, names, ptrs = count_row_matches(r.keywords, r.parent_ptr, check_tracks)
        match_counts[r] = c
        match_names[r] = names
        match_ptrs[r] = ptrs
    end

    if not clean_names_snapshot then return end

    local rules = build_organize_rules()
    for _, r in ipairs(clean_names_snapshot.rows) do
        -- Проверяем новое (предполагаемое после переименования) имя
        local name_to_check = (r.new_name and r.new_name ~= "") and r.new_name or r.name
        r.check_failed = not track_matches_rules(name_to_check, rules)
    end
end

function get_or_create_subfolder(parent_tr, folder_name, color)
    local parent_idx = reaper.GetMediaTrackInfo_Value(parent_tr, "IP_TRACKNUMBER")
    local depth = reaper.GetTrackDepth(parent_tr)
    local ln = utf8_lower_custom(folder_name)

    -- Ищем уже существующую ПАПКУ-потомка с таким же именем (глубина ровно depth+1).
    -- Обычные (не папки) треки не считаются совпадением, поэтому дубликаты не создаются.
    for i = parent_idx, reaper.CountTracks(0) - 1 do
        local child = reaper.GetTrack(0, i)
        local cd = reaper.GetTrackDepth(child)
        if i > parent_idx and cd <= depth then break end
        if cd == depth + 1 and reaper.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH") == 1 then
            local _, name = reaper.GetTrackName(child)
            if utf8_lower_custom(name) == ln then return child end
        end
    end
    
    reaper.InsertTrackAtIndex(parent_idx, true)
    local new_folder = reaper.GetTrack(0, parent_idx)
    reaper.GetSetMediaTrackInfo_String(new_folder, "P_NAME", folder_name, true)
    reaper.SetMediaTrackInfo_Value(parent_tr, "I_FOLDERDEPTH", 1)
    if color then
        reaper.SetTrackColor(new_folder, color)
    end

    return new_folder
end

-- ============================================================
-- CLEAN NAMES ENGINE
-- ============================================================
-- CLEAN NAMES ENGINE
-- ============================================================
-- Ранги (порядок сортировки итогового имени)
local CLEAN_RANK = { CLASS = 1, SUBCLASS = 2, INFO = 3, SECTION = 4, LAYER = 5, SOURCE = 6 }
local CLEAN_RANK_NAMES = { [1] = "CLASS", [2] = "SUBCLASS", [3] = "INFO", [4] = "SECTION", [5] = "LAYER", [6] = "SOURCE" }
local CLEAN_RULE_ORDER = { "INFO", "SECTION", "LAYER", "SOURCE" }
local CLEAN_RULE_LABELS = {
    INFO = "INFO (amb/big/low/high...)",
    SECTION = "SECTION (verse/chorus/bridge...)",
    LAYER   = "LAYER (dub/double...)",
    SOURCE  = "SOURCE / mic (di/amp/oh/room...)",
}

-- ============ CLASSES (each class has its own subclasses) ============
local CLEAN_DEFAULT_CLASSES = {
    {
        name = "Gtr",
        synonyms = { "gtr","gt","guitar","guitars","guit","git","gita","egtr",
                     "elecgtr","elgtr","electricguitar","electguitar",
                     "acgtr","acousticgtr","acousticguitar","acusticgtr","leadgtr" },
        subclasses = {
            { name = "El",    synonyms = { "e","el","elec","elect","electric","electr","elecgtr","elgtr","electricguitar","electguitar" } },
            { name = "Ac",    synonyms = { "ac","acc","aco","acoust","acoustic","acustic","acgtr","acousticgtr","acousticguitar","acusticgtr" } },
            { name = "Lead",  synonyms = { "lead","leads","leadg","leadgtr","ld","main","mainmel" } },
            { name = "Rh",    synonyms = { "rh","rhy","rythm","rhythm","ryhm","rhyt","rthm","ритм" } },
            { name = "Solo",  synonyms = { "solo","sol" } },
            { name = "Clean", synonyms = { "clean","cln" } },
            { name = "Dist",  synonyms = { "dist","disto","distortion","distorted","drive","overdrive","crunch" } },
        },
    },
    {
        name = "Bass",
        synonyms = { "bass","bs","bas","bassgtr","bassguitar","bajo",
                     "elbass","elecbass","el-bass","acbass","acousticbass",
                     "subbass","sub-bass","sub" },
        subclasses = {
            { name = "El", synonyms = { "e","el","elec","elect","electric","electr","elbass","elecbass","el-bass" } },
            { name = "Ac", synonyms = { "ac","acc","aco","acoust","acoustic","acustic","acbass","acousticbass" } },
            { name = "Sub", synonyms = { "sub","subbass","sub-bass" } },
        },
    },
    {
        name = "Kick",
        synonyms = { "kick","kic","kik","kk","kck","kd","kdk","bd","kickdrum" },
        subclasses = {},
    },
    {
        name = "Snare",
        synonyms = { "snare","sna","snr","sn","sdr","snaredrum" },
        subclasses = {},
    },
    {
        name = "Hat",
        synonyms = { "hat","hats","hihat","hh","hhat","closedhat","clhat","chh","chhat","openhat","ohhat" },
        subclasses = {
            { name = "Close", synonyms = { "closedhat","clhat","chh","chhat" } },
            { name = "Open",  synonyms = { "openhat","ohhat" } },
        },
    },
    {
        name = "Tom",
        synonyms = { "tom","toms" },
        subclasses = {},
    },
    {
        name = "Cym",
        synonyms = { "cymbal","cymbals","cym","cymb","ride","rides","crash","crashes","china","chinas","splash","splashes" },
        subclasses = {
            { name = "Ride",  synonyms = { "ride","rides" } },
            { name = "Crash", synonyms = { "crash","crashes" } },
            { name = "China", synonyms = { "china","chinas" } },
            { name = "Splash", synonyms = { "splash","splashes" } },
        },
    },
    {
        name = "Perc",
        synonyms = { "perc","per","percussion","percussions","percus",
                     "shaker","shakers","shake","tambo","tambourine","tamb",
                     "cowbell","clap","claps","handclaps","boom","booms" },
        subclasses = {
            { name = "Shaker", synonyms = { "shaker","shakers","shake" } },
            { name = "Tambo",  synonyms = { "tambo","tambourine","tamb" } },
            { name = "Cowbell", synonyms = { "cowbell" } },
            { name = "Clap",   synonyms = { "clap","claps","handclaps" } },
            { name = "Boom",   synonyms = { "boom","booms" } },
        },
    },
    {
        name = "Drum",
        synonyms = { "drums","drum","drm" },
        subclasses = {},
    },
    {
        name = "Piano",
        synonyms = { "piano","pno","pn","pf","pia","grand",
                     "elecpiano","epiano","e-piano","ep","wurlitzer","wurli","rhodes",
                     "acpiano","upright","uprightpiano" },
        subclasses = {
            { name = "El", synonyms = { "e","el","elec","elect","electric","electr","elecpiano","epiano","e-piano","ep","wurlitzer","wurli","rhodes" } },
            { name = "Ac", synonyms = { "ac","acc","aco","acoust","acoustic","acustic","acpiano","upright","uprightpiano" } },
        },
    },
    {
        name = "Clav",
        synonyms = { "clav","clavinet","klavesyn" },
        subclasses = {},
    },
    {
        name = "Keys",
        synonyms = { "keys","key","kb","keyboard","keyboards" },
        subclasses = {},
    },
    {
        name = "Synth",
        synonyms = { "synth","syn","sy","syth","synt","synthesizer",
                     "leadsynth","leadsyn","lsynth","padsynth","padsyn","psynth","arpsynth","arpsyn" },
        subclasses = {
            { name = "Lead", synonyms = { "lead","leads","ld","main","mainmel","leadsynth","leadsyn","lsynth" } },
            { name = "Pad",  synonyms = { "pad","pads","padsynth","padsyn","psynth" } },
            { name = "Arp",  synonyms = { "arp","arpeggio","arps","arpsynth","arpsyn" } },
        },
    },
    {
        name = "Organ",
        synonyms = { "organ","org","organs","hammond","bx3","tonewheel" },
        subclasses = {},
    },
    {
        name = "Strings",
        synonyms = { "st","str","string","strings","stringsection","orch","orchestra","orchestral",
                     "violin","violins","vln","cello","cellos","vc","viola","violas","vla" },
        subclasses = {
            { name = "Violin", synonyms = { "violin","violins","vln" } },
            { name = "Cello",  synonyms = { "cello","cellos","vc" } },
            { name = "Viola",  synonyms = { "viola","violas","vla" } },
        },
    },
    {
        name = "Pad",
        synonyms = { "pad","pads" },
        subclasses = {},
    },
    {
        name = "Voc",
        synonyms = { "vocal","vocals","vox","voc","vocs","voice","voices","вокал","вокалы","вок","голос","голоса","v",
                     "leadvocal","leadvox","leadvocals","mainvocal","mainvox","lvox","lvoc",
                     "backingvocal","backingvox","backvocal","backvox","backing","background" },
        subclasses = {
            { name = "Lead", synonyms = { "lead","leads","ld","main","mainmel","leadvocal","leadvox","leadvocals","mainvocal","mainvox","lvox","lvoc" } },
            { name = "Back", synonyms = { "back","backing","background","backingvocal","backingvox","backvocal","backvox" } },
        },
    },
    {
        name = "Back",
        synonyms = { "bgv","bgvox","bgvocals","bg","bv","bvg","bkg","бэк","бэквокал" },
        subclasses = {},
    },
    {
        name = "VocFX",
        synonyms = { "vx","vxfx","vocalfx","voxfx","vocalchops","vocalchop","chops","adlib","adlibs" },
        subclasses = {},
    },
    {
        name = "FX",
        synonyms = { "fx","sfx","effect","effects" },
        subclasses = {},
    },
}

-- ============ GLOBAL groups (applied to any class) ============
local CLEAN_DEFAULT_GROUPS = {
    -- INFO
    { rank = "INFO", keys = { "amb","ambi","ambient","atmo","atmos","atm" }, words = { "Amb" } },
    { rank = "INFO", keys = { "big" }, words = { "Big" } },
    { rank = "INFO", keys = { "little","small" }, words = { "Little" } },
    { rank = "INFO", keys = { "low","lows","lo" }, words = { "Low" } },
    { rank = "INFO", keys = { "high","highs","hi" }, words = { "High" } },
    { rank = "INFO", keys = { "mid","mids" }, words = { "Mid" } },
    { rank = "INFO", keys = { "dark","darker" }, words = { "Dark" } },
    { rank = "INFO", keys = { "bright","brighter" }, words = { "Bright" } },
    { rank = "INFO", keys = { "warm" }, words = { "Warm" } },
    { rank = "INFO", keys = { "wide","wider" }, words = { "Wide" } },
    { rank = "INFO", keys = { "deep","deeper" }, words = { "Deep" } },
    { rank = "INFO", keys = { "sparkle","sparkles" }, words = { "Sparkle" } },
    { rank = "INFO", keys = { "swell","swells" }, words = { "Swell" } },
    { rank = "INFO", keys = { "glide" }, words = { "Glide" } },
    { rank = "INFO", keys = { "arpeggio","arp","arps" }, words = { "Arp" } },
    { rank = "INFO", keys = { "pluck","plucks" }, words = { "Pluck" } },
    { rank = "INFO", keys = { "stab","stabs" }, words = { "Stab" } },
    { rank = "INFO", keys = { "chord","chords","chds" }, words = { "Chords" } },
    { rank = "INFO", keys = { "bell","bells" }, words = { "Bells" } },
    -- SECTION
    { rank = "SECTION", keys = { "verse","verses","vs","vrs" }, words = { "Verse" } },
    { rank = "SECTION", keys = { "chorus","choruses","ch","chrs","chor","припев" }, words = { "Chorus" } },
    { rank = "SECTION", keys = { "prechorus","pre-chorus","prech" }, words = { "PreChorus" } },
    { rank = "SECTION", keys = { "bridge","br","brg" }, words = { "Bridge" } },
    { rank = "SECTION", keys = { "intro","intr","int","интро" }, words = { "Intro" } },
    { rank = "SECTION", keys = { "outro","outr","аутро" }, words = { "Outro" } },
    { rank = "SECTION", keys = { "hook","hooks" }, words = { "Hook" } },
    { rank = "SECTION", keys = { "break","brk","breaks","breakdown" }, words = { "Break" } },
    { rank = "SECTION", keys = { "drop","drops" }, words = { "Drop" } },
    { rank = "SECTION", keys = { "build","buildup","build-up" }, words = { "Build" } },
    { rank = "SECTION", keys = { "interlude" }, words = { "Interlude" } },
    { rank = "SECTION", keys = { "coda","ending" }, words = { "Coda" } },
    { rank = "SECTION", keys = { "riff","riffs" }, words = { "Riff" } },
    { rank = "SECTION", keys = { "middle","mid8" }, words = { "Middle" } },
    -- LAYER
    { rank = "LAYER", keys = { "dub","dbl","double","doubled","dabl","dab" }, words = { "Dub" } },
    -- SOURCE
    { rank = "SOURCE", keys = { "di","direct" }, words = { "DI" } },
    { rank = "SOURCE", keys = { "amp","amps","amped" }, words = { "Amp" } },
    { rank = "SOURCE", keys = { "mic","mics","miced","microphone" }, words = { "Mic" } },
    { rank = "SOURCE", keys = { "top","tp" }, words = { "Top" } },
    { rank = "SOURCE", keys = { "btm","bt","bottom","bot" }, words = { "Btm" } },
    { rank = "SOURCE", keys = { "in","inside" }, words = { "In" } },
    { rank = "SOURCE", keys = { "out","outside" }, words = { "Out" } },
    { rank = "SOURCE", keys = { "room","rooms","rm" }, words = { "Room" } },
    { rank = "SOURCE", keys = { "oh","overhead","overheads","ov","ovh","ohs" }, words = { "OH" } },
    { rank = "SOURCE", keys = { "close","closemic" }, words = { "Close" } },
    { rank = "SOURCE", keys = { "far","farmic" }, words = { "Far" } },
    { rank = "SOURCE", keys = { "l","left","лево" }, words = { "L" } },
    { rank = "SOURCE", keys = { "r","right","право" }, words = { "R" } },
    { rank = "SOURCE", keys = { "mono","mon" }, words = { "Mono" } },
    { rank = "SOURCE", keys = { "stereo","ster" }, words = { "Stereo" } },
    { rank = "SOURCE", keys = { "ms","midside","mid-side","mid_side" }, words = { "Mid","Side" } },
}

-- ============ JUNK (always removed) ============
local CLEAN_DEFAULT_JUNK = { "rec","track","tracks","trk","trks","stem","stems","take","takes","bounce","bounced",
                             "render","rendered","rend","audio","rough","draft","demo","raw","copy","final",
                             "version","the","a","an","of","wav","mp3","flac","wave","lr" }

-- текущее (редактируемое) состояние движка
local clean_classes = {}
local clean_global_groups = {}
local clean_junk_words = {}

-- рантайм-таблицы (пересобираются через rebuild_engine_from_data)
local CLEAN_DICT = {}
local CLEAN_JUNK = {}
local CLEAN_CLASS_MAP = {}
local CLEAN_KNOWN = {}

-- ---------- clean engine: rebuild / persist ----------
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64_encode(s)
    local b = {}
    for i = 1, #s, 3 do
        local a = s:byte(i) or 0
        local b2 = s:byte(i + 1) or 0
        local c = s:byte(i + 2) or 0
        local n = a * 65536 + b2 * 256 + c
        b[#b + 1] = B64_CHARS:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
        b[#b + 1] = B64_CHARS:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        b[#b + 1] = B64_CHARS:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        b[#b + 1] = B64_CHARS:sub(n % 64 + 1, n % 64 + 1)
    end
    local rem = #s % 3
    if rem == 1 then
        b[#b - 1] = "="
        b[#b] = "="
    elseif rem == 2 then
        b[#b] = "="
    end
    return table.concat(b)
end

local function base64_decode(s)
    s = s:gsub("=%s*$", "")
    local rev = {}
    for i = 1, 64 do rev[B64_CHARS:sub(i, i)] = i - 1 end
    local out = {}
    for i = 1, #s, 4 do
        local c1 = rev[s:sub(i, i)]
        local c2 = rev[s:sub(i + 1, i + 1)]
        local c3 = rev[s:sub(i + 2, i + 2)] or 0
        local c4 = rev[s:sub(i + 3, i + 3)] or 0
        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        out[#out + 1] = string.char(math.floor(n / 256) % 256)
        out[#out + 1] = string.char(n % 256)
    end
    local text = table.concat(out)
    if #s % 4 == 2 then text = text:sub(1, -2)
    elseif #s % 4 == 3 then text = text:sub(1, -1) end
    return text
end

local function rebuild_engine_from_data(classes, global_groups, junk_words)
    CLEAN_CLASS_MAP = {}
    CLEAN_DICT = {}
    CLEAN_KNOWN = {}
    for _, cls in ipairs(classes) do
        local cname = cls.name
        local sub_map = {}
        for _, sub in ipairs(cls.subclasses) do
            for _, k in ipairs(sub.synonyms) do sub_map[k] = sub.name end
        end
        for _, k in ipairs(cls.synonyms) do
            CLEAN_CLASS_MAP[k] = { name = cname, sub_map = sub_map, has_sub = cls.subclasses[1] ~= nil }
        end
    end
    local rank_id = {}
    for id, rname in pairs(CLEAN_RANK_NAMES) do rank_id[rname] = id end
    for _, g in ipairs(global_groups) do
        local rank = rank_id[g.rank] or CLEAN_RANK.INFO
        local parts = {}
        for _, w in ipairs(g.words) do
            table.insert(parts, { word = w, rank = rank })
        end
        if #g.keys > 0 and #parts > 0 then
            for _, k in ipairs(g.keys) do CLEAN_DICT[k] = parts end
        end
    end
    for k, _ in pairs(CLEAN_CLASS_MAP) do CLEAN_KNOWN[k] = true end
    for k, v in pairs(CLEAN_CLASS_MAP) do
        for sk, _ in pairs(v.sub_map) do CLEAN_KNOWN[sk] = true end
    end
    for k, _ in pairs(CLEAN_DICT) do CLEAN_KNOWN[k] = true end
    CLEAN_JUNK = {}
    for _, w in ipairs(junk_words) do CLEAN_JUNK[w] = true end
    for w, _ in pairs(CLEAN_JUNK) do CLEAN_KNOWN[w] = true end
    clean_classes = classes
    clean_global_groups = global_groups
    clean_junk_words = junk_words
end

local function split_clean(str, sep)
    local parts = {}
    local buf = {}
    local i, n = 1, #str
    while i <= n do
        local c = str:sub(i, i)
        if c == "\\" then
            buf[#buf + 1] = str:sub(i, i + 1)
            i = i + 2
        elseif c == sep then
            parts[#parts + 1] = table.concat(buf)
            buf = {}
            i = i + 1
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    parts[#parts + 1] = table.concat(buf)
    return parts
end

local function clean_escape(s)
    return (s:gsub("[\\%,;|]", "\\%1"))
end

local function clean_unescape(s)
    return (s:gsub("\\(.)", "%1"))
end

local function serialize_clean_engine()
    local parts = {}
    for _, cls in ipairs(clean_classes) do
        local syns = {}
        for _, s in ipairs(cls.synonyms) do syns[#syns + 1] = clean_escape(s) end
        parts[#parts + 1] = "C|" .. clean_escape(cls.name) .. "|" .. table.concat(syns, ",")
        for _, sub in ipairs(cls.subclasses) do
            local ss = {}
            for _, s in ipairs(sub.synonyms) do ss[#ss + 1] = clean_escape(s) end
            parts[#parts + 1] = "S|" .. clean_escape(cls.name) .. "|" .. clean_escape(sub.name) .. "|" .. table.concat(ss, ",")
        end
    end
    for _, g in ipairs(clean_global_groups) do
        local ks, ws = {}, {}
        for _, k in ipairs(g.keys) do ks[#ks + 1] = clean_escape(k) end
        for _, w in ipairs(g.words) do ws[#ws + 1] = clean_escape(w) end
        parts[#parts + 1] = "G|" .. tostring(g.rank) .. "|" .. table.concat(ks, ",") .. "|" .. table.concat(ws, ",")
    end
    local js = {}
    for _, w in ipairs(clean_junk_words) do js[#js + 1] = clean_escape(w) end
    parts[#parts + 1] = "J|" .. table.concat(js, ",")
    return table.concat(parts, ";")
end

local function deserialize_clean_engine(str)
    local classes = {}
    local groups = {}
    local junk = {}
    local class_by_name = {}
    for _, rec in ipairs(split_clean(str, ";")) do
        if rec ~= "" then
            local f = split_clean(rec, "|")
            local kind = f[1]
            if kind == "C" then
                local cls = { name = clean_unescape(f[2] or ""), synonyms = {}, subclasses = {} }
                for _, w in ipairs(split_clean(f[3] or "", ",")) do
                    if w ~= "" then cls.synonyms[#cls.synonyms + 1] = clean_unescape(w) end
                end
                classes[#classes + 1] = cls
                class_by_name[cls.name] = cls
            elseif kind == "S" then
                local cls = class_by_name[clean_unescape(f[2] or "")]
                if cls then
                    local sub = { name = clean_unescape(f[3] or ""), synonyms = {} }
                    for _, w in ipairs(split_clean(f[4] or "", ",")) do
                        if w ~= "" then sub.synonyms[#sub.synonyms + 1] = clean_unescape(w) end
                    end
                    cls.subclasses[#cls.subclasses + 1] = sub
                end
            elseif kind == "G" then
                local keys, words = {}, {}
                for _, w in ipairs(split_clean(f[3] or "", ",")) do
                    if w ~= "" then keys[#keys + 1] = clean_unescape(w) end
                end
                for _, w in ipairs(split_clean(f[4] or "", ",")) do
                    if w ~= "" then words[#words + 1] = clean_unescape(w) end
                end
                groups[#groups + 1] = { rank = f[2], keys = keys, words = words }
            elseif kind == "J" then
                for _, w in ipairs(split_clean(f[2] or "", ",")) do
                    if w ~= "" then junk[#junk + 1] = clean_unescape(w) end
                end
            end
        end
    end
    return classes, groups, junk
end

local function load_clean_engine()
    local saved = reaper.GetExtState("MISHA_SESSION_ORGANIZER", "CLEAN_RULES")
    if saved and saved ~= "" then
        local plain = nil
        local function decode(b64)
            if reaper.NF_Base64_Decode then
                local ok, str = reaper.NF_Base64_Decode(b64)
                if ok and str then return str end
            end
            return base64_decode(b64)
        end
        local ok = pcall(function() plain = decode(saved) end)
        if ok and plain and plain ~= "" then
            local ok2, classes, groups, junk = pcall(deserialize_clean_engine, plain)
            if ok2 and #classes > 0 then
                rebuild_engine_from_data(classes, groups, junk)
                return
            end
        end
    end
    rebuild_engine_from_data(CLEAN_DEFAULT_CLASSES, CLEAN_DEFAULT_GROUPS, CLEAN_DEFAULT_JUNK)
end

local function save_clean_engine()
    local plain = serialize_clean_engine()
    local b64 = nil
    if reaper.NF_Base64_Encode then b64 = reaper.NF_Base64_Encode(plain, false) end
    if not b64 then b64 = base64_encode(plain) end
    reaper.SetExtState("MISHA_SESSION_ORGANIZER", "CLEAN_RULES", b64, true)
end

load_clean_engine()

-- ---------- utilities ----------
local AUDIO_EXTS = { wav=true, aif=true, aiff=true, flac=true, mp3=true, ogg=true, m4a=true, wma=true, aac=true, mid=true, midi=true, opus=true, mp4=true, m4v=true }
local function strip_ext(name)
    local stem, ext = name:match("^(.*)%.([%w]+)$")
    if stem and ext and AUDIO_EXTS[ext:lower()] then return stem end
    return name
end

local function tokenize(s)
    local toks, cur, last = {}, {}, nil
    local function flush()
        if #cur > 0 then toks[#toks + 1] = table.concat(cur) cur = {} end
    end
    local i, n = 1, #s
    while i <= n do
        local ch = s:sub(i, i)
        local b = ch:byte(1)
        local typ
        if b and b >= 48 and b <= 57 then typ = "digit"
        elseif b and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122)) then
            typ = (b >= 65 and b <= 90) and "upper" or "lower"
        elseif b and b >= 128 then typ = "lower"
        else typ = "sep" end
        if typ == "sep" then
            -- Точку между двумя цифрами сохраняем внутри токена (4.1, 1.1.2)
            if ch == "." and last == "digit" then
                local nb = s:byte(i + 1)
                if nb and nb >= 48 and nb <= 57 then
                    cur[#cur + 1] = ch
                else
                    flush()
                    last = nil
                end
            else
                flush()
                last = nil
            end
        else
            if last then
                if (last == "lower" and typ == "upper")
                   or ((last == "digit") ~= (typ == "digit")) then flush() end
            end
            cur[#cur + 1] = ch
            last = typ
        end
        i = i + 1
    end
    flush()
    return toks
end

local function lower_token(t) return utf8_lower_custom(t) end

local function cap_word(w)
    local b1 = w:byte(1)
    if not b1 then return w end
    if b1 >= 97 and b1 <= 122 then return w:sub(1,1):upper() .. w:sub(2) end
    local b2 = w:byte(2)
    if b1 == 0xD0 and b2 and b2 >= 0xB0 and b2 <= 0xBF then return string.char(0xD0, b2 - 0x20) .. w:sub(3) end
    if b1 == 0xD1 and b2 and b2 >= 0x80 and b2 <= 0x8F then return string.char(0xD1, b2 - 0x20) .. w:sub(3) end
    return w
end

-- Числовой токен: целое или дробное/версия с точками (4, 45, 4.1, 4.1.1)
local function is_numeric_token(t)
    return t:match("^%d+$") ~= nil or t:match("^%d+%.%d+(%.%d+)*$") ~= nil
end

-- detect common "session" word(s) at edges (rule 1)
local function detect_session(names)
    local total = #names
    local session = {}
    if total < 2 then return session end
    local firsts, lasts, phrF, phrL = {}, {}, {}, {}
    for _, nm in ipairs(names) do
        local toks = {}
        for _, t in ipairs(tokenize(strip_ext(nm))) do
            local tn = lower_token(t)
            if not is_numeric_token(tn) and #tn >= 3 and not CLEAN_KNOWN[tn] then
                toks[#toks + 1] = tn
            end
        end
        if #toks > 0 then
            firsts[toks[1]] = (firsts[toks[1]] or 0) + 1
            lasts[toks[#toks]] = (lasts[toks[#toks]] or 0) + 1
            if #toks >= 2 then
                local pf = toks[1] .. " " .. toks[2]
                phrF[pf] = (phrF[pf] or 0) + 1
                local pl = toks[#toks-1] .. " " .. toks[#toks]
                phrL[pl] = (phrL[pl] or 0) + 1
            end
        end
    end
    local thresh = math.max(2, math.ceil(total * 0.3))
    local best = nil
    local function consider(key, count)
        if count >= thresh then
            local sc = 1
            for _ in key:gmatch("%S+") do sc = sc + 1 end
            local score = count * 10 + sc
            if not best or score > best.score then best = { key = key, score = score } end
        end
    end
    for k, c in pairs(phrF) do consider(k, c) end
    for k, c in pairs(phrL) do consider(k, c) end
    for k, c in pairs(firsts) do consider(k, c) end
    for k, c in pairs(lasts) do consider(k, c) end
    if best then
        for w in best.key:gmatch("%S+") do session[w] = true end
    end
    return session
end

-- rule 6: most files start with an ordinal number (after the session phrase is ignored)
local function detect_leading_numbers(names, session)
    local total = #names
    if total < 2 then return false end
    local lead = 0
    for _, nm in ipairs(names) do
        local toks = tokenize(strip_ext(nm))
        for _, t in ipairs(toks) do
            local tn = lower_token(t)
            if session[tn] or CLEAN_JUNK[tn] then
                -- skip session/junk prefix
            else
                if is_numeric_token(tn) then lead = lead + 1 end
                break
            end
        end
    end
    return lead >= math.max(2, math.ceil(total * 0.6))
end

-- main formatter
local function process_name(raw, session, strip_lead)
    local toks = tokenize(strip_ext(raw))
    local items, idx = {}, 0
    local matched = {}
    for _, t in ipairs(toks) do
        local tn = lower_token(t)
        if not (session[tn] or CLEAN_JUNK[tn]) then
            local cm = CLEAN_CLASS_MAP[tn]
            if cm then matched[cm.name] = cm end
        end
    end
    local matched_list = {}
    for _, cm in pairs(matched) do matched_list[#matched_list + 1] = cm end
    local function add_item(word, rank)
        idx = idx + 1
        items[#items + 1] = { word = word, rank = rank, idx = idx }
    end
    -- класс/подкласс добавляются один раз: синонимы вроде 'perc' и 'shaker'
    -- ведут к одному классу Perc, и без дедупа получается 'Perc Perc Shaker'
    local added_class, added_sub = {}, {}
    local first = true
    for _, t in ipairs(toks) do
        local tn = lower_token(t)
        if session[tn] or CLEAN_JUNK[tn] then
            -- drop
        elseif strip_lead and first and is_numeric_token(tn) then
            -- drop ordinal
        else
            first = false
            local cm = CLEAN_CLASS_MAP[tn]
            if cm then
                if not added_class[cm.name] then
                    add_item(cm.name, CLEAN_RANK.CLASS)
                    added_class[cm.name] = true
                end
                local subn = cm.sub_map[tn]
                if subn and not added_sub[subn] then
                    add_item(subn, CLEAN_RANK.SUBCLASS)
                    added_sub[subn] = true
                end
            elseif is_numeric_token(tn) then
                add_item(tn, CLEAN_RANK.LAYER)
            else
                local parts = CLEAN_DICT[tn]
                if parts then
                    for _, p in ipairs(parts) do
                        add_item(p.word, p.rank)
                    end
                else
                    local subn = nil
                    for _, cm in ipairs(matched_list) do
                        local s = cm.sub_map[tn]
                        if s then subn = s break end
                    end
                    if subn then
                        add_item(subn, CLEAN_RANK.SUBCLASS)
                    else
                        add_item(cap_word(tn), CLEAN_RANK.INFO)
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.idx < b.idx
    end)
    local out = {}
    for _, it in ipairs(items) do out[#out + 1] = it.word end
    return table.concat(out, " ")
end

-- ============================================================
-- REGION SECTIONS ENGINE
-- После удаления тишины: если все итемы трека лежат в регионах с одинаковым
-- именем (без цифр, в нижнем регистре), это имя добавляется в название трека.
-- Имя собирается через process_name, поэтому слово встаёт как SECTION -
-- до LAYER и SOURCE: 'Gtr 1 R' + регион 'Chorus 2' -> 'Gtr Chorus 1 R'.
-- Допуск: один такт, если край итема чуть выходит за границу региона.
-- ============================================================
local function region_measure_length_at(t)
    local _, measures = reaper.TimeMap2_timeToBeats(0, t)
    return reaper.TimeMap2_beatsToTime(0, 0, measures + 1) - reaper.TimeMap2_beatsToTime(0, 0, measures)
end

-- Метка региона: без цифр, в нижнем регистре, без лишних пробелов/подчерков
local function region_clean_label(name)
    local lbl = utf8_lower_custom(name):gsub("%d+", ""):gsub("[%s_]+", " ")
    return lbl:match("^%s*(.-)%s*$")
end

local function get_project_regions()
    local regions = {}
    local total = reaper.GetNumRegionsOrMarkers(0)

    for idx = 0, total - 1 do
        local r = reaper.GetRegionOrMarker(0, idx, "")
        if r and r ~= 0 then
            local isrgn = reaper.GetRegionOrMarkerInfo_Value(0, r, "B_ISREGION")
            if isrgn == 1 then
                local retval, name = reaper.GetSetRegionOrMarkerInfo_String(0, r, "P_NAME", "", false)
                if retval and name ~= "" then
                    local lbl = region_clean_label(name)
                    local pos = reaper.GetRegionOrMarkerInfo_Value(0, r, "D_STARTPOS")
                    local fin = reaper.GetRegionOrMarkerInfo_Value(0, r, "D_ENDPOS" )
                    regions[#regions + 1] = { label = lbl, pos = pos, fin = fin }
                end
            end
        end
    end
    return regions


    -- local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
    -- for i = 0, num_markers + num_regions - 1 do
    --     local _, isrgn, pos, fin, rname = reaper.EnumProjectMarkers(0, i)
    --     if isrgn and rname and rname ~= "" then
    --         local lbl = region_clean_label(rname)
    --         print(lbl)
    --         if lbl ~= "" then
    --             regions[#regions + 1] = { label = lbl, pos = pos, fin = fin }
    --         end
    --     end
    -- end
end

local REGION_DEBUG = false -- true: печатать диагностику Region Sections в консоль
local REGION_COVERAGE = 0.90 -- минимальная доля итема, которую должен покрывать ОДИН тип регионов

-- Есть ли в имени трека уже слово-секция (по словарю Clean Names Engine)?
local function track_name_has_section(name)
    for _, t in ipairs(tokenize(strip_ext(name or ""))) do
        local tn = lower_token(t)
        local parts = CLEAN_DICT[tn]
        if parts then
            for _, p in ipairs(parts) do
                if p.rank == CLEAN_RANK.SECTION then return true end
            end
        end
    end
    return false
end

-- Оставляем в метке региона только новые для имени трека слова и убираем
-- слова-классы, чтобы не получать дубли вида 'Perc Perc Shaker...'
local function region_label_new_words(label, raw_name)
    local existing = {}
    for _, t in ipairs(tokenize(strip_ext(raw_name or ""))) do
        existing[lower_token(t)] = true
    end

    local kept = {}
    for _, t in ipairs(tokenize(label)) do
        local tn = lower_token(t)
        if not existing[tn] and not CLEAN_CLASS_MAP[tn] then
            kept[#kept + 1] = t
        end
    end
    return table.concat(kept, " ")
end

function apply_region_sections(tracks)
    local regions = get_project_regions()
    if #regions == 0 or not tracks then
        if REGION_DEBUG then print("[RegionSections] no regions or no candidate tracks") end
        return
    end
    if REGION_DEBUG then
        print("[RegionSections] regions:")
        for _, rg in ipairs(regions) do
            print(string.format("  '%s'  %.2f - %.2f", rg.label, rg.pos, rg.fin))
        end
    end

    for _, tr in ipairs(tracks) do
        if reaper.ValidatePtr(tr, "MediaTrack*") then
            local _, raw_name = reaper.GetTrackName(tr)

            -- В имени уже есть секция - не добавляем вторую и не меняем имя
            if track_name_has_section(raw_name) then
                if REGION_DEBUG then
                    print(string.format("[RegionSections] skip '%s': name already has a section", raw_name))
                end
            else
                local n_items = reaper.CountTrackMediaItems(tr)
                if REGION_DEBUG then
                    print(string.format("[RegionSections] track '%s': %d item(s)", raw_name, n_items))
                end
                if n_items > 0 then
                    local consensus = nil   -- метки, общие для всех уже просмотренных итемов
                    local all_matched = true
                    local fail_reason = nil

                    for j = 0, n_items - 1 do
                        local item = reaper.GetTrackMediaItem(tr, j)
                        local ipos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        local ifin = ipos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

                        local item_len = ifin - ipos

                        -- суммируем покрытие итема по типам регионов (метки без цифр)
                        local cov = {}
                        for _, rg in ipairs(regions) do
                            local ov = math.min(ifin, rg.fin) - math.max(ipos, rg.pos)
                            if ov > 0 then
                                cov[rg.label] = (cov[rg.label] or 0) + ov
                            end
                        end

                        -- типы, покрывающие не менее REGION_COVERAGE длины итема
                        local good, best_lbl = {}, nil
                        for lbl, c in pairs(cov) do
                            if c / item_len >= REGION_COVERAGE then
                                good[lbl] = true
                                if not best_lbl or #lbl > #best_lbl then best_lbl = lbl end
                            end
                        end

                        if REGION_DEBUG then
                            local cov_parts = {}
                            for lbl, c in pairs(cov) do
                                cov_parts[#cov_parts + 1] =
                                    string.format("%s:%.0f%%", lbl, (c / item_len) * 100)
                            end
                            print(string.format("  item %d: %.2f-%.2f (%s)", j, ipos, ifin,
                                #cov_parts > 0 and table.concat(cov_parts, ", ") or "no region coverage"))
                        end

                        if not best_lbl then
                            all_matched = false
                            fail_reason = string.format(
                                "item %d (%.2f-%.2f): no single region type covers >= %d%% of it",
                                j, ipos, ifin, math.floor(REGION_COVERAGE * 100 + 0.5))
                            break
                        end

                        local cand = { [best_lbl] = true }

                        if consensus == nil then
                            consensus = cand
                        else
                            local inter = {}
                            for lbl in pairs(consensus) do
                                if cand[lbl] then inter[lbl] = true end
                            end
                            consensus = inter
                        end

                        if next(consensus) == nil then
                            all_matched = false
                            fail_reason = string.format("item %d matches different region than previous items", j)
                            break
                        end
                    end

                    if all_matched and consensus and next(consensus) then
                        -- при нескольких общих метках берём самую длинную
                        local chosen = nil
                        for lbl in pairs(consensus) do
                            if not chosen or #lbl > #chosen then chosen = lbl end
                        end
                        local new_name = process_name(raw_name .. " " .. chosen, {}, false)
                        if REGION_DEBUG then
                            print(string.format("[RegionSections] '%s' -> '%s' (label '%s')",
                                raw_name, new_name, chosen))
                        end
                        if new_name ~= "" and new_name ~= raw_name then
                            reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", new_name, true)
                        end
                    elseif REGION_DEBUG then
                        print(string.format("[RegionSections] track '%s' skipped: %s",
                            raw_name, fail_reason or "no consensus"))
                    end
                end
            end
        end
    end
end

-- Собирает текущее выделение (треки + итемы), считает новые имена и кладёт в clean_names_snapshot
local function capture_session()
    local rows = {}
    local items = {}
    local names = {}
    local ntracks = reaper.CountSelectedTracks(0)
    for i = 0, ntracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        local _, tname = reaper.GetTrackName(track)
        if tname and tname ~= "" then
            table.insert(rows, { ptr = track, name = tname, solo = reaper.GetMediaTrackInfo_Value(track, "I_SOLO"), trim_s = 0, trim_e = 0 })
            table.insert(names, tname)
        end
        local nitems = reaper.CountTrackMediaItems(track)
        for j = 0, nitems - 1 do
            local item = reaper.GetTrackMediaItem(track, j)
            local take = reaper.GetActiveTake(item)
            if take then
                local iname = reaper.GetTakeName(take)
                if not iname or iname == "" then
                    local src = reaper.GetMediaItemTake_Source(take)
                    local ok, srcname = reaper.GetMediaSourceFileName(src, "")
                    if ok and srcname and srcname ~= "" then iname = srcname end
                end
                if iname and iname ~= "" then
                    table.insert(items, { item = item, take = take, name = iname })
                    table.insert(names, iname)
                end
            end
        end
    end
    local session = detect_session(names)
    local strip_lead = detect_leading_numbers(names, session)
    for _, r in ipairs(rows) do
        local nn = process_name(r.name, session, strip_lead)
        r.new_name = nn ~= "" and nn or r.name
        r.clean_base = r.new_name
    end
    for _, it in ipairs(items) do
        local nn = process_name(it.name, session, strip_lead)
        it.new_name = nn ~= "" and nn or it.name
        it.clean_base = it.new_name
    end
    clean_names_snapshot = { rows = rows, items = items }
    clean_names_sel = {}
    clean_names_sel_count = 0
    clean_names_anchor = nil
    clean_names_sel_mode = "items"
    clean_names_display_cache = nil
    clean_names_display_dirty = true
    run_clean_check()
end

-- Периодическое обновление кэша соло, чтобы индикатор оставался свежим
local function refresh_solo_cache()
    if not clean_names_snapshot then return end
    for _, r in ipairs(clean_names_snapshot.rows) do
        if r.ptr and reaper.ValidatePtr(r.ptr, "MediaTrack*") then
            r.solo = reaper.GetMediaTrackInfo_Value(r.ptr, "I_SOLO")
        end
    end
end

-- Экранирует спецсимволы Lua-паттернов, чтобы удалялся именно текст, а не паттерн
local function esc_pattern(s)
    return (s:gsub("[%(%)%.%%%+%-%*%?%[%^%$]", "%%%1"))
end

-- Убирает пробелы в конце имени
local function final_clean_spaces(name)
    return (name:gsub("%s+$", ""))
end

-- Применяет текущие настройки попапа (trim + удаление подстроки) к базовым именам выбранных строк.
-- Trim хранится персонально для каждой строки (r.trim_s / r.trim_e), удаление подстроки - общее.
local function apply_clean_edit()
    if not clean_names_snapshot then return end
    for _, sr in ipairs(clean_names_snapshot.rows) do
        if clean_names_sel[sr] and sr.clean_base then
            local nn = sr.clean_base
            local ts = sr.trim_s or 0
            local te = sr.trim_e or 0
            if ts > 0 or te > 0 then
                nn = string.sub(nn, ts + 1, #nn - te)
            end
            if clean_remove_str ~= "" then
                nn = (nn:gsub(esc_pattern(clean_remove_str), ""))
            end
            sr.new_name = nn
        end
    end
    clean_names_display_dirty = true
    run_clean_check()
end

-- Отменяет правки попапа: возвращает выбранным строкам новое имя после правил (clean_base)
local function undo_clean_edit()
    if not clean_names_snapshot then return end
    for _, sr in ipairs(clean_names_snapshot.rows) do
        if clean_names_sel[sr] and sr.clean_base then
            sr.new_name = sr.clean_base
            sr.trim_s = 0
            sr.trim_e = 0
        end
    end
    clean_remove_str = ""
    clean_names_display_dirty = true
    run_clean_check()
end

-- Синхронизирует выделение строк таблицы с выделением треков в REAPER.
-- Вызывается только при изменении выделения (не каждый кадр).
local function sync_track_selection()
    for i = 0, reaper.GetNumTracks() - 1 do
        reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
    end
    for sr in pairs(clean_names_sel) do
        if sr.ptr and reaper.ValidatePtr(sr.ptr, "MediaTrack*") then
            reaper.SetTrackSelected(sr.ptr, true)
        end
    end
    reaper.UpdateArrange()
end

-- ---------- Edit Rules window ----------
local clean_rules_editing = false
local clean_rules_edit = nil -- { classes = {...}, groups = {...}, junk = {...} } буфер редактирования

local function copy_clean_engine()
    local classes = {}
    for _, cls in ipairs(clean_classes) do
        local c = { name = cls.name, synonyms = {}, subclasses = {} }
        for _, s in ipairs(cls.synonyms) do c.synonyms[#c.synonyms + 1] = s end
        for _, sub in ipairs(cls.subclasses) do
            local sb = { name = sub.name, synonyms = {} }
            for _, s in ipairs(sub.synonyms) do sb.synonyms[#sb.synonyms + 1] = s end
            c.subclasses[#c.subclasses + 1] = sb
        end
        classes[#classes + 1] = c
    end
    local groups = {}
    for _, g in ipairs(clean_global_groups) do
        local keys = {}
        for _, k in ipairs(g.keys) do keys[#keys + 1] = k end
        local words = {}
        for _, w in ipairs(g.words) do words[#words + 1] = w end
        groups[#groups + 1] = { rank = g.rank, keys = keys, words = words }
    end
    local junk = {}
    for _, w in ipairs(clean_junk_words) do junk[#junk + 1] = w end
    return { classes = classes, groups = groups, junk = junk }
end

local function recompute_snapshot_names()
    if not clean_names_snapshot then return end
    local all = {}
    for _, r in ipairs(clean_names_snapshot.rows) do all[#all + 1] = r.name end
    for _, it in ipairs(clean_names_snapshot.items) do all[#all + 1] = it.name end
    local session = detect_session(all)
    local strip_lead = detect_leading_numbers(all, session)
    for _, r in ipairs(clean_names_snapshot.rows) do
        local nn = process_name(r.name, session, strip_lead)
        r.new_name = nn ~= "" and nn or r.name
        r.clean_base = r.new_name
    end
    for _, it in ipairs(clean_names_snapshot.items) do
        local nn = process_name(it.name, session, strip_lead)
        it.new_name = nn ~= "" and nn or it.name
        it.clean_base = it.new_name
    end
    clean_names_display_dirty = true
end

local function apply_clean_rules_edit()
    local edit = clean_rules_edit
    if not edit then return end
    local classes = {}
    for _, cls in ipairs(edit.classes) do
        local name = (cls.name or ""):match("^%s*(.-)%s*$")
        if name ~= "" then
            local c = { name = name, synonyms = {}, subclasses = {} }
            for _, s in ipairs(cls.synonyms) do
                s = s:match("^%s*(.-)%s*$")
                if s ~= "" then c.synonyms[#c.synonyms + 1] = s end
            end
            for _, sub in ipairs(cls.subclasses) do
                local sname = (sub.name or ""):match("^%s*(.-)%s*$")
                if sname ~= "" then
                    local sb = { name = sname, synonyms = {} }
                    for _, s in ipairs(sub.synonyms) do
                        s = s:match("^%s*(.-)%s*$")
                        if s ~= "" then sb.synonyms[#sb.synonyms + 1] = s end
                    end
                    c.subclasses[#c.subclasses + 1] = sb
                end
            end
            classes[#classes + 1] = c
        end
    end
    local groups = {}
    for _, g in ipairs(edit.groups) do
        local keys = {}
        for _, k in ipairs(g.keys) do
            k = k:match("^%s*(.-)%s*$")
            if k ~= "" then keys[#keys + 1] = k end
        end
        local words = {}
        for _, w in ipairs(g.words) do
            w = w:match("^%s*(.-)%s*$")
            if w ~= "" then words[#words + 1] = w end
        end
        if #keys > 0 and #words > 0 and g.rank then
            groups[#groups + 1] = { rank = g.rank, keys = keys, words = words }
        end
    end
    local junk = {}
    for _, w in ipairs(edit.junk) do
        w = w:match("^%s*(.-)%s*$")
        if w ~= "" then junk[#junk + 1] = w end
    end
    rebuild_engine_from_data(classes, groups, junk)
    save_clean_engine()
    recompute_snapshot_names()
    clean_rules_editing = false
    clean_rules_edit = nil
end

local function draw_clean_rules_window()
    if not clean_rules_edit then
        clean_rules_editing = false
        return
    end
    reaper.ImGui_SetNextWindowSize(ctx, 600, 680, reaper.ImGui_Cond_FirstUseEver())

    -- те же зелёные цвета кнопок, что и в главном окне (+ Header для TreeNode)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0x5BBB5A88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0x4C8A6E88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   0x55CF5488)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        0x5BBB5A70)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x5BBB5ACC)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),         0x5BBB5A88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(),  0x4C8A6E88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(),   0x55CF5488)

    local visible, open = reaper.ImGui_Begin(ctx, "Edit Rules - Clean Names Engine", true)
        -- reaper.ImGui_WindowFlags_NoSavedSettings())
    if not open then
        clean_rules_editing = false
        clean_rules_edit = nil
        reaper.ImGui_PopStyleColor(ctx, 8)
        reaper.ImGui_End(ctx)
        return
    end
    if visible then
        if reaper.ImGui_Button(ctx, "Save rules", 120) then
            apply_clean_rules_edit()
            reaper.ImGui_PopStyleColor(ctx, 8)
            reaper.ImGui_End(ctx)
            return
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", 120) then
            clean_rules_editing = false
            clean_rules_edit = nil
            reaper.ImGui_PopStyleColor(ctx, 8)
            reaper.ImGui_End(ctx)
            return
        end
        reaper.ImGui_TextColored(ctx, 0xA9A9A9FF,
            "  class = instrument family | subclass = only valid when its class is in the name")
        reaper.ImGui_Separator(ctx)

        local edit = clean_rules_edit
        local cls_to_remove = {}
        local sub_to_remove = {}
        local group_to_remove = {}

        if reaper.ImGui_TreeNode(ctx, "CLASSES (instrument families)") then
            for ci, cls in ipairs(edit.classes) do
                local label = (cls.name and cls.name ~= "") and cls.name or "(class)"
                -- "###" : в ID виджета идёт только часть после ###, поэтому
                -- переименование класса не меняет ID и не закрывает TreeNode
                if reaper.ImGui_TreeNode(ctx, label .. "###class" .. ci,reaper.ImGui_TreeNodeFlags_Framed()) then
                    reaper.ImGui_PushID(ctx, "class" .. ci)
                    reaper.ImGui_SetNextItemWidth(ctx, 80)
                    local nch, nnew = reaper.ImGui_InputText(ctx, "##name", cls.name or "")
                    if nch and reaper.ImGui_IsItemDeactivated( ctx ) then cls.name = nnew end
                    reaper.ImGui_SameLine( ctx)

                    local syn_str = table.concat(cls.synonyms, ",")
                    reaper.ImGui_SetNextItemWidth(ctx, -1)
                    local sch, snew = reaper.ImGui_InputText(ctx, "##syns", syn_str)
                    if sch then
                        cls.synonyms = {}
                        for s in snew:gmatch("[^,%s]+") do cls.synonyms[#cls.synonyms + 1] = s end
                    end

                    if reaper.ImGui_TreeNode(ctx, "Subclasses (" .. #cls.subclasses .. ")###subs" .. ci) then
                        local x, y = reaper.ImGui_GetContentRegionAvail( ctx )
                        for si, sub in ipairs(cls.subclasses) do
                            reaper.ImGui_PushID(ctx, "sub" .. si)
                            reaper.ImGui_SetNextItemWidth(ctx, 100)
                            local snch, snnew = reaper.ImGui_InputText(ctx, "##subname", sub.name or "")
                            if snch then sub.name = snnew end
                            reaper.ImGui_SameLine(ctx)
                            local ssyn_str = table.concat(sub.synonyms, ",")
                            reaper.ImGui_SetNextItemWidth(ctx, x-150)
                            local ssch, ssnew = reaper.ImGui_InputText(ctx, "##subsyns", ssyn_str)
                            if ssch then
                                sub.synonyms = {}
                                for s in ssnew:gmatch("[^,%s]+") do sub.synonyms[#sub.synonyms + 1] = s end
                            end
                            reaper.ImGui_SameLine(ctx)
                            if reaper.ImGui_Button(ctx, "x##delsub", 22) then
                                sub_to_remove[#sub_to_remove + 1] = { ci = ci, si = si }
                            end
                            reaper.ImGui_PopID(ctx)
                        end
                        if reaper.ImGui_Button(ctx, "+ Add subclass##addsub" .. ci) then
                            table.insert(cls.subclasses, { name = "", synonyms = {} })
                        end
                        reaper.ImGui_TreePop(ctx)
                    end

                    if reaper.ImGui_Button(ctx, "Remove class##delcls" .. ci, 95) then
                        table.insert(cls_to_remove, ci)
                    end
                    reaper.ImGui_PopID(ctx)
                    reaper.ImGui_TreePop(ctx)
                end
            end
            if reaper.ImGui_Button(ctx, "+ Add class") then
                table.insert(edit.classes, { name = "", synonyms = {}, subclasses = {} })
            end
            reaper.ImGui_TreePop(ctx)
        end

        for _, rname in ipairs(CLEAN_RULE_ORDER) do
            local label = CLEAN_RULE_LABELS[rname] or rname
            if reaper.ImGui_TreeNode(ctx, label .. "##" .. rname) then
                local x, y = reaper.ImGui_GetContentRegionAvail( ctx )

                local count = 0
                for gi, g in ipairs(edit.groups) do
                    if g.rank == rname then
                        count = count + 1
                        reaper.ImGui_PushID(ctx, "g" .. rname .. gi)
                        reaper.ImGui_Separator(ctx)

                        reaper.ImGui_SetNextItemWidth(ctx, 100)

                        local words_str = table.concat(g.words, ",")
                        local wch, wnew = reaper.ImGui_InputText(ctx, "##words", words_str)
                        if wch then
                            g.words = {}
                            for w in wnew:gmatch("[^,%s]+") do g.words[#g.words + 1] = w end
                        end
                        reaper.ImGui_SetNextItemWidth(ctx,x-130)
                        reaper.ImGui_SameLine(ctx)

                        local keys_str = table.concat(g.keys, ",")
                        local kch, knew = reaper.ImGui_InputText(ctx, "##synonyms", keys_str)
                        if kch then
                            g.keys = {}
                            for k in knew:gmatch("[^,%s]+") do g.keys[#g.keys + 1] = k end
                        end
                        
                        reaper.ImGui_SameLine(ctx)

                        if reaper.ImGui_Button(ctx, "x##delg", 22) then
                            table.insert(group_to_remove, gi)
                        end
                        reaper.ImGui_PopID(ctx)
                    end
                end
                if count == 0 then
                    reaper.ImGui_TextDisabled(ctx, "(no rules)")
                end
                if reaper.ImGui_Button(ctx, "+ Add rule##add_" .. rname) then
                    table.insert(edit.groups, { rank = rname, keys = { "" }, words = { "" } })
                end
                reaper.ImGui_TreePop(ctx)
            end
        end

        if reaper.ImGui_TreeNode(ctx, "JUNK (always removed)") then
            local junk_str = table.concat(edit.junk, ",")
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            local jch, jnew = reaper.ImGui_InputText(ctx, "##junklist", junk_str)
            if jch then
                edit.junk = {}
                for w in jnew:gmatch("[^,%s]+") do edit.junk[#edit.junk + 1] = w end
            end
            reaper.ImGui_TreePop(ctx)
        end

        if #sub_to_remove > 0 then
            table.sort(sub_to_remove, function(a, b)
                if a.ci ~= b.ci then return a.ci > b.ci end
                return a.si > b.si
            end)
            for _, ref in ipairs(sub_to_remove) do
                local cls = edit.classes[ref.ci]
                if cls then table.remove(cls.subclasses, ref.si) end
            end
        end
        if #cls_to_remove > 0 then
            table.sort(cls_to_remove, function(a, b) return a > b end)
            for _, ci in ipairs(cls_to_remove) do table.remove(edit.classes, ci) end
        end
        if #group_to_remove > 0 then
            table.sort(group_to_remove, function(a, b) return a > b end)
            for _, gi in ipairs(group_to_remove) do table.remove(edit.groups, gi) end
        end

        reaper.ImGui_PopStyleColor(ctx, 8)
        reaper.ImGui_End(ctx)
    end
end

-- ============================================================
-- TRACK RENAMER (встроен из 'ineed_Track Renamer.lua')
-- Отдельное окно внутри нашего ImGui-контекста: один экземпляр,
-- окно можно растягивать и скроллить - контент больше не обрезается.
-- ============================================================
local renamer_open = false

local rn_data = {}
local rn_default_input_text = 'type text to remove'
local rn_slider_s, rn_slider_e = 0, 0
local rn_str_len = 0
local rn_show_input = false
local rn_input_str = ''
local rn_input_track = nil
local rn_input_trackname = nil
local rn_input_color = 0
local rn_data_id = nil
local rn_clicked_x, rn_clicked_y, rn_clicked_xm, rn_clicked_ym = 0, 0, 0, 0
local rn_slider_retval, rn_trim_s, rn_trim_e
local rn_input_retval, rn_input_string
local rn_k_retval, rn_k_label
local rn_enter_rv, rn_new_name

local rn_window_flags =
    reaper.ImGui_WindowFlags_NoScrollWithMouse() +
    reaper.ImGui_WindowFlags_NoFocusOnAppearing() +
    reaper.ImGui_WindowFlags_NoNavFocus() +
    reaper.ImGui_WindowFlags_NoNavInputs() +
    reaper.ImGui_WindowFlags_NoResize()
    -- NoResize/NoScrollbar убраны: окно ресайзится, длинный список скроллится

local rn_list_window_flags =
    reaper.ImGui_WindowFlags_NoTitleBar() +
    reaper.ImGui_WindowFlags_NoDocking() +
    reaper.ImGui_WindowFlags_NoResize() +
    reaper.ImGui_WindowFlags_NoBackground() +
    reaper.ImGui_WindowFlags_NoScrollWithMouse() +
    reaper.ImGui_WindowFlags_NoScrollbar()

local function rn_init_data()
    local count = reaper.CountSelectedTracks(0)
    if count then
        for i = 0, count - 1 do
            local track_data = {}
            local track = reaper.GetSelectedTrack(0, i)
            local _, name = reaper.GetTrackName(track)

            track_data.track = track
            track_data.state = 0
            track_data.name = name

            local found = false
            if #rn_data == 0 then table.insert(rn_data, track_data) end

            for _, v in ipairs(rn_data) do
                if v.track == track then found = true end
            end

            if not found then table.insert(rn_data, track_data) end
        end
    end
end

local function rn_col(colr, a)
    local r, g, b = reaper.ColorFromNative(colr)
    return rgba(r, g, b, a)
end

local function rn_col_sat(colr, sat)
    sat = math.ceil(255 * sat)
    local r, g, b = reaper.ColorFromNative(colr)
    local h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)
    if v < 100 then
        v = 180 - v
        r, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)
    end

    if sat > 0 then
        r = math.min(r + sat, 255)
        g = math.min(g + sat, 255)
        b = math.min(b + sat, 255)
    else
        r = math.max(r + sat, 0)
        g = math.max(g + sat, 0)
        b = math.max(b + sat, 0)
    end

    return rgba(r, g, b, 1)
end

local function rn_frame()
    rn_str_len = 0

    rn_init_data()

    for k, t in ipairs(rn_data) do
        reaper.ImGui_PushID(ctx, k)
        if #t.name > rn_str_len then rn_str_len = #t.name end

        if rn_k_retval then
            _, _ = reaper.GetSetMediaTrackInfo_String(t.track, 'P_NAME', rn_k_label, 1)
            t.name = rn_k_label
        end

        if rn_slider_retval or rn_input_retval then
            local new_name = string.sub(t.name, rn_slider_s + 1, #t.name - rn_slider_e)
            new_name = string.gsub(new_name, rn_input_string, '')
            _, _ = reaper.GetSetMediaTrackInfo_String(t.track, 'P_NAME', new_name, 1)
        end

        reaper.ImGui_PopID(ctx)
    end

    if #rn_data > 0 then
        reaper.ImGui_SetNextItemWidth(ctx, 302)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),          rgba(90, 90, 90, 0.6))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),    rgba(184, 170, 112, 0.4))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),   rgba(120, 120, 120, 0.6))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(),       rgba(150, 150, 150, 0.8))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), rgba(212, 201, 120, 0.8))

        rn_slider_retval, rn_trim_s, rn_trim_e =
            reaper.ImGui_SliderInt2(ctx, '##rn_trim', rn_slider_s, rn_slider_e, 0, rn_str_len)
        reaper.ImGui_PopStyleColor(ctx, 2)

        reaper.ImGui_SetNextItemWidth(ctx, 302)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), rgba(90, 90, 90, 0.3))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),    rgba(220, 220, 220, 0.6))

        rn_input_retval, rn_input_string =
            reaper.ImGui_InputText(ctx, '##rn_input', rn_default_input_text, reaper.ImGui_InputTextFlags_AutoSelectAll())
        reaper.ImGui_PopStyleColor(ctx, 5)
    end

    for k, t in ipairs(rn_data) do
        reaper.ImGui_PushID(ctx, k)

        local _, current_name = reaper.GetTrackName(t.track)
        local color = reaper.GetTrackColor(t.track)

        if current_name:sub(#current_name) == ' ' or current_name:sub(0, 1) == ' ' then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), rgba(250, 102, 102, 1))
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), rgba(255, 255, 255, 1))
        end

        if reaper.IsTrackSelected(t.track) then
            reaper.ImGui_BeginGroup(ctx)

            if t.state == 1 then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), rn_col(color, 0.4))
            else
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), rn_col(color, 0.3))
            end

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), rn_col(color, 0.5))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  rn_col(color, 0.5))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),         rgba(0, 0, 0, 0))

            local button = reaper.ImGui_Button(ctx, k, 302, 26)

            reaper.ImGui_PopStyleColor(ctx, 4)

            reaper.ImGui_SameLine(ctx, 1, 1)

            if rn_slider_s > 0 then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), rgba(0, 0, 0, 0))
                reaper.ImGui_TextColored(ctx, rgba(150, 150, 150, 1), string.sub(t.name, 1, rn_slider_s))
                reaper.ImGui_SameLine(ctx, 0, 0)
                reaper.ImGui_PopStyleColor(ctx)
            end

            reaper.ImGui_Text(ctx, current_name)

            if rn_slider_e > 0 then
                reaper.ImGui_SameLine(ctx, 0, 0)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), rgba(0, 0, 0, 0))
                reaper.ImGui_TextColored(ctx, rgba(150, 150, 150, 1), string.sub(t.name, #t.name - rn_slider_e + 1, #t.name))
                reaper.ImGui_PopStyleColor(ctx)
            end

            if button then
                rn_clicked_x,  rn_clicked_y  = reaper.ImGui_GetItemRectMin(ctx)
                rn_clicked_xm, rn_clicked_ym = reaper.ImGui_GetItemRectMax(ctx)

                rn_input_str      = current_name
                rn_input_track    = t.track
                rn_input_trackname = t.name
                rn_input_color    = color
                rn_data_id        = k

                t.state = 1
                rn_show_input = true
            end
            reaper.ImGui_EndGroup(ctx)

        else
            table.remove(rn_data, k)
        end

        if rn_show_input then
            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            reaper.ImGui_DrawList_AddRectFilled(draw_list,
                rn_clicked_x, rn_clicked_y, rn_clicked_xm, rn_clicked_ym, rn_col_sat(rn_input_color, -0.7))
        end

        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_PopID(ctx)
    end

    if rn_slider_retval then
        rn_slider_s = rn_trim_s
        rn_slider_e = rn_trim_e
    elseif rn_input_retval then
        rn_default_input_text = rn_input_string
    end

    if rn_show_input then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowMinSize(), 10, 10)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), rgba(0, 0, 0, 0))

        reaper.ImGui_SetNextWindowPos(ctx, rn_clicked_x - 12, rn_clicked_y + 25)
        reaper.ImGui_SetNextWindowSize(ctx, 468 - (rn_slider_s * 20), 36, reaper.ImGui_Cond_Always())

        local input_rv, i_open = reaper.ImGui_Begin(ctx, "##rn_input_win", true, rn_list_window_flags)
        if not input_rv then
            -- не оставляем висячие пушы перед выходом
            reaper.ImGui_PopStyleColor(ctx)
            reaper.ImGui_PopStyleVar(ctx)
            if not i_open then rn_show_input = false end
            return
        end

        rn_enter_rv, rn_new_name = reaper.ImGui_InputText(ctx, ' ',
            rn_input_str, reaper.ImGui_InputTextFlags_EnterReturnsTrue() + reaper.ImGui_InputTextFlags_NoHorizontalScroll())
        if rn_enter_rv then
            _, _ = reaper.GetSetMediaTrackInfo_String(rn_input_track, 'P_NAME', rn_new_name, 1)

            rn_data[rn_data_id].name = rn_new_name
            rn_data[rn_data_id].state = 0

            rn_slider_s = 0
            rn_slider_e = 0

            rn_show_input = false
            rn_enter_rv = false
        end

        if not reaper.ImGui_IsWindowFocused(ctx) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            rn_show_input = false
            rn_enter_rv = false
            if rn_data[rn_data_id] then rn_data[rn_data_id].state = 0 end
        end

        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_End(ctx)
    end
end

local function draw_renamer_window()
    -- reaper.ImGui_PushFont(ctx, font, 20)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowTitleAlign(), 0.5, 0.5)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_SeparatorTextAlign(), 0.5, 0.5)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(),      rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(),  rgba(30, 30, 30, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),       rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(),        rgba(28, 29, 30, 1))

    -- Cond_FirstUseEver + ресайз + скролл: контент никогда не обрезается
    -- reaper.ImGui_SetNextWindowSize(ctx, 340, 430, reaper.ImGui_Cond_FirstUseEver())

    local visible, open = reaper.ImGui_Begin(ctx, 'Track Renamer', true, rn_window_flags)
    if visible then
        rn_frame()
        reaper.ImGui_End(ctx)
    end

    reaper.ImGui_PopStyleColor(ctx, 4)
    reaper.ImGui_PopStyleVar(ctx, 2)
    -- reaper.ImGui_PopFont(ctx)

    if not open then renamer_open = false end
end

local function frame()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x5BBB5A88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x4C8A6E88)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x55CF5488)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x5BBB5ACC)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x5BBB5ACC)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), 0xFFFFFFFF)

    if reaper.ImGui_Button(ctx, "Get session tracks", 160) then
        capture_session()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Capture the current selection once and compute names")
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Clear tracks",100) then
        clean_names_snapshot = nil
        clean_names_sel = {}
        clean_names_sel_count = 0
        clean_names_anchor = nil
        clean_names_sel_mode = "items"
        clean_names_display_cache = nil
        clean_names_display_dirty = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Clear the preview table")
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Check names", 110) then
        run_clean_check()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Check which tracks won't match any Move Tracks rule (red rows)")
    end

    reaper.ImGui_SameLine(ctx)

    -- Apply растягивается ровно на место между двумя фиксированными кнопками
    -- (Edit Rules = 110; Check уже занял свои 110 выше)
    local top_spacing = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
    local top_rem = reaper.ImGui_GetContentRegionAvail(ctx)
    local top_er_w = 110
    local top_apply_w = math.max(150, top_rem - top_er_w - top_spacing * 2)

    -- Apply серый, если нечего переименовывать (нет отличий новых имён от текущих)
    local apply_has_changes = false
    if clean_names_snapshot then
        for _, r in ipairs(clean_names_snapshot.rows) do
            if r.new_name and r.new_name ~= "" and r.new_name ~= r.name then
                apply_has_changes = true
                break
            end
        end
    end
    if not apply_has_changes then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0x55555577)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0x66666688)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   0x44444466)
    end

    local apply_clicked = reaper.ImGui_Button(ctx, "Apply name cleaning", top_apply_w, 0)
    if apply_clicked and apply_has_changes and clean_names_snapshot then
        reaper.Undo_BeginBlock()
        for _, r in ipairs(clean_names_snapshot.rows) do
            local target = r.new_name and final_clean_spaces(r.new_name)
            if target and target ~= "" and target ~= r.name then
                reaper.GetSetMediaTrackInfo_String(r.ptr, "P_NAME", target, true)
                r.name = target -- чтобы кнопка снова стала серой после применения
            end
        end
        reaper.Undo_EndBlock("Clean Names", -1)
        reaper.UpdateArrange()
    end
    if not apply_has_changes then
        reaper.ImGui_PopStyleColor(ctx, 3)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, apply_has_changes
            and "Rename the captured tracks to the formatted names"
            or  "No changes to apply")
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Edit Rules", top_er_w, 0) then
        clean_rules_editing = true
        clean_rules_edit = copy_clean_engine()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Edit the Clean Names Engine rules (synonyms, prefixes, junk)")
    end

    -- reaper.ImGui_SameLine(ctx)
    if clean_names_snapshot then
        reaper.ImGui_TextColored(ctx, 0xA9A9A9FF,
            string.format("%d track(s), %d item(s) captured", #clean_names_snapshot.rows, #clean_names_snapshot.items))

        -- Красный текст: сколько треков не прошло Check (+ список в тултипе)
        local failed_count = 0
        for _, r in ipairs(clean_names_snapshot.rows) do
            if r.check_failed then failed_count = failed_count + 1 end
        end
        if failed_count > 0 then
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, 0xFF5555FF,
                string.format("%d track(s) failed the check", failed_count))

            if reaper.ImGui_IsItemHovered(ctx) then
                local fail_lines = {}
                for _, r in ipairs(clean_names_snapshot.rows) do
                    if r.check_failed then
                        fail_lines[#fail_lines + 1] = ((r.new_name or r.name):gsub("_", " "))
                    end
                end
                reaper.ImGui_SetTooltip(ctx, table.concat(fail_lines, "\n"))
            end
        end
    end
 
    reaper.ImGui_PopStyleColor(ctx, 6)
    reaper.ImGui_Separator(ctx)

    local clean_tree_open = reaper.ImGui_TreeNode(ctx, "Clean Names")
    if clean_tree_open then
        -- Сортировку таблицы переключает клик по заголовку колонки "New"

        if clean_names_snapshot then
            local rows = clean_names_snapshot.rows
            local items = clean_names_snapshot.items
            clean_popup_open = false
            if #rows > 0 then
                local display_rows = rows
                if clean_names_sorted then
                    if clean_names_display_dirty or not clean_names_display_cache then
                        clean_names_display_cache = {}
                        for _, r in ipairs(rows) do clean_names_display_cache[#clean_names_display_cache + 1] = r end
                        table.sort(clean_names_display_cache, function(a, b)
                            local an = a.new_name:lower()
                            local bn = b.new_name:lower()
                            if an ~= bn then return an < bn end
                            return tostring(a.ptr) < tostring(b.ptr)
                        end)
                        clean_names_display_dirty = false
                    end
                    display_rows = clean_names_display_cache
                end
                if reaper.ImGui_BeginTable(ctx, 'CleanNamesTable', 3,
                    reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_Sortable()) then
                    reaper.ImGui_TableSetupColumn(ctx, 'Original', reaper.ImGui_TableColumnFlags_WidthStretch() | reaper.ImGui_TableColumnFlags_NoSort(), 1)
                    reaper.ImGui_TableSetupColumn(ctx, 'S', reaper.ImGui_TableColumnFlags_WidthFixed() | reaper.ImGui_TableColumnFlags_NoSort(), 24)
                    reaper.ImGui_TableSetupColumn(ctx, 'New', reaper.ImGui_TableColumnFlags_WidthStretch() | reaper.ImGui_TableColumnFlags_DefaultSort(), 1)
                    reaper.ImGui_TableHeadersRow(ctx)

                    -- Сортировку таблицы переключает клик по заголовку "New":
                    -- синхронизируем тоггл с флагом IsSorted этой колонки
                    local new_is_sorted = (reaper.ImGui_TableGetColumnFlags(ctx, 2) & reaper.ImGui_TableColumnFlags_IsSorted()) ~= 0
                    if new_is_sorted ~= clean_names_sorted then
                        clean_names_sorted = new_is_sorted
                        clean_names_display_dirty = true
                    end
                    -- TableHeadersRow оставила заголовок "New" последним итемом
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, "Click: sort table by new names")
                    end

                    local sel_rect_groups = {}
                    local cur_group = nil
                    local prev_sel = false

                    for i, r in ipairs(display_rows) do
                        reaper.ImGui_PushID(ctx, "clean_row_" .. i)
                        reaper.ImGui_TableNextRow(ctx)

                        -- Красный тинт для строк, не совпавших ни с одним правилом
                        if r.check_failed then
                            reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), 0xFF44442B)
                        end

                        reaper.ImGui_TableSetColumnIndex(ctx, 0)
                        local is_sel = clean_names_sel[r] == true
                        local clicked = reaper.ImGui_Selectable(ctx, r.name, is_sel, reaper.ImGui_SelectableFlags_SpanAllColumns() | reaper.ImGui_SelectableFlags_AllowOverlap())
                        local rmin_x, rmin_y, rmax_x, rmax_y
                        if is_sel then
                            rmin_x, rmin_y = reaper.ImGui_GetItemRectMin(ctx)
                            rmax_x, rmax_y = reaper.ImGui_GetItemRectMax(ctx)
                        end

                        -- Right-click: select the row under cursor (if not selected) and open prefix popup near cursor.
                        -- Must be done right after Selectable so BeginPopupContextItem still sees it as the last item.
                        if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) then
                            if not clean_names_sel[r] then
                                clean_names_sel = { [r] = true }
                                clean_names_sel_count = 1
                                clean_names_anchor = r
                                clean_names_sel_mode = "items"
                                is_sel = true
                                sync_track_selection()
                            end
                            local mx, my = reaper.ImGui_GetMousePos(ctx)
                            reaper.ImGui_SetNextWindowPos(ctx, mx, my)
                        end
                        if reaper.ImGui_BeginPopupContextItem(ctx, nil, reaper.ImGui_PopupFlags_MouseButtonRight()) then
                            clean_popup_open = true
                            clean_edit_active = true

                            -- Editable name field: shown only when a single row is selected
                            if clean_names_sel_count == 1 then
                                local solo_row = nil
                                for _, sr in ipairs(rows) do
                                    if clean_names_sel[sr] then
                                        solo_row = sr
                                        break
                                    end
                                end
                                if solo_row then
                                    local name_changed, name_str = reaper.ImGui_InputText(ctx, "Name", solo_row.new_name)
                                    if name_changed and reaper.ImGui_IsItemDeactivated(ctx) then
                                        solo_row.new_name = name_str
                                        clean_names_display_dirty = true
                                        run_clean_check()
                                    end
                                end
                            end

                            reaper.ImGui_Separator(ctx)

                            -- Class buttons из движка Clean Names: пользовательские классы
                            -- тоже попадают в попап. Одинаковая ширина (по самому длинному имени), 5 в ряд
                            local class_names = {}
                            for _, cls in ipairs(clean_classes) do
                                if cls.name and cls.name ~= "" then class_names[#class_names + 1] = cls.name end
                            end
                            local max_tw = 0
                            for _, pfx in ipairs(class_names) do
                                local tw = reaper.ImGui_CalcTextSize(ctx, pfx)
                                if tw > max_tw then max_tw = tw end
                            end
                            local fp_x, _ = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
                            local btn_w = max_tw + fp_x * 2 + 2
                            for i, pfx in ipairs(class_names) do
                                if reaper.ImGui_Button(ctx, pfx, btn_w) then
                                    for _, sr in ipairs(rows) do
                                        if clean_names_sel[sr] then
                                            sr.new_name = pfx .. " " .. (sr.clean_base or sr.new_name)
                                        end
                                    end
                                    clean_names_display_dirty = true
                                    run_clean_check()
                                    reaper.ImGui_CloseCurrentPopup(ctx)
                                end
                                if i % 5 ~= 0 and i ~= #class_names then
                                    reaper.ImGui_SameLine(ctx)
                                end
                            end

                            reaper.ImGui_Separator(ctx)

                            -- Trim slider: shared control that writes the same trim to all selected rows.
                            -- Each row keeps its own trim_s/trim_e (per-row memory). The slider shows the
                            -- trim of the first selected row as its starting position.
                            local anchor_row = nil
                            for _, sr in ipairs(rows) do
                                if clean_names_sel[sr] and sr.clean_base then
                                    anchor_row = sr
                                    break
                                end
                            end
                            local max_len = 0
                            for _, sr in ipairs(rows) do
                                if clean_names_sel[sr] and sr.clean_base then
                                    max_len = math.max(max_len, #sr.clean_base)
                                end
                            end
                            local sl_s = anchor_row and anchor_row.trim_s or 0
                            local sl_e = anchor_row and anchor_row.trim_e or 0
                            local sl_changed, sl_sv, sl_ev = reaper.ImGui_SliderInt2(ctx, "Trim start/end", sl_s, sl_e, 0, max_len)
                            if sl_changed then
                                for _, sr in ipairs(rows) do
                                    if clean_names_sel[sr] then
                                        sr.trim_s = sl_sv
                                        sr.trim_e = sl_ev
                                    end
                                end
                                apply_clean_edit()
                            end

                            -- Remove substring from new names of selected rows (live preview)
                            local in_changed, in_str = reaper.ImGui_InputText(ctx, "Remove text", clean_remove_str)
                            if in_changed and reaper.ImGui_IsItemDeactivated(ctx) then
                                clean_remove_str = in_str
                                apply_clean_edit()
                                clean_remove_str = ""
                            end

                            if reaper.ImGui_Button(ctx, "Undo changes") then
                                undo_clean_edit()
                            end

                            reaper.ImGui_EndPopup(ctx)
                        end

                        if clicked then
                            local ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
                            local shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
                            if shift and clean_names_anchor and clean_names_sel_count > 0 then
                                local aidx = nil
                                local cidx = nil
                                for k, dr in ipairs(display_rows) do
                                    if dr == clean_names_anchor then aidx = k end
                                    if dr == r then cidx = k end
                                end
                                if aidx and cidx then
                                    local lo = math.min(aidx, cidx)
                                    local hi = math.max(aidx, cidx)
                                    clean_names_sel = {}
                                    local count = 0
                                    for k = lo, hi do
                                        clean_names_sel[display_rows[k]] = true
                                        count = count + 1
                                    end
                                    clean_names_sel_count = count
                                else
                                    clean_names_sel = { [r] = true }
                                    clean_names_sel_count = 1
                                end
                                clean_names_anchor = r
                                clean_names_sel_mode = "range"
                            elseif ctrl then
                                if clean_names_sel[r] then
                                    clean_names_sel[r] = nil
                                    clean_names_sel_count = clean_names_sel_count - 1
                                else
                                    clean_names_sel[r] = true
                                    clean_names_sel_count = clean_names_sel_count + 1
                                end
                                clean_names_anchor = r
                                clean_names_sel_mode = "items"
                            else
                                clean_names_sel = { [r] = true }
                                clean_names_sel_count = 1
                                clean_names_anchor = r
                                clean_names_sel_mode = "items"
                            end
                            is_sel = clean_names_sel[r] == true
                            sync_track_selection()
                        end

                        reaper.ImGui_TableSetColumnIndex(ctx, 0)
                        -- reaper.ImGui_TextColored(ctx, 0xFFFFFFFF, r.name)

                        -- Solo button: if clicked row is not selected, select it first,
                        -- then solo all selected rows and unsolo all unselected ones
                        reaper.ImGui_TableSetColumnIndex(ctx, 1)
                        local row_soloed = (r.solo or 0) ~= 0
                        if row_soloed then
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xC5A723FF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xC9AD36FF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xDFBF32FF)
                        end
                        if reaper.ImGui_Button(ctx, "S##clean_solo_" .. i, 24) then
                            if not clean_names_sel[r] then
                                clean_names_sel = { [r] = true }
                                clean_names_sel_count = 1
                                clean_names_anchor = r
                                clean_names_sel_mode = "items"
                                is_sel = true
                                sync_track_selection()
                            end
                            reaper.PreventUIRefresh(1)
                            for sr in pairs(clean_names_sel) do
                                if sr.ptr and reaper.ValidatePtr(sr.ptr, "MediaTrack*") then
                                    local tr_solo = reaper.GetMediaTrackInfo_Value(sr.ptr, "I_SOLO")
                                    local new_solo = tr_solo == 1 and 0 or 1
                                    reaper.SetMediaTrackInfo_Value(sr.ptr, "I_SOLO", new_solo)
                                    sr.solo = new_solo
                                end
                            end
                            for _, rr in ipairs(rows) do
                                if rr.ptr and not clean_names_sel[rr] and reaper.ValidatePtr(rr.ptr, "MediaTrack*") then
                                    reaper.SetMediaTrackInfo_Value(rr.ptr, "I_SOLO", 0)
                                    rr.solo = 0
                                end
                            end
                            reaper.PreventUIRefresh(-1)
                            reaper.UpdateArrange()
                        end
                        if row_soloed then
                            reaper.ImGui_PopStyleColor(ctx, 3)
                        end
                        if reaper.ImGui_IsItemHovered(ctx) then
                            reaper.ImGui_SetTooltip(ctx, "Solo selected row(s). If the row is not selected, it will be selected first.")
                        end

                        reaper.ImGui_TableSetColumnIndex(ctx, 2)
                        local changed = r.new_name ~= r.name
                        local base = r.clean_base or r.new_name
                        local ts = math.min(r.trim_s or 0, #base)
                        local te = math.min(r.trim_e or 0, math.max(0, #base - ts))
                        local keep = string.sub(base, ts + 1, #base - te)
                        if clean_remove_str ~= "" then
                            keep = (keep:gsub(esc_pattern(clean_remove_str), ""))
                        end
                        if changed then
                            if ts > 0 or te > 0 then
                                reaper.ImGui_TextColored(ctx, 0x90C8FFFF, "→ ")
                                reaper.ImGui_SameLine(ctx, 0, 0)
                                if ts > 0 then
                                    reaper.ImGui_TextColored(ctx, 0x969696FF, string.sub(base, 1, ts))
                                    reaper.ImGui_SameLine(ctx, 0, 0)
                                end
                                reaper.ImGui_TextColored(ctx, 0x90C8FFFF, keep)
                                if te > 0 then
                                    reaper.ImGui_SameLine(ctx, 0, 0)
                                    reaper.ImGui_TextColored(ctx, 0x969696FF, string.sub(base, #base - te + 1, #base))
                                end
                            else
                                reaper.ImGui_TextColored(ctx, 0x90C8FFFF,  "→ " .. r.new_name)
                            end
                        else
                            reaper.ImGui_TextColored(ctx, 0xA9A9A9FF,  "→ " .. r.new_name)
                        end

                        reaper.ImGui_PopID(ctx)

                        if is_sel and rmin_x then
                            -- Start a new rect group when the previous row was not selected
                            if not prev_sel then
                                cur_group = {}
                                table.insert(sel_rect_groups, cur_group)
                            end
                            table.insert(cur_group, { rmin_x, rmin_y, rmax_x, rmax_y })
                        end
                        prev_sel = is_sel
                    end
                    reaper.ImGui_EndTable(ctx)

                    if #sel_rect_groups > 0 then
                        local dl = reaper.ImGui_GetWindowDrawList(ctx)
                        for _, group in ipairs(sel_rect_groups) do
                            local first = group[1]
                            local last = group[#group]
                            reaper.ImGui_DrawList_AddRect(dl, first[1], first[2], last[3], last[4], 0xFFFFFFCC, 0, 0, 2)
                        end
                    end
                end
                if clean_edit_active and not clean_popup_open then
                    clean_edit_active = false
                end
            else
                reaper.ImGui_Text(ctx, "No tracks captured.")
            end
        else
            reaper.ImGui_Text(ctx, "Select tracks, then press Get session tracks to preview formatted names.")
        end
        reaper.ImGui_TreePop(ctx)
    end


    local move_tree_open = reaper.ImGui_TreeNode(ctx, "Move Tracks")
    if move_tree_open then
        
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
                        table.insert(session_data, { parent_ptr = tr, name = name, keywords = "", items_mode = false, remove_silence = false, norm_on = false, norm_type = 0, remove_row = false })
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
        if reaper.ImGui_Button(ctx, "Save backup", btn_third, 0) then
            backup_status = save_backup()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Save Target Track names + Keywords to file")
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Load backup", btn_third, 0) then
            backup_status = load_backup()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Restore Keywords from file, matching Target Track names")
        end
        if backup_status ~= "" then
            reaper.ImGui_TextColored(ctx, 0xA9A9A9FF, backup_status)
        end

        -- reaper.ImGui_SameLine(ctx)
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

        -- Чекбокс Region Sections (имена регионов в названиях треков)
        reaper.ImGui_SameLine(ctx)
        local _, new_val4 = reaper.ImGui_Checkbox(ctx, "Name To Regions  ", region_sections)
        if _ then region_sections = new_val4 end

        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "If enabled: track names get the region name when all items lie inside same-named regions (Gtr 1 R -> Gtr Chorus 1 R)")
        end

        -- Мастер-выключатель нормализации: значения в колонке Normalize сохраняются,
        -- но применяются только при включённом чекбоксе
        reaper.ImGui_SameLine(ctx)
        local _, new_val5 = reaper.ImGui_Checkbox(ctx, "Normalization  ", norm_enabled)
        if _ then norm_enabled = new_val5 end

        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Master switch for normalization.\nRow checkboxes and dB values are kept but not applied while off.")
        end

        -- Remove Unused: помечает строки без входящих треков на удаление
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Remove Unused", 120) then
            for _, row in ipairs(session_data) do
                local cnt = match_counts[row] or 0
                local blocked = false
                if cnt == 0 then
                    -- папка с дочерними рядами, куда треки движутся - не помечаем
                    for _, r2 in ipairs(session_data) do
                        if r2 ~= row
                            and (match_counts[r2] or 0) > 0
                            and reaper.ValidatePtr(r2.parent_ptr, "MediaTrack*")
                            and reaper.ValidatePtr(row.parent_ptr, "MediaTrack*")
                            and IsTrackDescendant(r2.parent_ptr, row.parent_ptr) then
                            blocked = true
                            break
                        end
                    end
                end
                if cnt == 0 and not blocked then
                    row.remove_row = true
                end
            end
            save_data()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx,
                "Set Remove checkbox for rows with 0 incoming tracks.\nFolders whose children receive tracks are skipped.\nRun Check first to refresh counters.")
        end


        -- -- РАСЧЕТ ДЛЯ ПРАВОГО КРАЯ
        -- local bpm_input_w = 60 -- Ширина инпута
        -- local label_w = 35     -- Ширина текста "BPM:"
        -- local padding = 4      -- Отступ от правого края окна
        -- local total_w = bpm_input_w + label_w + padding

        -- -- Получаем ширину доступной области и ставим курсор
        -- local window_w = reaper.ImGui_GetContentRegionAvail(ctx)
        -- reaper.ImGui_SameLine(ctx)
        -- reaper.ImGui_SetCursorPosX(ctx, window_w - total_w)

        -- -- 2. Текст "BPM:"
        -- reaper.ImGui_AlignTextToFramePadding(ctx) -- Чтобы текст был на одной высоте с инпутом
        -- reaper.ImGui_Text(ctx, "BPM:")

        -- -- 3. Поле ввода BPM
        -- reaper.ImGui_SameLine(ctx)
        -- reaper.ImGui_SetNextItemWidth(ctx, bpm_input_w)
        -- local current_bpm = reaper.Master_GetTempo()
        -- local bpm_changed, new_bpm = reaper.ImGui_InputDouble(ctx, "##bpm", current_bpm, 0, 0, "%.2f")

        -- if reaper.ImGui_IsItemDeactivated( ctx ) then 
        --     reaper.SetCurrentBPM(0, new_bpm, true)
        -- end 

        reaper.ImGui_PopStyleColor(ctx, 6)

        -- local row_w = reaper.ImGui_GetContentRegionAvail(ctx)
        -- local btn_third = (row_w - 8) / 3

        -- if reaper.ImGui_Button(ctx, "Remove Silence", btn_third, 0) then
        --     local any_active = false
        --     for _, r in ipairs(session_data) do
        --         if r.remove_silence then any_active = true break end
        --     end
        --     for _, r in ipairs(session_data) do
        --         r.remove_silence = not any_active
        --     end
        --     save_data()
        -- end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Toggle Remove Silence for ALL rows (check all / uncheck all)")
        end


        reaper.ImGui_Separator(ctx)

        if #session_data > 0 then
            -- Счётчики match_counts/match_names/match_ptrs берутся из кэша,
            -- который пересчитывается только в run_clean_check() (по Check)
            local norm_vis = norm_enabled and reaper.ImGui_TableColumnFlags_IsVisible() or 0

            if reaper.ImGui_BeginTable(ctx, 'MainTable', 6,
                reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_Resizable() | reaper.ImGui_TableFlags_Hideable()) then
                -- Колонка Normalize (3) физически скрывается, когда выключен мастер Normalization;
                -- значения чекбоксов и dB в строках при этом сохраняются
                reaper.ImGui_TableSetColumnEnabled(ctx, 3, norm_enabled)

                reaper.ImGui_TableSetupColumn(ctx, 'Target Tracks',reaper.ImGui_TableColumnFlags_WidthStretch(), 0.25)
                reaper.ImGui_TableSetupColumn(ctx, 'Keywords',reaper.ImGui_TableColumnFlags_WidthStretch(), 1)
                reaper.ImGui_TableSetupColumn(ctx, 'Silence', reaper.ImGui_TableColumnFlags_WidthFixed(), 10)
                if norm_enabled then
                    reaper.ImGui_TableSetupColumn(ctx, 'Normalize', reaper.ImGui_TableColumnFlags_WidthFixed(), 115)
                else
                    reaper.ImGui_TableSetupColumn(ctx, 'Normalize', reaper.ImGui_TableColumnFlags_WidthFixed() | reaper.ImGui_TableColumnFlags_NoResize(), 115)
                end
                reaper.ImGui_TableSetupColumn(ctx, 'Remove', reaper.ImGui_TableColumnFlags_WidthFixed(), 10)
                reaper.ImGui_TableSetupColumn(ctx, 'Delete', reaper.ImGui_TableColumnFlags_WidthFixed(), 20)

                -- Собственная строка заголовков (как в ReaImGui Demo 'Custom headers'):
                -- TableHeader() создаёт реальный итем, поэтому клик ловится только на шапке
                reaper.ImGui_TableNextRow(ctx, reaper.ImGui_TableRowFlags_Headers())
                for column = 0, 5 do
                    -- скрытая колонка не принимает курсор - пропускаем её
                    if reaper.ImGui_TableSetColumnIndex(ctx, column) then
                    local column_name = reaper.ImGui_TableGetColumnName(ctx, column)
                    reaper.ImGui_PushID(ctx, "hdr_" .. column)
                    reaper.ImGui_TableHeader(ctx, column_name)

                    if column == 3 then -- Normalize
                        if reaper.ImGui_IsItemHovered(ctx) then
                            reaper.ImGui_SetTooltip(ctx, "Click: enable/disable Normalize for all rows")
                        end
                        if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left()) then
                            local any_off = false
                            for _, r in ipairs(session_data) do
                                if not r.norm_on then any_off = true break end
                            end
                            for _, r in ipairs(session_data) do
                                r.norm_on = any_off
                            end
                            save_data()
                        end
                    elseif column == 2 then -- Silence
                        if reaper.ImGui_IsItemHovered(ctx) then
                            reaper.ImGui_SetTooltip(ctx, "Click: enable/disable Remove Silence for all rows")
                        end
                        if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left()) then
                            local any_off = false
                            for _, r in ipairs(session_data) do
                                if not r.remove_silence then any_off = true break end
                            end
                            for _, r in ipairs(session_data) do
                                r.remove_silence = any_off
                            end
                            save_data()
                        end
                    end

                    reaper.ImGui_PopID(ctx)
                    end
                end

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

                    -- Кнопка-счётчик: сколько треков уйдёт в этот ряд по ключевым словам


                    reaper.ImGui_TableSetColumnIndex(ctx, 1)

                    local cnt = match_counts[row] or 0
                    local cnt_btn_w = 22
                    if cnt == 0 then
                        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 0.4)
                    end
                    if reaper.ImGui_Button(ctx, tostring(cnt) .. "##cnt", cnt_btn_w, 0) and cnt > 0 then
                        -- Клик: выделить все совпавшие треки в аранже
                        unselect_all_tracks()
                        for _, tr in ipairs(match_ptrs[row] or {}) do
                            if reaper.ValidatePtr(tr, "MediaTrack*") then
                                reaper.SetTrackSelected(tr, true)
                            end
                        end
                    end
                    if cnt == 0 then
                        reaper.ImGui_PopStyleVar(ctx)
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        if cnt > 0 then
                            local lines = { "-> " .. row.name }
                            for _, nm in ipairs(match_names[row]) do
                                lines[#lines + 1] = (nm:gsub("_", " "))
                            end
                            reaper.ImGui_SetTooltip(ctx, table.concat(lines, "\n"))
                        else
                            reaper.ImGui_SetTooltip(ctx, "No tracks will be moved to '" .. row.name .. "'")
                        end
                    end

                    reaper.ImGui_SameLine(ctx)


                    reaper.ImGui_SetNextItemWidth(ctx, -60) 
                    local changed, k = reaper.ImGui_InputText(ctx, "##key", row.keywords)
                    if changed and reaper.ImGui_IsItemDeactivated(ctx) then row.keywords = k save_data() run_clean_check() end
                    -- reaper.ImGui_SameLine(ctx)
                    -- reaper.ImGui_SetNextItemWidth(ctx, -15) 


                    -- reaper.ImGui_SameLine(ctx)
                    -- if reaper.ImGui_Button(ctx, "+##clip_" .. tostring(_), 25) then
                    --     local clip_text = reaper.ImGui_GetClipboardText(ctx)
                    --     if clip_text and clip_text ~= "" then
                    --         local clean_clip = clip_text:match("^%s*(.-)%s*$")
                            
                    --         if clean_clip and clean_clip ~= "" then
                    --             if row.keywords == "" then
                    --                 row.keywords = clean_clip
                    --             else
                    --                 row.keywords = row.keywords .. ", " .. clean_clip
                    --             end

                    --             save_data()
                    --             run_clean_check()
                    --         end
                    --     end
                    -- end
                    
                    -- if reaper.ImGui_IsItemHovered(ctx) then
                    --     reaper.ImGui_SetTooltip(ctx, row.name..': Paste keywords from clipboard with comma separator')
                    -- end


                    reaper.ImGui_SameLine(ctx)
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
                            run_clean_check()
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


                    --  Режим айтемов
                    reaper.ImGui_SameLine(ctx)

                    local c_changed, c = reaper.ImGui_Checkbox(ctx, "##check", row.items_mode)
                    if c_changed then row.items_mode = c save_data() end
                                        
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, row.name..": Move items to parent track")
                    end

                    --  Remove Silence (тишина удаляется у айтемов на перемещённых дорожках)
                    reaper.ImGui_TableSetColumnIndex(ctx, 2)
                    local rs_changed, rs = reaper.ImGui_Checkbox(ctx, "##rscheck", row.remove_silence)
                    if rs_changed then
                        row.remove_silence = rs
                        if reaper.ValidatePtr(row.parent_ptr, "MediaTrack*") then
                            for _, r in ipairs(session_data) do
                                if r ~= row and reaper.ValidatePtr(r.parent_ptr, "MediaTrack*") and IsTrackDescendant(r.parent_ptr, row.parent_ptr) then
                                    r.remove_silence = rs
                                end
                            end
                        end
                        save_data()
                    end

                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, row.name..": Remove Silence on moved items")
                    end

                    -- Normalize (чекбокс + кнопка P/L + инпут dB) - только когда колонка видима
                    if norm_enabled then
                    reaper.ImGui_TableSetColumnIndex(ctx, 3)
                    local norm_changed, new_norm = reaper.ImGui_Checkbox(ctx, "##normcheck", row.norm_on or false)
                    if norm_changed then
                        row.norm_on = new_norm
                        -- Клик по папке включает/выключает нормализацию и для всех дочерних строк
                        -- if reaper.ValidatePtr(row.parent_ptr, "MediaTrack*") then
                        --     for _, r in ipairs(session_data) do
                        --         if r ~= row and reaper.ValidatePtr(r.parent_ptr, "MediaTrack*") and IsTrackDescendant(r.parent_ptr, row.parent_ptr) then
                        --             r.norm_on = new_norm
                        --         end
                        --     end
                        -- end
                        save_data()
                    end

                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, row.name..": Normalize moved items")
                    end

                    if row.norm_on then
                        reaper.ImGui_SameLine(ctx)

                        -- Кнопка типа: P (Peak, зелёная) / L (LUFS-S short term max, синяя)
                        local type_name = (row.norm_type == 1) and "L" or "P"
                        if row.norm_type == 1 then
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0x8B3A3AFF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0xA34747FF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   0x6E2E2EFF)
                        else
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0x246E27FF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0x4C8A6EFF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   0x55CF54FF)
                        end
                        if reaper.ImGui_Button(ctx, type_name .. "##ntype", 20, 0) then
                            local new_type = (row.norm_type == 1) and 0 or 1
                            -- Если уровень не меняли вручную (стоит дефолт любого режима), подставляем дефолт нового режима
                            if row.norm_db == nil
                                or row.norm_db == default_norm_db(row.norm_type or 0)
                                or row.norm_db == default_norm_db(new_type) then
                                row.norm_db = default_norm_db(new_type)
                            end
                            row.norm_type = new_type
                            save_data()
                        end
                        reaper.ImGui_PopStyleColor(ctx, 3)

                        if reaper.ImGui_IsItemHovered(ctx) then
                            reaper.ImGui_SetTooltip(ctx, "Peak / LUFS short-term max detection. Click to toggle.")
                        end

                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 42)
                        local db_changed, new_db = reaper.ImGui_InputInt(ctx, "##normdb", math.floor(row.norm_db or default_norm_db(row.norm_type or 0)), 0, 0)
                        -- Применяем только после окончания ввода (Enter или клик мимо)
                        if db_changed and reaper.ImGui_IsItemDeactivated(ctx) then
                            if new_db > 0 then new_db = -new_db end -- 6 превращается в -6 автоматически
                            row.norm_db = new_db
                            save_data()
                        end

                        if reaper.ImGui_IsItemHovered(ctx) then
                            reaper.ImGui_SetTooltip(ctx, "Target level in dB / LUFS (integer)")
                        end
                    end
                    end -- norm_enabled

                    -- Remove Row: трек будет удалён при Organize как неиспользуемый
                    reaper.ImGui_TableSetColumnIndex(ctx, 4)
                    local rr_changed, rr = reaper.ImGui_Checkbox(ctx, "##rmrow", row.remove_row or false)
                    if rr_changed then
                        row.remove_row = rr

                        if reaper.ValidatePtr(row.parent_ptr, "MediaTrack*") then
                            for _, r in ipairs(session_data) do
                                if r ~= row and reaper.ValidatePtr(r.parent_ptr, "MediaTrack*") and IsTrackDescendant(r.parent_ptr, row.parent_ptr) then
                                    r.remove_row = rr
                                end
                            end
                        end

                        save_data()
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, row.name .. ": Delete this track from project during Organize (unused)")
                    end

                    -- Удаление
                    reaper.ImGui_TableSetColumnIndex(ctx, 5)
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
            


        end
        reaper.ImGui_TreePop( ctx )
    end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x203C20FF) -- 40% прозрачности (66)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE6894788) -- 50% прозрачности (80)0x4C8A6E88
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xDC9D7088)

    local organize_w = reaper.ImGui_GetContentRegionAvail(ctx)

    if reaper.ImGui_Button(ctx, 'Organize Session Tracks', organize_w, 40) then
        organize_session()
    end
    reaper.ImGui_PopStyleColor(ctx, 3)

    -- ============================================================
    -- UTILITIES
    -- ============================================================
    if reaper.ImGui_TreeNode(ctx, "Utilities") then
        local renamer_label = renamer_open and "Close Track Renamer" or "Track Renamer"
        if reaper.ImGui_Button(ctx, renamer_label, 160) then
            renamer_open = not renamer_open
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Toggle the Track Renamer tool window (single instance)")
        end

        reaper.ImGui_TreePop(ctx)
    end
end


function loop()
    clean_names_solo_tick = clean_names_solo_tick + 1
    if clean_names_solo_tick >= 30 then
        clean_names_solo_tick = 0
        refresh_solo_cache()
    end

    reaper.ImGui_PushFont(ctx, font, font_size)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 4, 4)    -- (X, Y) расстояние между кнопками/строками
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 3, 2)   -- (X, Y) внутренние отступы в кнопках/инпутах
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_CellPadding(), 2, 1)    -- отступы внутри ячеек таблицы
    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_FrameRounding(), 4.0)
    reaper.ImGui_PushStyleVar  (ctx,  reaper.ImGui_StyleVar_WindowRounding(), 4.0)

    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),           0x203C20FF)
    
    reaper.ImGui_SetNextWindowSize(ctx, 800, 700, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, 'Session Organizer', true)

    if visible then
        frame()
        reaper.ImGui_End(ctx)
    end

    if clean_rules_editing then
        draw_clean_rules_window()
    end

    if renamer_open then
        draw_renamer_window()
    end

    reaper.ImGui_PopStyleColor(ctx,2)
    reaper.ImGui_PopStyleVar(ctx, 5)

    reaper.ImGui_PopFont(ctx)
    
    if open then
        reaper.defer(loop)
    end

end

loop()