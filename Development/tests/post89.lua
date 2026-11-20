-- Binding contracts and scheduling only. These mocks do not execute Kenshi AI.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local logs={};package.loaded.Diagnostics={console=function(s)logs[#logs+1]=s end}
local bridge={available=function()return true end,create=function(factory,data,b,faction,p,q)return factory:createBound(data,p,b,faction,q)end}
package.loaded['Core.NPC.NativeBridge']=bridge
local Duty=require('Core.NPC.PostDuty');local Jobs=require('Core.NPC.PostJobs')
local Nodes=require('Core.NPC.NativeNodes');local Posts=require('Core.NPC.PostData');local Transform=require('Transform')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local current={}
local function hand(id,root)
 return {isNull=function()return id==nil end,toString=function()return id end,setNull=function()id=nil end,
 getCharacter=function()return current[id]end,
 getRootObject=function()return root end,getRootObjectBase=function()return root end}
end
local s,ms,b,calls,world,inside,active,blocked,newPriority,serial
local function fixture(role,shop,n)
 Duty.setTrace(false)
 Nodes.resetSession();current={};logs={};calls={jobs=0,rethinks=0,typed=0,opaque=0,public=0,inserts=0,physical=0,root=0};inside=true;active=268;blocked=false;newPriority=2;serial=0
 local container={selfType=1};local origin={x=100,y=10,z=200};local q={w=math.sqrt(0.5),x=0,y=math.sqrt(0.5),z=0}
 b={getRootNode=function()calls.root=calls.root+1;return 'physical-1'end,isPhysical=function()calls.physical=calls.physical+1;return true end,getScale=function()return 0.25 end,
 getTown=function()return {withinBordersRange=function()return true end}end,
 getPosition=function()return origin end,getOrientation=function()return q end,getFaction=function()return 'npc-faction'end,
 getDoor=function()return {getDoorPosOutside_extraFarOut=function(_,mult)return {x=101,y=10,z=200+5*mult}end}end}
 world={gamedata={getData=function(_,id,kind)assert(kind==0);return {stringID=id,bdata={['is node']=true}}end},theFactory={}}
 world.navmesh={getPositionValid=function()return true end}
 function getGameWorld()return world end
 function world.theFactory:createLocationNode()calls.opaque=calls.opaque+1;return {}end
 function world.theFactory:createBound(data,pos,home,owner,rot)
  assert(data.bdata['is node'] and home==b and owner=='npc-faction')
  calls.typed=calls.typed+1;serial=serial+1
  local wp=Transform.world(origin,q,1,{p={pos.x,pos.y,pos.z},q={rot.w,rot.x,rot.y,rot.z}})
  local floor=0
  local root={isInsideBuilding=hand('building'),getDataType=function()return 54 end,
   getPosition=function()return wp end,setFloor=function(_,v)floor=v end,getFloor=function()return floor end}
  root.getHandle=function()return hand('node-'..serial,root)end
  return root
 end
 world.theFactory.createBuilding=function()error('furniture mutation forbidden')end
 s={key='building',building=b,cfg={role=role or 'guard',shop=shop or 'weapons',count=n or 2},work={done=true},now=12*60}
 ms={}
 for i=1,(n or 2)do
  local goals={{},{},{},{},{}}
  for _,bucket in ipairs(goals)do function bucket:removeAt(index)table.remove(self,index)end end
  local order={goals=goals,hasOrders=function()return false end,setNeedGOAP=function()end,
   getCurrentGoal=function()return {key=function()return active end,subject=hand(nil)}end}
  function order:removeGoal(key)
   for _,bucket in ipairs(self.goals)do for j=#bucket,1,-1 do if bucket[j]:key()==key then table.remove(bucket,j)end end end
  end
  function order:addGoal(g)calls.inserts=calls.inserts+1;table.insert(goals[g.priority+1],g)end
  local npcName='guard-'..i
  local c={isValid=function()return true end,getName=function()return npcName end,setName=function(_,name)npcName=name end,getHandle=function()return hand('npc-'..i)end,getOrdersReciever=function()return order end,
   getCarryingObject=function()return hand(nil)end,getAI=function()return {resultsCache={resetAllCaches=function()end}}end,
   reThinkCurrentAIAction=function()calls.rethinks=calls.rethinks+1 end,
   getPosition=function()return origin end,getFloor=function()return 0 end,container=container,
   setDestination=function()error('coordinate movement forbidden')end,addJob=function()error('player order forbidden')end}
  setmetatable(c,{__index=function(_,k)if k=='isInsideBuilding'then return hand(inside and 'building' or nil)end end})
  for _,method in ipairs({'isDead','isDown','isUnconcious','isCrippled','isBeingCarried','isInCombatMode','isFleeing'})do c[method]=function()return blocked end end
  function c:addGoal(key,subject)
   assert(key==51 and subject:getDataType()==54);calls.jobs=calls.jobs+1
   order:addGoal({key=function()return key end,priority=newPriority,subject=subject:getHandle(),weight=1})
  end
  current['npc-'..i]=c;ms[#ms+1]={key='npc-'..i,char=c}
 end
end
test('exact shop boundaries including midnight and the following day',function()
 for _,row in ipairs({{0,false},{359.99,false},{360,true},{1379.99,true},{1380,false},{1439,false},{1440,false},{1800,true}})do
  assert(Duty.day(row[1])==row[2])
 end
end)
test('each two-floor shop supplies distinct original guard pools',function()
 for _,shop in ipairs({'bar','weapons','armour','engineering'})do
  for floor=0,1 do
   local list=Duty.candidates(shop,'guard',floor);assert(#list>=3)
   for _,i in ipairs(list)do assert(Posts[shop][i].kind==2 and Posts[shop][i].floor==floor)end
  end
 end
end)
test('two guards bind real node subjects with distinct floors; zero repeated jobs between rotations',function()
 fixture();Duty.tick(s,ms)
 assert(calls.jobs==2 and calls.rethinks==2)
 for i,m in ipairs(ms)do local _,g,bucket=Jobs.find(m.char);assert(bucket==1 and g.priority==1 and g.subject:getRootObject():getFloor()==i-1)end
 for i=1,100 do s.now=720+i*0.1;Duty.tick(s,ms)end
 assert(calls.jobs==2 and calls.rethinks==2)
end)
test('30 minute rotation changes subjects once; missed intervals do not issue catch-up orders',function()
 fixture();Duty.tick(s,ms);local _,g=Jobs.find(ms[1].char);local old=g.subject:toString()
 s.now=749.99;Duty.tick(s,ms);assert(calls.rethinks==2)
 s.now=750;Duty.tick(s,ms);assert(calls.rethinks==4 and g.subject:toString()~=old and calls.jobs==2)
 s.now=900;Duty.tick(s,ms);assert(calls.rethinks==6 and calls.jobs==2)
end)
test('combat/care defer rotation and resume one handoff when safe',function()
 fixture();Duty.tick(s,ms);blocked=true;s.now=750;Duty.tick(s,ms);assert(calls.rethinks==2)
 blocked=false;active=58;Duty.tick(s,ms);assert(calls.rethinks==2)
 active=268;Duty.tick(s,ms);assert(calls.rethinks==4)
end)
test('weapons shop closes at 23; one night job and one removal at 06, existing stock untouched',function()
 fixture('trader','weapons',1);active=20;Duty.tick(s,ms);assert(b.publicDaytime==true and calls.jobs==0)
 s.now=1380;Duty.tick(s,ms);assert(b.publicDaytime==false and calls.jobs==1)
 for i=1,20 do s.now=s.now+1;Duty.tick(s,ms)end;assert(calls.jobs==1 and calls.rethinks==1)
 s.now=1800;Duty.tick(s,ms);assert(b.publicDaytime==true and not select(2,Jobs.find(ms[1].char)) and calls.rethinks==2)
end)
test('24 hour shops receive neither closing flag nor night post job',function()
 for _,shop in ipairs({'bar','robotics'})do fixture('trader',shop,1);s.now=1380;Duty.tick(s,ms);assert(b.publicDaytime==nil and calls.jobs==0 and calls.typed==0)end
end)
test('chief street node follows actual door; night return works from outside the building',function()
 fixture('chief','police',1);active=38;Duty.tick(s,ms)
 local r=s.postDuty.members['npc-1'];local day=r.node
 assert(day.outside and day.root.isInsideBuilding:isNull() and day.floor==0)
 local p=day.base:getPosition();assert(math.abs(p.x-101)<0.0001 and math.abs(p.z-210)<0.0001)
 inside=false;s.now=1380;Duty.tick(s,ms)
 assert(r.mode=='NIGHT' and not r.node.outside and r.node.root.isInsideBuilding:toString()=='building' and calls.rethinks==2)
end)
test('NPC platoon containers are never confused with interiors; outside assignment needs no move order',function()
 fixture();inside=false;Duty.tick(s,ms);assert(calls.jobs==2 and calls.typed==#Posts.weapons and calls.opaque==0)
end)
test('new work goals use priority one, leaving rescue and urgent native care intact',function()
 fixture();newPriority=3
 local o=ms[1].char:getOrdersReciever();local care={key=function()return 58 end,priority=3};table.insert(o.goals[4],care)
 local rescue={key=function()return 106 end,priority=2};table.insert(o.goals[3],rescue)
 Duty.tick(s,ms);local _,g,bucket=Jobs.find(ms[1].char)
 assert(g and bucket==1 and g.priority==1 and o.goals[4][1]==care and o.goals[3][1]==rescue)
end)
test('saved KS posts migrate from priority two once without allocating replacement tasks',function()
 fixture();Duty.tick(s,ms)
 local c=ms[1].char;local o,g,bucket,tasks,slot=Jobs.find(c)
 local subject=g.subject
 tasks:removeAt(slot);g.priority=2;o:addGoal(g)
 local before=calls.inserts;local node=s.postDuty.members[ms[1].key].node
 assert(Jobs.assign(c,node))
 local _,after,priority=Jobs.find(c)
 assert(after==g and priority==1 and g.priority==1 and g.subject==subject)
 assert(calls.inserts==before+1 and calls.jobs==2)
 assert(Jobs.assign(c,node))
 assert(calls.inserts==before+1 and calls.jobs==2)
end)
test('saved post migration defers for combat and care without touching the task',function()
 fixture();Duty.tick(s,ms)
 local c=ms[1].char;local o,g,_,tasks,slot=Jobs.find(c)
 tasks:removeAt(slot);g.priority=2;o:addGoal(g)
 local before=calls.inserts;local node=s.postDuty.members[ms[1].key].node
 blocked=true;assert(not Jobs.assign(c,node));blocked=false
 active=58;assert(not Jobs.assign(c,node))
 assert(g.priority==2 and calls.inserts==before)
 active=268;assert(Jobs.assign(c,node))
 assert(g.priority==1 and calls.inserts==before+1)
end)
test('missing reinsert API preserves a saved KS task rather than deleting it',function()
 fixture();Duty.tick(s,ms)
 local c=ms[1].char;local o,g,_,tasks,slot=Jobs.find(c)
 tasks:removeAt(slot);g.priority=2;o:addGoal(g)
 o.addGoal=nil
 assert(not Jobs.assign(c,s.postDuty.members[ms[1].key].node))
 local _,same,bucket=Jobs.find(c)
 assert(same==g and bucket==2 and g.priority==2)
end)
test('failed priority-one insertion restores the saved post and stops after bounded retries',function()
 fixture();Duty.tick(s,ms)
 local c=ms[1].char;local o,g,_,tasks,slot=Jobs.find(c)
 tasks:removeAt(slot);g.priority=2;o:addGoal(g)
 local subject=g.subject;local nativeAdd=o.addGoal;local rejected,restored=0,0
 o.addGoal=function(self,task)
  if task.priority==1 then rejected=rejected+1;error('priority one unavailable')end
  restored=restored+1;return nativeAdd(self,task)
 end
 s.postDuty=nil
 for i=1,20 do Duty.tick(s,ms)end
 local _,same,bucket=Jobs.find(c)
 assert(rejected==3 and restored==3 and calls.jobs==2)
 assert(same==g and bucket==2 and g.priority==2 and g.subject==subject)
 assert(#o.goals[3]==1 and #o.goals[2]==0 and s.postDuty.members[ms[1].key].tries==3)
end)
test('foreign native goal 51 is preserved instead of claimed by the mod',function()
 fixture();local o=ms[1].char:getOrdersReciever();local foreign={key=function()return 51 end,weight=1,priority=2};table.insert(o.goals[3],foreign)
 Duty.tick(s,ms);assert(o.goals[3][1]==foreign and calls.jobs==1)
end)
test('foreign same-key posts prevent migration and clearing regardless of encounter order',function()
 for _,foreignFirst in ipairs({false,true})do
  fixture();Duty.tick(s,ms)
  local c=ms[1].char;local o,g,_,tasks,slot=Jobs.find(c)
  tasks:removeAt(slot);g.priority=2;o:addGoal(g)
  local foreign={key=function()return 51 end,weight=1,priority=2}
  table.insert(o.goals[3],foreignFirst and 1 or #o.goals[3]+1,foreign)
  local before=calls.inserts
  assert(not Jobs.assign(c,s.postDuty.members[ms[1].key].node))
  assert(not Jobs.clear(c))
  assert(g.priority==2 and foreign.priority==2 and #o.goals[3]==2 and calls.inserts==before)
 end
end)
test('typed API failures are bounded and keep original native posts available',function()
 fixture();local attempts=0;world.theFactory.createBound=function()attempts=attempts+1;error('unsupported')end
 for i=1,20 do Duty.tick(s,ms)end
 assert(calls.opaque==#Posts.weapons and attempts==1 and calls.jobs==0)
end)
test('night merchant and lower-floor guard do not claim the same post',function()
 fixture('guard','armour',2);Duty.tick(s,ms);local guard=ms[1];local _,gg=Jobs.find(guard.char)
 local trader=ms[2];local o=trader.char:getOrdersReciever();o:removeGoal(51)
 local ts={key=s.key,building=b,cfg={role='trader',shop='armour',count=1},work={done=true},now=1380}
 -- Use a different native handle from the actual second guard.
 trader={key='merchant',char=trader.char};Duty.tick(ts,{trader});local _,tg=Jobs.find(trader.char)
 assert(tg and tg.subject:toString()~=gg.subject:toString())
end)
test('assigned goal is not reported as actual arrival by readback',function()
 fixture();Duty.setTrace(true);Duty.tick(s,ms);s.now=722;Duty.tick(s,ms)
 local found=false
 for _,line in ipairs(logs)do if line:find('NPC_POST_OBSERVE90',1,true)then assert(line:find('arrived=false',1,true));found=true end end
 assert(found)
end)
test('routine rotations retain their cadence without disk or readback diagnostics by default',function()
 fixture('guard','weapons',1)
 local positionReads=0
 local originalPosition=ms[1].char.getPosition
 ms[1].char.getPosition=function(...)
  positionReads=positionReads+1
  return originalPosition(...)
 end
 Duty.tick(s,ms)
 local initial=#logs
 assert(logs[initial]:find('status=JOB_ASSIGNED',1,true))
 s.now=722;Duty.tick(s,ms)
 assert(s.postDuty.physicalAt==730 and positionReads==0)
 s.now=750;Duty.tick(s,ms)
 s.now=752;Duty.tick(s,ms)
 assert(#logs==initial and positionReads==0 and calls.rethinks==2)
 Duty.setTrace(true);s.now=780;Duty.tick(s,ms)
 s.now=782;Duty.tick(s,ms)
 assert(logs[initial+1]:find('status=JOB_ASSIGNED',1,true))
 assert(logs[initial+2]:find('NPC_POST_OBSERVE90',1,true) and positionReads==1)
 Duty.setTrace(false);s.now=810;Duty.tick(s,ms)
 s.now=812;Duty.tick(s,ms)
 assert(#logs==initial+2 and positionReads==1 and calls.rethinks==4)
end)
test('saved floor labels preserve a surviving second-floor guard across controller reload',function()
 fixture();Duty.tick(s,ms);assert(ms[2].char:getName()=='KS: Охрана (2 этаж)')
 s.postDuty=nil;s.now=800;Duty.tick(s,{ms[2]})
 assert(s.postDuty.floorByMember[ms[2].key]==1 and ms[2].char:getName()=='KS: Охрана (2 этаж)')
end)
test('working patrol receives no schedule or post interventions',function()
 fixture('patrol','police',3);for i=1,200 do s.now=720+i;Duty.tick(s,ms)end
 assert(calls.jobs==0 and calls.rethinks==0 and calls.typed==0 and calls.opaque==0)
end)
test('three patrol members get distinct outdoor night posts at the actual tower entrance',function()
 fixture('patrol','police',3);active=36;s.now=1380;Duty.tick(s,ms)
 assert(calls.jobs==3 and calls.rethinks==3)
 local positions={};local handles={}
 for i,m in ipairs(ms)do
  local r=s.postDuty.members[m.key];assert(r.mode=='NIGHT' and r.node.outside and r.node.floor==0)
  assert(r.node.root.isInsideBuilding:isNull())
  local p=r.node.base:getPosition();local key=string.format('%.3f:%.3f',p.x,p.z)
  assert(not positions[key] and not handles[r.node.handle:toString()]);positions[key]=true;handles[r.node.handle:toString()]=true
  assert(math.abs(p.z-210)<0.0001 and math.abs(p.x-101)<=5.001)
 end
 for i=1,100 do s.now=1380+i;Duty.tick(s,ms)end
 assert(calls.jobs==3 and calls.rethinks==3)
end)
test('06:00 removes each night job once; native patrol/follow is left to the package',function()
 fixture('patrol','police',3);active=141;s.now=1380;Duty.tick(s,ms)
 active=51;s.now=1800;Duty.tick(s,ms)
 assert(calls.jobs==3 and calls.rethinks==6)
 for _,m in ipairs(ms)do assert(not select(2,Jobs.find(m.char)) and s.postDuty.members[m.key].mode=='DAY')end
 for i=1,100 do s.now=1800+i;Duty.tick(s,ms)end
 assert(calls.rethinks==6)
end)
test('carrying and bed continuation defer only that patrol member, then complete one night handoff',function()
 fixture('patrol','police',3);active=36;s.now=1380
 local carrier=ms[1].char;local carry=true
 carrier.getCarryingObject=function()return hand(carry and 'patient' or nil)end
 Duty.tick(s,ms);assert(calls.jobs==2)
 carry=false;active=106;Duty.tick(s,ms);assert(calls.jobs==2)
 active=36;Duty.tick(s,ms);assert(calls.jobs==3)
end)
test('hired patrol stands by the tower during the day and patrols natively at night',function()
 fixture('patrol','police',3);s.cfg.patrolNight=true;s.cfg.streetSlotBase=3;active=36
 Duty.tick(s,ms);assert(calls.jobs==3 and calls.rethinks==3)
 for _,m in ipairs(ms)do
  local r=s.postDuty.members[m.key];assert(r.mode=='DAY' and r.node.outside and r.node.floor==0)
  assert(math.abs(r.node.base:getPosition().z-217.5)<0.0001)
 end
 for i=1,50 do s.now=720+i;Duty.tick(s,ms)end;assert(calls.jobs==3 and calls.rethinks==3)
 active=51;s.now=1380;Duty.tick(s,ms)
 for _,m in ipairs(ms)do assert(not select(2,Jobs.find(m.char)))end
 assert(calls.jobs==3 and calls.rethinks==6)
 for i=1,50 do s.now=1380+i;Duty.tick(s,ms)end;assert(calls.jobs==3 and calls.rethinks==6)
 s.now=1800;active=141;Duty.tick(s,ms);assert(calls.jobs==6 and calls.rethinks==9)
end)
test('two hired squads use separate post rows without claiming each other or original slots',function()
 fixture('patrol','police',6);s.cfg.count=3;s.cfg.patrolNight=true;s.cfg.streetSlotBase=3
 local first={ms[1],ms[2],ms[3]};local second={ms[4],ms[5],ms[6]}
 Duty.tick(s,first)
 local other={key=s.key,building=b,cfg={role='patrol',shop='police',count=3,patrolNight=true,streetSlotBase=6},work={done=true},now=s.now}
 Duty.tick(other,second);assert(calls.jobs==6)
 local locations={}
 for _,group in ipairs({{s,first},{other,second}})do
  for _,m in ipairs(group[2])do
   local p=group[1].postDuty.members[m.key].node.base:getPosition()
   local k=string.format('%.3f:%.3f',p.x,p.z);assert(not locations[k]);locations[k]=true
  end
 end
 for slot=1,3 do assert(Nodes.available(s,1,slot,'original'))end
end)
test('new hired posts reject invalid navigation and locations outside the city before creating a node',function()
 fixture('patrol','police',3);assert(Nodes.ensure(s,b));local before=calls.typed
 local index=Duty.candidates('police','patrol',0)[1]
 world.navmesh.getPositionValid=function()return false end
 local node,why=Nodes.target(s,b,ms,index,4)
 assert(not node and why:find('HIRED_POST_NAVMESH_INVALID',1,true) and calls.typed==before and calls.jobs==0)
 world.navmesh.getPositionValid=function()return true end
 b.getTown=function()return {withinBordersRange=function()return false end}end
 node,why=Nodes.target(s,b,ms,index,5)
 assert(not node and why:find('HIRED_POST_OUTSIDE_TOWN',1,true) and calls.typed==before and calls.jobs==0)
end)
test('a replacement patrol member reuses its predecessor slot while survivors keep theirs',function()
 fixture('patrol','police',4);s.cfg.count=3;s.cfg.patrolNight=true;s.cfg.streetSlotBase=3
 local old={ms[1],ms[2],ms[3]};Duty.tick(s,old)
 local oldSlot=s.postDuty.patrolSlots[ms[1].key];local survivorSlot=s.postDuty.patrolSlots[ms[2].key]
 s.now=730;Duty.tick(s,{ms[2],ms[3],ms[4]})
 assert(s.postDuty.patrolSlots[ms[1].key]==nil and s.postDuty.patrolSlots[ms[4].key]==oldSlot)
 assert(s.postDuty.patrolSlots[ms[2].key]==survivorSlot and calls.jobs==4)
end)
test('settled posts sleep until readback or rotation with only a ten-minute physical audit',function()
 fixture();Duty.setTrace(true);Duty.tick(s,ms);s.now=722;Duty.tick(s,ms)
 local physical,roots=calls.physical,calls.root
 for minute=723,731 do s.now=minute;Duty.tick(s,ms)end
 assert(calls.physical==physical and calls.root==roots and calls.rethinks==2)
 s.now=732;Duty.tick(s,ms)
 assert(calls.physical==physical+1 and calls.root==roots+1 and calls.rethinks==2)
 for minute=733,749 do s.now=minute;Duty.tick(s,ms)end
 assert(calls.rethinks==2)
 s.now=750;Duty.tick(s,ms);assert(calls.rethinks==4)
end)
test('native patrol shift waits for its deadline without polling each member',function()
 fixture('patrol','police',3);Duty.tick(s,ms)
 local physical,roots=calls.physical,calls.root
 for _,m in ipairs(ms)do m.char.getOrdersReciever=function()error('settled patrol was polled')end end
 for minute=721,739 do s.now=minute;Duty.tick(s,ms)end
 assert(calls.physical==physical+1 and calls.root==roots+1 and calls.rethinks==0)
end)
test('clock rollback recalculates deadlines and does not strand a guard rotation',function()
 fixture();Duty.tick(s,ms);s.now=722;Duty.tick(s,ms)
 s.now=700;Duty.tick(s,ms)
 assert(calls.rethinks==4 and s.postDuty.members[ms[1].key].nextAt==730)
 s.now=702;Duty.tick(s,ms);s.now=729;Duty.tick(s,ms);assert(calls.rethinks==4)
 s.now=730;Duty.tick(s,ms);assert(calls.rethinks==6)
end)
test('physical reload is audited and wakes settled posts before the next shift',function()
 fixture('chief','police',1);Duty.tick(s,ms)
 b.isPhysical=function()return false end;s.now=730;Duty.tick(s,ms)
 assert(s.postDuty.physical==nil and calls.rethinks==1)
 b.isPhysical=function()return true end;b.getRootNode=function()return 'physical-2'end
 s.now=731;Duty.tick(s,ms)
 assert(s.postDuty.physical=='physical-2' and calls.rethinks==2 and s.postDuty.members[ms[1].key].mode=='DAY')
end)
test('a deleted guard leaves no stale calls or occupied post when its replacement joins',function()
 fixture('guard','weapons',3);Duty.tick(s,{ms[1],ms[2]})
 local old=ms[1];local oldNode=s.postDuty.members[old.key].node
 local survivorNode=s.postDuty.members[ms[2].key].node
 local stale=0
 old.char.isDead=function()stale=stale+1;error('DELETED_CHARACTER_POINTER')end
 old.char.getHandle=function()stale=stale+1;error('DELETED_CHARACTER_POINTER')end
 current[old.key]=nil
 ms[3].char:setName('KS: Охрана (1 этаж)')
 s.now=721;Duty.tick(s,{ms[2],ms[3]})
 assert(stale==0 and calls.jobs==3)
 assert(s.postDuty.members[old.key]==nil and s.postDuty.floorByMember[old.key]==nil)
 assert(s.postDuty.members[ms[3].key].node.handle:toString()==oldNode.handle:toString())
 assert(s.postDuty.members[ms[2].key].node==survivorNode)
end)
test('claim health checks resolve the current character instead of a cached native wrapper',function()
 fixture('guard','weapons',1);Duty.tick(s,ms)
 local m=ms[1];local index=Duty.candidates('weapons','guard',0)[1]
 local stale,reads=0,0
 m.char.isDead=function()stale=stale+1;error('DELETED_CHARACTER_POINTER')end
 m.char.getHandle=function()stale=stale+1;error('DELETED_CHARACTER_POINTER')end
 local dead=false
 current[m.key]={isValid=function()return true end,getHandle=function()return hand(m.key)end,
  isDead=function()reads=reads+1;return dead end}
 assert(not Nodes.available(s,index,false,'other') and reads==1 and stale==0)
 dead=true;assert(Nodes.available(s,index,false,'other') and reads==2 and stale==0)
end)
test('an unloaded claim stays reserved until its own complete roster confirms departure',function()
 fixture('guard','weapons',2);Duty.tick(s,ms)
 local m=ms[1];local index=Duty.candidates('weapons','guard',0)[1]
 local stale=0;m.char.isDead=function()stale=stale+1;error('UNLOADED_CHARACTER_POINTER')end
 current[m.key]=nil
 assert(not Nodes.available(s,index,false,'other'))
 local other={key=s.key,cfg={shop='weapons',role='trader'}}
 Nodes.prune(other,{})
 assert(not Nodes.available(s,index,false,'other') and stale==0)
 current[m.key]={isValid=function()return true end,getHandle=function()return hand(m.key)end,isDead=function()return false end}
 assert(not Nodes.available(s,index,false,'other') and stale==0)
 Nodes.prune(s,{ms[2]})
 assert(Nodes.available(s,index,false,'replacement') and stale==0)
end)
test('all service roles release obsolete own claims without releasing another role',function()
 for _,role in ipairs({'guard','trader','chief','patrol'})do
  fixture(role,'police',2);assert(Nodes.ensure(s,b))
  Nodes.claim(s,1,false,ms[1])
  local other={key=s.key,cfg={shop='police',role='foreign-role'}}
  Nodes.claim(other,2,false,ms[2])
  Nodes.prune(s,{})
  assert(Nodes.available(s,1,false,'replacement'))
  assert(not Nodes.available(s,2,false,'replacement'))
 end
end)
test('extinct hired patrol claims follow the saved street row across new native platoon IDs',function()
 fixture('patrol','police',7);s.cfg.count=3;s.cfg.patrolNight=true;s.cfg.serviceHired=true
 s.cfg.streetSlotBase=3;s.cfg.existingID='old-pid'
 Duty.tick(s,{ms[1],ms[2],ms[3]})
 local other={key=s.key,building=b,cfg={role='patrol',shop='police',count=3,patrolNight=true,
  serviceHired=true,streetSlotBase=6,existingID='other-pid'},work={done=true},now=s.now}
 Duty.tick(other,{ms[4],ms[5],ms[6]})
 local stale=0
 for i=1,3 do
  current[ms[i].key]=nil
  ms[i].char.isDead=function()stale=stale+1;error('DELETED_CHARACTER_POINTER')end
 end
 local replacement={key=s.key,building=b,cfg={role='patrol',shop='police',count=3,patrolNight=true,
  serviceHired=true,streetSlotBase=3,existingID='new-pid'},work={done=true},now=s.now+1}
 Duty.tick(replacement,{ms[7]})
 assert(calls.jobs==7 and stale==0)
 local index=Duty.candidates('police','patrol',0)[1]
 assert(Nodes.available(replacement,index,4,ms[7].key))
 for slot=5,6 do assert(Nodes.available(replacement,index,slot,'other'))end
 for slot=7,9 do assert(not Nodes.available(replacement,index,slot,'other'))end
end)
test('physical unload and reload clear old node reservations before new selection',function()
 fixture('guard','weapons',3);Duty.tick(s,{ms[1],ms[2]})
 local stale=0;local oldKey=ms[1].key;local index=Duty.candidates('weapons','guard',0)[1]
 current[oldKey]=nil;ms[1].char.isDead=function()stale=stale+1;error('DELETED_CHARACTER_POINTER')end
 b.isPhysical=function()return false end;s.now=722;Duty.tick(s,{ms[2]})
 assert(not Nodes.available(s,index,false,'replacement') and stale==0)
 b.isPhysical=function()return true end;b.getRootNode=function()return 'new-physical'end
 ms[3].char:setName('KS: Охрана (1 этаж)');s.now=723;Duty.tick(s,{ms[2],ms[3]})
 assert(s.postDuty.members[ms[3].key].node and stale==0)
 Nodes.resetSession();assert(Nodes.available(s,index,false,'replacement') and stale==0)
end)
test('a temporary physical flag change reuses nodes when the actual root is unchanged',function()
 fixture('guard','weapons',3);local guards={ms[1],ms[2]};Duty.tick(s,guards)
 local other={key=s.key,cfg={shop='weapons',role='trader'}}
 local index=Duty.candidates('weapons','guard',0)[2];Nodes.claim(other,index,false,ms[3])
 local before=calls.typed
 b.isPhysical=function()return false end;s.now=730;Duty.tick(s,guards)
 b.isPhysical=function()return true end;s.now=731;Duty.tick(s,guards)
 assert(calls.typed==before and calls.opaque==0 and not Nodes.available(s,index,false,'replacement'))
 local nativeRoot=b.getRootNode;b.getRootNode=function()return nil end
 s.now=741;Duty.tick(s,guards)
 b.getRootNode=nativeRoot;s.now=742;Duty.tick(s,guards)
 assert(calls.typed==before and calls.opaque==0 and not Nodes.available(s,index,false,'replacement'))
 b.isPhysical=function()return false end;s.now=752;Duty.tick(s,guards)
 b.isPhysical=function()return true end;b.getRootNode=function()return 'different-native-root'end
 s.now=753;Duty.tick(s,guards)
 assert(calls.typed==before+#Posts.weapons and calls.opaque==0 and Nodes.available(s,index,false,'replacement'))
end)
test('an invalid resolved actor is never dereferenced for claim health',function()
 fixture('guard','weapons',1);Duty.tick(s,ms)
 local index=Duty.candidates('weapons','guard',0)[1];local read=0
 current[ms[1].key]={isValid=function()return false end,getHandle=function()error('INVALID_HANDLE_READ')end,
  isDead=function()read=read+1;error('INVALID_CHARACTER_READ')end}
 assert(not Nodes.available(s,index,false,'replacement') and read==0)
 Nodes.prune(s,{})
 assert(Nodes.available(s,index,false,'replacement') and read==0)
end)
print('Native post/shift API tests passed: '..count..'; game AI execution is not simulated')
