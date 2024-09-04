-- @description Master Bypass Manager
-- @author Misha Oshkanov
-- @version 1.3
-- @about
--  Manages bypass states of effects in master fx chain
--  use activate and deactivate toggle scripts to switch bypass states 

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

section = "INEED_BYPASS_MANAGER"

local value,ScriptWay,sec,cmd,mod,res,val = reaper.get_action_context()

reaper.Undo_BeginBlock() 
reaper.PreventUIRefresh(1)  

track = reaper.GetMasterTrack(0)
count_fx = reaper.TrackFX_GetCount(track)


r, state = reaper.GetProjExtState(0, 'INEED_BYPASS_STATE', 'STATE')

if state == '1' then 
    -- print('0')
    reaper.SetProjExtState(0, 'INEED_BYPASS_STATE', 'STATE', '0')

    i=-1
    enum, key, val = reaper.EnumProjExtState(0, section, 0)
    while enum ~= false do
        i = i + 1
        enum, key, val = reaper.EnumProjExtState(0, section, i)
        for i=1,count_fx do 
            guid = reaper.TrackFX_GetFXGUID(track, i-1)
            if key == guid and val:find('1') then 
                if val:find('b') then 
                    reaper.TrackFX_SetEnabled(track, i-1, false)
                elseif val:find('a') then 
                    reaper.TrackFX_SetEnabled(track, i-1, true)
                end
            end
        end
    end
    
end


reaper.PreventUIRefresh(-1) 

reaper.UpdateArrange()
reaper.Undo_EndBlock('Bypass Manager - deactivate toggle', -1)