-- Tests of the Lua/native API boundary. No Kenshi AI is executed.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local logs={}
package.loaded.Diagnostics={console=function(s)logs[#logs+1]=s end}
package.loaded['Core.NPC.NativeNodes']={ensure=function()return true end}
local O=require('Core.NPC.OriginTown')
local Home=require('Core.NPC.HomeAssignment')
local Service=require('Core.NPC.ServiceTown')
local Work=require('Core.NPC.RoleAI')
local Transport=require('Core.NPC.Transport')
local function handle(id,target)
 return {toString=function()return id end,isNull=function()return id==nil end,getTown=function()return target end}
end
local function faction(id,player,hostile)
 return {getData=function()return {stringID=id}end,isThePlayer=function()return player end,
 isNotARealFaction=function()return false end,relations={isEnemy=function(_,other)return hostile and other~=nil or false end}}
end
local npc=faction('400-KenshiShop.mod',false)
local other=faction('neutral',false)
local player=faction('player',true)
local enemy=faction('enemy',false,true)
local function town(id,f,x,kind)
 local t={townType=kind or 2,isValid=function()return true end,getFaction=function()return f end,
 getGameData=function()return {stringID=id..'-data'}end,getPosition=function()return {x=x,y=0,z=0}end}
 t.getHandle=function()return handle(id,t)end
 return t
end
local service=town('service',player,0,1)
local origin=town('origin',other,500)
local all
function getSharedKing()
 return {townList={getAllTowns=function()
  local roots={}
  for i,t in ipairs(all)do roots[i]={getHandle=t.getHandle}end
  return roots
 end}}
end
local state,ms,bb,p,owns,memberOwn,activePackage,replacements,wakes,birthWrites,buildingWrites
local busy=false
local function ownership(initial)
 local o={_homeTown=initial,_homeBuilding=handle('building')}
 function o:setHomeTown(t,kind)
  assert(kind==1);birthWrites=birthWrites+1
  -- Actual native guard: NPC faction may not take a player town as home.
  if t:getFaction():isThePlayer()==false then self._homeTown=t end
 end
 function o:setHomeBuilding(h,kind)
  buildingWrites=buildingWrites+1
  self:setHomeTown(service,kind) -- native setter's implicit home-town attempt
  self._homeBuilding=h
 end
 return o
end
local function fixture(initial)
 logs={};all={service,origin};replacements=0;wakes=0;birthWrites=0;buildingWrites=0;busy=false
 owns=ownership(initial);memberOwn=ownership(initial)
 activePackage={}
 bb={name='KS Medic Robotics Rescue',getCurrentPackage=function()return activePackage end}
 function bb:getCurrentAIPackageName()return self.name end
 function bb:replaceAIPackage(data)self.name=data.name;activePackage={};replacements=replacements+1 end
 function bb:getMissionTown(fallback)return self.override or activePackage.missionTown or (fallback and owns._homeTown:getHandle() or handle(nil))end
 local function member(id,own)
  local broadcast={}
  local c={getHandle=function()return handle(id)end,getStateBroadcast=function()return broadcast end,
   getBlackboard=function()return bb end,getOwnerships=function()return own end,
   getAI=function()return {resultsCache={resetAllCaches=function()end}}end,
  reThinkCurrentAIAction=function()end,setupPlatoonAI=function()end,getCarryingObject=function()return handle(nil)end,
   getOrdersReciever=function()return {goals={},hasOrders=function()return false end,setNeedGOAP=function()wakes=wakes+1 end}end}
  for _,key in ipairs({'isDead','isDown','isUnconcious','isCrippled','isBeingCarried','isInCombatMode','isFleeing'})do c[key]=function()return busy end end
  return {key=id,char=c}
 end
 ms={member('leader',owns),member('mate',memberOwn)}
 local ap={getSquadLeader=function()return ms[1].char end,getSquadSize=function()return #ms end}
 p={getFaction=function()return npc end,getOwnerships=function()return owns end,getSquadType=function()return 1 end,
 getActivePlatoon=function()return ap end,myBaseHomeTownData={stringID='old-player-template'}}
 local b={getHandle=function()return handle('building')end,getTown=function()return service end,
 getFaction=function()return npc end,getPosition=function()return {x=0,y=0,z=0}end,isValid=function()return true end}
 state={key='building',platoon=p,building=b,cfg={role='guard',shop='weapons',count=2,faction='400-KenshiShop.mod',template='staff'}}
 function getGameWorld()return {gamedata={getData=function()return {name='KSB2 Indoor guards'}end}}end
 return state
end
test('new origin selection excludes every player outpost, ruins and hostile towns',function()
 fixture(nil)
 local second=town('second-player-outpost',player,1,1)
 local third=town('third-player-outpost',player,2,1)
 local ruins=town('ruins',other,3,4)
 local hostile=town('hostile',enemy,4)
 all={third,hostile,service,ruins,second,origin}
 local result=O.select(npc,{x=0,z=0})
 assert(result==origin)
end)
test('saved origin remains stable when a closer town appears or NPC moves',function()
 fixture(origin);all={town('nearer',other,1),service}
 assert(O.select(npc,{x=99999,z=0},origin)==origin)
 assert(Home.ensure(state,ms,bb));assert(owns._homeTown==origin and memberOwn._homeTown==origin)
 assert(p.myBaseHomeTownData.stringID=='origin-data' and bb.targetTown==service)
end)
test('nil alpha.85 origins repaired before building setters; native guard is respected',function()
 fixture(nil);assert(Home.ensure(state,ms,bb))
 assert(owns._homeTown==origin and memberOwn._homeTown==origin)
 assert(O.handleID(owns._homeBuilding)=='building' and O.handleID(memberOwn._homeBuilding)=='building')
 assert(birthWrites==5 and buildingWrites==3)
 for _,m in ipairs(ms)do assert(O.handleID(m.char:getStateBroadcast().homeBuilding)=='building')end
end)
test('members with a different valid origin keep their own origin',function()
 fixture(origin);local ownOrigin=town('member-origin',other,800);memberOwn._homeTown=ownOrigin
 assert(Home.ensure(state,ms,bb));assert(memberOwn._homeTown==ownOrigin and owns._homeTown==origin)
end)
test('same-faction existing town wins deterministically; unknown flags do not authorize selection',function()
 fixture(nil)
 local mine=town('own-faction',npc,900);all={origin,mine,service}
 assert(O.select(npc,{x=0,z=0})==mine)
 local unknown=faction('unknown',nil);all={town('unknown',unknown,0)}
 assert(not O.select(npc,{x=0,z=0}))
end)
test('absent NPC town blocks spawning with a clear error',function()
 fixture(nil);all={service};local created=0
 local world=getGameWorld();world.theFactory={createRandomSquad=function()created=created+1 end}
 world.factionMgr={getFactionByStringID=function()return npc end}
 function getGameWorld()return world end
 local ok,err=pcall(Transport.preflight,state.building,state.cfg)
 assert(not ok and tostring(err):find('NPC_ORIGIN_UNAVAILABLE',1,true) and created==0)
end)
test('native squad creation receives origin and service as separate arguments',function()
 fixture(origin);local args
 local world={theFactory={createRandomSquad=function(_,...)args={...};return 'spawned'end}}
 assert(Transport.spawn({world=world,origin=origin,town=service,faction=npc,spawn={},template={}},state.building,state.cfg)=='spawned')
 assert(args[3]==origin and args[12]==service and args[5]==state.building and args[10]==true)
end)
test('mission town binds exact building town while native home remains unchanged',function()
 fixture(origin);assert(Home.ensure(state,ms,bb));assert(Service.bind(state,bb))
 assert(O.handleID(bb:getMissionTown(false))=='service' and O.handleID(bb:getMissionTown(true))=='service')
 assert(owns._homeTown==origin)
end)
test('targetTown alone cannot certify native mission routing',function()
 fixture(origin);bb.targetTown=service
 assert(not Service.verify(state,bb));assert(Service.bind(state,bb));assert(Service.verify(state,bb))
end)
test('higher-priority mission override fails readback; handoff stops after three failures',function()
 fixture(origin);bb.override=handle('different-town')
 for i=1,8 do assert(not Work.ensure(state,ms))end
 assert(state.work.tries==3 and not state.work.done and replacements==1 and wakes==0)
end)
test('saved KS86 package migrates once, does not force stock and keeps original native home',function()
 fixture(origin);bb.name='KS86 Indoor guards'
 assert(Work.isWorkingPackage(state.cfg,bb.name));assert(Work.ensure(state,ms))
 assert(Work.ensure(state,ms));assert(replacements==1 and wakes==2 and not state.work.upgraded)
 assert(owns._homeTown==origin and O.handleID(activePackage.missionTown)=='service')
end)
test('restored KSB2 package without a mission handle rebinds without replacing package',function()
 fixture(origin);bb.name='KSB2 Indoor guards'
 assert(Work.ensure(state,ms) and replacements==0 and Service.verify(state,bb))
end)
test('mission drift repairs are bounded, without changing origin or package',function()
 fixture(origin);assert(Work.ensure(state,ms));local writes=buildingWrites
 for i=1,3 do activePackage.missionTown=handle('origin');assert(Work.ensure(state,ms))end
 activePackage.missionTown=handle('origin');assert(not Work.ensure(state,ms))
 assert(state.work.missionDrifts==3 and replacements==1 and buildingWrites==writes and owns._homeTown==origin)
end)
test('later native packages and combat are not overridden by mission monitoring',function()
 fixture(origin);assert(Work.ensure(state,ms));local count=replacements
 bb.name='Native contracted job';assert(not Work.ensure(state,ms));assert(replacements==count)
 bb.name='KSB2 Indoor guards';assert(Work.ensure(state,ms) and state.work.missionDrifts==nil)
 activePackage.missionTown=handle('origin');busy=true
 assert(not Work.ensure(state,ms) and state.work.tries==0)
 busy=false;assert(Work.ensure(state,ms) and replacements==count)
end)
print('Origin/service boundary tests passed: '..passed)
