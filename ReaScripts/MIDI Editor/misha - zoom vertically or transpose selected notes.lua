-- @description Zoom vertically or transpose selected notes with mousewheel
-- @author misha
-- @version 1.0
-- @provides [midi_editor]
-- @about Nudge selected notes a bit with mousewheel

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

local is_new_value,filename,sectionID,cmdID,mode,resolution,wheel = reaper.get_action_context()
if wheel > 0 then VAL = 1 else VAL = -1 end

midieditor = reaper.MIDIEditor_GetActive()

cur_take = reaper.MIDIEditor_GetTake(midieditor)
local notes,_,_ = reaper.MIDI_CountEvts(cur_take)

reaper.Undo_BeginBlock()

found = false
for i = 0, notes - 1 do
    local retval,sel,mute,startppqpos,endppqpos,chan,pitch,vel = reaper.MIDI_GetNote(cur_take,i)
    if sel then
        found = true
    end
end

reaper.MIDI_Sort(cur_take)

if not found then 
    if VAL == 1 then 
        reaper.MIDIEditor_OnCommand(midieditor, 40111) -- zoom in
        reaper.MIDIEditor_OnCommand(midieditor, 40111) -- zoom in
    else 
        reaper.MIDIEditor_OnCommand(midieditor, 40112) -- zoom out
        reaper.MIDIEditor_OnCommand(midieditor, 40112) -- zoom out
    end
else 
    if VAL == 1 then 
        reaper.MIDIEditor_OnCommand(midieditor, 40177) -- up
    else 
        reaper.MIDIEditor_OnCommand(midieditor, 40178) -- down
    end
end 

reaper.defer(function() end)