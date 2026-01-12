-- @description Adjust midi notes of selected notes with mousewheel
-- @author mpl, misha
-- @version 1.0
-- @about Adjust midi notes of selected notes with mousewheel


  local VALUE = 5;

  VALUE = math.abs(VALUE);
  local cur_editor = reaper.MIDIEditor_GetActive();
  local is_new_value,filename,sectionID,cmdID,mode,resolution,val = reaper.get_action_context();
  if val < 0 then VALUE = VALUE-VALUE*2 end;
  if not cur_editor then return end;
  reaper.Undo_BeginBlock();
  local cur_take = reaper.MIDIEditor_GetTake(cur_editor);
  local _,_,_ = reaper.BR_GetMouseCursorContext();
  local _,_,noteRow,_,_,_ = reaper.BR_GetMouseCursorContext_MIDI();
  local mouse_time = reaper.BR_GetMouseCursorContext_Position();
  local mouse_ppq_pos = reaper.MIDI_GetPPQPosFromProjTime(cur_take,mouse_time);
  local notes,_,_ = reaper.MIDI_CountEvts(cur_take);
  for i = 0, notes - 1 do
    local retval,sel,mute,startppqpos,endppqpos,chan,pitch,vel = reaper.MIDI_GetNote(cur_take,i);
    --if startppqpos < mouse_ppq_pos and endppqpos > mouse_ppq_pos and noteRow == pitch then 
    if sel then
    vel2 = vel+VALUE;
    if vel2 <= 1 then vel2 = 1 end;
    if vel2 >= 127 then vel2 = 127 end;
    reaper.MIDI_SetNote(cur_take,i,sel,mute,startppqpos,endppqpos,chan,pitch,vel2,true);
    --break;
    end;
  end;
  reaper.UpdateArrange()
  
  reaper.MIDI_Sort(cur_take)
  reaper.Undo_EndBlock('Adjust selected notes velocity (mousewheel)', 4) 
