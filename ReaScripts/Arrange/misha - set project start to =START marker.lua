-- @description Set project start to =START marker
-- @author misha
-- @version 1.0
-- @about Set project start to =START marker


function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

count, num_markers, num_regions = reaper.CountProjectMarkers(proj)

local sws_exist = reaper.APIExists("SNM_SetDoubleConfigVar")
if sws_exist then
  for i=0, count-1 do 
    retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers(i)
    if not isrgn and name == '=START' then 
      _, measures, _, _, _ = reaper.TimeMap2_timeToBeats(0, pos)

      reaper.SNM_SetDoubleConfigVar("projtimeoffs", -pos)
      reaper.SNM_SetIntConfigVar("projmeasoffs", -(measures+1))

      reaper.UpdateTimeline()
      return
    end
  end
else
  reaper.ShowConsoleMsg("This script requires the SWS extension for REAPER. Please install it and try again.")
end