-- @description Smart trim or enlarge item via mouse or razor
-- @author Misha Oshkanov, AZ
-- @version 1.0
-- @about
--  Use this script to trim item under mouse cursor. Depending on mouse position:
--      if mouse cursor in the top half of the item, script will trim or enlarge start of the item
--      if mouse cursor in the bottom half of the item, script will trim or enlarge end of the item
--  Thanks AZ for the mouse item context detection logic!

function AddTrMediaEditingGroup(Items, timeT)
    local GrSelTrs = reaper.GetToggleCommandState(42581) --Track: Automatically group selected tracks for media/razor editing
    local GrAllTrs = reaper.GetToggleCommandState(42580) --Track: Automatically group all tracks for media/razor editing

    local GrIDsEn = {}                                 --enabled
    local TrGrData = {}
    local offsets = { 0, 32, 64, 96 }                  --each 32bit for 128 groups

    local reapVers = reaper.GetAppVersion()

    local trCnt = reaper.CountTracks(0)

    for i = 1, trCnt do
        local tr = reaper.GetTrack(0, i - 1)
        local sel = reaper.GetMediaTrackInfo_Value(tr, 'I_SELECTED')
        local trData = { track = tr, selected = sel }
        for o, v in ipairs(offsets) do
            local gr32map = reaper.GetSetTrackGroupMembershipEx(tr, "MEDIA_EDIT_LEAD", v, 0, 0)
            local gr32Fmap = reaper.GetSetTrackGroupMembershipEx(tr, "MEDIA_EDIT_FOLLOW", v, 0, 0)
            if not trData[o] then trData[o] = {} end
            trData[o]['lead'] = gr32map
            trData[o]['follow'] = gr32Fmap
        end
        table.insert(TrGrData, trData)
    end

    local function extract_version(s)
        if not s then return nil end

        -- trim spaces at edges
        s = s:match("^%s*(.-)%s*$")

        -- remove prefixes "v" или "version "
        s = s:gsub("^[Vv]%s*", "")
        s = s:gsub("^[Vv]ersion%s+", "")

        -- patterns
        local patterns = {
            "(%d+%.%d+%.%d+)", -- example: 1.2.3
            "(%d+%.%d+)", -- example: 1.2
            "(%d+)"      -- example: 1
        }

        for _, pat in ipairs(patterns) do
            local ver = s:match(pat)
            if ver then return ver end
        end

        return nil
    end
    --
    if reapVers >= extract_version(reapVers) then
        for o, v in ipairs(offsets) do
            local actionID = 42511
            if o >= 3 then actionID = 43278 end

            local shift = 0
            if math.fmod(o, 2) == 0 then shift = 32 end

            local map = 0
            for i = 0, 31 do
                map = map | (reaper.GetToggleCommandStateEx(0, actionID + (i + shift)) << i)
            end
            GrIDsEn[o] = map
        end
    end

    for t, time in ipairs(timeT) do
        local Tracks = {}
        local ItemsH = {}
        local GrTracks = {}
        local GrIDs = { 0, 0, 0, 0 }
        local SelState = 0

        for i, item in ipairs(Items) do
            local ipos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
            local iend = ipos + reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
            local tr = reaper.GetMediaItemTrack(item)
            if time > ipos and time < iend then
                FieldMatch(Tracks, tr, true)
                local mode = reaper.GetMediaTrackInfo_Value(tr, 'I_FREEMODE')
                local iY = reaper.GetMediaItemInfo_Value(item, 'F_FREEMODE_Y')
                local iH = reaper.GetMediaItemInfo_Value(item, 'F_FREEMODE_H')
                local iL = reaper.GetMediaItemInfo_Value(item, 'I_FIXEDLANE')
                ItemsH[tostring(item)] = { iY, iH, iL, mode }
            end
        end

        for i, tr in ipairs(Tracks) do -- collect gr info for tracks with initially captured items
            local sel = reaper.GetMediaTrackInfo_Value(tr, 'I_SELECTED')
            SelState = SelState | sel
            for o, v in ipairs(offsets) do
                local gr32map = reaper.GetSetTrackGroupMembershipEx(tr, "MEDIA_EDIT_LEAD", v, 0, 0)
                GrIDs[o] = GrIDs[o]| gr32map
            end
        end

        for o, enMap in ipairs(GrIDsEn) do --separated block for the case of older Reaper version
            GrIDs[o] = GrIDs[o] & enMap
        end


        local coeff = { -1, 1 }
        for c, swap in ipairs(coeff) do --go through tracks up and down
            local tridx, i = 1, 0
            if swap == -1 then tridx = trCnt end

            while i < trCnt do -- collect all matching group mappings
                local trGrIDs = {}
                local match
                local tr = TrGrData[tridx]['track']
                local sel = TrGrData[tridx]['selected']

                for o, grMap in ipairs(TrGrData[tridx]) do
                    if #GrIDsEn ~= 0 then
                        trGrIDs[o] = grMap.lead & GrIDsEn[o]
                    else
                        trGrIDs[o] = grMap.lead
                    end

                    if GrIDs[o] & grMap.lead ~= 0 or GrIDs[o] & grMap.follow ~= 0
                        or (SelState & sel ~= 0 and GrSelTrs == 1) then
                        match = true
                    end
                end

                if match then
                    for o, map in ipairs(trGrIDs) do
                        GrIDs[o] = GrIDs[o]| map
                    end
                end

                i = i + 1
                tridx = tridx + 1 * swap
            end
        end

        for i = 1, reaper.CountTracks(0) do -- add corresponding tracks to the table
            local tr = TrGrData[i]['track']
            if GrAllTrs == 1 then
                FieldMatch(GrTracks, tr, true)
            else
                local sel = TrGrData[i]['selected']
                if SelState & sel ~= 0 and GrSelTrs == 1 then FieldMatch(GrTracks, tr, true) end

                for o, grMap in ipairs(TrGrData[i]) do
                    if GrIDs[o] & grMap.lead ~= 0 or GrIDs[o] & grMap.follow ~= 0 then
                        FieldMatch(GrTracks, tr, true)
                        break
                    end
                end
            end
        end

        for i, tr in ipairs(GrTracks) do
            local mode = reaper.GetMediaTrackInfo_Value(tr, 'I_FREEMODE')
            for k = 0, reaper.CountTrackMediaItems(tr) - 1 do
                local item = reaper.GetTrackMediaItem(tr, k)
                local ipos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
                local iend = ipos + reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')

                if time > ipos and time < iend then
                    local iY = reaper.GetMediaItemInfo_Value(item, 'F_FREEMODE_Y')
                    local iH = reaper.GetMediaItemInfo_Value(item, 'F_FREEMODE_H')
                    local iL = reaper.GetMediaItemInfo_Value(item, 'I_FIXEDLANE')

                    for h, refItem in pairs(ItemsH) do
                        if mode == 2 and refItem[4] == mode then
                            if refItem[3] == iL then
                                FieldMatch(Items, item, true)
                            end
                        else
                            if math.abs(refItem[1] - iY) < math.min(refItem[2], iH) / 5
                                and math.max(refItem[2], iH) / math.min(refItem[2], iH) <= 1.5
                            then
                                FieldMatch(Items, item, true)
                            end
                        end
                    end
                end --if time > ipos and time < iend
            end --all items on the track cycle
        end --cycle through grouped tracks
    end     -- timeT cycle
end

function AddGroupedItems(itemsTable, retWithoutInputs) --table, boolean
    local grItems = {}
    local grIDs = {}
    local allCnt = reaper.CountMediaItems(0)
    local inpCnt = #itemsTable

    for i = 1, inpCnt do
        local item = itemsTable[i]
        local groupID = reaper.GetMediaItemInfo_Value(item, 'I_GROUPID')
        if groupID ~= 0 and FieldMatch(grIDs, groupID) == false then
            table.insert(grIDs, groupID)
        end
    end

    if #grIDs > 0 then
        for i = 0, allCnt - 1 do
            local item = reaper.GetMediaItem(0, i)
            local groupID = reaper.GetMediaItemInfo_Value(item, 'I_GROUPID')
            if groupID ~= 0 and FieldMatch(grIDs, groupID) == true then
                table.insert(grItems, item)
            end
        end
    end

    if retWithoutInputs == false then
        table.move(itemsTable, 1, #itemsTable, #grItems + 1, grItems)
    end
    --msg(#grItems)
    return grItems
end

function SetItemEdges(item, startTime, endTime)
    local pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local isloop = reaper.GetMediaItemInfo_Value(item, 'B_LOOPSRC')
    reaper.SetMediaItemInfo_Value(item, 'D_POSITION', startTime)
    reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', endTime - startTime)
    local takesN = reaper.CountTakes(item)
    for i = 0, takesN - 1 do
        local take = reaper.GetTake(item, i)
        if take then
            local offs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
            local rate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')
            offs = offs + (startTime - pos) * rate
            if isloop == 1 then
                local src = reaper.GetMediaItemTake_Source(take)
                local length, isQN = reaper.GetMediaSourceLength(src)
                if offs < 0 then
                    offs = length - math.fmod(-offs, length)
                elseif offs > length then
                    offs = math.fmod(offs, length)
                end
            end

            local strmarksnum = reaper.GetTakeNumStretchMarkers(take)
            if strmarksnum > 0 then
                reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs)
                for s = 0, strmarksnum - 1 do
                    local retval, strpos, srcpos = reaper.GetTakeStretchMarker(take, s)
                    reaper.SetTakeStretchMarker(take, s, strpos - (startTime - pos) * rate, srcpos)
                end
            else
                reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs)
            end

            local takeenvs = reaper.CountTakeEnvelopes(take)
            for e = 0, takeenvs - 1 do
                local env = reaper.GetTakeEnvelope(take, e)
                for p = 0, reaper.CountEnvelopePoints(env) - 1 do
                    local ret, time, value, shape, tens, sel = reaper.GetEnvelopePoint(env, p)
                    if ret then
                        time = time - (startTime - pos) * rate
                        reaper.SetEnvelopePoint(env, p, time, value, shape, tens, sel, true)
                    end
                end
                reaper.Envelope_SortPoints(env)
            end
        end
    end
end

function print(...)
    local values = { ... }
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

RespSnapItems = true
RespGrouping = true

function EditItems(items, action, editTime)
    if not action or not editTime then return nil end

    local undoDesc = nil

    for _, item in ipairs(items) do
        local iPos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local iLen = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local iEnd = iPos + iLen

        if action == "extend_left" then
            local leftLimit = GetItemSourceLeftLimit(item)
            local newStart = math.max(editTime, leftLimit) -- <-- главное ограничение

            if newStart < iPos then
                SetItemEdges(item, newStart, iEnd)
                undoDesc = "extend left"
            end
        elseif action == "extend_right" then
            if editTime > iEnd then
                SetItemEdges(item, iPos, editTime)
                undoDesc = "extend right"
            end
        elseif action == "trim_left" then
            if iPos < editTime and editTime < iEnd then
                SetItemEdges(item, editTime, iEnd)
                undoDesc = "left"
            end
        elseif action == "trim_right" then
            if iPos < editTime and editTime < iEnd then
                SetItemEdges(item, iPos, editTime)
                undoDesc = "right"
            end
        end
    end
    return undoDesc
end

function GetTopBottomItemHalf()
    local x, y = reaper.GetMousePosition()
    local item_under_mouse = reaper.GetItemFromPoint(x, y, true)
    if item_under_mouse then
        local item_h = reaper.GetMediaItemInfo_Value(item_under_mouse, "I_LASTH")
        local OScoeff = reaper.GetOS():match("^Win") and 1 or -1

        local test_point = math.floor(y + (item_h - 1) * OScoeff)
        local test_item = reaper.GetItemFromPoint(x, test_point, true)

        if item_under_mouse == test_item then
            return item_under_mouse, "header"
        end

        test_point = math.floor(y + item_h / 2 * OScoeff)
        test_item = reaper.GetItemFromPoint(x, test_point, true)

        if item_under_mouse ~= test_item then
            return item_under_mouse, "bottom"
        else
            return item_under_mouse, "top"
        end
    end
    return nil
end

function WhatTrim(half)
    if half == "top" then return "left" end
    if half == "bottom" then return "right" end
end

function SaveSelItems()
    local Sitems = {}
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item and reaper.GetMediaItemInfo_Value(item, 'C_LOCK') ~= 1 then
            table.insert(Sitems, item)
        end
    end
    return Sitems
end

function RestoreSelItems(Sitems)
    reaper.SelectAllMediaItems(0, false)
    for _, item in ipairs(Sitems) do
        reaper.SetMediaItemSelected(item, true)
    end
end

-- ==================== НОВЫЕ/ИСПРАВЛЕННЫЕ ФУНКЦИИ ====================

function GetEditAction(item, mPos)
    if not item then return nil, nil end

    local iPos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local iEnd = iPos + reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')

    -- Если айтем выбран — проверяем extend
    if reaper.IsMediaItemSelected(item) then
        if mPos < iPos then
            return "extend_left", mPos
        elseif mPos > iEnd then
            return "extend_right", mPos
        end
    end

    -- Обычный трим (не выбран или курсор внутри айтема)
    local _, half = GetTopBottomItemHalf()
    if half == "header" or not half then return nil end

    local side = WhatTrim(half)
    return "trim_" .. side, mPos
end

function FieldMatch(Table, value, AddRemoveFlag)
    for i = 1, #Table do
        if value == Table[i] then
            if AddRemoveFlag == false then table.remove(Table, i) end
            if AddRemoveFlag ~= nil then return true, Table else return true end
        end
    end
    if AddRemoveFlag == true then table.insert(Table, value) end
    if AddRemoveFlag ~= nil then return false, Table else return false end
end

function GetPrefs(key)
    local retval, buf = reaper.get_config_var_string(key)
    if retval == true then return tonumber(buf) end
end

function RazorEditSelectionExists()
    for i = 0, reaper.CountTracks(0) - 1 do
        local _, x = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), "P_RAZOREDITS", "", false)
        if x ~= "" then return true end
    end
    return false
end

function GetItemSourceLeftLimit(item)
    if not item then return -math.huge end

    local take = reaper.GetActiveTake(item)
    if not take then return -math.huge end

    local pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local rate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')
    local startoffs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')

    -- Минимальная позиция на таймлайне, до которой можно extend left
    return pos - (startoffs / rate)
end

-- ==================== ГЛАВНАЯ ФУНКЦИЯ ====================

function MouseTrim()
    GroupEnabled = reaper.GetToggleCommandState(1156)

    local SelectedItems = SaveSelItems()
    local item, half = GetTopBottomItemHalf()

    if not item then
        if reaper.CountSelectedMediaItems(0) > 0 then
            item = reaper.GetSelectedMediaItem(0, 0)
        else
            return
        end
    end


    reaper.Undo_BeginBlock2(0)
    reaper.PreventUIRefresh(1)

    local mPos = reaper.BR_PositionAtMouseCursor(false)
    if RespSnapItems then
        mPos = reaper.SnapToGrid(0, mPos)
    end

    -- Определяем действие ОДИН РАЗ по исходному айтему
    local action, editTime = GetEditAction(item, mPos)

    if not action then
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock2(0, "", -1)
        return
    end

    -- Собираем все айтемы для редактирования
    local inisel = reaper.IsMediaItemSelected(item) and SelectedItems or { item }

    local allItemsForEdit = {}
    if RespGrouping and GroupEnabled == 1 then
        allItemsForEdit = AddGroupedItems(inisel, false)
    else
        allItemsForEdit = inisel
    end

    if GroupEnabled == 1 then
        local refTime = editTime
        if action == "extend_left" then
            refTime = reaper.GetMediaItemInfo_Value(item, 'D_POSITION') + 0.0001
        elseif action == "extend_right" then
            local iEnd = reaper.GetMediaItemInfo_Value(item, 'D_POSITION') +
                reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
            refTime = iEnd - 0.0001
        end
        AddTrMediaEditingGroup(allItemsForEdit, { refTime })
    end

    local undoType = EditItems(allItemsForEdit, action, editTime)

    RestoreSelItems(SelectedItems)
    reaper.PreventUIRefresh(-1)

    if undoType then
        local actionName = action:find("extend") and "Extend" or "Trim"
        reaper.Undo_EndBlock2(0, actionName .. " " .. undoType .. " edge", -1)
        reaper.UpdateArrange()
    else
        reaper.defer(function() end)
    end
end

-- ==================== ЗАПУСК ====================

if RazorEditSelectionExists() then
    reaper.Undo_BeginBlock2(0)
    reaper.Main_OnCommand(40508, 0) -- Razor: Select all items in razor edit area
    reaper.Main_OnCommand(42406, 0) -- Razor: Trim items at razor edit area
    reaper.Undo_EndBlock2(0, "Trim Razor", -1)
else
    MouseTrim()
end
