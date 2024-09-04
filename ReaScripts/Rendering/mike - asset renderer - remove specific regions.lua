-- @description Asset Renderer - Remove scecific regions 
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  Use in pairs with create regions scripts
--  Script wii delete all regions in the project with names listed in regions to remove table before creating new regions
--  Use this script as template for your own preferences
--  
--  Используйте вместе со скриптами для создания регионов
--  Скрипт удалит все регионы, которые указаны в списке regions to remove перед созданием новых регионов
--  Используйте этот скрипт как темплейт для создания своих регионов, измените item name и regions to remove

---------------------------------------------------------------------
---------------------------------------------------------------------

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

regions_to_remove = {'Loop','Full'}

local count, _, num_regions = reaper.CountProjectMarkers(0)

for k,v in pairs(regions_to_remove) do 
    for i=1,count do 
        _, isrgn, _, _, name, id = reaper.EnumProjectMarkers(i-1)
        if isrgn and name == v then 
            reaper.DeleteProjectMarker(0, id, isrgn)
        end 
    end 
end
reaper.UpdateArrange()