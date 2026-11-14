local root=assert(arg[1]);package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
package.loaded.Diagnostics={console=function()end,error=function()end}
local Goals=require('Core.NPC.NativeGoals');local Route=require('Core.NPC.CityRoute');local Residence=require('Core.NPC.Residence')
local Duty=require('Core.NPC.Duty');local Catalog=require('Core.NPC.Catalog')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function handle(key,obj)
 local h={toString=function()return key end,getPlatoon=function()return obj end}
 function h:isNull()return key==nil end
 function h:setNull()key=nil end
 return h
end
local function character(key,pos)
 local c={position=pos or {x=0,y=0,z=0},busy=false,active=0,carrying=false}
 local o={goals={},hasOrders=function()return false end,setNeedGOAP=function()end}
 function o:removeGoal(t)for i=#self.goals,1,-1 do if self.goals[i]:key()==t then table.remove(self.goals,i)end end end
 function o:getCurrentGoal()return {key=function()return c.active end}end
 function o:clearCurrentGoal()c.active=0 end
 function c:getOrdersReciever()return o end
 function c:getHandle()local h=handle(key);h.getCharacter=function()return self end;return h end
 function c:getPosition()return self.position end
 function c:pathExists()return true end
 function c:getCarryingObject()return {isNull=function()return not c.carrying end}end
 for _,name in ipairs({'isDead','isDown','isUnconcious','isCrippled','isBeingCarried','isFleeing'})do c[name]=function()return false end end
 function c:isInCombatMode()return self.busy end
 function c:isValid()return true end
 function c:addGoal(t,sub)
  assert(sub and sub.getHandle,"bad argument #3 (KenshiLua.RootObjectBase expected, got nil)")
  local g={subject=sub:getHandle(),weight=1,priority=0,key=function()return t end,setLocation=function(self,p)self.location=p end}
  o.goals[#o.goals+1]=g
 end
 function c:isEnemy(enemy)return enemy.hostile==true end
 function c:getSensoryData()return {canISeeThisGuy=function()return true end}end
 return c,o
end
local function count(o,t)local n=0;for _,g in ipairs(o.goals)do if g:key()==t then n=n+1 end end;return n end
local gate={getOutsideGateCode=function()return 2 end,getGateCodeAt=function(_,p)return p.x<100 and 1 or 2 end}
local town={withinBordersRange=function(_,p)return math.abs(p.x)<200 and math.abs(p.z)<200 end,
 hasGates=function()return true end,getNearestGate=function()return gate end,getPosition=function()return {x=0,y=0,z=0}end}
local b={getPosition=function()return {x=0,y=0,z=0}end,getOrientation=function()return {w=1,x=0,y=0,z=0}end,
 getScale=function()return 1 end,getTown=function()return town end,getHandle=function()return handle('home')end}
local world={navmesh={getPositionValid=function()return true end},charUpdateListMain={}}
function getGameWorld()return world end
local function state(role,shop)return {cfg={role=role,shop=shop or 'weapons',count=1},key='home',now=12*60,work={done=true}}end
local function house(x,z)
 return {isValid=function()return true end,isFurniture=function()return false end,isAWall=function()return nil end,isGate=function()return nil end,
 getDoor=function()return {getPositionForWaypoint=function()return {x=x,y=0,z=z}end}end}
end
local h1,h2,h3=house(10,30),house(-30,-20),house(150,40)
function town:getBuildingsManager()return {buildingEntities={[h1]=true,[h2]=true,[h3]=true}}end
test('ordinary movement/hold goals stay below emergency priority and never duplicate',function()
 local c,o=character('one');assert(Goals.routine(c,{x=10,y=0,z=0},false));assert(Goals.routine(c,{x=10,y=0,z=0},false));assert(count(o,1)==1 and o.goals[1].priority==2)
 assert(Goals.routine(c,{x=10,y=0,z=0},true));assert(count(o,1)==0 and count(o,30)==1)
 assert(o.goals[1].subject:isNull() and not c:getHandle():isNull())
end)
test('old addGoal binding rejects nil; location-only tasks clear the temporary subject',function()
 local c,o=character('strict')
 assert(not pcall(c.addGoal,c,1,nil))
 assert(Goals.routine(c,{x=20,y=0,z=30},false))
 assert(o.goals[1].subject:isNull() and o.goals[1].location.x==20)
 assert(not c:getHandle():isNull())
 local enemy=character('target');assert(Goals.set(c,5,nil,enemy,3))
 assert(o.goals[2].subject:toString()=='target')
end)
test('foreign native goals are never adopted or removed',function()
 local c,o=character('two');c:addGoal(1,c);assert(not Goals.routine(c,{x=1,y=0,z=0},false));Goals.clearRoutine(c);assert(count(o,1)==1)
end)
test('post audit preserves care, dialogue, sleep, combat, carrying and orders',function()
 local c,o=character('three')
 for _,task in ipairs({58,57,148,25,60,105,153,12})do c.active=task;assert(not Goals.safe(c))end
 c.active=0;c.busy=true;assert(not Goals.safe(c));c.busy=false;c.carrying=true;assert(not Goals.safe(c));c.carrying=false
 o.hasOrders=function()return true end;assert(not Goals.safe(c))
end)
test('gate codes reject outside points that are inside the town radius',function()
 assert(Route.inside(town,b:getPosition(),{x=20,y=0,z=0}));assert(not Route.inside(town,b:getPosition(),{x=150,y=0,z=0}))
 local missing={withinBordersRange=town.withinBordersRange,hasGates=town.hasGates};assert(not Route.inside(missing,b:getPosition(),{x=20,y=0,z=0}))
end)
test('city route contains only reachable streets on the home side of gates',function()
 local c=character('four');local route=assert(Route.build(b,c,world));assert(#route==2)
 for _,p in ipairs(route)do assert(p.x<100)end
end)
test('merchant moves to the recorded world post and verifies arrival',function()
 local c,o=character('merchant');local s=state('trader');Duty.tick(s,{{key='merchant',char=c}},b)
 assert(count(o,1)==1 and o.goals[1].location.z==-90.3616562)
 c.position=o.goals[1].location;s.now=s.now+1;Duty.tick(s,{{key='merchant',char=c}},b)
 assert(count(o,30)==1 and Duty.status(s)=='AT_POST:1')
end)
test('closed daytime shops release only their own routine goals',function()
 local c,o=character('night');local s=state('trader');Duty.tick(s,{{key='night',char=c}},b);s.now=23*60
 Duty.tick(s,{{key='night',char=c}},b);assert(count(o,1)==0 and count(o,30)==0)
end)
test('guard acquires a visible enemy at home and drops it outside the permitted area',function()
 local c,o=character('guard');local enemy=character('enemy',{x=20,y=0,z=0});enemy.hostile=true
 world.charUpdateListMain={[c]=true,[enemy]=true}
 local s=state('guard');Duty.tick(s,{{key='guard',char=c}},b);assert(count(o,5)==1)
 c.active=5;c.busy=true;enemy.position={x=300,y=0,z=0};Duty.tick(s,{{key='guard',char=c}},b)
 assert(count(o,5)==0 and c.active==0)
 world.charUpdateListMain={}
end)
test('patrol cannot acquire an enemy beyond a city gate',function()
 local c,o=character('patrol',{x=60,y=0,z=0});local enemy=character('outside',{x=110,y=0,z=0});enemy.hostile=true
 world.charUpdateListMain={[c]=true,[enemy]=true};local s=state('patrol','police');Duty.tick(s,{{key='patrol',char=c}},b)
 assert(count(o,5)==0);world.charUpdateListMain={}
end)
test('failed route detection produces no wandering movement',function()
 local old=town.getBuildingsManager;town.getBuildingsManager=function()return {buildingEntities={}}end
 local c,o=character('waiting');local s=state('patrol','police');Duty.tick(s,{{key='waiting',char=c}},b);assert(#o.goals==0)
 town.getBuildingsManager=old
end)
test('resident setter no-op is repaired through the verified parent handle',function()
 local faction={getData=function()return {stringID='400-KenshiShop.mod'}end}
 local guard={getPlatoonStringID=function()return 'guards'end}
 local trader={getPlatoonStringID=function()return 'trader'end,squadTemplate={stringID='307-KenshiShop.mod'},getFaction=function()return faction end,
 getOwnerships=function()return {_homeBuilding=handle('home')}end}
 function trader:getHandle()return handle('trader',self)end
 local building={residentSquad=handle('guards',guard),setResidentSquad=function()end,getFaction=function()return faction end,getHandle=function()return handle('home')end}
 assert(Residence.bind(building,trader,guard));assert(building.residentSquad:getPlatoon()==trader)
 assert(building.residentSquadTemplate==trader.squadTemplate)
end)
test('faction quality weights are restored on success and on native failure',function()
 local original={idata={}};local quality={idata={}}
 for i=0,5 do original.idata['armors '..i]=i;quality.idata['armors '..i]=0 end
 quality.idata['armors 5']=100
 local s={platoon={getFaction=function()return {getData=function()return original end}end}}
 Catalog.withQuality(s,{quality=quality},function()assert(original.idata['armors 5']==100 and original.idata['armors 2']==0)end)
 assert(original.idata['armors 5']==5 and original.idata['armors 2']==2)
 assert(not pcall(Catalog.withQuality,s,{quality=quality},function()error('native fill failed')end))
 for i=0,5 do assert(original.idata['armors '..i]==i)end
end)
test('upgrading saved stock forces exactly one native refresh; reloading never forces again',function()
 local prepare=Catalog.prepare;Catalog.prepare=function()return true,{source='fixture'}end
 local forced,ordinary=0,0
 local ap={getHasVendorList=function()return true end,getIsTrader=function()return true end,setupTraderBuildings=function()end,
  _forceRefreshInventory=function()forced=forced+1 end,refreshInventory=function(_,first)assert(first==false);ordinary=ordinary+1 end}
 local p={getActivePlatoon=function()return ap end}
 local s={cfg={role='trader',shop='weapons'},saved=true,now=1,work={done=true,upgraded=true},platoon=p}
 assert(Catalog.ensure(s,{}));assert(Catalog.ensure(s,{}));assert(forced==1)
 local loaded={cfg=s.cfg,saved=true,now=2,work={done=true},platoon=p}
 assert(Catalog.ensure(loaded,{}));assert(forced==1 and ordinary==2)
 Catalog.prepare=prepare
end)
test('a stalled safe NPC gets at most three native movement recovery calls',function()
 local c,o=character('stalled');local moves=0
 c.setDestination=function()moves=moves+1 end
 local s=state('trader');local ms={{key='stalled',char=c}}
 for i=0,15 do s.now=12*60+i;Duty.tick(s,ms,b)end
 assert(moves==3 and count(o,1)==1)
 c.active=58;s.now=s.now+10;Duty.tick(s,ms,b);assert(moves==3)
end)
test('a failed native goal still gets bounded movement recovery, preserving care',function()
 local c,o=character('binding-failure');local moves=0
 c.addGoal=function()error('native API unavailable')end
 c.setDestination=function(_,p,teleport)assert(teleport==false and p.z<0);moves=moves+1 end
 local s=state('trader');local ms={{key='binding-failure',char=c}}
 for i=0,15 do s.now=12*60+i;Duty.tick(s,ms,b)end
 assert(moves==3 and #o.goals==0 and Duty.status(s)=='GOAL_FAILED:1')
 c.active=58;s.now=s.now+10;Duty.tick(s,ms,b);assert(moves==3)
end)
test('post projection only adjusts destination height within the same floor',function()
 local c,o=character('height');local old=world.navmesh.getPositionValid
 local Posts=require('Core.NPC.PostData');local raw
 for _,p in ipairs(Posts.weapons)do if p.role=='trader'then raw=p;break end end
 world.navmesh.getPositionValid=function(_,p)return math.abs(p.y-(raw.p[2]+2))<0.01 end
 local s=state('trader');Duty.tick(s,{{key='height',char=c}},b)
 assert(count(o,1)==1);local p=o.goals[1].location
 assert(p.x==raw.p[1] and p.z==raw.p[3] and math.abs(p.y-raw.p[2])<=8)
 world.navmesh.getPositionValid=old
end)
print('Duty regression tests passed: '..passed)
