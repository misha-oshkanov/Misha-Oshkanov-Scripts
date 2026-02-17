-- @description Adds pairs of selected tracks in free group and activates inverted pan
-- @version 1.0
-- @about
--     Adds pairs of selected tracks in free group and activates inverted pan, applies pan based on track name (gtr L, vocal R40 and so on)

function Main()
    local sel_track_count = reaper.CountSelectedTracks(0)
    if sel_track_count < 2 then 
        reaper.ShowMessageBox("Выберите как минимум 2 трека", "Ошибка", 0)
        return 
    end

    reaper.Undo_BeginBlock()

    for i = 0, sel_track_count - 2, 2 do
        local track1 = reaper.GetSelectedTrack(0, i)
        local track2 = reaper.GetSelectedTrack(0, i + 1)

        -- 1. Поиск свободной группы (1-32)
        local group_idx = -1
        for g = 0, 31 do
            local mask = 1 << g
            local is_used = false
            for t = 0, reaper.CountTracks(0) - 1 do
                local tr = reaper.GetTrack(0, t)
                if (reaper.GetSetTrackGroupMembership(tr, "PAN_LEAD", 0, 0) & mask) ~= 0 then
                    is_used = true; break
                end
            end
            if not is_used then group_idx = g; break end
        end

        if group_idx ~= -1 then
            local mask = 1 << group_idx
            
            -- Группировка Pan Lead/Follow
            reaper.GetSetTrackGroupMembership(track1, "PAN_LEAD", mask, mask)
            reaper.GetSetTrackGroupMembership(track1, "PAN_FOLLOW", mask, mask)
            reaper.GetSetTrackGroupMembership(track2, "PAN_LEAD", mask, mask)
            reaper.GetSetTrackGroupMembership(track2, "PAN_FOLLOW", mask, mask)
            
            -- Инверсия панорамы для второго трека
            reaper.GetSetTrackGroupMembership(track2, "PAN_REVERSE", mask, mask)

            -- 2. Логика панорамы (строгий поиск в конце имени)
            local tracks = {track1, track2}
            for _, tr in ipairs(tracks) do
                local _, name = reaper.GetTrackName(tr)
                -- Регулярка: ищем пробел/тире/подчеркивание + L или R + цифры до конца строки $
                -- Примеры: "Gtr L30", "Piano-R", "Synth_L100"
                local side, val = name:upper():match("[%s_%-]([LR])(%d*)$")
                
                if side then
                    local num = tonumber(val) or 100
                    local pan_value = math.max(0, math.min(num, 100)) / 100
                    
                    if side == "L" then
                        reaper.SetMediaTrackInfo_Value(tr, "D_PAN", -pan_value)
                    else
                        reaper.SetMediaTrackInfo_Value(tr, "D_PAN", pan_value)
                    end
                end
            end
        end
    end

    reaper.Undo_EndBlock("Smart inverted pan grouping selected tracks", -1)
    reaper.TrackList_AdjustWindows(false)
end

Main()