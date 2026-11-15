-- Native API wiring and readback; does not simulate patient movement or healing.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local logs={};package.loaded.Diagnostics={console=function(s)logs[#logs+1]=s end}
local Care=require('Core.NPC.NativeCare');local Role=require('Core.NPC.RoleAI')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function h(id,c)return {isNull=function()return id==nil end,toString=function()return id end,getCharacter=function()return c end}end
local function buckets()return {{},{},{},{},{}}end
local s,ms,c,ai,o,carried,dead,orders,fail,calls,inBed,label,active,patient
local function fixture()
 logs={};dead=false;orders=false;fail=false;calls={add=0,goap=0,queries=0};inBed=false;label='KS87 Indoor guards';active=51
 local pai={isInBed=function()return inBed end}
 patient={getAI=function()return pai end,getPosition=function()return {x=10,y=0,z=10}end,isDead=function()return false end}
 carried=h('patient',patient)
 o={goals=buckets(),squadAIPackage=buckets(),hasOrders=function()return orders end,
  getCurrentGoal=function()return {key=function()return active end,subject=h('bed')}end,
  setNeedGOAP=function()calls.goap=calls.goap+1 end}
 ai={addAIGoalsFrom=function(_,data,list)
  assert(data.id=='9007-KenshiShop.mod' and list=='Leader AI Goals');calls.add=calls.add+1
  if fail then error('native API unavailable')end
  table.insert(o.goals[4],{key=function()return 106 end,priority=3})
 end,
 findOwnedFreeBed=function(_,target,asking)
  assert(target:toString()=='patient' and asking==true);calls.queries=calls.queries+1;return 0.5,h('bed')
 end}
 c={getAI=function()return ai end,getOrdersReciever=function()return o end,
 getBlackboard=function()return {getCurrentAIPackageName=function()return label end}end,
 getCarryingObject=function()return carried end,isDead=function()return dead end,
 getStateBroadcast=function()return {taskTarget=h('bed')}end}
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
test('new package supplies continuation without duplicate personal goals',function()
 fixture();label='KS90 Indoor guards';table.insert(o.squadAIPackage[4],{key=function()return 106 end,priority=3})
 Care.tick(s,ms);assert(calls.add==0 and #o.goals[4]==0 and calls.queries==1)
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
test('KS87/older packages remain recognized for safe migration to KS90',function()
 fixture()
 for _,version in ipairs({'KS82','KS83','KS84','KS85','KS86','KS87','KS90'})do
  assert(Role.isWorkingPackage(s.cfg,version..' Indoor guards'))
 end
 assert(not Role.isWorkingPackage(s.cfg,'Foreign Indoor guards'))
end)
print('Native rescue API tests passed: '..count)
