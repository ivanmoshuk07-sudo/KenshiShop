-- Chief-service patrol integration: native identities and roster handoffs only.
-- This does not run the game planner or simulate a walking route.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function handle(id,b)return {toString=function()return id end,getBuilding=function()return b end,isNull=function()return id==nil end}end
local faction={getData=function()return {stringID='400-KenshiShop.mod'}end}
local building={isValid=function()return true end,getPosition=function()return {x=0,y=0,z=0}end}
function building:getHandle()return handle('tower',self)end
local function platoon(id)
 local p={squadTemplate={stringID='11000-KenshiShop.mod'}}
 function p:getPlatoonStringID()return id end
 function p:getOwnerships()return {_homeBuilding=handle('tower')}end
 function p:getFaction()return faction end
 return p
end
local first,second,unloaded=platoon('hire1'),platoon('hire2'),platoon('hire3')
function faction:getActivePlatoons()return {first,second}end
function faction:getUnloadedPlatoons()return {unloaded}end
local world={factionMgr={getFactionByStringID=function()return faction end}}
function getGameWorld()return world end
local Existing=require('Core.NPC.ExistingSquads')
test('same-template hired squads resolve by persistent platoon ID including unloaded rosters',function()
 local cfg={template='11000-KenshiShop.mod',faction='400-KenshiShop.mod'}
 local p,why=Existing.find(building,cfg);assert(p==nil and why:find('AMBIGUOUS',1,true))
 cfg.existingID='hire2';assert(Existing.find(building,cfg)==second)
 cfg.existingID='hire3';assert(Existing.find(building,cfg)==unloaded)
 cfg.existingID='never-spawned';assert(Existing.find(building,cfg)==false)
end)

local frames,clock,hooks={ },100,0
Events={on=function(_,fn)hooks=hooks+1;frames[hooks]=fn;return hooks end,off=function(id)frames[id]=nil end}
local function run(minutes)
 clock=clock+minutes
 for i=1,40 do for _,fn in pairs(frames)do fn()end end
end
local moves,spawns,owners,observations=0,0,0,0
local observed={}
package.loaded.Diagnostics={console=function()end,error=function(msg)error(msg)end}
local Live={call=function(o,m,...)if o and type(o[m])=='function'then return o[m](o,...)end end,
 clock=function()return clock end,halted=function()return false end,safeToOrder=function()return true end,copy=function(p)return p end}
package.loaded['Core.NPC.LiveState']=Live
package.loaded['Core.NPC.NoSever']={tick=function()end}
package.loaded['Core.NPC.Transport']={members=function(_,p)return p.members end,valid=function()return true end,
 distance2D=function()return 900 end,spawn=function()spawns=spawns+1 end}
package.loaded['Core.NPC.Appearance']={apply=function()error('saved NPC appearance must not change')end}
package.loaded['Core.NPC.Supplies']={sync=function()return true,'UNCHANGED'end}
package.loaded['Core.NPC.Residence']={ensure=function()return true end}
package.loaded['Core.NPC.Duty']={tick=function()end,status=function()return 'TEST'end}
package.loaded['Core.NPC.Catalog']={ensure=function()end,prepare=function()return true end}
package.loaded['Core.NPC.RoleAI']={
 isWorkingPackage=function(_,label)return label=='KSB3 Hired night patrol'end,
 package=function()return '11001-KenshiShop.mod','KSB3 Hired night patrol'end,
 ensure=function(s,ms)
  s.work=s.work or {setup={},activation={}}
  for _,m in ipairs(ms)do s.work.setup[m.key]=s.work.setup[m.key] or {};s.work.activation[m.key]=s.work.activation[m.key] or {}end
  s.work.done=true
 end,status=function()return 'READY'end}
package.loaded['Core.Ownership.Registry']={onArrived=function()owners=owners+1 end,onRestored=function()owners=owners+1 end}
_G.KenshiShopPoliceServices={observe=function(s)observations=observations+1;observed[s.platoon:getPlatoonStringID()]=s end}
local function member(id)
 return {key=id,char={getHandle=function()return handle(id)end,
 getBlackboard=function()return {getCurrentAIPackageName=function()return 'KSB3 Hired night patrol'end}end,
 setDestination=function()moves=moves+1 end}}
end
for _,p in ipairs({first,second})do
 p.members={member(p:getPlatoonStringID()..'-1'),member(p:getPlatoonStringID()..'-2')}
 local ap={getSquadSize=function()return #p.members end,getSquadLeader=function()return p.members[1].char end}
 function p:getActivePlatoon()return ap end
end
local Controller=require('Core.NPC.Controller')
local driver=Controller.new({shop='police',role='patrol',template='11000-KenshiShop.mod',faction='400-KenshiShop.mod',count=3,
 patrolNight=true,streetSlotBase=3,serviceHired=true,existingID='hire1'})
test('paid service adopts the exact native squad without spawning or replacing the tower resident',function()
 assert(not driver.start(building));assert(not driver.adopt(building,second))
 assert(driver.adopt(building,first));run(0)
 assert(driver.status(building):find('DELIVERED',1,true))
 assert(spawns==0 and moves==0 and owners==0 and observations>0)
end)
test('a paid replacement invalidates cached work while retaining survivor setup and activation',function()
 local s=assert(observed.hire1);local setup=s.work.setup[first.members[1].key];local activation=s.work.activation[first.members[1].key]
 first.members[2]=member('replacement');assert(driver.adopt(building,first));run(1)
 assert(observed.hire1==s and s.work.rosterDirty==true and s.work.homeDone==false)
 assert(s.work.setup[first.members[1].key]==setup and s.work.activation[first.members[1].key]==activation)
 assert(s.work.setup.replacement and s.work.activation.replacement)
 assert(spawns==0 and moves==0 and owners==0)
end)
test('separate hired drivers coexist at one tower and resume only their own squad',function()
 local other=Controller.new({shop='police',role='patrol',template='11000-KenshiShop.mod',faction='400-KenshiShop.mod',count=3,
  patrolNight=true,streetSlotBase=6,serviceHired=true,existingID='hire2'})
 assert(other.adopt(building,second));run(1)
 assert(observed.hire1~=observed.hire2 and observed.hire2.platoon==second)
 assert(driver.resume(building));run(0);run(10);run(0)
 assert(observed.hire1.platoon==first and owners==0 and spawns==0 and moves==0)
 other.resetSession();driver.resetSession();assert(next(frames)==nil)
end)
_G.KenshiShopPoliceServices=nil

-- Exercise the real RoleAI and activation cache with a verified roster change.
package.loaded['Core.NPC.RoleAI']=nil
package.loaded['Core.NPC.NativeActivation']=nil
package.loaded['Core.NPC.NativeGoals']={remove=function()return true,false end,current=function()end}
package.loaded['Core.NPC.NativeNodes']={ensure=function()return true end}
package.loaded['Core.NPC.HomeAssignment']={ensure=function()return true end}
package.loaded['Core.NPC.ServiceTown']={verify=function()return true end,bind=function()return true end}
package.loaded['Core.NPC.OriginTown']={id=function()return 'town'end,field=function(o,k)return o and o[k]end}
local Role=require('Core.NPC.RoleAI')
local bb={name='KSB2 Indoor guards',getCurrentAIPackageName=function(self)return self.name end,
 replaceAIPackage=function()error('matching package must not be replaced')end}
local setups,wakes={},{ }
local function actual(id)
 local c={getHandle=function()return handle(id)end,getBlackboard=function()return bb end,
  getCarryingObject=function()return handle(nil)end,
  setupPlatoonAI=function()setups[id]=(setups[id] or 0)+1 end,
  getAI=function()return {resultsCache={resetAllCaches=function()end}}end,
  reThinkCurrentAIAction=function()wakes[id]=(wakes[id] or 0)+1 end,
  getOrdersReciever=function()return {goals={},hasOrders=function()return false end,setNeedGOAP=function()end,
   getCurrentGoal=function()return {key=function()return 51 end}end}end}
 return {key=id,char=c}
end
local a,b,c=actual('survivor'),actual('former'),actual('new')
local roster={a,b};local ap={getSquadSize=function()return #roster end,getSquadLeader=function()return roster[1].char end}
local p={getActivePlatoon=function()return ap end,getOwnerships=function()return {_homeBuilding=handle('tower')}end}
building.getTown=function()return {}end
world.gamedata={getData=function()return {name='KSB2 Indoor guards'}end}
local s={cfg={shop='weapons',role='guard',count=2},key='tower',building=building,platoon=p}
test('new members receive real role setup once while initialized survivors retain activation',function()
 assert(Role.ensure(s,roster));assert(setups.survivor==1 and wakes.survivor==1)
 local setup,activation=s.work.setup,s.work.activation
 roster={a,c};s.work.rosterDirty=true;s.work.done=false;s.work.homeDone=false
 assert(Role.ensure(s,roster));assert(Role.ensure(s,roster))
 assert(s.work.setup==setup and s.work.activation==activation)
 assert(setups.survivor==1 and wakes.survivor==1 and setups.new==1 and wakes.new==1)
 roster={c,a};assert(Role.ensure(s,roster));assert(setups.survivor==1 and wakes.survivor==1 and setups.new==1 and wakes.new==1)
end)
test('a roster change does not overwrite a later foreign native contract',function()
 bb.name='Foreign emergency';s.work.rosterDirty=true;s.work.done=false
 assert(not Role.ensure(s,roster));assert(bb.name=='Foreign emergency')
end)
test('a replacement leader in the mod care package resumes work without resetting survivors',function()
 bb.name='KS Medic Robotics Rescue';s.work.rosterDirty=true;s.work.done=false
 local replaced=0
 bb.replaceAIPackage=function(self,data)replaced=replaced+1;self.name=data.name end
 assert(Role.ensure(s,roster));assert(Role.ensure(s,roster))
 assert(replaced==1 and bb.name=='KSB2 Indoor guards')
 assert(setups.survivor==1 and setups.new==1)
end)
test('only the hired night variant uses its distinct package',function()
 local id,label=Role.package({role='patrol',patrolNight=true})
 assert(id=='11001-KenshiShop.mod' and label=='KSB3 Hired night patrol')
 assert(Role.isWorkingPackage({role='patrol',patrolNight=true},label))
 assert(not Role.isWorkingPackage({role='patrol',patrolNight=true},'KSB2 Town patrol'))
 assert(Role.package({role='patrol'})=='10004-KenshiShop.mod')
end)
print('Chief hired-patrol integration tests passed: '..count)
