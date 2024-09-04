-- @description Asset Renderer - Create regions 'FUll'
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  1. Define a region track name and item name (RENDER by default). Region track is a track in the project that contains empty items with text/
--  2. Use these empty items with text to specify where regions with item names will be created.
--
--  Script wii delete all regions in the project with names listed in regions to remove table before creating new regions
--  Use this script as template for your own preferences
--
--  1. Определите название трека в проекте (по умолчанию RENDER), который будет использоваться для регионов. На этом треке должны быть пустые айтемы с текстом
--  2. Текст в пустых айтемах будет определять название региона, границы региона будут соответствовать границам айтема
--  
--  Скрипт удалит все регионы, которые указаны в списке regions to remove перед созданием новых регионов
--  Используйте этот скрипт как темплейт для создания своих регионов, измените item name и regions to remove

---------------------------------------------------------------------
---------------------------------------------------------------------

region_track = "RENDER" -- Name of region track in project -- Имя регион-трека в проекте
item_name = 'Full' -- Text in empty items. Used for naming and creating regions -- Текст в пустых айтемах. Используется как имя региона.

regions_to_remove = {'Loop','Full'} -- Name of regions to delete before creating new ones -- Имена регионов для удаления

---------------------------------------------------------------------
---------------------------------------------------------------------

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end


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