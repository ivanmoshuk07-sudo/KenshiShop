-- Tests API boundaries and failure reporting, not the game's AI implementation.
local root=assert(arg[1]);package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local messages={}
package.loaded.Diagnostics={console=function(x)messages[#messages+1]=x end,error=function(x)messages[#messages+1]=x end}
package.loaded['Core.NPC.NativeNodes']={ensure=function()return true end}
local Home=require('Core.NPC.HomeAssignment')
local Work=require('Core.NPC.RoleAI')
local passed=0
local function test(name,fn)messages={};fn();passed=passed+1;print('PASS '..name)end
local function hand(id)return {toString=function()return id end,isNull=function()return false end}end
local function town(id)return {getHandle=function()return hand(id)end}end
local function fixture()
 local t=town('target-town');local nearby=town('wrong-town')
 local f={getData=function()return {stringID='400-KenshiShop.mod'}end}
 local own={_homeBuilding=hand('home')};local counters={home=0,town=0,replace=0,setup=0,goap=0}
 function own:setHomeBuilding(h,kind)assert(kind==1);self._homeBuilding=h;counters.home=counters.home+1 end
 function own:setHomeTown(value,kind)assert(kind==1);self._homeTown=value;counters.town=counters.town+1 end
 local label='KS84 Indoor guards'
 local bb={getCurrentTownLocation=function()return t end,getCurrentAIPackageName=function()return label end,
  replaceAIPackage=function(_,data)counters.replace=counters.replace+1;label=data.name end}
 local members={}
 for i=1,2 do
  local state={homeBuilding=hand('stale-home')}
  local orders={goals={},hasOrders=function()return false end,setNeedGOAP=function()counters.goap=counters.goap+1 end}
  local c={getHandle=function()return hand('npc'..i)end,getBlackboard=function()return bb end,
   getStateBroadcast=function()return state end,getOwnerships=function()return own end,
   setupPlatoonAI=function()counters.setup=counters.setup+1;label='initial-package' end,
   getOrdersReciever=function()return orders end,getCarryingObject=function()return {isNull=function()return true end}end}
  for _,m in ipairs({'isDead','isDown','isUnconcious','isCrippled','isBeingCarried','isInCombatMode','isFleeing'})do c[m]=function()return false end end
  members[i]={key='npc'..i,char=c,state=state,orders=orders}
 end
 local ap={getSquadLeader=function()return members[1].char end,getSquadSize=function()return #members end}
 local kind=2
 local p={getOwnerships=function()return own end,getFaction=function()return f end,getActivePlatoon=function()return ap end,
  getSquadType=function()return kind end,setSquadType=function(_,v)kind=v end}
 local b={getHandle=function()return hand('home')end,getTown=function()return t end,getFaction=function()return f end}
 local s={key='home',cfg={shop='bar',role='guard',count=2,faction='400-KenshiShop.mod'},platoon=p,building=b}
 function getGameWorld()return {gamedata={getData=function(_,id,typ)assert(typ==72);return {name='KS85 Indoor guards'}end}}end
 return s,members,bb,own,counters,t,nearby
end
test('resident type, shared ownership and both broadcast homes are assigned',function()
 local s,ms,bb,o,n,t=fixture();assert(Home.ensure(s,ms,bb))
 assert(n.home==1 and n.town==1 and o._homeTown==t and bb.targetTown==t)
 assert(s.platoon:getSquadType()==1)
 for _,m in ipairs(ms)do assert(m.state.homeBuilding:toString()=='home')end
end)
test('a foreign current town never replaces the assigned building town',function()
 local s,ms,bb,o,n,t,wrong=fixture();bb.getCurrentTownLocation=function()return wrong end
 assert(Home.ensure(s,ms,bb));assert(o._homeTown==t and bb.targetTown==t)
end)
test('distinct member ownership contexts are verified and assigned',function()
 local s,ms,bb,o,n,t=fixture();local other={setHomeBuilding=o.setHomeBuilding,setHomeTown=o.setHomeTown}
 ms[2].char.getOwnerships=function()return other end
 assert(Home.ensure(s,ms,bb));assert(other._homeTown==t and other._homeBuilding:toString()=='home')
end)
test('a silent native town setter failure cannot be reported as success',function()
 local s,ms,bb,o,n=fixture();o.setHomeTown=function()end
 local ok,why=Home.ensure(s,ms,bb)
 assert(not ok and why:find('expected=target%-town') and why:find('actual=nil'))
 assert(n.replace==0)
end)
test('missing broadcast binding blocks work instead of claiming a working resident',function()
 local s,ms,bb=fixture();ms[2].char.getStateBroadcast=function()return nil end
 local ok,why=Home.ensure(s,ms,bb);assert(not ok and why:find('MEMBER_STATE_UNAVAILABLE'))
end)
test('home ownership wait does not spend the role failure budget',function()
 local s,ms,bb,o,n=fixture();s.building.getFaction=function()return nil end
 for i=1,8 do assert(not Work.ensure(s,ms))end
 assert(s.work.tries==0 and n.replace==0)
end)
test('initialization precedes final package; repeat audits issue no movement or replacement',function()
 local s,ms,bb,o,n=fixture()
 local original=ms[2].char.setupPlatoonAI;local fail=true
 ms[2].char.setupPlatoonAI=function(...)
  if fail then fail=false;error('temporary initialization failure')end
  return original(...)
 end
 assert(not Work.ensure(s,ms));assert(n.replace==0)
 assert(Work.ensure(s,ms))
 assert(bb:getCurrentAIPackageName()=='KS85 Indoor guards' and n.replace==1 and n.setup==2)
 assert(not s.work.upgraded,'alpha84 AI-only migration must not force stock refresh')
 for i=1,100 do assert(Work.ensure(s,ms))end
 assert(n.replace==1 and n.setup==2 and n.home==1 and n.goap==2)
end)
test('unsupported native town assignment stops after three attempts with actual values',function()
 local s,ms,bb,o,n=fixture();o.setHomeTown=function()end
 for i=1,9 do assert(not Work.ensure(s,ms))end
 assert(s.work.tries==3 and n.replace==0 and not s.work.done)
 assert(table.concat(messages,'\n'):find('actual=nil'))
end)
test('old role labels migrate without being mistaken for unfinished delivery',function()
 for _,label in ipairs({'KS Native Town patrol','KS82 Town patrol','KS83 Town patrol','KS84 Town patrol','KS85 Town patrol'})do
  assert(Work.isWorkingPackage({shop='police',role='patrol'},label))
 end
 assert(not Work.isWorkingPackage({role='patrol'},'Foreign patrol'))
end)
print('Residence API boundary tests passed: '..passed)
