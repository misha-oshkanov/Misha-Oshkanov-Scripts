-- @description Nudge selected notes a bit with mousewheel
-- @author misha
-- @version 1.0
-- @provides [midi_editor]
-- @about Nudge selected notes a bit with mousewheel

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

local is_new_value,filename,sectionID,cmdID,mode,resolution,wheel = reaper.get_action_context()

incr = 20

midieditor = reaper.MIDIEditor_GetActive()

if not midieditor then  return end
cur_take = reaper.MIDIEditor_GetTake(midieditor)
if not cur_take then return end

gr, swing, noteLen = reaper.MIDI_GetGrid(cur_take)

if wheel > 0 then VAL = incr*gr else VAL = -incr*gr end

local notes,_,_ = reaper.MIDI_CountEvts(cur_take)
for i = 0, notes - 1 do
    local retval,sel,mute,startppqpos,endppqpos,chan,pitch,vel = reaper.MIDI_GetNote(cur_take,i)
    if sel then
        found = true
        reaper.MIDI_SetNote(cur_take,i,sel,mute,startppqpos+VAL,endppqpos+VAL,chan,pitch,vel,true)
    end
end

reaper.defer(function() end)
