-- @description cycle folder state or lane state
-- @author misha
-- @version 1.0
-- @about cycle folder state or lane state

folderPNG = "folder.png"
use_icon = true

track = reaper.GetSelectedTrack(0, 0)
if track then 

    is_folder = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH') == 1
    is_lane_mode = reaper.GetMediaTrackInfo_Value(track, 'I_FREEMODE') == 2
    is_lane_collapsed = reaper.GetMediaTrackInfo_Value(track, 'C_LANESCOLLAPSED') == 1
    is_folder_compact = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERCOMPACT') == 2
    -- collapse = is_lane_collapsed == false and 1 or 0
    if is_lane_mode then 
        if is_folder then 
            if not is_lane_collapsed and not is_folder_compact then 
                reaper.Main_OnCommand(42638, 0) -- cycle lanes
            elseif is_lane_collapsed and not is_folder_compact then 
                reaper.Main_OnCommand(1042, 0) -- cycle folder
            elseif is_lane_collapsed and is_folder_compact then
                reaper.Main_OnCommand(42638, 0) -- cycle lanes
            elseif not is_lane_collapsed and is_folder_compact then 
                reaper.Main_OnCommand(1042, 0) -- cycle folder
            end
        else 
            reaper.Main_OnCommand(42638, 0) -- cycle lanes
        end
    else 
        reaper.Main_OnCommand(1042, 0) -- cycle folder
    end
end

if use_icon then 
    count = reaper.CountSelectedTracks(0)
    if count > 0 then 
        for i = 0, count-1 do
            track = reaper.GetSelectedTrack(0,i)
            if track ~= nil and reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH') == 1 then
                _, icon = reaper.GetSetMediaTrackInfo_String(track, "P_ICON", '', false)
                if reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERCOMPACT') ~= 2 then
                    if string.find(icon, folderPNG) then
                        _, _ = reaper.GetSetMediaTrackInfo_String(track, "P_ICON", '', true)
                    end
                else 
                    if not string.find(icon, folderPNG) then
                        _, _ = reaper.GetSetMediaTrackInfo_String(track, "P_ICON", folderPNG, true)
                    end
                end
            end
        end
    end
end