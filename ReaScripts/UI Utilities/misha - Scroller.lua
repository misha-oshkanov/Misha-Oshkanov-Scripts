-- @description Scroller
-- @author Misha Oshkanov
-- @version 0.7.5
-- @about
--  Panel to select and scroll to desired track or folder. In midi editor panel can show notes of selected tracks.--
--  Uses first-order folder as buttons
--
--  left click - select folder track and scroll view to it
--  right click - show folder track structure, you can click on children track to select and scroll to it
--  shift + click - mute folder track
--  control + click - solo folder track
--
--  control + click in child tracklist - copy items to clicked track
--  shift + click in child tracklist - move items to clicked track
--  alt + click in child tracklist - rename selected track


-------------- SETTINGS -------------- 
floating_window = false -- use to freely move script

-- Mode
panel_position = 'BOTTOM'  -- Panel position There is two modes: 'TOP', 'BOTTOM', 'RIGHT'

max_list = 40   ----- MAX AMOUNT OF CHILDREN TRACKS IN THE LIST

--- TRICS TO UPDATE MIDI EDITOR 
use_invert_hack = false  -- do 2x Time selection invert action to update midi editor -- use if you you don't see notes when folder buttons are clicked
select_tracks   = false   -- select tracks on click -- use if you you don't see notes when folder buttons are clicked

-- Buttons
button_w  = 96           -- minimum button width
button_h  = 26           -- main button heigth
child_button_h  = 28     -- child button height
folder_padding = 10      -- reduce width of child tracks
folder_level = 0         -- target depth of folder tracks used to generate buttons (default is 0). Use this if you have one premaster folder which contains all other folders
scroll_offset = 0        -- this will offset scroll position by x pixels, can be used to place scrolled track at the middle of arrange

-- Panel padding
bottom_padding = -10       -- padding in bottom mode
top_padding = 84         -- padding in top mode
midi_padding = 0        -- padding with open midi editor
use_arr_bottom = true    -- if true use bottom of arrange view for panel positioning, if false use reaper window bottom
use_arr_middle = false

-- Fonts
folder_font_size = 16    -- font for main buttons
child_font_size  = 14    -- font for tracklist


-- Other settings
show_only_tracks_with_midi_in_editor =  false   -- children tracklist will contain all tracks in folder if false, otherwise will contain only tracks with midi items
use_custom_color_for_folder_names = true        -- folders in children tracklist will have red labels
custom_color = {255,132,132}                    -- set custom color here (rgb)

BLOCKED_TRACK_LAYOUTS = {'Separator', 'M - VCA'}                        -- tracks with this names will be hidden
BLOCKED_CHILD_TRACK_NAMES  = {'VCA'}                                    -- tracks with this names will be hidden
BLOCKED_FOLDER_TRACK_NAMES = {'VCA'}                                    -- tracks with this names will be hidden
arch_prefix = "_" -- tracks with this prefix will be hidden

-----------------------------------------------------------------------

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function name(track)  retval, buf = reaper.GetTrackName(track) print(buf) end

function printt(t, indent)
    indent = indent or 0
    for k, v in pairs(t) do
      if type(v) == "table" then
        print(string.rep(" ", indent) .. k .. " = {")
        printt(v, indent + 2)
        print(string.rep(" ", indent) .. "}")
      else
        print(string.rep(" ", indent) .. k .. " = " .. tostring(v))
      end
    end
end

local ctx   = reaper.ImGui_CreateContext('Scroller')

local font       = reaper.ImGui_CreateFont('sans-serif', folder_font_size)
local font2      = reaper.ImGui_CreateFont('sans-serif', child_font_size)
local font_bold  = reaper.ImGui_CreateFont('sans-serif', folder_font_size, reaper.ImGui_FontFlags_Bold())

-- Detect operating system
local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OSX') or os:match('macOS')
local is_linux = os:match('Other')

reaper.ImGui_Attach(ctx, font)
reaper.ImGui_Attach(ctx, font2)
reaper.ImGui_Attach(ctx, font_bold)

collapse_action = reaper.NamedCommandLookup('_RS1e92997967aa4e08ac529e9e3b83120b26f55fce')
scale = reaper.ImGui_GetWindowDpiScale( ctx )

proj = 0
active = {}
was_active = {}
disable = false
show_input = false 
show_list = false
was_renamed = false
calc_w = 0

-- scroll = 0
clicked_button_x = 0
clicked_button_y = 0
clicked_w = 0
clicked_h = 0

popup_flags =  reaper.ImGui_PopupFlags_MouseButtonRight()

list_window_flags =  reaper.ImGui_WindowFlags_NoTitleBar() +  
                reaper.ImGui_WindowFlags_NoDocking() +
                reaper.ImGui_WindowFlags_NoResize() +
                reaper.ImGui_WindowFlags_NoBackground() 
                -- reaper.ImGui_WindowFlags_TopMost()


window_flags =  reaper.ImGui_WindowFlags_NoTitleBar() +  
                reaper.ImGui_WindowFlags_NoDocking() +
                reaper.ImGui_WindowFlags_NoResize() +
                reaper.ImGui_WindowFlags_NoScrollbar() 
                -- reaper.ImGui_WindowFlags_TopMost()
                -- reaper.ImGui_WindowFlags_NoBackground()-

topmost_window_flags =  reaper.ImGui_WindowFlags_NoTitleBar() +  
                reaper.ImGui_WindowFlags_NoDocking() +
                reaper.ImGui_WindowFlags_NoResize() +
                reaper.ImGui_WindowFlags_NoScrollbar() + 
                reaper.ImGui_WindowFlags_TopMost()
                -- reaper.ImGui_WindowFlags_NoBackground()-

input_flags =   reaper.ImGui_InputTextFlags_EnterReturnsTrue() +
                reaper.ImGui_InputTextFlags_CtrlEnterForNewLine()
                -- reaper.ImGui_InputTextFlags_AutoSelectAll()

folder_list = {}
children_list = {}

function GetParent(track)
    depth = reaper.GetTrackDepth( track )
    for d=1,depth do 
        track =  reaper.GetParentTrack(track)
    end 
    return track
end

function GetChildren(parent)
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
    
function GetParentTable(track)
    local parentlist = {}
    local oldparent
    local parent = GetParent(track)
    if parent ~= oldparent then
        table.insert(parentlist, parent)
    end
        oldparent = parent
    return parentlist
end

function AnyHidden(tracks)
    for i=1, #tracks do
        if not reaper.IsTrackVisible( tracks[i], false ) then return true end
    end
    return false
end

function SetVisibility(tracks, bool)
    for i=1, #tracks do
        reaper.SetMediaTrackInfo_Value( tracks[i], "B_SHOWINTCP", bool ) 
    end--for
end -- SetVisibility

function SetCompact(tracks, bool)
    for i=1, #tracks do
        reaper.SetMediaTrackInfo_Value( tracks[i], "I_FOLDERCOMPACT", bool ) 
    end--for
end -- SetCompact

function hide(track)
    -- reaper.ClearConsole()
    reaper.PreventUIRefresh(1)
    parents = GetParentTable(track)

    local compacted
    local hide
    for i=1, #parents do
    
        if parents[i] ~= false then
            local parent = parents[i]
            local kids = GetChildren(parent)
            
            if i==1 then
                compacted = reaper.GetMediaTrackInfo_Value(parent, "I_FOLDERCOMPACT")
            end

            reaper.SetMediaTrackInfo_Value(parent, "I_FOLDERCOMPACT", compacted==2 and 0 or 2)
            -- SetVisibility (kids, compacted==2 and 1 or 0)
            -- SetCompact    (kids, compacted==2 and 0 or 2)

        end
    end
        
    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(0)
end

function clear_list()
    folder_list = {}
    -- children_list = {}
end

function get_ch_list(parent,editor)
    children_list = {}
    children = GetChildren(parent)
    for t=1, #children do 
        local blocked = false
        has_midi = false
        tr = {
            track = nil,
            id    = nil,
            name  = nil,
            depth = nil,
            col   = nil,
            fol   = nil,
            midi  = nil,
            
        }
        track = children[t]
        fold  = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')
        id    = reaper.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER')
        check_hide = reaper.GetMediaTrackInfo_Value(track, 'B_SHOWINTCP' )
        local _, layout = reaper.GetSetMediaTrackInfo_String(track, 'P_TCP_LAYOUT', '', false )

        -- for f=1, reaper.TrackFX_GetCount(track) do 
        --     get_off =  reaper.TrackFX_GetOffline(track, f)
        --     print(get_off)
        -- end 

        depth = reaper.GetTrackDepth(track)
        color = reaper.GetTrackColor(track)
        _, tn = reaper.GetTrackName(track)

        for v,k in pairs (BLOCKED_CHILD_TRACK_NAMES) do 
            if tn:match(k) or string.sub(tn,1,1) == arch_prefix then 
                blocked = true 
            end   
        end
      
        for v,l in pairs (BLOCKED_TRACK_LAYOUTS) do 
            if layout == l then blocked = true  end   
        end

        if show_only_tracks_with_midi_in_editor then 
            if reaper.CountTrackMediaItems(track)  > 0 then  
                item = reaper.GetTrackMediaItem(track, 0)
                take = reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI (take) then 
                    has_midi = true 
                end
            else 
                has_midi = false 
            end
        else has_midi = true end
        if depth > 0 and check_hide == 1 and not blocked then 
            tr.track  = track
            tr.id     = id
            tr.name   = tn
            tr.depth  = depth
            tr.col    = color
            tr.midi   = has_midi
            tr.fol    = fold
            tr.layout = layout
            tr.off    = off
            if editor and not has_midi then donothing()
            else table.insert(children_list, tr) end
        end

    end 
end     

function donothing()
   return
end

function check_fx_offline(track)
    o = 0
    fx_count = reaper.TrackFX_GetCount(track)
    for f=1, fx_count do 
        get_off =  reaper.TrackFX_GetOffline(track, f-1)
        if get_off == true then 
            o = o + 1
        end 
    end 

    if o == fx_count and fx_count > 0 then return true else return false end
end

function get_list()
    clear_list()
    local count = reaper.CountTracks(proj)
    for t=1, count do 
        local blocked = false

        tr = {
            track  = nil,
            name   = nil,
            col    = nil,
        }
        track = reaper.GetTrack(proj,t-1)
        fold  = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')
        local _, layout = reaper.GetSetMediaTrackInfo_String(track, 'P_TCP_LAYOUT', '', false )
        guid  = reaper.BR_GetMediaTrackGUID(track)
        depth = reaper.GetTrackDepth(track)
        color = reaper.GetTrackColor(track)
        _, tn = reaper.GetTrackName(track)

        for v,k in pairs (BLOCKED_FOLDER_TRACK_NAMES) do 
            if tn:match(k) or string.sub(tn,1,1) == arch_prefix then 
                blocked = true 
            end   
        end
        for v,l in pairs (BLOCKED_TRACK_LAYOUTS) do 
            if layout == l then blocked = true  end   
        end

        check_off = check_fx_offline(track)
        
        if fold == 1 and depth == folder_level and check_off == false and not blocked then 
            tr.track = track
            tr.name = tn
            tr.col = color
            table.insert(folder_list, tr)
        end
    end 
end     

-- function update_list()
--     clear_list()
--     local count = reaper.CountTracks(proj)
--     for t=1, count do 
--         track = reaper.GetTrack(proj,t-1)
--         _, track_name = reaper.GetTrackName(track)
--         depth = reaper.GetTrackDepth(track)
--         fold =  reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')
--         if depth > 0 then 
--             for d=0, depth do 
--                 track = reaper.GetParentTrack(track)
--             end 
--         end
  
--     end
-- end

function rgba(r, g, b, a)
    b = b/255
    g = g/255 
    r = r/255 
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

function col_vib(col,vib)
    -- sat = math.ceil(255 * sat)
    r, g, b = reaper.ColorFromNative(col)

    -- if sat > 0 then 
    --     r = math.min(r+sat,255)
    --     g = math.min(g+sat,255)
    --     b = math.min(b+sat,255)
    -- else
    --     r = math.max(r+sat,0)
    --     g = math.max(g+sat,0)
    --     b = math.max(b+sat,0)
    -- end
    h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)
    -- s = s*sat
    -- s =s-(s/4)
    v = math.max(v,100)

    v = math.min(v * vib,230)
    r, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)


    result = rgba(r,g,b,1)
    return result
end

function col_vib_inv(col,vib)
    -- sat = math.ceil(255 * sat)
    r, g, b = reaper.ColorFromNative(col)

    h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)
    if v < 100 then 
        v = 255 - v
    end
    v = math.min(v * vib,230)
    r, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)


    result = rgba(r,g,b,1)
    return result
end

function col_sat(col,sat)
    sat = math.ceil(255 * sat)
    r, g, b = reaper.ColorFromNative(col)
    h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(r, g, b)
    if v < 100 then 
        v = 180 - v
        r, g, b = reaper.ImGui_ColorConvertHSVtoRGB( h, s, v )
    end 

    if sat > 0 then 
        r = math.min(r+sat,255)
        g = math.min(g+sat,255)
        b = math.min(b+sat,255)
    else
        r = math.max(r+sat,0)
        g = math.max(g+sat,0)
        b = math.max(b+sat,0)
    end

    result = rgba(r,g,b,1)
    return result
end

function col_sat_a(col,sat,a)
    sat = math.ceil(255 * sat)
    r, g, b = reaper.ColorFromNative(col)

    if sat > 0 then 
        r = math.min(r+sat,255)
        g = math.min(g+sat,255)
        b = math.min(b+sat,255)
    else
        r = math.max(r+sat,0)
        g = math.max(g+sat,0)
        b = math.max(b+sat,0)
    end

    result = rgba(r,g,b,a)
    return result
end

function draw_color(color,px)
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x, max_y,  color,0,0,px)
end

function draw_color_fill(color)
    min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRectFilled(draw_list, min_x, min_y, max_x, max_y, color)
  -- 
end
  
function table_contains(table, element)
    for _, value in pairs(table) do
      if value == element then
        return true
      end
    end
    return false
end
  
function table_remove(table, element)
    for k, v in pairs(table) do -- ipairs can also be used instead of pairs
        if v == element then
            table[k] = nil
            break
        end
    end
end 

function show_tracklist(str)
    rv = nil
    reaper.ImGui_SetNextWindowPos( ctx,(right-200)/1.7, bottom-115, condIn, 0.5, 0.5 ) -- h = 1400

    local rv, tracklist_open = reaper.ImGui_Begin( ctx, str, true )
    -- if not rv then return tracklist_open end
    if rv then
        reaper.ImGui_End(ctx)
    end
    return tracklist_open
end

function scroll_to_track(track)
    reaper.PreventUIRefresh( 1 )
    local track_tcpy = reaper.GetMediaTrackInfo_Value( track, "I_TCPY" )
    local scroll_retval, scroll_position, scroll_pageSize, scroll_min, scroll_max, scroll_trackPos = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
    reaper.SetOnlyTrackSelected(track)
    reaper.SetMixerScroll(track)
    reaper.JS_Window_SetScrollPos( windowHWND, "v", track_tcpy + scroll_position - scroll_offset)
    -- reaper.TrackList_AdjustWindows(false)
    -- local scroll_retval, scroll_position, scroll_pageSize, scroll_min, scroll_max, scroll_trackPos = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
    -- reaper.JS_Window_SetScrollPos( windowHWND, "v", track_tcpy + scroll_position - scroll_offset)

    reaper.TrackList_AdjustWindows(true)
    reaper.PreventUIRefresh( -1 )
end

function todb(val) 
    if val ~= nil then 
        if val > 0.0000000298023223876953125 then 
            return 20 * math.log(val, 10)         
        else
            return -150.0
        end
    end 
 return
end

function set_height(folder)
    local children = GetChildren(folder)
    mainHWND = reaper.GetMainHwnd()
    windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
    retval, left, top, right, bottom = reaper.JS_Window_GetClientRect( windowHWND )
    window_height = bottom-top
    height = math.ceil(window_height/(#children+2))

    for child=1,#children do 
        local track = children[child]
        local check_locked = reaper.GetMediaTrackInfo_Value(track, 'B_HEIGHTLOCK')
        if check_locked ~= 1 then reaper.SetMediaTrackInfo_Value(track, 'I_HEIGHTOVERRIDE', height) end
        for i = 1,  reaper.CountTrackEnvelopes(track) do
            local env = reaper.GetTrackEnvelope(track, i-1 )
            local br_env = reaper.BR_EnvAlloc( env, false )
            local active, visible, armed, inLane, laneHeight, defaultShape, _, _, _, _, faderScaling = reaper.BR_EnvGetProperties( br_env )
            reaper.BR_EnvSetProperties( br_env, 
                                      active, 
                                      visible, 
                                      armed, 
                                      inLane, 
                                      height,--laneHeight, 
                                      defaultShape, 
                                      faderScaling )
            reaper.BR_EnvFree( br_env, true )
        end

    end 
    -- for t=1, reaper.CountTracks(0) do 
    --     local track =  reaper.GetTrack(0, t-1)
    --     local check_locked = reaper.GetMediaTrackInfo_Value(track, 'B_HEIGHTLOCK')
    --     if check_locked ~= 1 then reaper.SetMediaTrackInfo_Value(track, 'I_HEIGHTOVERRIDE', height) end
    --     for i = 1,  reaper.CountTrackEnvelopes(track) do
    --         local env = reaper.GetTrackEnvelope(track, i-1 )
    --         local br_env = reaper.BR_EnvAlloc( env, false )
    --         local active, visible, armed, inLane, laneHeight, defaultShape, _, _, _, _, faderScaling = reaper.BR_EnvGetProperties( br_env )
    --         reaper.BR_EnvSetProperties( br_env, 
    --                                   active, 
    --                                   visible, 
    --                                   armed, 
    --                                   inLane, 
    --                                   height,--laneHeight, 
    --                                   defaultShape, 
    --                                   faderScaling )
    --         reaper.BR_EnvFree( br_env, true )
    --     end

    -- end 
end

function draw_buttons()
    editor = reaper.MIDIEditor_GetActive()

    for i,t in ipairs(folder_list) do
        reaper.ImGui_PushID(ctx, i)

        solo =  reaper.GetMediaTrackInfo_Value( t.track, 'I_SOLO' )
        mute =  reaper.GetMediaTrackInfo_Value( t.track, 'B_MUTE' )

        current_take  = reaper.MIDIEditor_GetTake(editor)
        peak = reaper.Track_GetPeakInfo(t.track, 1, false)

        if todb(peak) > -40 then
            a = 0.5+(math.min(peak,0.2))
        else a = 0.6
        end

        if current_take then 
            current_track = reaper.GetMediaItemTake_Track(current_take)
            GetParent(current_track)
        end
        
        if editor then 

            if table_contains(active,t.track) then 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col(t.col,0.5))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col(t.col,0.6))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  col(t.col,0.7))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  col(t.col,0.7))
            else
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col(t.col,0.2))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col(t.col,0.3))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  col(t.col,0.4))
                -- reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),          col_vib(t.col,1))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),          col_sat(t.col,0.3))

            end
        else
            if #active ~= 0 then active = {} end 

            compacted = reaper.GetMediaTrackInfo_Value(t.track, "I_FOLDERCOMPACT")
            if compacted ~= 2 then 
                -- reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col(t.col,a))  --0x768EFF
                -- reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col_vib(t.col,a))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col_vib(t.col,a))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col(t.col,0.6))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  col(t.col,0.7))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  col(t.col,0.7))
            else
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col(t.col,a-0.3))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col(t.col,0.3))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  col(t.col,0.4))
                -- reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),          col(t.col,0.8))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),           col_sat(t.col,0.3))
            end

        end
        if panel_position ~= 'RIGHT' then reaper.ImGui_SameLine(ctx,0,2) end
        
        calc_w = calc_text_size(folder_list,button_w)
        b = reaper.ImGui_Button(ctx, t.name, calc_w, button_h)
    

        min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
        max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
        draw_list = reaper.ImGui_GetWindowDrawList(ctx)

        if solo > 0 then 
            reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x, max_y,  rgba(255,216,50,0.7),0,0,3)
            reaper.ImGui_DrawList_AddRectFilled( draw_list, min_x, min_y, max_x, max_y, rgba(238,199,12,0.2), 0, 0 )
        end

        if mute > 0 and solo == 0 then 
            reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x, max_y,  rgba(255,14,59,0.7),0,0,3)
            reaper.ImGui_DrawList_AddRectFilled( draw_list, min_x, min_y, max_x, max_y, rgba(146,0,20,0.2), 0, 0 )
        end

        if todb(peak) > 0 then
            reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x, max_y,  rgba(255,18,18,1*(math.abs(peak)*9)),0,0,3)
        end 

        if reaper.ImGui_IsMouseDoubleClicked( ctx,  reaper.ImGui_MouseButton_Left() ) and reaper.ImGui_IsItemClicked( ctx, reaper.ImGui_MouseButton_Left() ) then 
            hide(t.track)
        end 

        -- if reaper.ImGui_IsMouseClicked( ctx,  reaper.ImGui_MouseButton_Right() ) and reaper.ImGui_IsItemClicked( ctx, reaper.ImGui_MouseButton_Right() ) then 
        --     solo = reaper.SetTrackUIMute( t.track, -1, 0 )
        -- end 


        if b then
            if show_list  then show_list = false end
            -- if  reaper.ImGui_IsKeyDown( ctx,  reaper.ImGui_Key_LeftShift() ) and not editor then 
            if reaper.JS_Mouse_GetState(9) == 8 and not editor then -- shift
                solo = reaper.SetTrackUIMute( t.track, -1, 0 )
                -- get_sel_track = reaper.GetSelectedTrack(0,0)
                -- if get_sel_track then 
                -- reaper.ReorderSelectedTracks( reaper.GetMediaTrackInfo_Value( t.track, 'IP_TRACKNUMBER' ), 0 )
                -- reaper.UpdateArrange()
                -- end
            -- elseif reaper.ImGui_IsKeyDown( ctx,  reaper.ImGui_Key_LeftAlt()) then 
            elseif reaper.JS_Mouse_GetState(16) == 15 then 
                input = ''
                show_input = true
                i_clicked_button_x, i_clicked_button_y = reaper.ImGui_GetItemRectMin(ctx)
                i_clicked_w, i_clicked_h = reaper.ImGui_GetItemRectSize( ctx )
                i_t = t
            elseif reaper.JS_Mouse_GetState(5) == 4  then
                solo = reaper.SetTrackUISolo( t.track, -1, 0 )
            else
                if current_track and editor then 
                    children = GetChildren(t.track)
                    if not table_contains(active,t.track) then  
                        table.insert(active, t.track)
                        state = true
                    else 
                        table_remove( active, t.track)
                        state = false
                    end

                    reaper.SetMediaItemSelected(reaper.GetMediaItemTake_Item(current_take), true)

                    for n,c in ipairs(children) do 
                        if select_tracks then reaper.SetTrackSelected(c, state==true and true or false) end
                        count_items =  reaper.CountTrackMediaItems(c)
                        for ci=1,count_items do 
                            item = reaper.GetTrackMediaItem( c, ci-1 )
                            if item ~= reaper.GetMediaItemTake_Item(current_take) and  reaper.TakeIsMIDI( reaper.GetActiveTake( item ) ) then 
                                reaper.SetMediaItemSelected(item, state==true and true or false)
                            end
                        end
                    end

                    if use_invert_hack then 
                        reaper.MIDIEditor_LastFocused_OnCommand(40501,0) 
                        reaper.MIDIEditor_LastFocused_OnCommand(40501,0) 
                    end
                    reaper.UpdateArrange()
                else
                    -- set_height(t.track)
                    scroll_to_track(t.track)
                    reaper.SetOnlyTrackSelected(t.track)

                    reaper.TrackList_AdjustWindows(0)
                end
            end
            
        end
        
        -- reaper.UpdateArrange()
        reaper.ImGui_PopStyleColor(ctx,4)

        if editor and GetParent(current_track) == t.track then 
            draw_color(col(t.col,0.5),3)
        end

        reaper.ImGui_PopID(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(),     rgba(100,40,30,1))
        reaper.ImGui_PopStyleColor(ctx,1)

        if  reaper.ImGui_IsItemClicked( ctx, reaper.ImGui_MouseButton_Right() ) then 
            clicked_button_x, clicked_button_y = reaper.ImGui_GetItemRectMin( ctx )
            clicked_w, clicked_h = reaper.ImGui_GetItemRectSize( ctx )

            children_list = {}
            clicked_parent = t.track
            name_w = button_w
            show_list = true 
        end
    end
end

function calc_text_size(list,name_w)
    original_w = name_w
    for t=1,#list do 
        tw, _ = reaper.ImGui_CalcTextSize( ctx, list[t].name)
        if tw > name_w then 
            name_w = tw
        end
    end 
    if name_w > original_w then name_w = name_w + 8 end
    return name_w
end 


function getStartPosSelItems()
    local position = math.huge
    local num_sel_items = reaper.CountSelectedMediaItems(0)
    if num_sel_items > 0 then
      for i=0, num_sel_items - 1 do
        local item = reaper.GetSelectedMediaItem( 0, i )
        local item_start_pos = reaper.GetMediaItemInfo_Value( item, "D_POSITION" )
        if item_start_pos < position then
          position = item_start_pos
        end
      end
    end
    return position
end

function move_items(track)
    local count = reaper.CountSelectedMediaItems(0)
    if count > 0 then 
        for i=1,count do 
            local item = reaper.GetSelectedMediaItem(0, i-1)
            reaper.MoveMediaItemToTrack(item, track)
        end 
    end
end 

function copy_items(track)
    reaper.Undo_BeginBlock()
    init_cursor_pos = reaper.GetCursorPosition()

    if reaper.CountSelectedMediaItems() > 0 then
        reaper.Main_OnCommand(40297, 0) -- Unselect all tracks (so that it can copy items)
        reaper.Main_OnCommand(40698, 0) -- Copy selected items
        local pos = getStartPosSelItems()
        reaper.SetEditCurPos2(0, pos, false, false)
        reaper.SetTrackSelected(track, true)
        reaper.Main_OnCommand(40914,0) -- Set first selected track as last touched
        reaper.Main_OnCommand(40058,0) -- Paste
    end
    reaper.SetEditCurPos(init_cursor_pos, false, false)

    reaper.Undo_EndBlock('Copy items to track',-1)
end

function frame()
    get_list()
    draw_buttons()

    if show_list then
        get_ch_list(clicked_parent,editor)
        dw = 0
        for t=1,#children_list do 
            tw, _ = reaper.ImGui_CalcTextSize( ctx, children_list[t].name )
            dw = children_list[t].depth - folder_level
            if tw > name_w then 
                name_w = tw
            elseif dw > children_list[t].depth then 
                dw = children_list[t].depth - folder_level
            end
        end 
        -- if dw>0 then dw = dw-1 end

        -- name_w = name_w + (dw*folder_padding)
        if #children_list > max_list then 
            max_h = max_list*child_button_h+12
        else
            max_h = (#children_list)*child_button_h
        end
        
        if name_w < calc_w then name_w = calc_w end
        if panel_position == 'BOTTOM' then
            reaper.ImGui_SetNextWindowPos( ctx,(clicked_button_x)-(((name_w+(dw*folder_padding))-calc_w)/2),clicked_button_y, condIn, 0, 1 )
        elseif panel_position == 'TOP' then 
            reaper.ImGui_SetNextWindowPos( ctx,(clicked_button_x)-(((name_w+(dw*folder_padding))-calc_w)/2),clicked_button_y+max_h+(clicked_h+4), condIn, 0, 1 )
        elseif panel_position == 'RIGHT' then 
            -- reaper.ImGui_SetNextWindowPos( ctx,clicked_button_x-(name_w+(dw*folder_padding)),clicked_button_y+max_h+4, condIn, 0, 1 )
            reaper.ImGui_SetNextWindowPos( ctx,clicked_button_x-((dw*folder_padding)),clicked_button_y+max_h+4, condIn, 0, 1 )
        end


        reaper.ImGui_SetNextWindowSize(ctx, name_w+(dw*folder_padding), max_h+8,  reaper.ImGui_Cond_Always()) 

        rv, p_open = reaper.ImGui_Begin( ctx, 'list', true, list_window_flags)
        if not rv then return p_open end 
 
        for ci,ct in ipairs(children_list) do 
            reaper.ImGui_PushID(ctx, ci)

            -- if string.match( ct.layout,'delay' ) then 
            --     reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               rgba(205,85,225,1))
            --     reaper.ImGui_PopStyleColor(ctx, 1)


            -- elseif string.match( ct.layout,'reverb' ) then

            -- elseif string.match( ct.layout,'par' )

            if ct.fol == 1 then
                -- reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        col(children_list[t].col,0.35))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         col_vib(ct.col,0.58))
                if use_custom_color_for_folder_names then 
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               rgba(custom_color[1],custom_color[2],custom_color[3],1))
                else 
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               col_sat(ct.col,0.4))
                end
            elseif string.match( ct.layout,'delay' ) then 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         col_vib(ct.col,0.50))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               rgba(243,168,255,1))
            elseif string.match( ct.layout,'reverb' ) then 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         col_vib(ct.col,0.50))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               rgba(144,216,252,1))
            elseif string.match( ct.layout,'par2' ) then 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         col_vib(ct.col,0.50))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               rgba(239,227,98,1))
    
            elseif string.match( ct.layout,'par' ) then 
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         col_vib(ct.col,0.50))  --0x768EFF
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               rgba(255,128,128,1))

            else
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         col_vib(ct.col,0.50))  --0x768EFF
                -- reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               col_vib_inv(children_list[t].col,1))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),               col_sat(ct.col,0.2))
            end
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),      col_vib(ct.col,0.64))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),       col_vib(ct.col,0.70))
            reaper.ImGui_PushStyleVar( ctx,   reaper.ImGui_StyleVar_WindowPadding(), 0,0) 
            reaper.ImGui_PushStyleVar( ctx,   reaper.ImGui_StyleVar_ItemSpacing(), 0,0)
            reaper.ImGui_PushFont( ctx, font2 )

            if #children_list > max_list then  
            child_button_w = (name_w-4)-(ct.depth-1-folder_level)*folder_padding - 14
            else 
            child_button_w = (name_w-4)-(ct.depth-1-folder_level)*folder_padding   
            end 

            peak = reaper.Track_GetPeakInfo(ct.track, 1, false)

            -- draw_color(col_vib(children_list[t].col,0.1),1) -- dark child border


            -- if reaper.ImGui_IsKeyDown( ctx,  reaper.ImGui_Key_LeftAlt() ) and  reaper.ImGui_IsItemClicked( ctx, reaper.ImGui_MouseButton_Left() ) then 
            --     input = ''
            --     show_input = true
            --     i_clicked_button_x, i_clicked_button_y = reaper.ImGui_GetItemRectMin(ctx)
            --     i_t = children_list[t]
            -- end 

            if ct.depth - folder_level > 1  then
                reaper.ImGui_Dummy(ctx, (ct.depth-1-folder_level)*folder_padding,child_button_h)
                reaper.ImGui_SameLine(ctx)
            end

            cb = reaper.ImGui_Button(ctx, ct.name, child_button_w+(dw*folder_padding), child_button_h)

            if todb(peak) > -40 then
                -- reaper.ImGui_SameLine( ctx, 0, 0 )
                draw_color(col_sat_a(ct.col,0.1,0.7),  1)
            else
                draw_color(col_vib(ct.col,0.1),1) -- dark child border
            end

            if editor and current_track == ct.track then 
                -- draw_color(col_vib(ct.col,0.8),3)
                draw_color(col_sat_a(ct.col,0.1,0.7),2)
            end

            -- if editor and current_track == ct.track then 
            --     reaper.ImGui_PushFont( ctx, font_bold )
            -- end
            
            if cb then 
                if reaper.ImGui_IsKeyDown(ctx,  reaper.ImGui_Key_LeftAlt()) then 
                    input = ''
                    show_input = true
                    i_clicked_button_x, i_clicked_button_y = reaper.ImGui_GetItemRectMin(ctx)
                    i_clicked_w, i_clicked_h = reaper.ImGui_GetItemRectSize(ctx)
                    i_t = ct
                elseif reaper.ImGui_IsKeyDown(ctx,  reaper.ImGui_Key_LeftShift()) then 
                    move_items(ct.track)
                    scroll_to_track(ct.track)
                    show_list = false 
                elseif reaper.ImGui_IsKeyDown(ctx,  reaper.ImGui_Key_LeftCtrl()) then 
                    copy_items(ct.track)
                    scroll_to_track(ct.track)
                    show_list = false 
                else
                    show_input = false
                    scroll_to_track(ct.track)
                    if editor then 
                        reload = false
                        reaper.SetMediaItemSelected(reaper.GetMediaItemTake_Item( current_take ), 0)
                        if table_contains(active,GetParent(current_track)) then 
                            reload = true
                        end
                        if reload then reaper.MIDIEditor_OnCommand(editor, 2) end

                        -- reaper.SelectAllMediaItems( 0, 0 )
                        if select_tracks then reaper.SetTrackSelected(ct.track, true) end

                        for i=1, reaper.CountTrackMediaItems( ct.track ) do 
                            mitem = reaper.GetTrackMediaItem( ct.track, i-1 )
                            if  reaper.TakeIsMIDI( reaper.GetActiveTake( mitem ) ) then 
                                current_take = ( reaper.GetActiveTake( mitem ) )
                                reaper.SetMediaItemSelected(mitem, 1)
                            end
                        end
                        if reload then reaper.Main_OnCommand(40153,0) end

                        for a=1,#active do 
                            active_track = active[a]
                            
                            -- table.insert(active, active_track)
                            children = GetChildren(active_track)
                            
                            for n,c in ipairs(children) do 
                                if select_tracks then reaper.SetTrackSelected(c, state==true and true or false) end
                                count_items =  reaper.CountTrackMediaItems(c)
                                for ci=1,count_items do 
                                    item = reaper.GetTrackMediaItem( c, ci-1 )
                                    -- if item ~= reaper.GetMediaItemTake_Item(current_take) and  reaper.TakeIsMIDI( reaper.GetActiveTake( item ) ) then
                                        reaper.SetMediaItemSelected(item, true)
                                    
                                end
                            end
                        end

                        -- table.insert( active, GetParent(children_list[t].track))
                        -- if use_invert_hack then 
                        -- reaper.MIDIEditor_LastFocused_OnCommand(40501,0) 
                        -- reaper.MIDIEditor_LastFocused_OnCommand(40501,0) 
                        -- end
                        reaper.UpdateArrange()
                    end
                    if not show_input then  
                        show_list = false 
                    end

                end
                -- show_list = false
            end
            
            reaper.ImGui_PopStyleColor(ctx, 4)
            reaper.ImGui_PopStyleVar  (ctx, 2)
            reaper.ImGui_PopID(ctx)
            reaper.ImGui_PopFont(ctx)
            -- reaper.ImGui_EndGroup(ctx)


        end 
        if was_renamed and (not reaper.ImGui_IsAnyItemHovered( ctx ) and not show_input and show_list) then 
            reaper.ImGui_SetWindowFocusEx( ctx, 'list' )
            -- show_list = false
            was_renamed = false
        end


        -- if not was_renamed and not reaper.ImGui_IsWindowFocused(ctx) and not show_input then 
        --     show_list = false
        -- end
        -- if not reaper.ImGui_IsWindowFocused(ctx) and not show_input then 
        --     show_list = false
        -- end
        reaper.ImGui_End( ctx )
    end
    if show_input then 
        -- clicked_w, clicked_h = reaper.ImGui_GetItemRectSize( ctx )

        -- if show_list then clicked_w = child_button_w end
        
        reaper.ImGui_PushStyleColor( ctx,  reaper.ImGui_Col_FrameBg(), col_vib(i_t.col,0.5) )

        reaper.ImGui_SetNextWindowPos( ctx, i_clicked_button_x,i_clicked_button_y+button_h+4, condIn, 0, 1 ) -- h = 1400
        reaper.ImGui_SetNextWindowSize(ctx, i_clicked_w+(i_clicked_w/2), button_h,  reaper.ImGui_Cond_Always()) 

        -- reaper.ImGui_SetNextWindowSize(ctx, clicked_w+(clicked_w/2), clicked_h,  reaper.ImGui_Cond_Always()) 

        input_rv, i_open = reaper.ImGui_Begin( ctx, "input", true, list_window_flags)

        if not input_rv then return i_open end 

        if  reaper.ImGui_IsAnyItemHovered( ctx ) then 
            reaper.ImGui_SetKeyboardFocusHere( ctx, offsetIn ) 
        end
        
        enter_rv, input = reaper.ImGui_InputText( ctx, ' ', input,  reaper.ImGui_InputTextFlags_EnterReturnsTrue() )
        if enter_rv then 
            _, _ = reaper.GetSetMediaTrackInfo_String( i_t.track, 'P_NAME', input, 1 )
            show_input = false 
            input = nil
            enter_rv = false
            was_renamed = true
            reaper.ImGui_SetWindowFocusEx( ctx, 'list' )
        end

        if not reaper.ImGui_IsWindowFocused( ctx, flagsIn ) then 
            show_input = false
            enter_rv = false
        end
        
        reaper.ImGui_PopStyleColor(ctx,1)
        reaper.ImGui_End( ctx )
    end  


    -- if show_input then 
    --     reaper.ImGui_OpenPopup( ctx, 'input', popup_flagsIn )
    --     reaper.ImGui_BeginPopup( ctx, 'input', flagsIn )
    --     if  reaper.ImGui_IsAnyItemHovered( ctx ) then 
    --         reaper.ImGui_SetKeyboardFocusHere( ctx, offsetIn ) 
    --     end

    --     enter_rv, input = reaper.ImGui_InputText( ctx, ' ', input,  reaper.ImGui_InputTextFlags_EnterReturnsTrue() )
    --     if enter_rv then 
    --         _, _ = reaper.GetSetMediaTrackInfo_String( i_t.track, 'P_NAME', input, 1 )
    --         show_input = false 
    --         input = nil
    --         enter_rv = false
    --         was_renamed = true
    --     end


    --     -- if not reaper.ImGui_IsWindowFocused( ctx, flagsIn ) then 
    --     --     show_input = false
    --     -- end

    --     reaper.ImGui_EndPopup( ctx )
    -- end
end 

function loop()

    reaper.ImGui_PushFont(ctx, font)
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(36, 37, 38, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
    reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(68, 69, 70, 1))
    -- reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_ScrollbarBg(),       rgba(68, 69, 70, 0))

    reaper.ImGui_PushStyleVar( ctx,    reaper.ImGui_StyleVar_WindowPadding(), 2,4) 

    mainHWND = reaper.GetMainHwnd()
    windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
    -- retval, left, top, right, bottom = reaper.JS_Window_GetClientRect( mainHWND )

    -- retval, me_left, me_top, me_right, me_bottom = reaper.JS_Window_GetClientRect( editor )
    retval, ar_left, ar_top, ar_right, ar_bottom = reaper.JS_Window_GetClientRect( windowHWND )
    retval, left, top, right, bottom = reaper.JS_Window_GetClientRect( mainHWND )

    if editor then 
        retval, left, top, right, bottom = reaper.JS_Window_GetClientRect( editor )
        bottom = bottom + midi_padding
    else 
        if use_arr_bottom then 
            _, _, _, _, bottom = reaper.JS_Window_GetClientRect( windowHWND )
        else 
            _, _, _, _, bottom = reaper.JS_Window_GetClientRect( mainHWND )
        end 
        if use_arr_middle then 
            _, left, _, right, _= reaper.JS_Window_GetClientRect( windowHWND )
        -- else 
            -- _, left, _, right, _= reaper.JS_Window_GetClientRect( mainHWND )
        end
    end

    retval, ar_left, ar_top, ar_right, ar_bottom = reaper.JS_Window_GetClientRect( windowHWND )
    if is_macos then m_left, m_top, m_right, m_bottom = reaper.JS_Window_GetViewportFromRect(0, 0, 0, 0, false ) end

    -- if use_arr_bottom and not editor then bottom = ar_bottom end 
        -- reaper.ImGui_SetNextWindowPos( ctx,(right)/2, bottom-button_h-bottom_padding, condIn, 0.5, 0.5 ) -- h = 1400
    if not floating_window then 
        if panel_position == 'BOTTOM' then 
            if is_windows then  
                reaper.ImGui_SetNextWindowPos( ctx,(right-((right-left)/2))*(1/scale), (bottom-button_h-bottom_padding)*(1/scale), condIn, 0.5, 0.5 )
            else 
                reaper.ImGui_SetNextWindowPos( ctx,right-((right-left)/2), m_top-bottom, condIn, 0.5, 0.5 )
            end
                
        elseif panel_position == 'TOP' then 
            if is_windows then  
                reaper.ImGui_SetNextWindowPos( ctx,(right-((right-left)/2))*(1/scale), (top+top_padding)*(1/scale), condIn, 0.5, 0.5 )
            else
                reaper.ImGui_SetNextWindowPos( ctx,right-((right-left)/2), m_top-bottom, condIn, 0.5, 0.5 )
            end
        elseif panel_position == 'RIGHT' and not editor then 
            if is_windows then  
                reaper.ImGui_SetNextWindowPos( ctx,(right-(calc_w/2))*(1/scale), (ar_bottom-((ar_bottom-ar_top)/2)-button_h-bottom_padding)*(1/scale), condIn, 0.5, 0.5 )
            else
                reaper.ImGui_SetNextWindowPos( ctx,right-((right-left)/2), m_top-bottom, condIn, 0.5, 0.5 )
            end
        end

    end
    if panel_position == 'RIGHT' then 
        reaper.ImGui_SetNextWindowSize(ctx, calc_w+5,(#folder_list*(button_h+4)+4) ,  reaper.ImGui_Cond_Always())
    else 
        reaper.ImGui_SetNextWindowSize(ctx, (#folder_list*calc_w)+(2*#folder_list)+6,button_h+8 ,  reaper.ImGui_Cond_Always())
    end
    -- reaper.ImGui_SetNextWindowSize(ctx, 300,button_h+8 ,  reaper.ImGui_Cond_Always())
    
    if editor then 
        wflags = topmost_window_flags
    else 
        wflags = window_flags 
    end

    local visible, open = reaper.ImGui_Begin(ctx, 'Scroller', true, wflags) 

    if visible then
        frame()
        if reaper.JS_Mouse_GetState( 1 ) == 1 and not reaper.ImGui_IsAnyMouseDown( ctx ) == true and show_list and not show_input then show_list = false end

        -- print(reaper.ImGui_IsAnyMouseDown( ctx ))
        -- p_open = reaper.ImGui_ShowMetricsWindow( ctx, p_open )
 
    --   if editor then
    --     wx, wy = reaper.ImGui_GetWindowPos( ctx )
    --     ww, wh = reaper.ImGui_GetWindowSize( ctx )
    --     draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    --     -- reaper.ImGui_DrawList_AddRectFilled( draw_list, wx, wy, wx, wy+1,  rgba(205,205,205,1))
    --     -- reaper.ImGui_DrawList_AddRectFilled( draw_list, wx+4, wy, wx+ww-4, wy+4,  rgba(33,205,227,0.7))
    --     reaper.ImGui_DrawList_AddRect( draw_list, wx, wy+wh-2, wx+ww, wy+2,  rgba(132,246,158,0.6),0,0,5)
    --     -- reaper.ImGui_DrawList_AddRect( draw_list, wx, wy+wh-2, wx+ww, wy+2,  rgba(255,255,255,0.8),0,0,4)
    --   end
        reaper.ImGui_End(ctx)
      
    end

    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar( ctx, 1 )

    reaper.ImGui_PopFont(ctx)
    
    if open then
      reaper.defer(loop)
    else
      reaper.ImGui_DestroyContext(ctx)
    end

end

reaper.defer(loop)

get_list()