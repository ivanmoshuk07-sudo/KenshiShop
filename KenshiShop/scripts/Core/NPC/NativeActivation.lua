-- One native planning refresh after a completed home/node/package handoff.
-- SentientSands also rethinks the current action after restoring NPC context.
local O=require('Core.NPC.OriginTown')
local M={}
function M.ensure(r,ms)
 r.activation=r.activation or {}
 local epoch=r.missionDrifts or 0
 for _,m in ipairs(ms)do
  if r.activation[m.key]~=epoch then
   local ok,err=pcall(function()
    local ai=assert(m.char:getAI(),'AI_UNAVAILABLE')
    local cache=assert(O.field(ai,'resultsCache'),'AI_CACHE_UNAVAILABLE')
    cache:resetAllCaches()
    m.char:reThinkCurrentAIAction()
    m.char:getOrdersReciever():setNeedGOAP()
   end)
   if not ok then return false,m.key..' '..tostring(err) end
   r.activation[m.key]=epoch
  end
 end
 return true
end
return M
