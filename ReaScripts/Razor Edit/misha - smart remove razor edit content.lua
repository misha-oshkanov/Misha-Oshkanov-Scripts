-- @description Smart remove razor edit content
-- @author Misha Oshkanov
-- @version 1.4
-- @about
--  Use to delete content within razor edit area(items, envelope points, automation items, midi notes)

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end


track_cnt = reaper.CountTracks(0)
if track_cnt == 0 then return reaper.defer(function() end) end

envs, env_cnt = {}, 0

function check_if_notes()
  for tr = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, tr)
    local _, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if area == "" then return end

    local areas = {}
    local tokens = {}
    for token in area:gmatch("(%S+)") do  
        table.insert(tokens, token)
    end

    for i = 1, #tokens - 2, 3 do
        local start_pos = tonumber(tokens[i])
        local end_pos = tonumber(tokens[i+1])
        local zone_type = tokens[i+2]

        if zone_type == '""' then  -- только медиа-зоны
            table.insert(areas, {start_pos, end_pos})
        end
    end

    local item_count = reaper.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local take = reaper.GetActiveTake(item)
      if take and reaper.TakeIsMIDI(take) then
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = item_pos + item_len

        for _, area in ipairs(areas) do
          local r_start = math.max(area[1], item_pos)
          local r_end = math.min(area[2], item_end)
          if r_start == item_pos and r_end == item_end then
            goto continue_area
          end
          
          if r_start < r_end then
            local qn_start = reaper.TimeMap2_timeToQN(0, r_start)
            local qn_end = reaper.TimeMap2_timeToQN(0, r_end)
            local _, note_count = reaper.MIDI_CountEvts(take)
            for n = note_count - 1, 0, -1 do
              local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
              local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, startppq)
              local end_qn = reaper.MIDI_GetProjQNFromPPQPos(take, endppq)

              if start_qn < qn_end and end_qn > qn_start then
                return true 
              end 
            end 
          end
          ::continue_area::
        end
      end
    end 
  end
end

function delete_midi_notes_in_razor()
  for tr = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, tr)
    local _, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    local _, _    = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
    if area == "" then return end

    local areas = {}
    local tokens = {}
    for token in area:gmatch("(%S+)") do
        table.insert(tokens, token)
    end

    for i = 1, #tokens - 2, 3 do
        local start_pos = tonumber(tokens[i])
        local end_pos = tonumber(tokens[i+1])
        local zone_type = tokens[i+2]

        if zone_type == '""' then  -- только медиа-зоны
            table.insert(areas, {start_pos, end_pos})
        end
    end

    local item_count = reaper.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local take = reaper.GetActiveTake(item)
      if take and reaper.TakeIsMIDI(take) then
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = item_pos + item_len

        for _, area in ipairs(areas) do
            local r_start = math.max(area[1], item_pos)
            local r_end = math.min(area[2], item_end)
            
            if r_start < r_end then
              delete = 0
              local qn_start = reaper.TimeMap2_timeToQN(0, r_start)
              local qn_end = reaper.TimeMap2_timeToQN(0, r_end)

              reaper.MIDI_DisableSort(take)
              local _, note_count = reaper.MIDI_CountEvts(take)
              for n = note_count - 1, 0, -1 do
                  local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n)
                  local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, startppq)
                  local end_qn = reaper.MIDI_GetProjQNFromPPQPos(take, endppq)

                  if start_qn < qn_end and end_qn > qn_start then
                      delete = delete + 1
                      -- Нота частично или полностью пересекается с Razor Edit
                      if start_qn >= qn_start and end_qn <= qn_end then
                          -- Полностью внутри — удалить
                          reaper.MIDI_DeleteNote(take, n)
                      elseif start_qn < qn_start and end_qn > qn_start and end_qn <= qn_end then
                          -- Конец внутри Razor Edit — обрезать конец
                          local new_end_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn_start)
                          reaper.MIDI_SetNote(take, n, nil, nil, startppq, new_end_ppq, nil, nil, nil, false)
                      elseif start_qn >= qn_start and start_qn < qn_end and end_qn > qn_end then
                          -- Начало внутри — обрезать начало
                          local new_start_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn_end)
                          reaper.MIDI_SetNote(take, n, nil, nil, new_start_ppq, endppq, nil, nil, nil, false)
                      elseif start_qn < qn_start and end_qn > qn_end then
                          -- Нота охватывает весь Razor Edit — разрезать на две (или обрезать одну часть)
                          local new_end_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn_start)
                          local new_start_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn_end)
                          -- Укорачиваем исходную до начала Razor Edit
                          reaper.MIDI_SetNote(take, n, nil, nil, startppq, new_end_ppq, nil, nil, nil, false)
                          -- Добавляем новую ноту после Razor Edit (если нужно сохранить обе части)
                          reaper.MIDI_InsertNote(take, false, false, new_start_ppq, endppq, chan, pitch, vel, false)
                      end
                  end

                end
                reaper.MIDI_Sort(take)
                reaper.MarkTrackItemsDirty(track, item)
                reaper.UpdateItemInProject(item)

            end
        end
      end
    end
  end
end


function get_envs(track)
    local _, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if area ~= "" then
      local arStart, arEnv
      for str in area:gmatch("(%S+)") do
        if not arStart then arStart = str
        elseif not arEnv then arEnv = str
        else
          if str ~= '""' then
            env_cnt = env_cnt + 1
            envs[env_cnt] = { reaper.GetTrackEnvelopeByChunkName( track, str:sub(2,-1) ),
                          tonumber(arStart), tonumber(arEnv) }
          end
          arStart, arEnv = nil, nil
        end
      end
    end
    return envs, env_cnt
  end
  

function main()
    master = reaper.GetMasterTrack(0)
    local _, master_area = reaper.GetSetMediaTrackInfo_String(master, "P_RAZOREDITS", "", false)
    master_envs,master_env_cnt = get_envs(master)

    for tr = 0, track_cnt - 1 do
        local track = reaper.GetTrack(0, tr)
        envs, env_cnt = get_envs(track)
    end

    if env_cnt == 0 then return reaper.defer(function() end) end

    for e = 1, env_cnt do
        reaper.DeleteEnvelopePointRange( envs[e][1] , envs[e][2] , envs[e][3]  )
        a_items = reaper.CountAutomationItems(envs[e][1])
        if a_items > 0 then 
            for i=1, a_items do 
                a_st = reaper.GetSetAutomationItemInfo( envs[e][1], i-1, 'D_POSITION', 0, false )
                a_len = reaper.GetSetAutomationItemInfo( envs[e][1], i-1, 'D_LENGTH'  , 0, false )
                a_end = a_st + a_len
                if envs[e][2] >= a_st and envs[e][2] <= a_end or envs[e][3] >= a_st and envs[e][2] <= a_end then 
                    reaper.Main_OnCommand(40312,0)
                end 
            end 
        end 

    end

end
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh( 1 )

local window, segment, details = reaper.BR_GetMouseCursorContext()
if details == 'item' then 
  if reaper.TakeIsMIDI(reaper.BR_GetMouseCursorContext_Take()) then mode = 'midi' end 
end
if segment == 'envelope' then mode = 'envelope' end


if mode == 'envelope' then 
  main()
  reaper.Main_OnCommand(42406,0)
elseif mode == 'midi' then 
  if check_if_notes() == true then 
    delete_midi_notes_in_razor()
    -- print('da')
  else 
    reaper.Main_OnCommand(40312,0)
  end
else
  main()
  reaper.Main_OnCommand(40312,0)
  main()
end

reaper.PreventUIRefresh( -1 )
reaper.UpdateArrange()
reaper.Undo_EndBlock( "Remove content or points in razor edit area", 1 )
