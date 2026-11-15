-- Native FCS continuation for NPCs already carrying someone when upgrading.
-- Never drop/place a patient, choose a scripted bed, or interrupt an action.
local Live=require('Core.NPC.LiveState')
local Work=require('Core.NPC.RoleAI')
local PostJobs=require('Core.NPC.PostJobs')
local Log=require('Diagnostics')
local M={}
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function id(h)
 if not h or Live.call(h,'isNull')~=false then return nil end
 return Live.call(h,'toString')
end
function M.goal(c,key,personalOnly)
 local o=Live.call(c,'getOrdersReciever')
 for _,name in ipairs(personalOnly and {'goals'} or {'goals','squadAIPackage'})do
  local buckets=field(o,name)
  if buckets then
   for bucket=1,#buckets do
    for i=1,#buckets[bucket]do
     local g=buckets[bucket][i]
     local priority=field(g,'priority')
     -- Rescue now lives at priority 2, above role work at priority 1.
     -- Observe legacy/foreign higher-priority continuations without claiming
     -- or rewriting them; their source cannot be recovered from Tasker.
     if Live.call(g,'key')==key and type(priority)=='number'
      and priority>=2 and priority<=4 and bucket==priority+1 then return g end
    end
   end
  end
 end
end
local function say(s,r,event,detail)
 Log.console('NPC_RESCUE90 shop='..s.cfg.shop..' role='..s.cfg.role..' member='..r.member
  ..' hour='..string.format('%.3f',s.now/60%24)..' event='..event..' '..tostring(detail or ''))
end
local function legacyContinuation(c)
 local o=Live.call(c,'getOrdersReciever');local buckets=field(o,'goals')
 local tasks=buckets and buckets[4]
 if tasks then
  for i=1,#tasks do
   local g=tasks[i];local weight=field(g,'weight')
   -- The alpha.90/.91 helper was the only mod-owned personal carry goal:
   -- 106, urgent, weight 110, all day. Limit the migration to that signature
   -- inside a recognized KenshiShop role; never key-remove another goal.
   if Live.call(g,'key')==106 and field(g,'priority')==3
    and type(weight)=='number' and math.abs(weight-110)<0.0001
    and field(g,'startTime')==0 and field(g,'endTime')==24 then
    return o,g,tasks,i
   end
  end
 end
end
local function migrateLegacy(s,r,c)
 local o,g,tasks,slot=legacyContinuation(c)
 if not g or (r.migrationTries or 0)>=3 then return end
 local label=Live.call(Live.call(c,'getBlackboard'),'getCurrentAIPackageName')
 if not Work.isWorkingPackage(s.cfg,label) and label~='KS Medic Robotics Rescue' then return end
 -- Finish an already active medical/bed action first. Re-bucketing an idle
 -- Tasker does not interrupt its native action, rewrite a patient or move NPCs.
 local safe=PostJobs.safe(c);if not safe then return end
 r.migrationTries=(r.migrationTries or 0)+1
 local ok,err=pcall(function()
  assert(type(field(tasks,'removeAt'))=='function' and type(field(o,'addGoal'))=='function','CARRY_REINSERT_API_UNAVAILABLE')
  tasks:removeAt(slot);g.priority=2
  local inserted,problem=pcall(o.addGoal,o,g)
  if not inserted then
   g.priority=3;pcall(o.addGoal,o,g)
   error(problem)
  end
  assert(M.goal(c,106,true) and field(g,'priority')==2,'CARRY_PRIORITY_VERIFY_FAILED')
  o:setNeedGOAP()
 end)
 say(s,r,ok and 'LEGACY_PRIORITY_MIGRATED' or 'LEGACY_PRIORITY_FAILED',
  ok and 'task=106 old_priority=3 priority=2 action_reset=false' or 'attempt='..r.migrationTries..'/3 '..tostring(err))
end
function M.ensure(s,r,c,carried)
 if M.goal(c,106)then return true end
 if not carried or r.tries>=3 then return false end
 local label=Live.call(Live.call(c,'getBlackboard'),'getCurrentAIPackageName')
 if not Work.isWorkingPackage(s.cfg,label) and label~='KS Medic Robotics Rescue' then return false end
 local o=Live.call(c,'getOrdersReciever')
 if Live.call(o,'hasOrders')~=false then return false end
 -- A later personal task with this key belongs to its original owner.
 local buckets=field(o,'goals')
 if buckets then
  for b=1,#buckets do for i=1,#buckets[b]do
   if Live.call(buckets[b][i],'key')==106 then
    if not r.conflict then say(s,r,'FOREIGN_GOAL','key=106 preserved=true');r.conflict=true end
    return false
   end
  end end
 end
 local world=getGameWorld();local data=world and Live.call(world.gamedata,'getData','10007-KenshiShop.mod',72)
 if not data then return false end
 r.tries=r.tries+1
 local ok,err=pcall(function()
  local ai=assert(c:getAI(),'AI_UNAVAILABLE')
  ai:addAIGoalsFrom(data,'Leader AI Goals')
  local goal=M.goal(c,106,true)
  assert(goal and field(goal,'priority')==2,'RESCUE_CARRY_GOAL_VERIFY_FAILED')
  -- Let native arbitration resume the bed chain above ordinary work. In particular,
  -- no setupPlatoonAI/reThinkCurrentAIAction is called during carrying.
  o:setNeedGOAP()
 end)
 say(s,r,ok and 'CONTINUATION_READY' or 'CONTINUATION_FAILED',ok and 'task=106 priority=2 native_fcs=true' or tostring(err))
 return ok
end
local function sample(s,r,c,carried)
 local o=Live.call(c,'getOrdersReciever');local current=Live.call(o,'getCurrentGoal')
 local key=Live.call(current,'key')
 local action=Live.call(field(Live.call(c,'getBody'),'currentAction'),'key')
 local target=id(field(Live.call(c,'getStateBroadcast'),'taskTarget'))
 local candidate,score
 local ai=Live.call(c,'getAI');local finder=field(ai,'findOwnedFreeBed')
 if type(finder)=='function' then
  local ok,value,h=pcall(finder,ai,carried,true)
  if ok then score=value;candidate=id(h)end
 end
 local continuation=M.goal(c,106)
 local carryPriority=field(continuation,'priority')
 say(s,r,'CARRY_OBSERVE','patient='..tostring(r.carried)..' active='..tostring(key)
  ..' action='..tostring(action)..' continuation106='..tostring(continuation~=nil)
  ..' carry_priority='..tostring(carryPriority)..' subject='..tostring(id(field(current,'subject')))
  ..' task_target='..tostring(target)..' bed_candidate='..tostring(candidate)..' bed_score='..tostring(score)
  ..' bed_query_only=true')
end
function M.tick(s,ms)
 if not s.platoon or type(s.now)~='number' then return end
 s.nativeCare=s.nativeCare or {}
 for _,m in ipairs(ms)do
  local c=m.char
  if Live.call(c,'isDead')~=true then
   local r=s.nativeCare[m.key] or {member=m.key,tries=0};s.nativeCare[m.key]=r
   local carried=Live.call(c,'getCarryingObject');local null=Live.call(carried,'isNull')
   if null==false then
    local patient=id(carried)
    if patient~=r.carried then
     r.carried=patient;r.patient=carried;r.samples=0;r.nextSample=s.now;r.releaseChecks=nil
     say(s,r,'CARRY_STARTED','patient='..tostring(patient))
    end
    M.ensure(s,r,c,carried)
    if (r.samples or 0)<3 and s.now>=(r.nextSample or 0)then
     sample(s,r,c,carried);r.samples=(r.samples or 0)+1;r.nextSample=s.now+10
    end
   elseif null==true then
    migrateLegacy(s,r,c)
    if r.carried then
     say(s,r,'CARRY_RELEASED','patient='..r.carried..' bed_result=NOT_YET_CONFIRMED')
     r.carried=nil;r.releaseChecks=0;r.nextReleaseCheck=s.now+0.25
    end
    if r.releaseChecks and r.releaseChecks<2 and s.now>=r.nextReleaseCheck then
     local patient=Live.call(r.patient,'getCharacter')
     local ai=Live.call(patient,'getAI');local pos=Live.call(patient,'getPosition')
     local inBed=pos and Live.call(ai,'isInBed',r.patient,pos)
     say(s,r,inBed==true and 'BED_CONFIRMED' or 'BED_NOT_CONFIRMED','patient='..tostring(id(r.patient))
      ..' native_in_bed='..tostring(inBed)..' dead='..tostring(Live.call(patient,'isDead')))
     r.releaseChecks=inBed==true and 2 or r.releaseChecks+1;r.nextReleaseCheck=s.now+2
    end
   end
  end
 end
end
return M
