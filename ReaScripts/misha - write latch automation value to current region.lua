-- @description Write stored latch automation value to current region
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--    Use latch preview mode to store latch value and 
--    when use this script to write this stored latch automation value to current region


function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end


function set_time_selection_to_region_at_cursor()
    local cursor_pos
    
    local edit_cursor = reaper.GetCursorPosition()
    local play_state = reaper.GetPlayState()
    local play_cursor = reaper.GetPlayPosition()
    
    if play_state == 1 or play_state == 5 then
        cursor_pos = play_cursor
    else
        cursor_pos = edit_cursor
    end
    
    local region_start = 0
    local region_end = 0
    
    local i = 0
    while true do
        local retval, isrgn, pos, rgnend = reaper.EnumProjectMarkers3(0, i)
        if retval == 0 then break end
        
        if isrgn then
            if cursor_pos >= pos and cursor_pos <= rgnend then
                region_start = pos
                region_end = rgnend
                break
            elseif cursor_pos < pos then
                break
            end
        end
        
        i = i + 1
    end
    
    if region_start ~= region_end then
        reaper.GetSet_LoopTimeRange(true, false, region_start, region_end, false)
        return true
    end
end

if set_time_selection_to_region_at_cursor() then 
    reaper.Main_OnCommand(41160, 0) -- write value
    reaper.GetSet_LoopTimeRange(true, false, false, false, false)
    reaper.SetGlobalAutomationOverride(0)
end

if  reaper.GetGlobalAutomationOverride() == 5 then
    reaper.SetGlobalAutomationOverride(0)
end