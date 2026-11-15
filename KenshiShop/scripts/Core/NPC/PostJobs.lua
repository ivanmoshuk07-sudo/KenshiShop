-- One real STAND_AT_NODE job with a LocationNode subject. The native planner
-- walks, stands, fights and resumes work. No coordinate orders or idle loop.
local Live=require('Core.NPC.LiveState')
local M={}
local MARK=1.089
local PRIORITY=1
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
function M.find(c)
 local orders=Live.call(c,'getOrdersReciever');local buckets=field(orders,'goals')
 if not buckets then return orders end
 local owned
 -- KenshiLua exposes five priority lektors, NOT a flat array of Taskers.
 for bucket=1,#buckets do
  local tasks=buckets[bucket]
  for i=1,#tasks do
   local g=tasks[i]
   if Live.call(g,'key')==51 then
    -- Key-based removal cannot distinguish an old KS post from a foreign
    -- post. A foreign task always prevents us claiming or clearing this key.
    if not M.ours(g) then return orders,g,bucket-1,tasks,i end
    owned={g,bucket-1,tasks,i}
   end
  end
 end
 if owned then return orders,owned[1],owned[2],owned[3],owned[4] end
 return orders
end
function M.ours(g)local w=field(g,'weight');return type(w)=='number' and math.abs(w-MARK)<0.00001 end
function M.safe(c)
 local busy,why=Live.halted(c);if busy then return false,why end
 local o=Live.call(c,'getOrdersReciever')
 if Live.call(o,'hasOrders')~=false then return false,'NATIVE_ORDERS_OR_UNKNOWN'end
 local active=Live.call(Live.call(o,'getCurrentGoal'),'key')
 if not ({[0]=true,[14]=true,[19]=true,[20]=true,[30]=true,[36]=true,[38]=true,[43]=true,[47]=true,[51]=true,[54]=true,[62]=true,[141]=true,[268]=true})[active] then
  return false,'NATIVE_TASK_'..tostring(active)
 end
 return true
end
local function wake(c,o)
 local ai=assert(Live.call(c,'getAI'),'AI_UNAVAILABLE')
 local cache=assert(field(ai,'resultsCache'),'CACHE_UNAVAILABLE')
 cache:resetAllCaches();c:reThinkCurrentAIAction();o:setNeedGOAP()
end
function M.clear(c)
 local o,g=M.find(c)
 if not g then return true end
 if not M.ours(g) then return false,'FOREIGN_POST_JOB'end
 local safe,why=M.safe(c);if not safe then return false,why end
 local ok,err=pcall(function()o:removeGoal(51);wake(c,o)end)
 return ok,err
end
function M.assign(c,node)
 local safe,why=M.safe(c);if not safe then return false,why end
 local o,g,bucket,tasks,slot=M.find(c)
 if not o then return false,'ORDERS_UNAVAILABLE'end
 if g and not M.ours(g) then return false,'FOREIGN_POST_JOB'end
 local ok,err=pcall(function()
  local created=false
  if not g then
   c:addGoal(51,node.base)
   o,g,bucket,tasks,slot=M.find(c)
   assert(g,'POST_JOB_NOT_REGISTERED')
   created=true
  end
  -- Priority is represented by BOTH a field and the owning bucket. Reinsert
  -- new posts and saved KS posts from the previous priority through the native
  -- receiver. removeAt on Tasker* removes a pointer; it does not delete Tasker.
  if bucket~=PRIORITY or g.priority~=PRIORITY then
   if type(field(tasks,'removeAt'))~='function' or type(field(o,'addGoal'))~='function' then
    if created then o:removeGoal(51)end
    error('POST_JOB_REINSERT_API_UNAVAILABLE')
   end
   local previousPriority=g.priority
   tasks:removeAt(slot);g.priority=PRIORITY
   local inserted,problem=pcall(o.addGoal,o,g)
   if not inserted then
    -- A failed upgrade must leave the previous native task available. Its
    -- subject and other fields have not yet been changed by this assignment.
    g.priority=previousPriority;pcall(o.addGoal,o,g)
    error('POST_JOB_REINSERT_FAILED '..tostring(problem))
   end
   o,g,bucket=M.find(c)
  end
  assert(g and bucket==PRIORITY and g.priority==PRIORITY,'POST_JOB_PRIORITY_VERIFY_FAILED')
  g.weight=MARK
  g.subject=node.handle;g.resetsWhenDone=true;g.startTime=0;g.endTime=24
  assert(g.subject:toString()==node.handle:toString(),'POST_SUBJECT_VERIFY_FAILED')
  wake(c,o)
 end)
 return ok,err
end
return M
