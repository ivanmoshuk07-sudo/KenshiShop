-- Shared, finite medical-supply audits. The queue owns copied handles, never
-- Character pointers; each frame checks at most one current loaded member.
local Live=require('Core.NPC.LiveState')
local Supplies=require('Core.NPC.Supplies')
local Log=require('Diagnostics')
local M={}
local queue,head,pending={},1,{}
local hook
local function idle()
 if hook then Events.off(hook);hook=nil end
 queue={};head=1
end
function M.cancel(s)
 for key,entry in pairs(pending)do
  if entry.state==s then pending[key]=nil end
 end
 -- Release stale state/handle references immediately, even if no more frames run.
 local keep={}
 for i=head,#queue do local e=queue[i];if pending[e.key]==e then keep[#keep+1]=e end end
 queue=keep;head=1
 if #queue==0 then idle()end
end
function M.reset()
 pending={};idle()
end
local function pid(c)
 local ap=Live.call(c,'getPlatoon')
 local ok,p=pcall(function()return ap and ap.me end)
 return ok and Live.call(p,'getPlatoonStringID') or nil
end
local function resolve(e)
 local c=Live.call(e.handle,'getCharacter')
 if not c or Live.call(c,'isValid')~=true then return nil end
 if Live.call(Live.call(c,'getHandle'),'toString')~=e.key then return nil end
 if pid(c)~=e.pid or Live.call(c,'isDead')~=false then return nil end
 return c
end
function M.tick()
 local e
 -- Stale entries cost no native calls and have a finite per-frame budget.
 for _=1,64 do
  e=queue[head]
  if not e then idle();return end
  queue[head]=false;head=head+1
  if pending[e.key]==e then pending[e.key]=nil;break end
  e=nil
 end
 if not e then return end
 local s=e.state
 local good,now=pcall(Live.clock)
 if not good then M.cancel(s);return end
 if now+0.001<e.queuedAt then
  M.cancel(s);s.nextSupplyCheck=nil;s.supplyClock=nil
  s.supplyFailures={};s.supplyResetAt=nil
  return
 end
 local c=resolve(e)
 if c then
  s.supplyFailures=s.supplyFailures or {}
  local world=getGameWorld()
  local ok,done,detail=pcall(Supplies.sync,c,world)
  if ok and done then
   s.supplyFailures[e.key]=0
   if detail~='UNCHANGED' then
    Log.console('NPC_SUPPLY_REFILL shop='..s.cfg.shop..' squad='..s.cfg.role..' member='..e.key..' '..tostring(detail))
   end
  else
   local fail=(s.supplyFailures[e.key] or 0)+1;s.supplyFailures[e.key]=fail
   Log.console('NPC_SUPPLY_RETRY shop='..s.cfg.shop..' squad='..s.cfg.role..' member='..e.key..' attempt='..fail..'/3 '..tostring(ok and detail or done))
   if fail>=3 then
    s.supplyResetAt=s.supplyResetAt or now+60
    Log.error('NPC_SUPPLY_COOLDOWN shop='..s.cfg.shop..' member='..e.key..' retry_after=60_game_minutes')
   end
  end
 end
 if head>#queue then idle()end
end
local function attach()
 if hook then return true end
 local ok,id=pcall(Events.on,'MyGUI::Gui::eventFrameStart',function()
  local good,why=pcall(M.tick)
  if not good then
   M.reset();Log.error('NPC_SUPPLY_QUEUE_FAILED '..tostring(why))
  end
 end)
 if not ok or not id then return false end
 hook=id;return true
end
function M.enqueue(s,ms,now)
 if s.supplyClock and now+0.001<s.supplyClock then
  M.cancel(s);s.nextSupplyCheck=nil;s.supplyFailures={};s.supplyResetAt=nil
 end
 s.supplyClock=now
 if s.nextSupplyCheck and now<s.nextSupplyCheck then return true end
 if s.supplyResetAt and now>=s.supplyResetAt then s.supplyFailures={};s.supplyResetAt=nil end
 s.supplyFailures=s.supplyFailures or {}
 local id=Live.call(s.platoon,'getPlatoonStringID')
 if not id or id=='' then return false end
 -- Install the single queue hook before accepting work. A failed hook leaves
 -- the audit due, so a later normal controller visit can retry safely.
 if not attach()then return false end
 s.nextSupplyCheck=now+10
 for _,m in ipairs(ms)do
  if (s.supplyFailures[m.key] or 0)<3 then
   local h=Live.call(m.char,'getHandle')
   if h and Live.call(h,'toString')==m.key then
    local old=pending[m.key]
    if not old then
     local e={state=s,key=m.key,handle=h,pid=id,queuedAt=now}
     pending[m.key]=e;queue[#queue+1]=e
    end
   end
  end
 end
 if head>#queue then idle()end
 return true
end
return M
