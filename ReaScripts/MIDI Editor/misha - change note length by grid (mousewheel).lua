-- @description Adjust note lenght by grid with mousewheel
-- @author misha
-- @version 1.0
-- @about Adjust note lenght by grid with mousewheel
  

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

local is_new_value,filename,sectionID,cmdID,mode,resolution,wheel = reaper.get_action_context()

incr = 50

if wheel > 0 then VAL = incr else VAL = -incr end

midieditor = reaper.MIDIEditor_GetActive()
if not midieditor then  return end
cur_take = reaper.MIDIEditor_GetTake(midieditor)
if not cur_take then return end

local notes,_,_ = reaper.MIDI_CountEvts(cur_take)
found = false
for i = 0, notes - 1 do
    local retval,sel,mute,startppqpos,endppqpos,chan,pitch,vel = reaper.MIDI_GetNote(cur_take,i)
    if sel then
        found = true
        -- reaper.MIDI_SetNote(cur_take,i,sel,mute,startppqpos+VAL,endppqpos+VAL,chan,pitch,vel,true)
    end
end


if found then 
    if wheel > 0 then 
        reaper.MIDIEditor_OnCommand(midieditor, 40446)
    else 
        reaper.MIDIEditor_OnCommand(midieditor, 40447)
    end
end

reaper.defer(function() end)