-- @description insert or open UI of FX plugin on selected tracks
-- @author Misha Oshkanov
-- @version 1.1
-- @about
--  use to add and open desired fx on tracks
--  1. If there is no fx on track, script will add new instance of fx
--  2. If there is instance of fx on track, script will open the UI of last fx in chain
--  3. if there is instance of fx and UI is open, script will add a new instance and open its UI
--  You can use this script as template for new scripts
-- @changelog
--   # do not open if fx is bypassed or wet is 0%


FX = 'ReaEQ' -- FX name (e.g 'VST3: Pro-Q 4')

---------------------------------------
---------------------------------------
---------------------------------------
reaper.Undo_BeginBlock()

function get_last_fx(track)
  local count_fx = reaper.TrackFX_GetCount(track)
  local FX = FX:lower()
  local insert_FX = FX:gsub('-','%%-')
  for fx=count_fx,0,-1 do 
    local retval, fx_name = reaper.TrackFX_GetFXName(track, fx)
    local wetparam = reaper.TrackFX_GetParamFromIdent(track, fx, ":wet" )
    local val = reaper.TrackFX_GetParam(track, fx, wetparam)
    -- print(val)
    fx_name = fx_name:lower()
    if fx_name:match(insert_FX) and reaper.TrackFX_GetEnabled(track, fx) and val>0 then return fx end
  end 
  return -1
end

track_id = 0
track_count = reaper.CountSelectedTracks(0)
while track_id < track_count do
  track = reaper.GetSelectedTrack(0, track_id)
  -- fx_on_track = reaper.TrackFX_AddByName(track, FX, false, 0)
  fx_on_track = get_last_fx(track)
  
  if fx_on_track ~= -1 then 
    is_open = reaper.TrackFX_GetOpen(track, fx_on_track)
    if not is_open then 
      reaper.TrackFX_SetOpen(track, fx_on_track, true)
    else
      reaper.TrackFX_SetOpen(track, fx_on_track, false)
      reaper.TrackFX_AddByName(track, FX, false, -1)
    end
  else 
    reaper.TrackFX_AddByName(track, FX, false, -1)
  end
  track_id =track_id+1
end

reaper.Undo_EndBlock("Insert FX: "..FX,-1)