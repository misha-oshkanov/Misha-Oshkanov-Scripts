-- @description Select all midi items in project at edit cursor
-- @author misha
-- @version 1.0
-- @about Select all midi items in project at edit cursor


function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end
-------------------------

usetrackcolors = false 

black_list = {"Drums", "FX"}

function check_names(depth, track)
    _, name = reaper.GetTrackName(track)
    if depth > 0 then
        for i=0,depth do 
            parent = reaper.GetParentTrack(track)
            _, parname = reaper.GetTrackName(parent)
            for v,k in pairs (black_list) do 
                if string.lower(parname) == string.lower(k) then return true end
            end 
        end
    end 
end

cursor = reaper.GetCursorPosition()
midieditor = reaper.MIDIEditor_GetActive()
if midieditor then 
    miditake = reaper.MIDIEditor_GetTake(midieditor)
    midiitem = reaper.GetMediaItemTake_Item(miditake)
    -- reaper.SetMediaItemSelected(midiitem,1)
end 
for i=1, reaper.CountMediaItems(0) do 
    item = reaper.GetMediaItem(0,i-1)
    take =  reaper.GetActiveTake(item)
    track = reaper.GetMediaItem_Track(item)
    depth = reaper.GetTrackDepth(track)
    if not check_names(depth, track) then 
        ismidi, inProjectMidi = reaper.BR_IsTakeMidi(take)
        isvisible = reaper.IsTrackVisible(track, 0)
        isselected = reaper.GetMediaItemInfo_Value(item, 'B_UISEL')

        pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        len = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        
        if item ~= midiitem then     
            if ismidi and isvisible then 
                if cursor >= pos and cursor <=pos+len then 
                    if isselected == 1 then 
                        if usetrackcolors then
                            reaper.MIDIEditor_OnCommand(midieditor,40740) --color by pitch
                        end
                        reaper.SetMediaItemSelected(item, 0)
                    elseif isselected == 0 then  
                        if usetrackcolors then
                            reaper.MIDIEditor_OnCommand(midieditor,40768) --color by track
                        end 
                        reaper.SetMediaItemSelected(item, 1)
                    end 
                end
            end
        end 
    end
end