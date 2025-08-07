-- @description Auto gain fx chain for selected track using GainMatch
-- @author Misha Oshkanov
-- @version 1.1
-- @about
--  You need GainMatch plugin for this to work. Script will add instance of Gainmatch at the start and at the end of FX chain.


function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end


function set_fx_name(track, fx, new_name)
    if not new_name then return end
    local edited_line,edited_line_id, segm
    -- get ref guid
      if not track or not tonumber(fx) then return end
      local FX_GUID = reaper.TrackFX_GetFXGUID( track, fx )
      if not FX_GUID then return else FX_GUID = FX_GUID:gsub('-',''):sub(2,-2) end
      local plug_type = reaper.TrackFX_GetIOSize( track, fx )
    -- get chunk t
      local _, chunk = reaper.GetTrackStateChunk( track, '', false )
      local t = {} for line in chunk:gmatch("[^\r\n]+") do t[#t+1] = line end
    -- find edit line
      local search
      for i = #t, 1, -1 do
        local t_check = t[i]:gsub('-','')
        if t_check:find(FX_GUID) then search = true  end
        if t[i]:find('<') and search and not t[i]:find('JS_SER') then
          edited_line = t[i]:sub(2)
          edited_line_id = i
          break
        end
      end
    -- parse line
      if not edited_line then return end
      local t1 = {}
      for word in edited_line:gmatch('[%S]+') do t1[#t1+1] = word end
      local t2 = {}
      for i = 1, #t1 do
        segm = t1[i]
        if not q then t2[#t2+1] = segm else t2[#t2] = t2[#t2]..' '..segm end
        if segm:find('"') and not segm:find('""') then if not q then q = true else q = nil end end
      end
  
      if plug_type == 2 then t2[3] = '"'..new_name..'"' end -- if JS
      if plug_type == 3 then t2[5] = '"'..new_name..'"' end -- if VST
  
      local out_line = table.concat(t2,' ')
      t[edited_line_id] = '<'..out_line
      local out_chunk = table.concat(t,'\n')
      --msg(out_chunk)
      reaper.SetTrackStateChunk( track, out_chunk, false )
      reaper.UpdateArrange()
end


fxname = 'VST3: GainMatch (LetiMix)'

count_tracks = reaper.CountSelectedTracks(0)
reaper.Undo_BeginBlock()

for i=1, count_tracks do 
    track = reaper.GetSelectedTrack(0, i-1)


    first_id = reaper.TrackFX_AddByName(track, fxname, false, -1000)
    reaper.TrackFX_Show(track, first_id, 2)
    set_fx_name(track,first_id,'- - -')
    count = reaper.TrackFX_GetCount(track)
    reaper.TrackFX_CopyToTrack(track, first_id, track, count, false)
    set_fx_name(track,count,'- GM -')
    reaper.TrackFX_Show(track, count, 3)

end

reaper.Undo_EndBlock('Gain Match', -1)