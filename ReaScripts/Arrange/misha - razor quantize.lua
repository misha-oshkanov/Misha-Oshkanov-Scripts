-- @description quantize audio transient to nearest grid in razor area
-- @author misha
-- @version 1.0
-- @about quantize audio transient to nearest grid in razor area


function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

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

function table_contains(table, element)
    for _, value in pairs(table) do
      if value == element then
        return true
      end
    end
    return false
end

function quantize(new_item,pos)
    reaper.Main_OnCommand(40375, 0) -- move cursor to next transient 
    local transient = reaper.GetCursorPosition()
    startoffs = reaper.GetMediaItemTakeInfo_Value( reaper.GetActiveTake(new_item),  'D_STARTOFFS' )
    if startoffs == nil then startoffs = 0 end

    -- pos = rz.st
    local grid_duration = 0
    if reaper.GetToggleCommandState( 41885 ) == 1 then -- Toggle framerate grid
        grid_duration = 0.4/reaper.TimeMap_curFrameRate( 0 )
    else
        local _, division = reaper.GetSetProjectGrid( 0, 0, 0, 0, 0 )
        local tmsgn_cnt = reaper.CountTempoTimeSigMarkers( 0 )
        local _, tempo
        if tmsgn_cnt == 0 then
            tempo = reaper.Master_GetTempo()
        else
            local active_tmsgn = reaper.FindTempoTimeSigMarker( 0, pos )
            _, _, _, _, tempo = reaper.GetTempoTimeSigMarker( 0, active_tmsgn )
        end
        grid_duration = 60/tempo * division
    end

    local snapped, grid = reaper.SnapToGrid(0, pos)
    if snapped > pos then
        grid = snapped
    else
        grid = pos
        while (grid <= pos) do
            pos = pos + grid_duration
            grid = reaper.SnapToGrid(0, pos)
        end
    end
    reaper.SetMediaItemTakeInfo_Value(reaper.GetActiveTake(new_item), 'D_STARTOFFS',  startoffs + (transient-grid) )
    grid = 0
    reaper.SelectAllMediaItems( 0, false )
end

local floor = math.floor

local function GetRazorEditEdgesPerTrack()
  local RazorEdges, track_cnt = {}, 0
  for i = 0, reaper.CountTracks(0)-1 do
    local track = reaper.GetTrack(0, i)
    local _, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS_EXT", "", false)
    if area ~= "" then
      local first_item = reaper.GetTrackMediaItem( track, 0 )
      if first_item then
        local fixed_lanes = reaper.GetMediaTrackInfo_Value( track, "I_FREEMODE" ) == 2
        local lane_height
        if fixed_lanes then
          lane_height = reaper.GetMediaItemInfo_Value( first_item, "F_FREEMODE_H" )
        else
          lane_height = 1
        end
        track_cnt = track_cnt + 1
        RazorEdges[track_cnt] = {track = track, lane = {}, numberOfLanes = floor(1/lane_height+0.5)}
        for tuple in string.gmatch(area, "[^,]+") do
          for st, en, env, y_top, y_bot in string.gmatch(tuple, "(%S+) (%S+) (%S+) (%S+) (%S+)") do
            if env == '""' then
              if lane_height == 1 then
                local num = 0
                if not RazorEdges[track_cnt].lane[1] then
                  RazorEdges[track_cnt].lane[1] = {n = 0}
                else
                  num = RazorEdges[track_cnt].lane[1].n
                end
                num = num + 1 ; RazorEdges[track_cnt].lane[1].n = num
                RazorEdges[track_cnt].lane[1][num] = tonumber(st)
                num = num + 1 ; RazorEdges[track_cnt].lane[1].n = num
                RazorEdges[track_cnt].lane[1][num] = tonumber(en)
              else
                local upper_RE_lane = floor( tonumber(y_top) / lane_height + 1.5 )
                local lower_RE_lane = floor( tonumber(y_bot) / lane_height + 0.5 )
                for lane = upper_RE_lane, lower_RE_lane do
                  local num = 0
                  if not RazorEdges[track_cnt].lane[lane] then
                    RazorEdges[track_cnt].lane[lane] = {n = 0}
                  else
                    num = RazorEdges[track_cnt].lane[lane].n
                  end
                  num = num + 1 ; RazorEdges[track_cnt].lane[lane].n = num
                  RazorEdges[track_cnt].lane[lane][num] = tonumber(st)
                  num = num + 1 ; RazorEdges[track_cnt].lane[lane].n = num
                  RazorEdges[track_cnt].lane[lane][num] = tonumber(en)
                end
              end
            end
          end
        end
      end
    end
  end
  -- Remove same starts and ends to make it work like native split action
  for tr = 1, track_cnt do
    if RazorEdges[tr].numberOfLanes ~= 1 then
      for lane, Edges in pairs(RazorEdges[tr].lane) do
        if Edges.n > 2 then
          local prev_edge = Edges[Edges.n - 1]
          for ed = Edges.n-2, 2, -2 do
            if prev_edge == Edges[ed] then
              table.remove(Edges, ed+1)
              table.remove(Edges, ed)
              Edges.n = Edges.n - 2
            end
            prev_edge = Edges[ed-1]
          end
        end
      end
    end
  end
  return RazorEdges, track_cnt
end

local RazorEdges, TracksWithEdges_cnt = GetRazorEditEdgesPerTrack()
if TracksWithEdges_cnt == 0 then return reaper.defer(function() end) end

-----------------------------------------------------------------------------------------

local Items = {}
local function GetItems()
  for tr = 1, TracksWithEdges_cnt do
    local track = RazorEdges[tr].track
    local item_cnt = reaper.CountTrackMediaItems(track)
    if item_cnt > 0 then
      Items[tr] = {lane = {}}
      for it = 0, item_cnt-1 do 
        local item = reaper.GetTrackMediaItem(track, it)
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local isEmpty = reaper.CountTakes( item ) == 0
        local isMidi = (not isEmpty) and ( reaper.TakeIsMIDI( reaper.GetActiveTake( item ) ) )
        local item_lane = 1
        if RazorEdges[tr].numberOfLanes ~= 1 then
          item_lane =
          floor(reaper.GetMediaItemInfo_Value( item, "F_FREEMODE_Y" ) * RazorEdges[tr].numberOfLanes + 1.5)
        end
        if RazorEdges[tr].lane[item_lane] then
          local num = 0
          if not Items[tr].lane[item_lane] then
            Items[tr].lane[item_lane] = {n = 0}
          else
            num = Items[tr].lane[item_lane].n
          end
          num = num + 1 ; Items[tr].lane[item_lane].n = num
          Items[tr].lane[item_lane][num] = 
          { item = item, _pos = item_pos, _end = item_end, moveXfade = ( ((not isEmpty) and (not isMidi)) ) }
        end
      end
    end
  end
end

GetItems()

-----------------------------------------------------------------------------------------

local function SplitAtEdges( RazorEdges, TracksWithEdges_cnt, Items )
  local xfadetime = 0
  if reaper.GetToggleCommandState( 40912 ) == 1 then -- -- Auto-crossfade on split enabled
    xfadetime = tonumber(({reaper.get_config_var_string( "defsplitxfadelen" )})[2]) or 0.01
  end
  for tr = 1, TracksWithEdges_cnt do
    for lane, Edges in pairs(RazorEdges[tr].lane) do
      local current_edge = Edges.n
      local Item = Items[tr].lane[lane]
      local it = Item.n
      while it ~= 0 do
        while current_edge ~= 0 do
          local split_pos = RazorEdges[tr].lane[lane][current_edge] - (Item[it].moveXfade and xfadetime or 0)
          if split_pos > Item[it]._pos and split_pos < Item[it]._end then
            local new_item = reaper.SplitMediaItem( Item[it].item, split_pos )
            if current_edge % 2 == 1 then 
                reaper.SetMediaItemSelected(new_item, true )
                
                quantize(new_item,RazorEdges[tr].lane[lane][current_edge])
            
                -- print(new_item)     
            
            end
            current_edge = current_edge - 1
          elseif split_pos >= Item[it]._end then
            current_edge = current_edge - 1
          elseif split_pos <= Item[it]._pos then
            break
          end
        end
        it = it - 1
      end


    -- reaper.Main_OnCommand(40375, 0) -- move cursor to next transient 
    -- local transient = reaper.GetCursorPosition()
    -- startoffs = reaper.GetMediaItemTakeInfo_Value( reaper.GetActiveTake(new_item),  'D_STARTOFFS' )
    -- if startoffs == nil then startoffs = 0 end

    -- pos = rz.st
    -- local grid_duration = 0
    -- if reaper.GetToggleCommandState( 41885 ) == 1 then -- Toggle framerate grid
    --     grid_duration = 0.4/reaper.TimeMap_curFrameRate( 0 )
    -- else
    --     local _, division = reaper.GetSetProjectGrid( 0, 0, 0, 0, 0 )
    --     local tmsgn_cnt = reaper.CountTempoTimeSigMarkers( 0 )
    --     local _, tempo
    --     if tmsgn_cnt == 0 then
    --         tempo = reaper.Master_GetTempo()
    --     else
    --         local active_tmsgn = reaper.FindTempoTimeSigMarker( 0, pos )
    --         _, _, _, _, tempo = reaper.GetTempoTimeSigMarker( 0, active_tmsgn )
    --     end
    --     grid_duration = 60/tempo * division
    -- end

    -- local snapped, grid = reaper.SnapToGrid(0, pos)
    -- if snapped > pos then
    --     grid = snapped
    -- else
    --     grid = pos
    --     while (grid <= pos) do
    --         pos = pos + grid_duration
    --         grid = reaper.SnapToGrid(0, pos)
    --     end
    -- end
    -- reaper.SetMediaItemTakeInfo_Value(reaper.GetActiveTake(new_item), 'D_STARTOFFS',  startoffs + (transient-grid) )
    -- grid = 0



    end
    reaper.GetSetMediaTrackInfo_String(RazorEdges[tr].track, "P_RAZOREDITS", "", true)
  end
end

-----------------------------------------------------------------------------------------

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh( 1 )
SplitAtEdges( RazorEdges, TracksWithEdges_cnt, Items )
reaper.PreventUIRefresh( -1 )
reaper.UpdateArrange()
reaper.Undo_EndBlock( "Razor quantize", 1|4 )

-- local count_tracks = reaper.CountTracks(0)
-- if count_tracks == 0 then return end 

-- razors = {}

-- for i=0,count_tracks-1 do 
--     local track = reaper.GetTrack(0, i)
--     local retval, str = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS_EXT', '', false)
--     if area ~= "" then 
--         for block in str:gmatch("[^,]+") do
--             local rz = {}
--             local st, en, env, top, bot = block:match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
--             rz.track = track
--             rz.st = tonumber(st)
--             rz.en = tonumber(en) 
--             rz.top = tonumber(top) 
--             rz.bot = tonumber(bot)
--             rz.env = env 
--             table.insert(razors,rz)
--         end
--     end
-- end

-- printt(razors)

-- for i,rz in ipairs(razors) do
--     split_items = {}
--     local count_items = reaper.CountTrackMediaItems(rz.track)
--     -- print(count_items)
--     for it=0,count_items-1 do 
--         local item = reaper.GetTrackMediaItem(rz.track, it)
--         local item_start = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
--         local item_end = item_start + reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
--         -- if (rz.st > item_start and rz.st < item_end) or (rz.en > item_start and rz.en < item_end) then
--             -- if table_contains(split_items, item) then break end
--             -- new_item = reaper.SplitMediaItem(item, rz.st)
--             -- new_item = reaper.SplitMediaItem(new_item, rz.en)
--             -- table.insert( split_items,new_item )
--         -- end
--     end 

    -- reaper.SetMediaItemSelected(new_item, true)


    -- reaper.Main_OnCommand(40375, 0) -- move cursor to next transient 
    -- local transient = reaper.GetCursorPosition()
    -- startoffs = reaper.GetMediaItemTakeInfo_Value( reaper.GetActiveTake(new_item),  'D_STARTOFFS' )
    -- if startoffs == nil then startoffs = 0 end

    -- pos = rz.st
    -- local grid_duration = 0
    -- if reaper.GetToggleCommandState( 41885 ) == 1 then -- Toggle framerate grid
    --     grid_duration = 0.4/reaper.TimeMap_curFrameRate( 0 )
    -- else
    --     local _, division = reaper.GetSetProjectGrid( 0, 0, 0, 0, 0 )
    --     local tmsgn_cnt = reaper.CountTempoTimeSigMarkers( 0 )
    --     local _, tempo
    --     if tmsgn_cnt == 0 then
    --         tempo = reaper.Master_GetTempo()
    --     else
    --         local active_tmsgn = reaper.FindTempoTimeSigMarker( 0, pos )
    --         _, _, _, _, tempo = reaper.GetTempoTimeSigMarker( 0, active_tmsgn )
    --     end
    --     grid_duration = 60/tempo * division
    -- end

    -- local snapped, grid = reaper.SnapToGrid(0, pos)
    -- if snapped > pos then
    --     grid = snapped
    -- else
    --     grid = pos
    --     while (grid <= pos) do
    --         pos = pos + grid_duration
    --         grid = reaper.SnapToGrid(0, pos)
    --     end
    -- end
    -- reaper.SetMediaItemTakeInfo_Value(reaper.GetActiveTake(new_item), 'D_STARTOFFS',  startoffs + (transient-grid) )
    -- grid = 0
-- end
-- reaper.Main_OnCommand(42406, 0)
-- reaper.UpdateArrange()