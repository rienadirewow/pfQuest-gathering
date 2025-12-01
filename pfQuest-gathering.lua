-- pfQuest-gathering: Skill-colored shapes for mining and herbalism nodes
-- Shows triangles for mines, leaves for herbs, colored by skill difficulty
-- Detect addon path
local addonpath
local tocs = {"", "-master", "-main"}
for _, name in pairs(tocs) do
    local current = string.format("pfQuest-gathering%s", name)
    local _, title = GetAddOnInfo(current)
    if title then
        addonpath = "Interface\\AddOns\\" .. current
        break
    end
end

-- Fallback if detection failed
if not addonpath then
    addonpath = "Interface\\AddOns\\pfQuest-gathering"
end

-- Check pfQuest is loaded
if not pfQuest or not pfDatabase then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest-Shapes: pfQuest is required.")
    return
end

-- Skill IDs
local SKILL_MINING = 186
local SKILL_HERBALISM = 182

-- Texture paths
local TEXTURE_MINE = addonpath .. "\\img\\triangle"
local TEXTURE_HERB = addonpath .. "\\img\\flower"

-- Calculate skill-based color
-- Returns r, g, b values based on player skill vs node requirement
-- WoW's gathering color system (based on skill difference):
--   Red: Can't gather (skill too low)
--   Orange: diff < 25 (guaranteed skillup)
--   Yellow: diff 25-49 (likely skillup)
--   Green: diff 50-99 (low skillup chance)
--   Grey: diff 100+ (trivial, no skillup)
local function GetSkillColor(nodeSkill, playerSkill)
    if not playerSkill or playerSkill == 0 then
        return 1, 1, 1 -- White: no skill data available
    end

    local diff = playerSkill - nodeSkill

    if diff < 0 then
        -- Red: can't gather this node yet
        return 1, 0.2, 0.2
    elseif diff < 25 then
        -- Orange: guaranteed skillup
        return 1, 0.5, 0.25
    elseif diff < 50 then
        -- Yellow: likely skillup
        return 1, 1, 0
    elseif diff < 100 then
        -- Green: low skillup chance
        return 0.2, 1, 0.2
    else
        -- Grey: trivial, no skillup
        return 0.6, 0.6, 0.6
    end
end

-- Hook pfDatabase.SearchObjectID to apply custom shapes and colors
local origSearchObjectID = pfDatabase.SearchObjectID

pfDatabase.SearchObjectID = function(self, id, meta, maps, prio)
    -- Check if this object is a mine or herb BEFORE calling original
    local mineSkill = pfDB["meta"]["mines"] and pfDB["meta"]["mines"][-id]
    local herbSkill = pfDB["meta"]["herbs"] and pfDB["meta"]["herbs"][-id]

    if mineSkill or herbSkill then
        local isMine = mineSkill ~= nil
        local nodeSkill = mineSkill or herbSkill
        local skillID = isMine and SKILL_MINING or SKILL_HERBALISM
        local playerSkill = pfDatabase:GetPlayerSkill(skillID) or 0

        -- Ensure meta table exists
        meta = meta or {}

        -- Set custom shape texture and color BEFORE original function adds the node
        meta.texture = isMine and TEXTURE_MINE or TEXTURE_HERB

        -- Calculate and apply skill-based color
        local r, g, b = GetSkillColor(nodeSkill, playerSkill)
        meta.vertex = {r, g, b}
    end

    -- Now call original function with modified meta
    return origSearchObjectID(self, id, meta, maps, prio)
end

-- Track what's currently being displayed for refresh
local currentTracking = nil -- "mines" or "herbs"
local currentTrackingAuto = false

-- Hook TrackMeta to remember what we're tracking
local origTrackMeta = pfDatabase.TrackMeta
pfDatabase.TrackMeta = function(self, meta, query)
    if meta == "mines" or meta == "herbs" then
        currentTracking = meta
        currentTrackingAuto = query and query.max and true or false
    end
    return origTrackMeta(self, meta, query)
end

-- Function to refresh current tracking
local function RefreshTracking()
    if currentTracking then
        -- Clear current nodes
        pfMap:DeleteNode("PFDB")
        -- Re-track with auto if it was auto
        if currentTrackingAuto then
            local skillID = currentTracking == "mines" and SKILL_MINING or SKILL_HERBALISM
            local playerSkill = pfDatabase:GetPlayerSkill(skillID) or 0
            pfDatabase:TrackMeta(currentTracking, {
                min = playerSkill - 100,
                max = playerSkill
            })
        else
            pfDatabase:TrackMeta(currentTracking, {})
        end
    end
end

-- Auto-refresh on skill up
local lastMiningSkill = 0
local lastHerbSkill = 0

local refreshFrame = CreateFrame("Frame")
refreshFrame:RegisterEvent("SKILL_LINES_CHANGED")
refreshFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
refreshFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        -- Initialize skill tracking
        lastMiningSkill = pfDatabase:GetPlayerSkill(SKILL_MINING) or 0
        lastHerbSkill = pfDatabase:GetPlayerSkill(SKILL_HERBALISM) or 0
        return
    end

    -- SKILL_LINES_CHANGED
    local newMining = pfDatabase:GetPlayerSkill(SKILL_MINING) or 0
    local newHerb = pfDatabase:GetPlayerSkill(SKILL_HERBALISM) or 0

    local skillChanged = false
    if newMining > lastMiningSkill then
        lastMiningSkill = newMining
        if currentTracking == "mines" then
            skillChanged = true
        end
    end
    if newHerb > lastHerbSkill then
        lastHerbSkill = newHerb
        if currentTracking == "herbs" then
            skillChanged = true
        end
    end

    if skillChanged then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest-Shapes: Skill up detected, refreshing...")
        this.timer = 0.5
    end
end)
refreshFrame:SetScript("OnUpdate", function()
    if this.timer then
        this.timer = this.timer - arg1
        if this.timer <= 0 then
            this.timer = nil
            RefreshTracking()
        end
    end
end)

-- Slash command for debug and manual refresh
SLASH_PFQUESTSHAPES1 = "/pfshapes"
SlashCmdList["PFQUESTSHAPES"] = function(msg)
    if msg == "refresh" then
        if currentTracking then
            RefreshTracking()
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest-Shapes: Refreshed " .. currentTracking ..
                                              " nodes")
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff33ffccpf|cffffffffQuest-Shapes: Nothing to refresh. Use /db mines auto or /db herbs auto first.")
        end
    elseif msg == "debug" then
        -- Show current tracking state
        local mining = pfDatabase:GetPlayerSkill(SKILL_MINING) or 0
        local herb = pfDatabase:GetPlayerSkill(SKILL_HERBALISM) or 0
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest-Shapes Debug:")
        DEFAULT_CHAT_FRAME:AddMessage("  Tracking: " .. (currentTracking or "nothing") ..
                                          (currentTrackingAuto and " (auto)" or ""))
        DEFAULT_CHAT_FRAME:AddMessage("  Mining: " .. mining .. " (last seen: " .. lastMiningSkill .. ")")
        DEFAULT_CHAT_FRAME:AddMessage("  Herbalism: " .. herb .. " (last seen: " .. lastHerbSkill .. ")")
        -- Show some node skill requirements
        DEFAULT_CHAT_FRAME:AddMessage("  Tin requires: " .. (pfDB["meta"]["mines"][-1732] or "?"))
        DEFAULT_CHAT_FRAME:AddMessage("  Iron requires: " .. (pfDB["meta"]["mines"][-1735] or "?"))
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest-Shapes commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  /pfshapes refresh - Manually refresh node colors")
        DEFAULT_CHAT_FRAME:AddMessage("  /pfshapes debug - Show skill levels and node requirements")
        DEFAULT_CHAT_FRAME:AddMessage("  (Colors auto-refresh on skill-up)")
    end
end

-- Print load message
DEFAULT_CHAT_FRAME:AddMessage(
    "|cff33ffccpf|cffffffffQuest-Shapes loaded. Mining: triangles, Herbs: squares. Type /pfshapes for options.")
