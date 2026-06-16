-- @description Render first FX to lane without affecting original track
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  Renders selected items through the first FX plugin to a new lane on the same track.
--  Bypasses all other FX and envelopes during rendering, then restores them.
--  Creates a colored rendered copy in a new fixed lane with original track settings preserved.
    


-- ADD_TAIL = false
TAIL = 5000

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


function table_contains(table, element)
    for _, value in pairs(table) do
      if value == element then
        return true
      end
    end
    return false
end

function rgba(r, g, b, a)
    b = b/255
    g = g/255 
    r = r/255 
    local b = math.floor(b * 255) * 256
    local g = math.floor(g * 255) * 256 * 256
    local r = math.floor(r * 255) * 256 * 256 * 256
    local a = math.floor(a * 255)
    return r + g + b + a
end

function col(col,a)
    r, g, b = reaper.ColorFromNative(col)
    result = rgba(r,g,b,a)
    return result
end

function get_children(parent)
    if parent then 
        local parentdepth = reaper.GetTrackDepth(parent)
        local parentnumber = reaper.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER")
        local children = {}
        for i=parentnumber, reaper.CountTracks(0)-1 do
                local track = reaper.GetTrack(0,i)
                local depth = reaper.GetTrackDepth(track)
                if depth > parentdepth then
                    table.insert(children, track)
                else
                    break
                end
        end
        return children
    end
end

function unselect_all_tracks()
    local count_tracks = reaper.CountTracks(0)
    for i = 0, count_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.IsTrackSelected(track) then 
            reaper.SetTrackSelected(track, 0)
        end
    end 
end

function save_render_settings()
    local S = {};
    S.RENDER_SETTINGS    = reaper.GetSetProjectInfo       (0,"RENDER_SETTINGS"    ,0,0)--Sourse
    S.RENDER_NORMALIZE   = reaper.GetSetProjectInfo       (0,"RENDER_NORMALIZE"    ,0,0)--Sourse

    S.RENDER_BOUNDSFLAG  = reaper.GetSetProjectInfo       (0,"RENDER_BOUNDSFLAG"  ,0,0)--Bounds
    S.RENDER_TAILFLAG    = reaper.GetSetProjectInfo       (0,"RENDER_TAILFLAG"    ,0,0)--Tail
    S.RENDER_TAILMS      = reaper.GetSetProjectInfo       (0,"RENDER_TAILMS"      ,0,0)--Tail ms
    S.RENDER_SRATE       = reaper.GetSetProjectInfo       (0,"RENDER_SRATE"       ,0,0)--Sample rate
    S.RENDER_CHANNELS    = reaper.GetSetProjectInfo       (0,"RENDER_CHANNELS"    ,0,0)--channels
    S.RENDER_ADDTOPROJ   = reaper.GetSetProjectInfo       (0,"RENDER_ADDTOPROJ"   ,0,0)--add rendered files to project
    
    S._,S.RENDER_FORMAT  = reaper.GetSetProjectInfo_String(0,"RENDER_FORMAT"      ,0,0)--render_format
    S._,S.RENDER_FORMAT2 = reaper.GetSetProjectInfo_String(0,"RENDER_FORMAT2"     ,0,0)--render_format2

    S._, S.RENDER_FILE   = reaper.GetSetProjectInfo_String(0,"RENDER_FILE"        ,0,0) -- render directory
    S._, S.RENDER_NAME   = reaper.GetSetProjectInfo_String(0,"RENDER_PATTERN",""    ,0)-- Render Name
    
    S.RENDER_SPEED       = reaper.SNM_GetIntConfigVar     (  "projrenderlimit"      ,0)--speed
    S.RENDER_RESAMPLE    = reaper.SNM_GetIntConfigVar     (  "projrenderresample"   ,0)--resample
    -- S.RENDER_STEMS       = reaper.SNM_GetIntConfigVar     (  "projrenderstems"      ,0)

    S.SILENTLY_iNCREMENT = reaper.SNM_GetIntConfigVar     (  "renderclosewhendone"  ,0)--Silently increment filenames to avoid overwriting 1 of / 17 on
    return S
end 

function restore_render_settings(S)
    reaper.GetSetProjectInfo(0,"RENDER_SETTINGS"      ,S.RENDER_SETTINGS  ,1)
    reaper.GetSetProjectInfo(0,"RENDER_NORMALIZE"     ,S.RENDER_NORMALIZE  ,1)

    reaper.GetSetProjectInfo(0,"RENDER_BOUNDSFLAG"    ,S.RENDER_BOUNDSFLAG,1)
    reaper.GetSetProjectInfo(0,"RENDER_TAILFLAG"      ,S.RENDER_TAILFLAG  ,1)
    reaper.GetSetProjectInfo(0,"RENDER_TAILMS"        ,S.RENDER_TAILMS    ,1)
    reaper.GetSetProjectInfo(0,"RENDER_SRATE"         ,S.RENDER_SRATE     ,1)
    reaper.GetSetProjectInfo(0,"RENDER_CHANNELS"      ,S.RENDER_CHANNELS  ,1)
    reaper.GetSetProjectInfo(0,"RENDER_ADDTOPROJ"     ,S.RENDER_ADDTOPROJ ,1)

    reaper.GetSetProjectInfo_String(0,"RENDER_FORMAT" ,S.RENDER_FORMAT    ,1)
    reaper.GetSetProjectInfo_String(0,"RENDER_FORMAT2",S.RENDER_FORMAT2   ,1)

    reaper.GetSetProjectInfo_String(0,"RENDER_FILE"   ,S.RENDER_FILE      ,1)
    reaper.GetSetProjectInfo_String(0,"RENDER_PATTERN",S.RENDER_NAME      ,1)

    reaper.SNM_SetIntConfigVar("projrenderlimit"      ,S.RENDER_SPEED       )
    -- reaper.SNM_SetIntConfigVar("projrenderstems"      ,S.RENDER_STEMS       )
    reaper.SNM_SetIntConfigVar("projrenderresample"   ,S.RENDER_RESAMPLE    )
    reaper.SNM_SetIntConfigVar("renderclosewhendone"  ,S.SILENTLY_iNCREMENT )

end

function set_razor_render_settings(S,render_name)
 
    -- if reaper.MB('Add Tail?', '', 4)== 1 then 
    --     ADD_TAIL = true 
    -- else ADD_TAIL = false end 

    -- retval, retvals_csv = reaper.GetUserInputs( 'Render first FX to lane', 1, 'Add Tail?', 5000 )
    -- if retval then ADD_TAIL = true TAIL = retvals_csv else ADD_TAIL = false end 
    ADD_TAIL = false

    reaper.GetSetProjectInfo(0,"RENDER_SETTINGS",   4096 | 16, 1)
    reaper.GetSetProjectInfo(0,"RENDER_NORMALIZE",  0, 1)

    reaper.GetSetProjectInfo(0,"RENDER_BOUNDSFLAG", 6,      1)
    reaper.GetSetProjectInfo(0,"RENDER_TAILFLAG",   ADD_TAIL==true and 72 or 16,     1)
    reaper.GetSetProjectInfo(0,"RENDER_TAILMS"        ,TAIL,1)
    reaper.GetSetProjectInfo(0,"RENDER_SRATE"         ,S.RENDER_SRATE     ,1)
    reaper.GetSetProjectInfo(0,"RENDER_CHANNELS"      ,2  ,1)
    reaper.GetSetProjectInfo(0,"RENDER_ADDTOPROJ"     ,1 ,1)

    reaper.GetSetProjectInfo_String(0,"RENDER_FORMAT",  'a3B2dwQAAAABAAAAAAAAAAMAAAA='   ,1)
    reaper.GetSetProjectInfo_String(0,"RENDER_FORMAT2",  ''   ,1)
    reaper.GetSetProjectInfo_String(0,"RENDER_FILE"   ,     'Media/lane render/'    ,1)
    reaper.GetSetProjectInfo_String(0,"RENDER_PATTERN",     render_name    ,    1)


    reaper.SNM_SetIntConfigVar("projrenderlimit"      ,S.RENDER_SPEED )
    -- reaper.SNM_SetIntConfigVar("projrenderstems"      ,16   )
    reaper.SNM_SetIntConfigVar("projrenderresample"   ,S.RENDER_RESAMPLE )
    reaper.SNM_SetIntConfigVar("renderclosewhendone"  ,16|1)
end

function get_playing_lanes(track,count_lanes)
    local lanes = {}
    for l=0, count_lanes-1 do 
        if reaper.GetMediaTrackInfo_Value(track, 'C_LANEPLAYS:'..l) > 0 then 
            table.insert(lanes,l )
        end 
    end
    return lanes
end

function find_envelopes(track)
    active_envs = {}
    local count_envs = reaper.CountTrackEnvelopes(track)
    for i=0, count_envs-1 do
        local env = reaper.GetTrackEnvelope(track,i)
        local retval, str = reaper.GetEnvelopeStateChunk(env, '', false)
        if string.find(str,'ACT 1') then
            table.insert(active_envs, env)
            -- reaper.SetEnvelopeStateChunk(pre_fx_env, str:gsub('ACT 1', 'ACT 0'), false)
        end
    end
    return active_envs
end 

function bypass_envelope(env)
    local retval, str = reaper.GetEnvelopeStateChunk(env, '', false)
    if string.find(str,'ACT 1') then reaper.SetEnvelopeStateChunk(env, str:gsub('ACT 1', 'ACT 0'), false) end 
end

function unbypass_envelope(env)
    local retval, str = reaper.GetEnvelopeStateChunk(env, '', false)
    if string.find(str,'ACT 0') then reaper.SetEnvelopeStateChunk(env, str:gsub('ACT 0', 'ACT 1'), false) end 
end

function save_selected_tracks()
    selected_tracks = {}
    local count_tracks = reaper.CountTracks(0)
    for i = 0, count_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.IsTrackSelected(track) then table.insert( selected_tracks, track) end
    end
    return selected_tracks
end

function restore_selected_tracks(table)
    for k,track in ipairs(table) do reaper.SetTrackSelected(track, true) end
end


function check_for_render(track)
    local check = false
    local count_lanes = reaper.GetMediaTrackInfo_Value(track, 'I_NUMFIXEDLANES')
    local playing_lanes = get_playing_lanes(track,count_lanes)
    local count_items = reaper.GetTrackNumMediaItems(track)
    for it=0, count_items-1 do 
        local item = reaper.GetTrackMediaItem(track, it)
        local is_mute = reaper.GetMediaItemInfo_Value( item, 'B_MUTE')==1
        local is_sel = reaper.IsMediaItemSelected(item)
        if is_sel then 
            for l=1,count_lanes do 
                lane = reaper.GetMediaItemInfo_Value(item, 'I_FIXEDLANE')
                if table_contains(playing_lanes,lane) and (not is_mute) then
                    check = true
                else reaper.SetMediaItemSelected(item, 0) 
                end
            end
        end
    end

    return check
end

reaper.Undo_BeginBlock()

og_render_settings = save_render_settings()
-- selected_tracks = save_selected_tracks()

function main()
    processed = {}
    local count_tracks = reaper.CountTracks(0)
    for i = 0, count_tracks - 1 do
        render_track = nil
        local track = reaper.GetTrack(0, i)
        check = check_for_render(track)
        if check then 

            bypass_list = {}
            for f=0,reaper.TrackFX_GetCount(track)-1 do 
                if reaper.TrackFX_GetEnabled(track, f) and f>0 then 
                    table.insert(bypass_list, f)
                    reaper.TrackFX_SetEnabled(track, f,0)
                end
            end 

            vol   = reaper.GetMediaTrackInfo_Value(track, 'D_VOL')
            pan   = reaper.GetMediaTrackInfo_Value(track, 'D_PAN')
            width = reaper.GetMediaTrackInfo_Value(track, 'D_WIDTH')
            reaper.SetMediaTrackInfo_Value(track, 'D_VOL', 1)
            reaper.SetMediaTrackInfo_Value(track, 'D_PAN', 0)
            reaper.SetMediaTrackInfo_Value(track, 'D_WIDTH', 0)

            envs = find_envelopes(track)
            if envs then for e=1,#envs do bypass_envelope(envs[e]) end end

            table.insert(processed, {track=track, bypass_list = bypass_list,envs=envs,vol=vol,pan=pan,width=width})
        end
    end
    if #processed > 0 then 
        reaper.Main_OnCommand(42630, 0) -- Razor edit: Enclose media items

        set_razor_render_settings(og_render_settings,'LR_$track')

        reaper.Main_OnCommand(42230,0) -- RENDER
        
        local count = reaper.CountTracks(0)
        r=0
        for p = #processed, 1, -1 do 
            r = r+1
            local render_track = reaper.GetTrack(0, count-r)

            local track = processed[p].track
            local bypass_list = processed[p].bypass_list
            local envs  = processed[p].envs
            local vol   = processed[p].vol
            local pan   = processed[p].pan
            local width = processed[p].width

            local new_items = {}
            for i = 0, reaper.GetTrackNumMediaItems(render_track) - 1 do
                table.insert(new_items, reaper.GetTrackMediaItem(render_track, i))
            end

            local count_new_items = reaper.GetTrackNumMediaItems(render_track)

            local count_lanes = reaper.GetMediaTrackInfo_Value(track, 'I_NUMFIXEDLANES')
            local lane_mode = reaper.GetMediaTrackInfo_Value(track, 'I_FREEMODE')
            if lane_mode ~= 2 then reaper.SetMediaTrackInfo_Value(track, 'I_FREEMODE', 2) end
            
            col_r = math.random(50,230)
            col_g = math.random(50,230)
            col_b = math.random(50,230)

            for _, new_item in ipairs(new_items) do
                reaper.SetMediaItemInfo_Value(new_item, 'I_FIXEDLANE', count_lanes)
                reaper.SetMediaItemInfo_Value(new_item, 'I_CUSTOMCOLOR', reaper.ColorToNative(col_r,col_g,col_b)|0x1000000, 1)   
                reaper.MoveMediaItemToTrack(new_item, track)
            end
            reaper.SetMediaTrackInfo_Value(track, 'C_LANEPLAYS:'..count_lanes, 1)
            reaper.UpdateItemLanes(0)

            for f=1,#bypass_list do reaper.TrackFX_SetEnabled(track, bypass_list[f],1) end
            if envs then for e=1,#envs do unbypass_envelope(envs[e]) end end

            reaper.SetMediaTrackInfo_Value(track, 'D_VOL', vol)
            reaper.SetMediaTrackInfo_Value(track, 'D_PAN', pan)
            reaper.SetMediaTrackInfo_Value(track, 'D_WIDTH', width)

            reaper.SetMediaTrackInfo_Value(track, 'C_LANESCOLLAPSED', 1)
            reaper.TrackFX_SetEnabled(track, 0, 0)
            reaper.DeleteTrack(render_track)
        end
    end 
end

local success, err = pcall(main)

restore_render_settings(og_render_settings)
-- restore_selected_tracks(selected_tracks)
reaper.Main_OnCommand(42406, 0) -- remove razors

if not success then
    reaper.ShowConsoleMsg("ОШИБКА: " .. tostring(err) .. "\nНастройки рендера восстановлены.\n")
end
reaper.UpdateArrange()
reaper.Undo_EndBlock('Render First FX to lane', -1)