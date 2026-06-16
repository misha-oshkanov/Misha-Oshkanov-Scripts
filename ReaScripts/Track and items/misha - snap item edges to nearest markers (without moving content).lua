-- @description Snap item edges to neares markers (without moving content)
-- @author Misha Oshkanov
-- @version 1.0
-- @about
--  Move item edges to nearest markers
--  if item start is bigger than new item start, then move item start to left marker

local use_fades = true          
local overlap_amount = 0.010    
local edge_offset = 0.005  

------------------------------------------------------------

local function FindNearestMarker(pos)
    local nearestPos = nil
    local minDist = math.huge
    local i = 0
    
    while true do
        local retval, isrgn, mpos = reaper.EnumProjectMarkers(i)
        if retval == 0 then break end
        if not isrgn then
            local dist = math.abs(mpos - pos)
            if dist < minDist then
                minDist = dist
                nearestPos = mpos
            end
        end
        i = i + 1
    end
    return nearestPos
end

local function SnapItemEdges(item)
    if not item then return end
    
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local endPos = pos + length
    local take = reaper.GetActiveTake(item)
    
    local newStart = FindNearestMarker(pos)
    local newEnd   = FindNearestMarker(endPos)
    
    if not newStart or not newEnd or newEnd <= newStart then return end

    local startOffset = 0
    local sourceLength = 0
    if take then
        startOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        local source = reaper.GetMediaItemTake_Source(take)
        if source then
            sourceLength = reaper.GetMediaSourceLength(source)
        end
    end
    
    local adjustedStart = newStart - edge_offset
    local delta = adjustedStart - pos
    local newStartOffset = startOffset + delta
    
    if newStartOffset < 0 then
        newStartOffset = 0
    end
    
    if take then
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", newStartOffset)
    end
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", adjustedStart)
    
    local adjustedEnd = newEnd + edge_offset
    local newLength = adjustedEnd - adjustedStart
    
    if take and sourceLength > 0 then
        local maxLength = sourceLength - newStartOffset
        if newLength > maxLength then
            newLength = maxLength
        end
    end
    
    if newLength > 0 then
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", newLength)
    end
    
    reaper.UpdateItemInProject(item)
end


local function CreateSmartCrossfades()
    if not use_fades then return end
    
    local itemCount = reaper.CountMediaItems(0)
    
    for i = 0, itemCount - 1 do
        local sel_item = reaper.GetMediaItem(0, i)
        if not reaper.IsMediaItemSelected(sel_item) then goto continue end
        
        local sel_track = reaper.GetMediaItem_Track(sel_item)
        local sel_pos = reaper.GetMediaItemInfo_Value(sel_item, "D_POSITION")
        local sel_len = reaper.GetMediaItemInfo_Value(sel_item, "D_LENGTH")
        local sel_end = sel_pos + sel_len
        
        for j = 0, itemCount - 1 do
            local other_item = reaper.GetMediaItem(0, j)
            if other_item == sel_item or reaper.IsMediaItemSelected(other_item) then goto next_item end
            
            local oth_track = reaper.GetMediaItem_Track(other_item)
            if oth_track ~= sel_track then goto next_item end
            
            local oth_pos = reaper.GetMediaItemInfo_Value(other_item, "D_POSITION")
            local oth_len = reaper.GetMediaItemInfo_Value(other_item, "D_LENGTH")
            local oth_end = oth_pos + oth_len
            
            if sel_end > oth_pos and sel_pos < oth_end then
                if sel_end > oth_pos and sel_end < oth_end then
                    local marker = sel_end
                    local new_oth_pos = marker - overlap_amount
                    local delta = new_oth_pos - oth_pos
                    local take = reaper.GetActiveTake(other_item)
                    local startoffs = 0
                    local sourceLength = 0
                    
                    if take then
                        startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                        local source = reaper.GetMediaItemTake_Source(take)
                        if source then
                            sourceLength = reaper.GetMediaSourceLength(source)
                        end
                        
                        local newStartOffset = startoffs + delta
                        
                        if newStartOffset < 0 then
                            newStartOffset = 0
                        end
                        
                        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", newStartOffset)
                    end
                    
                    reaper.SetMediaItemInfo_Value(other_item, "D_POSITION", new_oth_pos)
                    
                    if take and sourceLength > 0 then
                        local currentLen = reaper.GetMediaItemInfo_Value(other_item, "D_LENGTH")
                        local currentStartOff = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                        local maxLen = sourceLength - currentStartOff
                        if currentLen > maxLen then
                            reaper.SetMediaItemInfo_Value(other_item, "D_LENGTH", maxLen)
                        end
                    end
                    
                    reaper.SetMediaItemInfo_Value(sel_item,   "D_FADEOUTLEN", overlap_amount)
                    reaper.SetMediaItemInfo_Value(other_item, "D_FADEINLEN",  overlap_amount)
                    
                    reaper.UpdateItemInProject(other_item)
                end
                
                if sel_pos > oth_pos and sel_pos < oth_end then
                    local marker = sel_pos
                    local new_oth_len = marker + overlap_amount - oth_pos
                    
                    if new_oth_len > 0 then
                        local take = reaper.GetActiveTake(other_item)
                        if take then
                            local startOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                            local source = reaper.GetMediaItemTake_Source(take)
                            if source then
                                local sourceLength = reaper.GetMediaSourceLength(source)
                                local maxLen = sourceLength - startOffset
                                if new_oth_len > maxLen then
                                    new_oth_len = maxLen
                                end
                            end
                        end
                        
                        reaper.SetMediaItemInfo_Value(other_item, "D_LENGTH", new_oth_len) 
                        reaper.SetMediaItemInfo_Value(other_item, "D_FADEOUTLEN", overlap_amount)
                        reaper.SetMediaItemInfo_Value(sel_item,   "D_FADEINLEN",  overlap_amount)
                        reaper.UpdateItemInProject(other_item)
                    end
                end
            end
            ::next_item::
        end
        ::continue::
    end
end

-- ====================== MAIN ======================
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local selCount = reaper.CountSelectedMediaItems(0)
if selCount == 0 then
    reaper.ShowMessageBox("Выберите хотя бы один айтем!", "Ошибка", 0)
    return
end

for i = 0, selCount - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    SnapItemEdges(item)
end

CreateSmartCrossfades()

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Snap item edges to markers + smart crossfades (same track only)", -1)
reaper.UpdateArrange()