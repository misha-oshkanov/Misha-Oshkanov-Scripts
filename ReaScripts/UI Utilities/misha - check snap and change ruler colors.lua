-- @description Color ruler if snap is on
-- @author Misha Oshkanov
-- @version 1.3
-- @about
--  Apply colors to ruler if snap is active

function setColors()
    local snap_state = reaper.GetToggleCommandState(1157)
    if snap_state == 1 then
        reaper.SetThemeColor("col_tl_fg",   reaper.ColorToNative( 127, 210, 210 ))
        reaper.SetThemeColor("col_tl_fg2",  reaper.ColorToNative( 107, 190, 190 ))
        reaper.SetThemeColor("col_tl_bg",   reaper.ColorToNative( 61,  92,  92  ))
    else
        reaper.SetThemeColor("col_tl_fg", -1, 0)
        reaper.SetThemeColor("col_tl_fg2", -1, 0)
        reaper.SetThemeColor("col_tl_bg", -1, 0)  
    end
    
    reaper.UpdateTimeline()
end

function mainLoop()
    local current_snap = reaper.GetToggleCommandState(1157)
    if current_snap ~= last_snap_state then
        setColors()
        last_snap_state = current_snap
    end
    reaper.defer(mainLoop)
end

last_snap_state = reaper.GetToggleCommandState(1157)
setColors()
mainLoop()