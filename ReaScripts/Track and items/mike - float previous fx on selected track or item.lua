-- @description Float previous fx on selected track or item
-- @author Misha Oshkanov
-- @version 1.0
-- @about

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function float_takefx(mouse_at_item, takefx_count)
    item = mouse_at_item
    if reaper.IsMediaItemSelected(item) then
        take = reaper.GetActiveTake(item)
        takefx_count=takefx_count-1
        currento = takefx_count
        for i=0, reaper.TakeFX_GetCount(take)-1 do 
            o = reaper.TakeFX_GetOpen(take, i)
            if o then 
                reaper.TakeFX_SetOpen(take, i, 0)
                currento = i-1
            end
        end 
        if currento < 0 then 
            reaper.TakeFX_SetOpen(take, takefx_count, 1)
        else
            reaper.TakeFX_SetOpen(take, currento, 1)
        end 
        
    end
end

reaper.SetCursorContext(1,nil)

window, segment, details = reaper.BR_GetMouseCursorContext()
selitem = reaper.GetSelectedMediaItem(0, 0)
if selitem then takefx_count = reaper.TakeFX_GetCount(reaper.GetActiveTake(selitem)) end 
if selitem and takefx_count > 0 and window ~= 'tcp' then float_takefx(selitem, takefx_count)
else 
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_WNONLY1"), 0)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_MOVE_FX_WINDOW_TO_MOUSE_H_M_V_M"), 0)
end 

reaper.SetCursorContext(1,nil)