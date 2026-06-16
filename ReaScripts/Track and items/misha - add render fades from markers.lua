-- @description Set render fades using marker positions
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  Automatically configures render fade-in and fade-out durations based on marker positions.
--  Based on distance between markers (for example betwee marker named "FI" and "=START" for fade in)
--  "=START" for render start, and "=END" for render end.
--  Also enables fade options in render post-processing based on which fade markers are present.


local fade_in_name  = 'FI'
local fade_out_name = 'FO'
local start_marker  = '=START'
local end_marker    = '=END'

local markers = {}

function truncate(num, digits)
    local mult = 10^(digits)
    return math.modf(num*mult)/mult
end

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

local _, num_markers = reaper.CountProjectMarkers(0)
for i = 0, num_markers - 1 do
    local _, isrgn, pos, _, name, _ = reaper.EnumProjectMarkers(i)
    if not isrgn then
        if name == start_marker  then markers.start = pos end
        if name == end_marker    then markers.stop  = pos end
        if name == fade_in_name  then markers.fi    = pos end
        if name == fade_out_name then markers.fo    = pos end
    end
end

if markers.fi or markers.fo then 
    render_settings =  reaper.GetSetProjectInfo(0, 'RENDER_NORMALIZE', 0, 0)
    if markers.start and markers.fi and not markers.fo then 
        reaper.GetSetProjectInfo(0, 'RENDER_NORMALIZE', render_settings|512, 1)
    elseif markers.stop and markers.fo and not markers.fi then 
        reaper.GetSetProjectInfo(0, 'RENDER_NORMALIZE', render_settings|1024, 1)
    elseif markers.start and markers.stop and markers.fo and markers.fi then 
        reaper.GetSetProjectInfo(0, 'RENDER_NORMALIZE', render_settings|1542, 1)
    end

    -- Fade In: расстояние от =START до FI
    if markers.start and markers.fi and markers.fi > markers.start  then
        local fi_duration = truncate(math.abs(markers.fi - markers.start),3)
        reaper.GetSetProjectInfo(0, 'RENDER_FADEIN', fi_duration, true)
    end

    -- Fade Out: расстояние от FO до =END
    if markers.stop and markers.fo and markers.fo < markers.stop then
        local fo_duration = truncate(math.abs(markers.stop - markers.fo),3)
        reaper.GetSetProjectInfo(0, 'RENDER_FADEOUT', fo_duration, true)
    end
end