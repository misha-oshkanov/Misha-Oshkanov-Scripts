
function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

region_track = "RENDER"
item_name = 'Loop'

regions_to_remove = {'Loop','Full'}
-- mute = 1

function get_region_track()
    local count = reaper.CountTracks(0)
    for i=1,count do 
        local track = reaper.GetTrack(0, i-1)
        local _, name = reaper.GetTrackName(track)
        if name == region_track then return track end 
    end 
end 

function remove_regions()
    local count, _, num_regions = reaper.CountProjectMarkers(0)

    for k,v in pairs(regions_to_remove) do 
        for i=1,count do 
            _, isrgn, _, _, name, id = reaper.EnumProjectMarkers(i-1)
            if isrgn and name == v then 
                reaper.DeleteProjectMarker(0, id, isrgn)
            end 
        end 
    end
end



remove_regions()
track = get_region_track()

count = reaper.CountTrackMediaItems(track)
for i=1,count do 
    item = reaper.GetTrackMediaItem(track, i-1)
    if not reaper.GetActiveTake(item) then 
        _, notes = reaper.GetSetMediaItemInfo_String(item, 'P_NOTES', '', 0)
        mute_state = reaper.GetMediaItemInfo_Value(item, 'B_MUTE')
        if mute_state == 0 and notes == item_name then 
            item_start = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
            item_end   = item_start + reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
            col = reaper.GetMediaItemInfo_Value(item, 'I_CUSTOMCOLOR')
            -- reaper.SetMediaItemInfo_Value(item, 'B_MUTE', mute)
            reaper.AddProjectMarker2(0, 1, item_start, item_end, item_name, 0,col)
        end 
    end 
end

reaper.UpdateArrange()