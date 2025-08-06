-- @description Smart nudge volume up. Works on tracks and automation items via selection, items and envelopes via razor or selection
-- @author Misha Oshkanov
-- @version 1.3
-- @about
----    Smart nudge volume up.
----    Via selection:
----        1. track volume (track volume changes are in priority)
----        2. envelope items
----        3. envelope points
----    Via razor edit:
----        1. item volume
-----       2. envelope segments

add = 0.5 --amount to nudge
fx_env_steps = 60 -- divide fx range in this amount of steps, one press is one step

----------------------------------------------------------------
----------------------------------------------------------------

retval, desc = reaper.GetAudioDeviceInfo( 'SRATE' )
samplerate = tonumber(desc)

function print(msg) if msg == nil then msg = 'da' end reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

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

function name(track)  retval, buf = reaper.GetTrackName(track) print(buf) end

function db2val(db)
  local LN10_OVER_TWENTY = 0.11512925464970228420089957273422
  return math.exp(db*LN10_OVER_TWENTY) 
end

function val2db(val)
  if val < 0.0000000298023223876953125 then
    return -150
  else
    return math.max(-150, math.log(val)* 8.6858896380650365530225783783321)
  end
end
  
mode = nil
razors = {}
count_tracks = reaper.CountTracks(0)

if count_tracks > 0 then 
    mode = "tr"
    for i=0,count_tracks-1 do
        track = reaper.GetTrack(0, i)
        local _, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
      
        if area ~= "" then
            rz = {}
            row = 0
            for str in area:gmatch("(%S+)") do
                row = row + 1
                if row == 1 then rz.start_time = tonumber(str) 
                elseif row == 2 then rz.end_time = tonumber(str)
                elseif row == 3 then 
                    if string.len(str) > 2 then  
                        mode = 'rz_env'
                        rz.env = str 
                        row = 0
                    else mode = 'rz_item' end
                    table.insert(razors,rz)
                    rz = {}
                end
            end
            -- if (rz.start_time > ai_start and rz.start_time < ai_end) and rz.end_time > ai_start and rz.end_time < ai_end then 
            -- end
            for ir,rz in ipairs(razors) do      
                items_tocut = {}
                for i=0,reaper.CountTrackMediaItems(track)-1 do 
                    nocut = false
                    item = reaper.GetTrackMediaItem(track, i)
                    itc = {}
                    item_start = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
                    item_end   = item_start + reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
                    item_afadeout  = reaper.GetMediaItemInfo_Value(item, 'D_FADEOUTLEN_AUTO')
                    item_afadein   = reaper.GetMediaItemInfo_Value(item, 'D_FADEINLEN_AUTO')

                    -- if (rz.start_time >= item_start and rz.start_time <= item_end) or (rz.end_time >= item_start and  rz.end_time <= item_end) then 
                        if item_end == rz.start_time + item_afadeout or item_start == rz.end_time - item_afadein then 
                            nocut = true
                        elseif item_start >= rz.start_time and item_end <= rz.end_time and mode == 'rz_item' then
                            reaper.SetMediaItemInfo_Value(item, 'D_VOL', db2val(val2db(reaper.GetMediaItemInfo_Value( item, 'D_VOL'))+add) )
                        end
                        if not nocut then 
                            if item_start < rz.start_time and item_end > rz.end_time then                     
                                itc.item = item 
                                itc.mode = 'both'
                                table.insert(items_tocut, itc)
                            elseif item_start > rz.start_time and item_start < rz.end_time and item_end > rz.end_time then 
                                itc.item = item 
                                itc.mode = 'right'
                                table.insert(items_tocut, itc)
                            elseif item_start < rz.start_time and item_end < rz.end_time and item_start < rz.end_time and item_end > rz.start_time then
                                itc.item = item 
                                itc.mode = 'left'
                                table.insert(items_tocut, itc)
                            end
                        end
                        
                        -- if item_start >= rz.start_time and item_end <= rz.end_time and mode == 'rz_item' then
                        --     reaper.SetMediaItemInfo_Value(item, 'D_VOL', db2val(val2db(reaper.GetMediaItemInfo_Value( item, 'D_VOL'))+add) )
                        -- end
                    -- end
                end  
                if mode == 'rz_item' then
                    for _, cut_item in ipairs(items_tocut) do 
                        item_afadeout  = reaper.GetMediaItemInfo_Value(cut_item.item, 'D_FADEOUTLEN_AUTO')
                        item_afadein   = reaper.GetMediaItemInfo_Value(cut_item.item, 'D_FADEINLEN_AUTO')
                        if cut_item.mode == 'left' then 
                            split_item = reaper.SplitMediaItem(cut_item.item, rz.start_time)
                            -- reaper.SplitMediaItem(split_item, rz.end_time)
                            reaper.SetMediaItemInfo_Value(split_item, 'D_VOL', db2val(val2db(reaper.GetMediaItemInfo_Value(cut_item.item, 'D_VOL'))+add) )
                        elseif cut_item.mode == 'right' then 
                            split_item = reaper.SplitMediaItem(cut_item.item, rz.end_time-item_afadeout)
                            -- reaper.SplitMediaItem(split_item, rz.end_time)
                            reaper.SetMediaItemInfo_Value(split_item, 'D_VOL', db2val(val2db(reaper.GetMediaItemInfo_Value(cut_item.item, 'D_VOL'))+add) )
                        elseif cut_item.mode == 'both' then 
                            split_item = reaper.SplitMediaItem(cut_item.item, rz.start_time)
                            split_afadein   = reaper.GetMediaItemInfo_Value(split_item, 'D_FADEINLEN_AUTO')
                            reaper.SplitMediaItem(split_item, rz.end_time-split_afadein)
                            reaper.UpdateArrange()

                            reaper.SetMediaItemInfo_Value(split_item, 'D_VOL', db2val(val2db(reaper.GetMediaItemInfo_Value(cut_item.item, 'D_VOL'))+add) )
                        end
                    end
                end

                if mode == 'rz_env' then 
                    env = reaper.GetTrackEnvelopeByChunkName(track, string.sub( rz.env, 2,-2 ))
                    if env then
                        count_aitems = reaper.CountAutomationItems(env)
                        ai = -1
                        for a=0,count_aitems-1 do 
                            ai_sel   = reaper.GetSetAutomationItemInfo(env, a, 'D_UISEL',    0, false)
                            ai_start = reaper.GetSetAutomationItemInfo(env, a, 'D_POSITION', 0, false)
                            ai_end   = ai_start + reaper.GetSetAutomationItemInfo(env, a, 'D_LENGTH',   0, false)
                            if (rz.start_time > ai_start and rz.start_time < ai_end) and (rz.end_time > ai_start and rz.end_time < ai_end) then 
                                ai = a
                            end
                        end

                        scaling = reaper.GetEnvelopeScalingMode(env)
                        br_env = reaper.BR_EnvAlloc(env, false)
                        active, visible, armed, _, _, _, min_val, max_val, center_val, env_type, faderScaling, ai_options = reaper.BR_EnvGetProperties(br_env)
                        range = max_val - min_val
                        step = range/fx_env_steps

                        local _, start_value, start_dVdS, start_ddVdS, start_dddVdS = reaper.Envelope_Evaluate(env, rz.start_time, samplerate, 0 )
                        local _, end_value, end_dVdS, end_ddVdS, end_dddVdS   = reaper.Envelope_Evaluate(env, rz.end_time,   samplerate, 0 )

                        -- _, start_time, _, _, _, _ = reaper.GetEnvelopePoint(env, reaper.GetEnvelopePointByTime(env, rz.start_time))

                        _, start_time, s_value, s_shape, s_tension, s_sel = reaper.GetEnvelopePointEx(env, ai, reaper.GetEnvelopePointByTimeEx(env, ai, rz.start_time))
                        _, end_time, e_value, e_shape, e_tension, e_sel = reaper.GetEnvelopePointEx(env, ai, reaper.GetEnvelopePointByTimeEx(env, ai, rz.end_time))

                        if not (start_time == rz.start_time) then
                            -- reaper.InsertEnvelopePoint(env, rz.start_time, start_value, 0, 1, 0, true )
                            reaper.InsertEnvelopePointEx(env, ai, rz.start_time, start_value, 0, 1, 0, true )
                            reaper.InsertEnvelopePointEx(env, ai, rz.start_time - 0.03, start_value, 0, 1, 0, true )
                            reaper.Envelope_SortPointsEx(env, ai)
                        end

                        if not (end_time == rz.end_time) then
                            reaper.InsertEnvelopePointEx(env, ai, rz.end_time, end_value, 0, 1, 0, true )
                            reaper.InsertEnvelopePointEx(env, ai, rz.end_time + 0.03, end_value, 0, 1, 0, true )
                            reaper.Envelope_SortPointsEx(env, ai)
                        end 

                        for p=0,reaper.CountEnvelopePointsEx(env,ai)-1 do 
                            retval, time, value, shape, tension, selected = reaper.GetEnvelopePointEx(env, ai, p)
                            
                            if env_type <= 1 and (time >= rz.start_time and time <= rz.end_time) then 
                                value = val2db(reaper.ScaleFromEnvelopeMode(scaling, value),3)
                                value = value + add
                                value = reaper.ScaleToEnvelopeMode(scaling, db2val(value))
                                reaper.SetEnvelopePointEx(env, ai, p, time, value, shape, tension, selected, true )
                            end 
                            if env_type >1 and (time >= rz.start_time and time <= rz.end_time) then 
                                value = value + step
                                value = math.min(value,max_val)
                                reaper.SetEnvelopePointEx(env, ai, p, time, value, shape, tension, selected, true )
                            end
                        end
                        reaper.Envelope_SortPointsEx(env, ai)
                    end
                end
            end

        end
        count_env = reaper.CountTrackEnvelopes(track)
        if count_env > 0 then 
            for e=0,count_env-1 do 
                env = reaper.GetTrackEnvelope(track, e)
                if env then 
                    scaling = reaper.GetEnvelopeScalingMode(env)
                    br_env = reaper.BR_EnvAlloc(env, false)
                    active, visible, armed, _, _, _, min_val, max_val, center_val, env_type, faderScaling, ai_options = reaper.BR_EnvGetProperties(br_env)
                    
                    range = max_val - min_val
                    step = range/fx_env_steps
                    if visible then 
                        count_aitems = reaper.CountAutomationItems(env)

                        for a=0,count_aitems-1 do 
                            ai_sel   = reaper.GetSetAutomationItemInfo(env, a, 'D_UISEL',    0, false)
                            ai_start = reaper.GetSetAutomationItemInfo(env, a, 'D_POSITION', 0, false)
                            ai_end   = ai_start + reaper.GetSetAutomationItemInfo(env, a, 'D_LENGTH',   0, false)

                            if ai_sel == 1 then 
                                mode = 'ai' 
                                count_points = reaper.CountEnvelopePointsEx(env, a) --- 0x10000000
                                for p=0,count_points-1 do 
                                    retval, time, value, shape, tension, selected = reaper.GetEnvelopePointEx(env, a, p)
                                    if env_type <=1 then 
                                        value = val2db(reaper.ScaleFromEnvelopeMode(scaling, value),3)
                                        value = value + add
                                        value = reaper.ScaleToEnvelopeMode(scaling, db2val(value))
                                        reaper.SetEnvelopePointEx(env, a, p, time, value,  nil, nil, nil, true)
                                    end 
                                    if env_type >1 then 
                                        value = value + step
                                        value = math.min(value,max_val)
                                        reaper.SetEnvelopePointEx(env, a, p, time, value,nil, nil, nil, true )
                                    end
                                end

                                reaper.Envelope_SortPointsEx(env, a)
                            end
                        end       

                        _, _, _ = reaper.BR_GetMouseCursorContext()
                        mouse_pos = reaper.BR_GetMouseCursorContext_Position()
                        mouse_env_track, _ = reaper.BR_GetMouseCursorContext_Envelope()

                        if mode ~= 'ai' and mouse_env_track == env then 
                            -- mode = 'env'
                            env = mouse_env_track
                            count_aitems = reaper.CountAutomationItems(env)
                            ai = -1
                            for a=0,count_aitems-1 do 
                                ai_sel   = reaper.GetSetAutomationItemInfo(env, a, 'D_UISEL',    0, false)
                                ai_start = reaper.GetSetAutomationItemInfo(env, a, 'D_POSITION', 0, false)
                                ai_end   = ai_start + reaper.GetSetAutomationItemInfo(env, a, 'D_LENGTH',   0, false)
                                if ai_start < mouse_pos and ai_end > mouse_pos then 
                                    ai = a
                                end
                            end

                            for p=0,reaper.CountEnvelopePointsEx(env,ai)-1 do 
                                retval, time, value, shape, tension, selected = reaper.GetEnvelopePointEx(env, ai, p)
                                if selected then  mode = 'env' end
                                if env_type <= 1 and selected then 
                                    value = val2db(reaper.ScaleFromEnvelopeMode(scaling, value),3)
                                    value = value + add
                                    value = reaper.ScaleToEnvelopeMode(scaling, db2val(value))
                                    reaper.SetEnvelopePointEx(env, ai, p, time, value, shape, tension, selected, true )
                                end 
                                if env_type >1 and selected then 
                                    value = value + step
                                    value = math.min(value,max_val)
                                    reaper.SetEnvelopePointEx(env, ai, p, time, value, shape, tension, selected, true )
                                end
                            end
                            reaper.Envelope_SortPointsEx(env, ai)
                        end

                    end
                    reaper.BR_EnvFree(br_env, true)
                end
            end
        end

       if mode == 'tr' then 
           if reaper.IsTrackSelected( track ) then reaper.SetTrackUIVolume(track, add, true, true, 0 ) break end
       end
    end
end