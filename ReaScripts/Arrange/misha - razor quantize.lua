-- @description quantize audio transient to nearest grid in razor area
-- @author misha
-- @version 1.1
-- @about quantize audio transient to nearest grid in razor area
-- @changelog
--   # fix track group offset

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

local group_offsets = {} 

function get_track_group_offset(tr)
    local lead1_32 = reaper.GetSetTrackGroupMembership(tr, "MEDIA_EDIT_LEAD", 0, 0)
    local follow1_32 = reaper.GetSetTrackGroupMembership(tr, "MEDIA_EDIT_FOLLOW", 0, 0)
    local lead33_64 = reaper.GetSetTrackGroupMembershipHigh(tr, "MEDIA_EDIT_LEAD", 0, 0)
    local follow33_64 = reaper.GetSetTrackGroupMembershipHigh(tr, "MEDIA_EDIT_FOLLOW", 0, 0)

    local mask1_32 = lead1_32 | follow1_32
    local mask33_64 = lead33_64 | follow33_64

    -- Проверяем 1-32
    for i = 0, 31 do
        if (mask1_32 & (1 << i)) ~= 0 then
            local gid = i + 1
            if group_offsets[gid] then return group_offsets[gid], gid end
            return nil, gid
        end
    end
    -- Проверяем 33-64
    for i = 0, 31 do
        if (mask33_64 & (1 << i)) ~= 0 then
            local gid = i + 33
            if group_offsets[gid] then return group_offsets[gid], gid end
            return nil, gid
        end
    end
    return nil, nil
end

function quantize(new_item, pos, track)
    local take = reaper.GetActiveTake(new_item)
    if not take or reaper.TakeIsMIDI(take) then return end

    local saved_offset, group_id = get_track_group_offset(track)
    local final_offset = 0

    if saved_offset then
        final_offset = saved_offset
    else
        reaper.SetEditCurPos(pos, false, false)
        reaper.SelectAllMediaItems(0, false)
        reaper.SetMediaItemSelected(new_item, true)
        
        reaper.Main_OnCommand(40375, 0) -- move cursor to next transient 
        local transient = reaper.GetCursorPosition()
        
        local _, division = reaper.GetSetProjectGrid(0, 0, 0, 0, 0)
        local _, tempo = reaper.GetTempoTimeSigMarker(0, reaper.FindTempoTimeSigMarker(0, pos))
        if tempo <= 0 then tempo = reaper.Master_GetTempo() end
        local grid_duration = 

60/tempo * division

        local snapped, grid = reaper.SnapToGrid(0, pos)
        if snapped <= pos then
            grid = pos
            while (grid <= pos) do pos = pos + grid_duration ; grid = reaper.SnapToGrid(0, pos) end
        else
            grid = snapped
        end

        final_offset = transient - grid
        
        if group_id then group_offsets[group_id] = final_offset end
    end

    local startoffs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
    reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', startoffs + final_offset)
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
                
                -- quantize(new_item,RazorEdges[tr].lane[lane][current_edge])
                quantize(new_item,RazorEdges[tr].lane[lane][current_edge], RazorEdges[tr].track)
            
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
reaper.Undo_EndBlock( "Razor quantize", -1)