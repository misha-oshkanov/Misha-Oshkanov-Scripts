-- @description Create master fade-in and Fade-out from regions
-- @author Misha Oshkanov
-- @version 1.1
-- @about
--  Creates fade-in and fade-out on master track using regions named Fade-in and Fade-out.
--  Script will remove all points on master track volume envelope before adding fades
--
--  Cоздает фэйды на мастер треке, используя границы регионов с названиями Fade-in и Fade-out
--  Скрипт удалит все точки с огибающей громкости на мастере перед созданием фэйдов

USE_RENDER_FADES = true
fade_in_name  = 'Fade-in'
fade_out_name = 'Fade-out'
-------------------------------------
remove_all_points_on_start = true

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


function save_selected_tracks()
    tracks = {}
    local count_sel_tracks = reaper.CountSelectedTracks(0)
    if count_sel_tracks > 0 then 
        for t=0,count_sel_tracks-1 do 
            local track = reaper.GetSelectedTrack(0, t)
            table.insert(tracks, track)
        end 
        return tracks
    else return nil end
end 


function recall_selected_tracks(tracks)
    for track=1, #tracks do 
        reaper.SetTrackSelected(track, true)
    end
end 

function remove_all_points_on_start()
    reaper.DeleteEnvelopePointRange(envelope, 0, reaper.GetProjectLength(0))
end

function add_fade_in(start_time,end_time)
    reaper.DeleteEnvelopePointRange(envelope, start_time-0.01, end_time)
    retval, value, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate(envelope, end_time, 0, 0 )
    reaper.InsertEnvelopePoint(envelope, start_time, 0, 0, 0, false, true)
    reaper.InsertEnvelopePoint(envelope, start_time-0.005, value,  0, 0, false, true)
    reaper.InsertEnvelopePoint(envelope, end_time, value,  0, 0, false, true)
    reaper.Envelope_SortPoints(envelope)
end 


function add_fade_out(start_time,end_time)
    reaper.DeleteEnvelopePointRange(envelope, start_time, end_time+0.01)
    retval, value, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate(envelope, start_time, 0, 0 )
    reaper.InsertEnvelopePoint(envelope, start_time, value,  0, 0, false, true)
    reaper.InsertEnvelopePoint(envelope, end_time+0.005, value,  0, 0, false, true)
    reaper.InsertEnvelopePoint(envelope, end_time, 0, 0, 0, false, true)
    reaper.Envelope_SortPoints(envelope)
end

reaper.Undo_BeginBlock()

master = reaper.GetMasterTrack(0)
envelope = reaper.GetTrackEnvelopeByName(master, 'Volume')
if envelope == nil then 
    reaper.SetOnlyTrackSelected(master)
    reaper.SetTrackSelected( master, false )
    reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_SELMASTER'), 0)
    reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_SHOWMASTER'), 0)

    reaper.Main_OnCommand(40406, 0)
    envelope = reaper.GetTrackEnvelopeByName(master, 'Volume')
end

if remove_all_points_on_start then 
    remove_all_points_on_start()
end

all, _, num_regions = reaper.CountProjectMarkers(0)
for i=0, all do
    _, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
    if isrgn then 
        if USE_RENDER_FADES then 
            reaper.GetSetProjectInfo(0, 'RENDER_NORMALIZE',  1542, 1)
            if name == fade_in_name  then
                reaper.GetSetProjectInfo(0, 'RENDER_FADEIN',  rgnend-pos, 1 )
            end
            if name == fade_out_name then
                reaper.GetSetProjectInfo(0, 'RENDER_FADEOUT', rgnend-pos, 1 )
            end
        else 
            if name == fade_in_name  then add_fade_in(pos,rgnend)  end
            if name == fade_out_name then add_fade_out(pos,rgnend) end
        end
    end
end 
reaper.Undo_EndBlock( 'Add master fades', -1 )