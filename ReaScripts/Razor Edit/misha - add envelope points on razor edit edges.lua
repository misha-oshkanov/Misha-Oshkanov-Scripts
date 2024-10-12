-- @description Add envelope points on razor edit edges
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  Use to add 4 points on razor edit area edge added to envelope.



function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

slope = 4
envs, env_cnt = {}, 0

local track_cnt = reaper.CountTracks(0)
if track_cnt == 0 then return reaper.defer(function() end) end

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


function set_points()
  master = reaper.GetMasterTrack(0)
  local _, master_area = reaper.GetSetMediaTrackInfo_String(master, "P_RAZOREDITS", "", false)
  master_envs,master_env_cnt = get_envs(master)

  for tr = 0, track_cnt - 1 do
    local track = reaper.GetTrack(0, tr)
    envs, env_cnt = get_envs(track)
  end

  if env_cnt == 0 then return reaper.defer(function() end) end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh( 1 )

  mouse = reaper.BR_PositionAtMouseCursor( 1 )
  _, samplerate = reaper.GetAudioDeviceInfo('SRATE')


  for e = 1, env_cnt do
      local envelope   = envs[e][1]
      local env_start  = envs[e][2]
      local env_end    = envs[e][3]

      local _, start_value = reaper.Envelope_Evaluate( envelope, env_start, tonumber(samplerate), 0 )
      local _, end_value = reaper.Envelope_Evaluate( envelope, env_end, tonumber(samplerate), 0 )

      offset = 60/(reaper.TimeMap_GetDividedBpmAtTime(env_start))/(4+slope)

      reaper.InsertEnvelopePoint( envelope, env_start, start_value, 0, 1, 0, true )
      reaper.InsertEnvelopePoint( envelope, env_start - offset, start_value, 0, 1, 0, true )

      reaper.InsertEnvelopePoint( envelope, env_end, end_value, 0, 1, 0, true )
      reaper.InsertEnvelopePoint( envelope, env_end + offset, end_value, 0, 1, 0, true )

      reaper.Envelope_SortPoints( envelope )
  end
end

local window, segment, details = reaper.BR_GetMouseCursorContext()
if segment == 'envelope' then 
  set_points()
else
  reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_SMARTSPLIT2'),0)
end

reaper.Main_OnCommand (42406,0)

reaper.PreventUIRefresh( -1 )
reaper.UpdateArrange()

reaper.Undo_EndBlock( "Add points", 1 )