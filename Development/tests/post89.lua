-- Binding contracts and scheduling only. These mocks do not execute Kenshi AI.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local logs={};package.loaded.Diagnostics={console=function(s)logs[#logs+1]=s end}
local bridge={available=function()return true end,create=function(factory,data,b,faction,p,q)return factory:createBound(data,p,b,faction,q)end}
package.loaded['Core.NPC.NativeBridge']=bridge
local Duty=require('Core.NPC.PostDuty');local Jobs=require('Core.NPC.PostJobs')
local Nodes=require('Core.NPC.NativeNodes');local Posts=require('Core.NPC.PostData');local Transform=require('Transform')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function hand(id,root)
 return {isNull=function()return id==nil end,toString=function()return id end,setNull=function()id=nil end,
 getRootObject=function()return root end,getRootObjectBase=function()return root end}
end
local s,ms,b,calls,world,inside,active,blocked,newPriority,serial
local function fixture(role,shop,n)
 Nodes.resetSession();logs={};calls={jobs=0,rethinks=0,typed=0,opaque=0,public=0};inside=true;active=268;blocked=false;newPriority=2;serial=0
 local container={selfType=1};local origin={x=100,y=10,z=200};local q={w=math.sqrt(0.5),x=0,y=math.sqrt(0.5),z=0}
 b={getRootNode=function()return 'physical-1'end,isPhysical=function()return true end,getScale=function()return 0.25 end,
 getPosition=function()return origin end,getOrientation=function()return q end,getFaction=function()return 'npc-faction'end,
 getDoor=function()return {getDoorPosOutside_extraFarOut=function(_,mult)assert(mult==2);return {x=101,y=10,z=210}end}end}
 world={gamedata={getData=function(_,id,kind)assert(kind==0);return {stringID=id,bdata={['is node']=true}}end},theFactory={}}
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
  function order:addGoal(g)table.insert(goals[g.priority+1],g)end
  local npcName='guard-'..i
  local c={getName=function()return npcName end,setName=function(_,name)npcName=name end,getHandle=function()return hand('npc-'..i)end,getOrdersReciever=function()return order end,
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
  ms[#ms+1]={key='npc-'..i,char=c}
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
 for i,m in ipairs(ms)do local _,g,bucket=Jobs.find(m.char);assert(bucket==2 and g.subject:getRootObject():getFloor()==i-1)end
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
test('new goals are placed in the actual nonurgent bucket, leaving urgent native care intact',function()
 fixture();newPriority=3
 local o=ms[1].char:getOrdersReciever();local care={key=function()return 58 end,priority=3};table.insert(o.goals[4],care)
 Duty.tick(s,ms);local _,g,bucket=Jobs.find(ms[1].char)
 assert(g and bucket==2 and g.priority==2 and o.goals[4][1]==care)
end)
test('foreign native goal 51 is preserved instead of claimed by the mod',function()
 fixture();local o=ms[1].char:getOrdersReciever();local foreign={key=function()return 51 end,weight=1,priority=2};table.insert(o.goals[3],foreign)
 Duty.tick(s,ms);assert(o.goals[3][1]==foreign and calls.jobs==1)
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
 fixture();Duty.tick(s,ms);s.now=722;Duty.tick(s,ms)
 local found=false
 for _,line in ipairs(logs)do if line:find('NPC_POST_OBSERVE89',1,true)then assert(line:find('arrived=false',1,true));found=true end end
 assert(found)
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
print('Native post/shift API tests passed: '..count..'; game AI execution is not simulated')
