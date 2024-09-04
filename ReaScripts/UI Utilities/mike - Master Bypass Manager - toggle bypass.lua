-- @description Master Bypass Manager
-- @author Misha Oshkanov
-- @version 1.3
-- @about
--  Manages bypass states of effects in master fx chain
--  use activate and deactivate toggle scripts to switch bypass states 

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end


section = "INEED_BYPASS_MANAGER"
-- reaper.gmem_attach("INEED_BM")


local value,ScriptWay,sec,cmd,mod,res,val = reaper.get_action_context()

reaper.Undo_BeginBlock() 
reaper.PreventUIRefresh(1)  

-- extstate = reaper.GetExtState( section, key )  
state = reaper.GetToggleCommandStateEx( sec, cmd )


function SetButtonState(numb)
    local value,ScriptWay,sec,cmd,mod,res,val = reaper.get_action_context();
    reaper.SetToggleCommandState(sec,cmd,numb or 0)
    reaper.RefreshToolbar2(sec,cmd)
end

track = reaper.GetMasterTrack(0)
count_fx = reaper.TrackFX_GetCount(track)

if state == 1 then 
    active = false
    reaper.SetProjExtState(0, 'INEED_BYPASS_STATE', 'STATE', '0')
    SetButtonState(0)
else 
    active = true
    -- reaper.gmem_write(1, 1)
    reaper.SetProjExtState(0, 'INEED_BYPASS_STATE', 'STATE', '1')
    SetButtonState(1)
end

i=-1
enum, key, val = reaper.EnumProjExtState(0, section, 0)
while enum ~= false do
    i = i + 1
    enum, key, val = reaper.EnumProjExtState(0, section, i)
    for i=1,count_fx do 
        guid = reaper.TrackFX_GetFXGUID(track, i-1)
        if key == guid and val:find('1') then 
            -- if active then 
                -- print('active')
                enabled = reaper.TrackFX_GetEnabled(track, i-1)
                reaper.TrackFX_SetEnabled(track, i-1, not enabled)
                -- reaper.TrackFX_SetEnabled(track, i-1, not val:find('a') == true and false or true)
            -- else
                -- print('not active')
                -- reaper.TrackFX_SetEnabled(track, i-1, not val:find('a') == true and true or false)
            -- end
        end
    end

end



reaper.PreventUIRefresh(-1) 

reaper.UpdateArrange()
reaper.Undo_EndBlock('Bypass Manager - toggle bypass', -1)