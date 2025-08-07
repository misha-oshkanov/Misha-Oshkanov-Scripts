-- @description ShowHide Manager
-- @author Misha Oshkanov
-- @version 1.2
-- @about
--  UI panel for showind and hiding different types of tracks in project
--  Types: sends, selected tracks, muted tracks, empty tracks, track within region, offline tracks
---------------------------------------------------------------------
---------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------
------------ SETTINGS ------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------

-- ff floating window is false the script window will stay in bottom right corner of arrange view:+
-- if floating window is true you can freely move script window:
floating_window = false

-- There are three visual mods with diferent button placement:
--'BOX' - 'VERTLINE' - 'LINE'
MOD = 'LINE'

-- if USE_FX_LAYOUT is true script will search for layout_check string in the layout name. 
-- if the search is successful, the tracks will be hidden when the SENDS button is clicked:
USE_FX_LAYOUT = false
layout_check = 'fx'

-- script will ignore track if track name starts with this prefix:
arch_prefix = '_'

 -- script will ignore tracks with these names:
black_list = {'PARTS','ref','__LBX_RRMIDI','MIDI Feedback (Reaticulate)','______prefx_Track_Inspector 1'}

 -- script will ignore tracks with these layouts:
black_list_layouts = { 'Mix Bus', 'Separator', 'C - name' }

-- Button size:
button_h = 24 -- height default - 24
button_w = 54 -- width  default - 54

-- Additional panel position adjustments. Use negative or positive numbers:
move_x = 0
move_y = -5

panel_position = 'TOP' -- 'BOTTOM'

font_size = 15

----------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end
function pname(track)  retval, buf = reaper.GetTrackName(track) print(buf) end

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.6')

extname = 'INEED_TRACKS_STATE'
tracklist_extname = 'INEED_HIDE_TCP' 

local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OSX') or os:match('macOS')
local is_linux = os:match('Other')

local ctx = reaper.ImGui_CreateContext('Show/Hide')
local font = reaper.ImGui_CreateFont('sans-serif', 0)
-- reaper.ImGui_AttachFont(ctx, font)

window_flags =  reaper.ImGui_WindowFlags_NoTitleBar() +  
                reaper.ImGui_WindowFlags_NoDocking() +
                reaper.ImGui_WindowFlags_NoResize() +
                reaper.ImGui_WindowFlags_NoScrollbar() 
                -- reaper.ImGui_WindowFlags_NoBackground()-
local ImGui = {}
for name, func in pairs(reaper) do
  name = name:match('^ImGui_(.+)$')
  if name then ImGui[name] = func end
end

buttons = {
  {
    name = 'Select',
    key = 'SEL',
    button = nil,
    state = 0,
    col = {240, 240, 240, 0.6}
  }, 

  {
    name = 'Empty',
    key = 'EMPTY',
    button = nil,
    state = 0,
    tracks = {},
    col =  {188, 143, 3, 0.6}
  },
  {
    name = 'Muted',
    key = 'MUTED',
    button = nil,
    state = 0,
    col = {165, 18, 29, 0.6}
  },
  {
    name = 'Sends',
    key = 'SENDS',
    button = nil,
    state = 0,
    col = {23, 156, 255, 0.6}
  }, 
  {
    name = 'Offline',
    key = 'OFFLINE',
    button = nil,
    state = 0,
    col = {240, 56, 146, 0.6}
  },
  {
    name = 'Region',
    key = 'REG',
    button = nil,
    state = 0,
    col = {82, 223, 106, 0.6}
  },
}

function get_state(key)
  key = tostring(key)
  retval, extstate = reaper.GetProjExtState( 0, extname, string.upper(key) )  
  return extstate
end

function set_state(key,state)
  reaper.SetProjExtState( 0, extname, key, tostring(state))
end 

function colored_frame(col)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  local text_min_x, text_min_y = reaper.ImGui_GetItemRectMin(ctx)
  local text_max_x, text_max_y = reaper.ImGui_GetItemRectMax(ctx)
  reaper.ImGui_DrawList_AddRect(draw_list, text_min_x, text_min_y, text_max_x, text_max_y, col)
end

function draw_color_fill(color)
  button_col = 0xaf1d70
  min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
  max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
  draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddRectFilled(draw_list, min_x, min_y, max_x, max_y, color)
end

function draw_color(color)
  button_col = 0xaf1d70
  min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
  max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
  draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  reaper.ImGui_DrawList_AddRect( draw_list, min_x, min_y, max_x, max_y,  color,0,0,3)
end

function check_regions(track, rg_start, rg_end)
  tohide = 0
  for i = 1, reaper.CountTrackMediaItems(track) do
    local item =  reaper.GetTrackMediaItem(track, i-1)
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end   = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if tohide < 1 then
      if rg_start >= item_start and rg_start < item_end then 
          tohide = tohide + 1
      elseif rg_end > item_start and rg_end <= item_end then
          tohide = tohide + 1
      elseif rg_start <= item_start and rg_end >= item_end then 
          tohide = tohide + 1
      else 
          tohide = tohide + 0
      end
    end 
  end
  return tohide
end 

function SelectItemsTracks()
  local sel_items = reaper.CountSelectedMediaItems(0)
  if not sel_items then return end
  for s = 1, sel_items do 
      item = reaper.GetSelectedMediaItem(0, s-1)
      track = reaper.GetMediaItem_Track(item)
      reaper.SetTrackSelected(track, true)
  end
end 

function RestoreTracks()
  i = 0
  repeat
  local retval, key, value = reaper.EnumProjExtState(0, tracklist_extname, i)
  local track = reaper.BR_GetMediaTrackByGUID(0, key)
  
  if track and retval then
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMCP", 1)
          -- reaper.SetProjExtState(0,tracklist_extname,key,'')
  end
      
  i = i + 1
  
  until not retval
end

function ClearTracks();
  local i = 0
  while 0 do
      i=i+1
      retval,key,val = reaper.EnumProjExtState(0,tracklist_extname,i-1)
      if not retval then break end
      track = reaper.BR_GetMediaTrackByGUID(0,key)
      reaper.SetProjExtState(0,tracklist_extname,key,'')
      i = i-1
  end
end

function ScrollTrackToTop()
  track = reaper.GetSelectedTrack( 0, 0)
  if not track then reaper.Main_OnCommand(reaper.NamedCommandLookup('_XENAKIOS_TVPAGEHOME'),0) return end
  vis =  reaper.GetMediaTrackInfo_Value( track, 'B_SHOWINTCP' )
  if vis then 
      reaper.PreventUIRefresh( 1 )
      local track_tcpy = reaper.GetMediaTrackInfo_Value( track, "I_TCPY" )
      local mainHWND = reaper.GetMainHwnd()
      local windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
      local scroll_retval, scroll_position, scroll_pageSize, scroll_min, scroll_max, scroll_trackPos = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
      reaper.JS_Window_SetScrollPos( windowHWND, "v", track_tcpy + scroll_position )
      reaper.PreventUIRefresh( -1 )
  end 
end

-- function HideTracks()
--   for i = 1,reaper.CountTracks(0)do
--       local track = reaper.GetTrack(0,i-1)
--       local rec_state = reaper.GetMediaTrackInfo_Value(track,"I_RECARM")
--       if rec_state ~= 1 then 
--           if tcp_state == 1 and not reaper.IsTrackSelected(track) then 
--               reaper.SetMediaTrackInfo_Value(track,"B_SHOWINTCP",0)
--               reaper.SetMediaTrackInfo_Value(track,"B_SHOWINMCP",0)
--               local GUID = reaper.GetTrackGUID(track)
--               reaper.SetProjExtState(0,tracklist_extname,GUID,0)
--           end
--       end
--   end
-- end

function get_parent(track)
  depth = reaper.GetTrackDepth( track )
  for d=1,depth do 
      track =  reaper.GetParentTrack(track)
  end 
  return track
end

function toggle_showhide(s)
  for i=1, reaper.CountTracks(0) do
    blocked = false
    hide = false
    local track = reaper.GetTrack(0,i-1)
    local item_count =  reaper.CountTrackMediaItems(track)
    local is_sel =  reaper.IsTrackSelected(track)
    local rec_arm = reaper.GetMediaTrackInfo_Value(track, 'I_RECARM')
    local _, layout = reaper.GetSetMediaTrackInfo_String(track, 'P_TCP_LAYOUT', '', false)
    local mute_state = reaper.GetMediaTrackInfo_Value(track, 'B_MUTE') 
    local fol =  reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH' )
    local check_send = reaper.GetTrackNumSends(track, -1)
    local retval, name = reaper.GetTrackName(track)
    local offline = reaper.TrackFX_GetOffline(track, 0)  
    local cur_pos = reaper.GetCursorPosition()
    local _, regionidx = reaper.GetLastMarkerAndCurRegion(0, cur_pos)
    local _, isrgn, rg_start, rg_end, rg_name, markrgnindexnumber = reaper.EnumProjectMarkers(regionidx)
    
    for v,k in pairs (black_list) do 
      if name == k or string.sub(name,1,1) == arch_prefix then 
        blocked = true 
      end   
    end

    for v,l in pairs (black_list_layouts) do 
        if layout == l then blocked = true  end   
    end

    for i,button in ipairs(buttons) do 
      if button.state == 1 then 
        if     button.key == 'EMPTY' then
            if item_count == 0 and not is_sel and rec_arm == 0 and check_send == 0 and mute_state == 0 and fol ~= 1 then hide = true end

        elseif button.key == 'MUTED' then
            if mute_state == 1 then 
                hide = true 
            else
              depth = reaper.GetTrackDepth(track)
              ptrack = track
              for d=1,depth do 
                  ptrack =  reaper.GetParentTrack(ptrack)
                  parent_mute = reaper.GetMediaTrackInfo_Value(ptrack, 'B_MUTE')
                  if parent_mute == 1 then
                    hide = true
                  end
              end
            end

        elseif button.key == 'SENDS' then
            if USE_FX_LAYOUT == true then 
              if string.match(layout,layout_check) and check_send >0 then hide = true end
            end
            if USE_FX_LAYOUT == false then  
              if check_send >0 then hide = true end
            end

        elseif button.key == 'OFFLINE' then
            if offline then hide = true end

        elseif button.key == 'REG' then
            if isrgn and cur_pos >= rg_start and cur_pos <= rg_end then
              if not (depth == 0 and fol == 1.0) and rec_arm == 0 then 
                check = check_regions(track, rg_start, rg_end)
                if check == 0 then hide = true end
              end
            end

        elseif button.key == 'SEL' then
          local tcp_state = reaper.GetMediaTrackInfo_Value(track,"B_SHOWINTCP")

          if s == 1 then 
            SelectItemsTracks()
            -- HideTracks()
            if rec_arm ~= 1 and not blocked then 
              if tcp_state == 1 and not is_sel then 
                hide = true 
                local GUID = reaper.GetTrackGUID(track)
                reaper.SetProjExtState(0,tracklist_extname,GUID,0)
              end
            end
            ScrollTrackToTop()
          else
            -- RestoreTracks()

            r = 0
            repeat
            local retval, key, value = reaper.EnumProjExtState(0, tracklist_extname, r)
            local get_track = reaper.BR_GetMediaTrackByGUID(0, key)
            
            if get_track and retval then
              reaper.SetMediaTrackInfo_Value(get_track, "B_SHOWINTCP", 1)
              reaper.SetMediaTrackInfo_Value(get_track, "B_SHOWINMCP", 1)
              -- hide = false
              reaper.SetProjExtState(0,tracklist_extname,key,'')
            end
                
            r = r + 1
            
            until not retval
            -- ScrollTrackToTop()
          end
        end
      end
    end

    if not blocked then 
      reaper.SetMediaTrackInfo_Value( track, 'B_SHOWINTCP',   hide == true and 0 or 1)
      reaper.SetMediaTrackInfo_Value( track, 'B_SHOWINMIXER', hide == true and 0 or 1)
    end       
  end

end

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


function GetClientBounds(hwnd)
  ret, left, top, right, bottom = reaper.JS_Window_GetClientRect(hwnd)
  return left, top, right-left, bottom-top
end

function FindChildByClass(hwnd, classname, occurance) 
  local arr = reaper.new_array({}, 255)
  reaper.JS_Window_ArrayAllChild(hwnd, arr)
  local adr = arr.table() 
  local control_occurance = 0
  for j = 1, #adr do
    local hwnd = reaper.JS_Window_HandleFromAddress(adr[j]) 
    if reaper.JS_Window_GetClassName(hwnd)== classname then
      control_occurance = control_occurance + 1
      if occurance == control_occurance then
        return hwnd
      end
    end
  end
end


function Main()
  for i,b in ipairs(buttons) do

    s = get_state(b.key)
    s = tonumber(s)

    if MOD == 'LINE' then 
      ImGui.SameLine(ctx)
    end
    ImGui.PushID(ctx, i)

    if s == 1 then
      -- draw_color(rgba(b.col[1], b.col[2], b.col[3], b.col[4]))
      -- draw_color_fill(rgba(b.col[1], b.col[2], b.col[3], 0.1))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), rgba(b.col[1], b.col[2], b.col[3], b.col[4]))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),  rgba(b.col[1], b.col[2], b.col[3], b.col[4]))
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(),  rgba(240,240,240,1))
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(),rgba(b.col[1], b.col[2], b.col[3], 0.5))

    else
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered(), rgba(b.col[1], b.col[2], b.col[3], 0.4))
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive(),  rgba(b.col[1], b.col[2], b.col[3], 0.4))
      ImGui.PushStyleColor(ctx, ImGui.Col_Button(),        rgba(105,105,105,0.8))
      ImGui.PushStyleColor(ctx, ImGui.Col_Text(),  rgba(224,224,224,1))
    end

    if panel_position == 'TOP' then 

      -- tcp_hwnd = FindChildByClass(reaper.GetMainHwnd(),'REAPERTCPDisplay',1)
      -- if tcp_hwnd then
      --   tcp_x,tcp_y,tcp_w,tcp_h = GetClientBounds(tcp_hwnd)
      --   retval, tcp_left, tcp_top, tcp_right, tcp_bottom = reaper.JS_Window_GetClientRect( mainHWND )
      -- end
      -- button_w = tcp_w/6

    end 

    b.button = ImGui.Button(ctx, b.name, button_w, button_h)
    
    if MOD == 'BOX' and i%3~=0 then reaper.ImGui_SameLine(ctx) end

    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopID(ctx)
    
    if b.button then 

      s = s == 1 and 0 or 1
      if reaper.ImGui_IsKeyDown( ctx, reaper.ImGui_Key_LeftCtrl()) then 
        toggle_showhide(s == 1 and 0 or 1)
      else 
        b.state = s
        set_state(b.key,s)
      end
      toggle_showhide(s)

      reaper.UpdateArrange()
      reaper.TrackList_AdjustWindows(true)
    end 
   end

end

-- local last_proj = nil
-- function project_check()
--     local curr_proj_id, curr_proj_name = reaper.EnumProjects(-1, "")    
--     if last_proj ~= curr_proj_id then
--         last_proj = curr_proj_id    
--         Main()    
--     end    reaper.defer(project_check)
-- end

function loop()   
  reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_WindowBg(),          rgba(36, 37, 38, 1))
  reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBg(),           rgba(28, 29, 30, 1))
  reaper.ImGui_PushStyleColor(ctx,  reaper.ImGui_Col_TitleBgActive(),     rgba(68, 69, 70, 1))

  reaper.ImGui_PushStyleVar( ctx,    reaper.ImGui_StyleVar_WindowPadding(), 3,4) 
  reaper.ImGui_PushStyleVar( ctx,     reaper.ImGui_StyleVar_ItemSpacing(), 2,2) 

  reaper.ImGui_PushFont(ctx, nil, font_size)

  mainHWND = reaper.GetMainHwnd()
  windowHWND = reaper.JS_Window_FindChildByID(mainHWND, 1000)
  retval, left, top, right, bottom = reaper.JS_Window_GetClientRect( mainHWND )
  retval, ar_left, ar_top, ar_right, ar_bottom = reaper.JS_Window_GetClientRect( windowHWND )

  -- reaper.ImGui_SetNextWindowSize(ctx, 130, 230, reaper.ImGui_Cond_FirstUseEver())
  -- reaper.ImGui_SetNextWindowSize(ctx, (button_w+3)*6, button_h+8)

  if is_windows then 
    scale = reaper.ImGui_GetWindowDpiScale(ctx)
    os_scale = 1/scale
  else 
    os_scale = 1
  end

  cw, ch = reaper.ImGui_GetWindowSize( ctx )

  tcp_hwnd = FindChildByClass(reaper.GetMainHwnd(),'REAPERTCPDisplay',1)
  if tcp_hwnd then
    tcp_x,tcp_y,tcp_w,tcp_h = GetClientBounds(tcp_hwnd)
    retval, tcp_left, tcp_top, tcp_right, tcp_bottom = reaper.JS_Window_GetClientRect( mainHWND )
  end

  if panel_position == 'TOP' then
    ar_bottom = ar_top
    ar_right = right
  end
    
  if MOD == 'BOX' then 
    reaper.ImGui_SetNextWindowSize(ctx, ((button_w+2)*3)+4, (button_h*2)+10)
    
    if not floating_window then 
      reaper.ImGui_SetNextWindowPos( ctx, move_x + (ar_right-(cw/6))*os_scale, move_y + (ar_bottom-(ch-10))*os_scale, condIn, 0.5, 0.5)
    end


  elseif MOD == 'LINE' then 
    -- reaper.ImGui_SetNextWindowSize(ctx, ((button_w+2)*6)+8, button_h+8)
    reaper.ImGui_SetNextWindowSize(ctx, tcp_w*os_scale, (button_h+8)*os_scale)
    button_w = (tcp_w/6)-3
    -- print(right-ar_right)
    if not floating_window then 
      -- reaper.ImGui_SetNextWindowPos( ctx, move_x + (ar_right-(cw/2.3))*os_scale, move_y + (ar_bottom-(ch/9.8))*os_scale, condIn, 0.5, 0.5 )
      reaper.ImGui_SetNextWindowPos( ctx,  move_x + (tcp_right-(tcp_right-right)-(tcp_w/2))*os_scale, move_y + (ar_bottom-(ch))*os_scale, condIn, 0.5, 0.5 )
    end

  elseif MOD == 'VERTLINE' then 
    reaper.ImGui_SetNextWindowSize(ctx, (button_w+3)+3, ((button_h+2)*6)+6)
    if not floating_window then 
      reaper.ImGui_SetNextWindowPos( ctx, move_x + (ar_right-button_w/6)*os_scale, move_y + (ar_bottom-ch*4.1)*os_scale, condIn, 0.5, 0.5 )
    end

  end

  local visible, open = reaper.ImGui_Begin(ctx, 'Show/Hide', true, window_flags)

  if visible  then
    Main()     
    reaper.ImGui_End(ctx)
  end
  reaper.ImGui_PopStyleColor(ctx,3)
  reaper.ImGui_PopStyleVar( ctx, 2 )
  reaper.ImGui_PopFont(ctx)

  if open then
    reaper.defer(loop)
  end
end

loop()
-- reaper.defer(loop)