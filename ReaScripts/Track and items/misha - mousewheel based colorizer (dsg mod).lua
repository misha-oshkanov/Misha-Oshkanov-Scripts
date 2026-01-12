-- @description Mousewheel based colorizer (DSG mod)
-- @author DSG, misha
-- @version 1.0
-- @about use mousewheel to change colors of track and items (up to set random colors and down to decrease brightness)

function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

function get_children(parent)
    if parent then 
        local parentdepth = reaper.GetTrackDepth(parent)
        local parentnumber = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
        local children = {}
        for i=parentnumber, reaper.CountTracks(0)-1 do
                local track = reaper.GetTrack(0,i)
                local depth = reaper.GetTrackDepth(track)
                if depth > parentdepth then
                    table.insert(children, track)
                else
                    break
                end
        end
        return children
    end
end

function rgba(r, g, b, a)
    local b = b/255
    local g = g/255 
    local r = r/255 
    local b = math.floor(b * 255) * 256
    local g = math.floor(g * 255) * 256 * 256
    local r = math.floor(r * 255) * 256 * 256 * 256
    local a = math.floor(a * 255)
    return r + g + b + a
end

function col(col,a)
    r, g, b = reaper.ColorFromNative(col)
    result = rgba(r,g,b,a)
    return result
end

function dim(color)
    r, g, b = reaper.ColorFromNative(color) 
    value = 0.95
    r = math.max(math.ceil(r*value),10)
    g = math.max(math.ceil(g*value),10)
    b = math.max(math.ceil(b*value),10)

    color = reaper.ColorToNative(r, g, b)
    return color
end

CONTEXT_TCP = 0
CONTEXT_ITEMS = 1
CONTEXT_ENVELOPES = 2

_,_,_,_,_,_,mouse_scroll  = reaper.get_action_context()
context = reaper.GetCursorContext()

if(context == CONTEXT_TCP) then
  if(mouse_scroll > 0) then
    local sel_track = reaper.GetSelectedTrack(0, 0)
    reaper.Main_OnCommand(40360, 0) -- Track: Set to one random color
    if sel_track then 
        color = reaper.GetTrackColor(sel_track)
        is_folder = reaper.GetMediaTrackInfo_Value(reaper.GetSelectedTrack( 0, 0), 'I_FOLDERDEPTH')==1
        if is_folder then 
            children = get_children(sel_track)
            for k,child in pairs(children) do 
                reaper.SetTrackColor(child, color)
            end
        end 
    end

  else
    local sel_track = reaper.GetSelectedTrack(0, 0)
    if sel_track then 
        color = reaper.GetTrackColor(sel_track)

        reaper.SetTrackColor(sel_track, dim(color))
        is_folder = reaper.GetMediaTrackInfo_Value(reaper.GetSelectedTrack( 0, 0), 'I_FOLDERDEPTH')==1
        if is_folder then 
            children = get_children(sel_track)
            for k,child in pairs(children) do 
                reaper.SetTrackColor(child, dim(color))
            end
        end 
    end
  end
end

if(context == CONTEXT_ITEMS or context == CONTEXT_ENVELOPES) then
    if(mouse_scroll > 0) then
        reaper.Main_OnCommand(40706, 0) -- Item: Set to one random color
    else
        local count = reaper.CountSelectedMediaItems(0)
        if count > 0 then 
            for i=0, count-1 do 
                item = reaper.GetSelectedMediaItem(0, i)
                item_color = reaper.GetMediaItemInfo_Value(item, 'I_CUSTOMCOLOR')
                reaper.SetMediaItemInfo_Value(item, 'I_CUSTOMCOLOR', dim(item_color)|0x1000000)
                reaper.UpdateItemInProject(item)
            end 
        end
    end
end