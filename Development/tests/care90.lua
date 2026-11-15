-- Native API wiring and readback; does not simulate patient movement or healing.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local logs={};package.loaded.Diagnostics={console=function(s)logs[#logs+1]=s end}
local Care=require('Core.NPC.NativeCare');local Role=require('Core.NPC.RoleAI')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function h(id,c)return {isNull=function()return id==nil end,toString=function()return id end,getCharacter=function()return c end}end
local function buckets()
 local all={}
 for i=1,5 do all[i]={removeAt=function(self,slot)table.remove(self,slot)end}end
 return all
end
local s,ms,c,ai,o,carried,dead,orders,fail,calls,inBed,label,active,patient,combat
local function fixture()
 logs={};dead=false;orders=false;fail=false;combat=false;calls={add=0,goap=0,queries=0,rebucket=0};inBed=false;label='KS87 Indoor guards';active=51
 local pai={isInBed=function()return inBed end}
 patient={getAI=function()return pai end,getPosition=function()return {x=10,y=0,z=10}end,isDead=function()return false end}
 carried=h('patient',patient)
 o={goals=buckets(),squadAIPackage=buckets(),hasOrders=function()return orders end,
  getCurrentGoal=function()return {key=function()return active end,subject=h('bed')}end,
  setNeedGOAP=function()calls.goap=calls.goap+1 end}
 o.addGoal=function(_,g)calls.rebucket=calls.rebucket+1;table.insert(o.goals[g.priority+1],g)end
 ai={addAIGoalsFrom=function(_,data,list)
  assert(data.id=='10007-KenshiShop.mod' and list=='Leader AI Goals');calls.add=calls.add+1
  if fail then error('native API unavailable')end
  table.insert(o.goals[3],{key=function()return 106 end,priority=2})
 end,
 findOwnedFreeBed=function(_,target,asking)
  assert(target:toString()=='patient' and asking==true);calls.queries=calls.queries+1;return 0.5,h('bed')
 end}
 c={getAI=function()return ai end,getOrdersReciever=function()return o end,
 getBlackboard=function()return {getCurrentAIPackageName=function()return label end}end,
 getCarryingObject=function()return carried end,isDead=function()return dead end,
 getStateBroadcast=function()return {taskTarget=h('bed')}end}
 for _,method in ipairs({'isDown','isUnconcious','isCrippled','isBeingCarried','isFleeing'})do c[method]=function()return false end end
 c.isInCombatMode=function()return combat end
 for _,method in ipairs({'reThinkCurrentAIAction','setupPlatoonAI','dropCarriedObject','setDestination','setRace','addGoal','addJob'})do
  c[method]=function()error('disruptive mutation forbidden: '..method)end
 end
 function getGameWorld()return {gamedata={getData=function(_,id,kind)assert(kind==72);return {id=id}end}}end
 s={platoon={},cfg={role='guard',shop='weapons'},now=720,work={done=false}};ms={{key='guard',char=c}}
end
test('old carrying NPC gets native bed continuation even while role handoff is deferred',function()
 fixture();Care.tick(s,ms)
 assert(calls.add==1 and calls.goap==1 and Care.goal(c,106))
 for i=1,100 do s.now=720+i*0.1;Care.tick(s,ms)end
 assert(calls.add==1 and calls.goap==1)
end)
test('new package supplies priority 2 continuation without duplicate personal goals',function()
 fixture();label='KSB2 Indoor guards';table.insert(o.squadAIPackage[3],{key=function()return 106 end,priority=2})
 Care.tick(s,ms);assert(calls.add==0 and #o.goals[3]==0 and calls.queries==1)
end)
test('existing carriers in the care-only package also receive the native continuation',function()
 fixture();label='KS Medic Robotics Rescue';Care.tick(s,ms);assert(calls.add==1)
end)
test('API errors stop after three attempts without action resets or scripted bed placement',function()
 fixture();fail=true;for i=1,20 do Care.tick(s,ms)end;assert(calls.add==3 and calls.goap==0)
end)
test('native/player orders and later foreign packages are preserved',function()
 fixture();orders=true;Care.tick(s,ms);assert(calls.add==0)
 orders=false;label='Foreign emergency';Care.tick(s,ms);assert(calls.add==0)
end)
test('a foreign personal carry goal is never overwritten',function()
 fixture();local foreign={key=function()return 106 end,priority=2};table.insert(o.goals[3],foreign)
 Care.tick(s,ms);assert(calls.add==0 and o.goals[3][1]==foreign)
end)
test('legacy or player continuations are observed without rewriting their priority',function()
 for priority=3,4 do
  fixture();local legacy={key=function()return 106 end,priority=priority};table.insert(o.goals[priority+1],legacy)
  Care.tick(s,ms)
  assert(calls.add==0 and calls.goap==0 and legacy.priority==priority and o.goals[priority+1][1]==legacy)
  assert(logs[#logs]:find('carry_priority='..priority,1,true))
 end
end)
test('legacy helper is re-bucketed only after carrying and bed continuation finish',function()
 fixture();label='KSB2 Indoor guards'
 local subject,target=h('legacy-subject'),h('legacy-target')
 local legacy={key=function()return 106 end,priority=3,weight=110,startTime=0,endTime=24,
  subject=subject,currentSubTarget=target,resetsWhenDone=false}
 table.insert(o.goals[4],legacy)
 Care.tick(s,ms);assert(calls.rebucket==0 and calls.add==0 and legacy.priority==3)
 carried=h(nil);active=106;s.now=721;Care.tick(s,ms);assert(calls.rebucket==0 and legacy.priority==3)
 active=51;s.now=722;Care.tick(s,ms)
 assert(calls.rebucket==1 and calls.goap==1 and o.goals[3][1]==legacy and #o.goals[4]==0 and legacy.priority==2)
 assert(legacy.subject==subject and legacy.currentSubTarget==target and legacy.weight==110 and not legacy.resetsWhenDone)
 for i=1,30 do s.now=722+i;Care.tick(s,ms)end
 assert(calls.rebucket==1 and calls.goap==1)
end)
test('legacy migration preserves foreign signatures, later packages and player orders',function()
 for _,alter in ipairs({
  function(g)g.weight=109 end,
  function(g)g.startTime=6 end,
  function(g)g.endTime=23 end,
  function()label='Foreign emergency' end,
  function()orders=true end,
  function()combat=true end,
 })do
  fixture();carried=h(nil)
  local g={key=function()return 106 end,priority=3,weight=110,startTime=0,endTime=24}
  table.insert(o.goals[4],g);alter(g);Care.tick(s,ms)
  assert(calls.rebucket==0 and calls.goap==0 and g.priority==3)
 end
end)
test('unavailable legacy re-bucketing API stops after three safe attempts',function()
 fixture();carried=h(nil)
 local g={key=function()return 106 end,priority=3,weight=110,startTime=0,endTime=24}
 table.insert(o.goals[4],g);o.addGoal=nil
 for i=1,20 do s.now=720+i;Care.tick(s,ms)end
 assert(s.nativeCare.guard.migrationTries==3 and g.priority==3 and calls.goap==0)
end)
test('a rejected legacy reinsert restores the original goal without resetting its action',function()
 fixture();carried=h(nil)
 local g={key=function()return 106 end,priority=3,weight=110,startTime=0,endTime=24}
 table.insert(o.goals[4],g)
 o.addGoal=function(_,goal)
  if goal.priority==2 then error('rescue bucket unavailable')end
  table.insert(o.goals[goal.priority+1],goal)
 end
 for i=1,20 do s.now=720+i;Care.tick(s,ms)end
 assert(s.nativeCare.guard.migrationTries==3 and o.goals[4][1]==g and #o.goals[4]==1 and #o.goals[3]==0)
 assert(g.priority==3 and calls.goap==0)
end)
test('carry readback rejects a goal in the wrong priority bucket',function()
 fixture();local foreign={key=function()return 106 end,priority=2};table.insert(o.goals[4],foreign)
 assert(Care.goal(c,106)==nil)
 Care.tick(s,ms);assert(calls.add==0 and o.goals[4][1]==foreign)
end)
test('the helper registers priority 2 while urgent medical goals remain unchanged',function()
 fixture();local medical={key=function()return 58 end,priority=3};table.insert(o.squadAIPackage[4],medical)
 Care.tick(s,ms);local continuation=Care.goal(c,106,true)
 assert(continuation and continuation.priority==2 and o.goals[3][1]==continuation)
 assert(o.squadAIPackage[4][1]==medical and medical.priority==3)
 assert(logs[2]:find('CONTINUATION_READY',1,true) and logs[2]:find('priority=2',1,true))
end)
test('ordinary unloaded/noncarrying duty does not install or falsely complete rescue',function()
 fixture();carried=h(nil);Care.tick(s,ms);assert(calls.add==0 and calls.queries==0 and #logs==0)
 s.platoon=nil;carried=h('patient',patient);Care.tick(s,ms);assert(calls.add==0)
end)
test('release alone is not proof of success; only native in-bed readback confirms it',function()
 fixture();Care.tick(s,ms);carried=h(nil);s.now=721;Care.tick(s,ms)
 s.now=721.3;Care.tick(s,ms);assert(logs[#logs]:find('BED_NOT_CONFIRMED',1,true))
 inBed=true;s.now=724;Care.tick(s,ms);assert(logs[#logs]:find('event=BED_CONFIRMED',1,true))
end)
test('carrying observations and bed queries are bounded, with justAsking=true',function()
 fixture();for i=0,50 do s.now=720+i;Care.tick(s,ms)end;assert(calls.queries==3)
end)
test('KSB2 and older packages remain recognized for safe native migration',function()
 fixture()
 for _,version in ipairs({'KS82','KS83','KS84','KS85','KS86','KS87','KS90','KSB2'})do
  assert(Role.isWorkingPackage(s.cfg,version..' Indoor guards'))
 end
 assert(not Role.isWorkingPackage(s.cfg,'Foreign Indoor guards'))
end)
print('Native rescue API tests passed: '..count)
