-- Ordinary native goals, below urgent care/combat. Only our marked goals are removed.
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
 for i=1,#g do if Live.call(g[i],'key')==key then return o,g[i] end end
 return o,nil
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
function M.set(c,key,point,subject,priority)
 local o,g=find(c,key)
 if not o then return false,'ORDERS_UNAVAILABLE' end
 if g and not M.isOurs(g) then return false,'GOAL_CONFLICT '..key end
 if not g then
  -- Older KenshiLua requires a RootObjectBase even for location-only tasks.
  -- Use a real carrier, then clear the task's copied handle below.
  local ok,err=pcall(c.addGoal,c,key,subject or c)
  if not ok then return false,'ADD_GOAL '..tostring(err) end
  o,g=find(c,key)
  if not g then return false,'GOAL_NOT_REGISTERED '..key end
 end
 local ok,err=pcall(function()
  g.weight=WEIGHT;g.priority=priority or 2;g.startTime=0;g.endTime=24
  g.resetsWhenDone=true
  if subject then g.subject=subject:getHandle()
  else
   -- Tasker.subject is a value copy. Never null the character's own handle.
   local empty=g.subject;empty:setNull();g.subject=empty
   assert(g.subject:isNull(),'LOCATION_GOAL_HAS_SUBJECT')
  end
  if point then g:setLocation(point) end
 end)
 if not ok then return false,'GOAL_SETUP '..tostring(err) end
 Live.call(o,'setNeedGOAP')
 return true
end
function M.current(c)
 local o=Live.call(c,'getOrdersReciever')
 local match=Live.call(o,'getCurrentGoal')
 return Live.call(match,'key'),o
end
-- Preserve all non-routine tasks, including medical subtasks, dialogue, eating and sleep.
local ROUTINE={[0]=true,[1]=true,[14]=true,[30]=true,[62]=true,[20]=true,[268]=true,[36]=true,[38]=true}
function M.safe(c)
 local held,why=Live.halted(c);if held then return false,why end
 local key,o=M.current(c)
 if key==nil then return false,'CURRENT_GOAL_UNKNOWN' end
 if not ROUTINE[key] then return false,'NATIVE_TASK_'..key end
 if Live.call(o,'hasOrders')~=false then return false,'ORDERS_OR_UNKNOWN' end
 return true
end
function M.routine(c,point,reached)
 if reached then
  M.remove(c,1)
  return M.set(c,30,point,nil,2)
 end
 M.remove(c,30)
 return M.set(c,1,point,nil,2)
end
function M.clearRoutine(c)M.remove(c,1);M.remove(c,30)end
return M
