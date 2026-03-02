-- @description Smart track delete.
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  Deletes track only if there is no items, receives. Removes bypassed plugins. Works on children track if folders are selected.

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function is_all_items_muted(track)
    local count_items = reaper.CountTrackMediaItems(track)
    if count_items == 0 then return false end 
    for i = 0, count_items - 1 do 
        local item = reaper.GetTrackMediaItem(track, i)
        if reaper.GetMediaItemInfo_Value(item, 'B_MUTE_ACTUAL') == 0 then return false end 
    end 
    return true
end

function get_children(parent)
    local children = {}
    local parent_depth = reaper.GetTrackDepth(parent)
    local track_idx = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
    
    for i = track_idx, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.GetTrackDepth(track) > parent_depth then
            table.insert(children, track)
        else
            break
        end
    end
    return children
end

function remove_muted_receives(track)
    for i = reaper.GetTrackNumSends(track, -1) - 1, 0, -1 do 
        if reaper.GetTrackSendInfo_Value(track, -1, i, 'B_MUTE') == 1 then 
            reaper.RemoveTrackSend(track, -1, i)
        end
    end
end

function valid_for_delete(track)
    remove_muted_receives(track)
    local is_hidden = reaper.GetMediaTrackInfo_Value(track, 'B_SHOWINTCP') == 0
    local has_receives = reaper.GetTrackNumSends(track, -1) > 0
    local has_no_items = reaper.CountTrackMediaItems(track) == 0
    local _, layout = reaper.GetSetMediaTrackInfo_String(track, 'P_TCP_LAYOUT', '', 0)

    if (has_no_items or is_all_items_muted(track)) and not has_receives and not is_hidden and layout ~= 'M - VCA' then
        return true
    end
    return false
end

function folder_valid_for_delete(track)
    if reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH') ~= 1 then return false end
    local children = get_children(track)
    for _, ch in ipairs(children) do
        if not valid_for_delete(ch) then return false end
    end
    return true
end

function safe_delete_tracks(final_list)

    for i, item in ipairs(final_list) do
        local tr = item.ptr
        local depth_change = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        local _, tr_name = reaper.GetTrackName(tr)
        local tr_idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")

        if depth_change < 0 then
            if tr_idx > 1 then
                local prev_tr = reaper.GetTrack(0, tr_idx - 2)
                if prev_tr then
                    local prev_depth = reaper.GetMediaTrackInfo_Value(prev_tr, "I_FOLDERDEPTH")
                    reaper.SetMediaTrackInfo_Value(prev_tr, "I_FOLDERDEPTH", prev_depth + depth_change)
                end
            end
        end
        print(string.format("%d. [Удален] %d: %s", i, tr_idx, tr_name))
        reaper.DeleteTrack(tr)
        deleted_count = i
    end
end

reaper.Undo_BeginBlock()

local tracks_to_remove_map = {}
local count_selected = reaper.CountSelectedTracks(0)
for i = 0, count_selected - 1 do
    local track = reaper.GetSelectedTrack(0, i)

    for fx = reaper.TrackFX_GetCount(track) - 1, 0, -1 do
        if not reaper.TrackFX_GetEnabled(track, fx) then
            reaper.TrackFX_Delete(track, fx)
        end
    end
    local is_folder = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH') == 1
    if is_folder then 
        if folder_valid_for_delete(track) then
            tracks_to_remove_map[track] = true
            local children = get_children(track)
            for _, ch in ipairs(children) do tracks_to_remove_map[ch] = true end
        else 
            local children = get_children(track)
            for _, ch in ipairs(children) do
                if valid_for_delete(ch) then tracks_to_remove_map[ch] = true end
            end
        end
    else if valid_for_delete(track) then tracks_to_remove_map[track] = true end end
end

local final_list = {}
for tr in pairs(tracks_to_remove_map) do
    table.insert(final_list, {ptr = tr, idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")})
end

table.sort(final_list, function(a, b) return a.idx > b.idx end)

deleted_count = 0
print("--- Отчет об удалении ---")

safe_delete_tracks(final_list)

if deleted_count == 0 then 
    print("Лишних треков не обнаружено.") 
else
    print("-------------------------")
    print("Итого удалено треков: " .. deleted_count)
end

reaper.Undo_EndBlock('Smart track delete', -1)
reaper.TrackList_AdjustWindows(false)