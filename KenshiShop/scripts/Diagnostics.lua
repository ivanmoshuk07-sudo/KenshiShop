-- KenshiShop: bounded in-memory log, readable through KS.logs() in the existing KenshiLua console.
local M = {}
local ring = {}
local npcRing = {}
local MAX_NPC_RING = 400
local MAX_RING = 220
local MAX_INFO = 1400
local infoCount, errorCount = 0, 0

local function append(level, message)
    local line = '[KenshiShop][' .. level .. '] ' .. tostring(message)
    ring[#ring + 1] = line
    if #ring > MAX_RING then table.remove(ring, 1) end
    if tostring(message):sub(1,4)=='NPC_' then
        npcRing[#npcRing + 1]=line
        if #npcRing>MAX_NPC_RING then table.remove(npcRing,1) end
    end
    local ok = false
    if KenshiLua then
        local fn=(level=='ERROR' and KenshiLua.logError) or (level=='WARN' and KenshiLua.logWarn) or KenshiLua.log
        if type(fn)=='function' then ok=pcall(fn,line) end
    end
    if not ok then print(line) end
end

function M.info(message)
    infoCount = infoCount + 1
    if infoCount <= MAX_INFO then
        append('INFO', message)
    elseif infoCount == MAX_INFO + 1 then
        append('WARN', 'INFO output capped; ERROR and CONSOLE remain enabled')
    end
end
function M.error(message)
    errorCount = errorCount + 1
    append('ERROR', message)
end
function M.console(message)
    append('CONSOLE', message)
end
function M.history(limit)
    limit = math.max(1, math.min(100, tonumber(limit) or 60))
    local out = {}
    for i = math.max(1, #ring - limit + 1), #ring do out[#out+1] = ring[i] end
    return out
end
function M.historyNPC(limit)
    limit = math.max(1,math.min(MAX_NPC_RING,tonumber(limit) or 80))
    local out={}
    for i=math.max(1,#npcRing-limit+1),#npcRing do out[#out+1]=npcRing[i] end
    return out
end
function M.stats() return {info=infoCount, errors=errorCount, retained=#ring, npcRetained=#npcRing} end
function M.clear() ring = {}; npcRing = {} end
return M
