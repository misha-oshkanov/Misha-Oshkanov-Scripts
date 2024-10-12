-- @description Add envelope points on razor edit edges
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  Use to delete content within razor edit area(items, envelope points, automation items)



function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end


local track_cnt = reaper.CountTracks(0)
if track_cnt == 0 then return reaper.defer(function() end) end

envs, env_cnt = {}, 0

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
if segment == 'envelope' then 
  main()
  reaper.Main_OnCommand(42406,0)
else
  reaper.Main_OnCommand(40312,0)
end

reaper.PreventUIRefresh( -1 )
reaper.UpdateArrange()
reaper.Undo_EndBlock( "Remove content or points in razor edit area", 1 )