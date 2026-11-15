-- One-time cleanup of old scripted goals during native-package migration.
-- Only our alpha.82/.83 weight marker authorizes removal; no goals are created.
local Live=require('Core.NPC.LiveState')
local M={}
local WEIGHT=1.082
local function list(c)
 local o=Live.call(c,'getOrdersReciever')
 local ok,g=pcall(function()return o.goals end)
 return o,ok and g or nil
end
local function find(c,key)
 local o,g=list(c);if not g then return o,nil end
 local owned
 -- The native API exposes priority buckets, each containing Tasker pointers.
 -- A same-key foreign task makes key-based removal unsafe, even if ours is
 -- encountered first. Preserve both rather than removing another owner's job.
 for bucket=1,#g do
  local tasks=g[bucket]
  for i=1,#tasks do
   local goal=tasks[i]
   if Live.call(goal,'key')==key then
    if not M.isOurs(goal) then return o,nil end
    owned=goal
   end
  end
 end
 return o,owned
end
function M.isOurs(goal)
 local ok,w=pcall(function()return goal.weight end)
 return ok and type(w)=='number' and math.abs(w-WEIGHT)<0.00001
end
function M.remove(c,key)
 local o,g=find(c,key)
 if g and M.isOurs(g) then
  local ok=pcall(o.removeGoal,o,key)
  if ok then Live.call(o,'setNeedGOAP') end
  return ok,ok
 end
 return true,false
end
function M.current(c)
 local o=Live.call(c,'getOrdersReciever')
 local match=Live.call(o,'getCurrentGoal')
 return Live.call(match,'key'),o
end
return M
