-- @description Monitor Volume Controller Shortcut - next ref solo
-- @author Misha Oshkanov
-- @version 0.1
-- @about
--  Action to solo of nex ref track

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

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


ref_data = {}
solos = {}

REF_FOLDER_NAME = reaper.GetExtState( 'MISHA_MONITOR', 'REF_FOLDER')

master = reaper.GetMasterTrack()

function get_children_refs(parent)
    if parent then 
      local parentdepth = reaper.GetTrackDepth(parent)
      local parentnumber = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
      local children = {}
      for i=parentnumber, reaper.CountTracks(0)-1 do
        local data = {}
        local track = reaper.GetTrack(0,i)
        local depth = reaper.GetTrackDepth(track)
        local color = reaper.GetTrackColor(track)
        local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO') ~= 0
        local mute = reaper.GetMediaTrackInfo_Value(track, 'B_MUTE')

        local _, name = reaper.GetTrackName(track)

        data.track = track
        data.solo = solo 
        data.name = name 
        
        if depth > parentdepth then
            if mute == 0 then reaper.SetMediaTrackInfo_Value(track, 'B_MUTE', 1) end
            table.insert(children, data)
        else
            break
        end
      end
      return children
    end
end

function save_solos()
    solos = {}
    local count = reaper.CountTracks(0)
    for k,v in ipairs(ref_data) do 
        if v.solo then 
        is_ref_soloed = true
        end 
    end
    if not is_ref_soloed then solos = {} end
    for i=0,count-1 do 
        local track = reaper.GetTrack(0, i) 
        local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO')
        if solo > 0 then 
            is_ref = false
            is_ref_soloed = false 
            for k,v in ipairs(ref_data) do 
                if v.track == track then 
                    is_ref = true
                end 
            end
            if not is_ref then 
                local data = {}
                data.solo = solo 
                data.track = track 
                table.insert(solos, data)
            end 
        end
    end 
end 

function write_solos_to_ext()
    local parts = {}
    for i, v in ipairs(solos) do
        local guid = reaper.GetTrackGUID(v.track)
        parts[#parts+1] = string.format("%d:%s:%.1f", i, guid, v.solo)
    end
    local str = table.concat(parts, "|")
    reaper.SetProjExtState(0, "MISHA_MONITOR", "SOLOS", str)
end

function load_solos_from_ext()
    local _, str = reaper.GetProjExtState(0, "MISHA_MONITOR", "SOLOS")
    local t = {}
    for item in str:gmatch("[^|]+") do
        local i, guid, solo = item:match("(%d+):({.*}):([%d%.]+)")
        local track = reaper.BR_GetMediaTrackByGUID(0, guid)
        t[#t+1] = { track = track, solo = tonumber(solo)}
    end
    return t
end

function unsolo_all_tracks()
  local count = reaper.CountTracks(0)
  for i=0,count-1 do 
    local track = reaper.GetTrack(0, i) 
    local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO')
    if solo > 0 then 
      reaper.SetMediaTrackInfo_Value(track, 'I_SOLO',0)
    end  
  end 
end 

function restore_solos()
  unsolo_all_tracks()
  if #solos < 0 then return end  
  for k,v in ipairs(solos) do 
      reaper.SetMediaTrackInfo_Value(v.track, 'I_SOLO',v.solo)
  end
end 

ref_solo_is_active = false
function get_children_refs(parent)
    if parent then 
      local parentdepth = reaper.GetTrackDepth(parent)
      local parentnumber = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
      local children = {}
      for i=parentnumber, reaper.CountTracks(0)-1 do
        local data = {}
        local track = reaper.GetTrack(0,i)
        local depth = reaper.GetTrackDepth(track)
        local color = reaper.GetTrackColor(track)
        local solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO') ~= 0
        local mute = reaper.GetMediaTrackInfo_Value(track, 'B_MUTE')

        if solo then ref_solo_is_active = true end 

        local _, name = reaper.GetTrackName(track)

        data.track = track
        data.solo = solo 
        data.name = name
        
        if depth > parentdepth then
            if mute == 0 then reaper.SetMediaTrackInfo_Value(track, 'B_MUTE', 1) end
            table.insert(children, data)
        else
            break
        end
      end
      return children
    end
end


local count = reaper.CountTracks(0)
for i=0,count-1 do 
    local track = reaper.GetTrack(0, i) 
    local _, name = reaper.GetTrackName(track)
    if name == REF_FOLDER_NAME then 
        ref_data = get_children_refs(track)
        break
    end
end

if ref_solo_is_active then 
    for k,ref in ipairs(ref_data) do 
        if ref.solo then 
            if k == #ref_data then 
            next_index = 1
            else
                next_index = k + 1
            end
        end
    end
    unsolo_all_tracks()
    reaper.SetMediaTrackInfo_Value(ref_data[next_index].track, 'I_SOLO',2)
    reaper.SetProjExtState(0, 'MISHA_MONITOR', 'LAST_SOLO',reaper.GetTrackGUID(ref_data[next_index].track))
else
    _, LAST_SOLO = reaper.GetProjExtState(0, 'MISHA_MONITOR', 'LAST_SOLO')
    if LAST_SOLO ~= '' then
        solo_track = reaper.BR_GetMediaTrackByGUID(0, LAST_SOLO)
        is_soloed = reaper.GetMediaTrackInfo_Value(solo_track, "I_SOLO" ) == 2
        if is_soloed then
            for k,ref in ipairs(ref_data) do 
                if ref.solo and ref.track == solo_track then 
                    if k == #ref_data then 
                    next_index = 0
                    else
                        next_index = k + 1
                    end
                end
            end
            unsolo_all_tracks()
            reaper.SetMediaTrackInfo_Value(ref_data[next_index].track, 'I_SOLO',2)      
        else
            unsolo_all_tracks()
            reaper.SetMediaTrackInfo_Value(solo_track, 'I_SOLO',2)
        end
    end
end