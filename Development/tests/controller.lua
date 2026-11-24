-- Real shared monitor/supply queues around native API mocks: scheduling changes
-- must preserve saved native work without fresh movement, spawning or outfits.
local root=assert(arg[1]);package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local frames,hookID,time={},0,100
Events={on=function(_,fn)hookID=hookID+1;frames[hookID]=fn;return hookID end,
 off=function(id)frames[id]=nil end}
local moves,spawns,gear,work,catalog,supplies,resets=0,0,0,0,0,0,0
local objects,homes,groups={},{},{}
local revision=0
local workThisFrame=0
local function hooks()local n=0;for _ in pairs(frames)do n=n+1 end;return n end
local function runFrames(n,minutes)
 time=time+(minutes or 0)
 for _=1,n do
  local callbacks={};for id,fn in pairs(frames)do callbacks[#callbacks+1]={id=id,fn=fn}end
  table.sort(callbacks,function(a,b)return a.id<b.id end)
  workThisFrame=0
  for _,entry in ipairs(callbacks)do if frames[entry.id]==entry.fn then entry.fn()end end
  assert(workThisFrame<=1,'only one squad may perform role maintenance in one frame')
 end
end
local function run(minutes)runFrames(40,minutes)end
package.loaded.Diagnostics={console=function()end,error=function(msg)error(msg)end}
local function handle(id)
 return {toString=function()return id end,getPlatoon=function()return groups[id]end,
 getBuilding=function()local b=objects[id];return b and b.kind=='building' and b.loaded and b or nil end,
 getCharacter=function()local c=objects[id];return c and c.kind=='character' and c.loaded and c or nil end}
end
local label='KS Native Town patrol'
local bb={getCurrentAIPackageName=function()return label end}
local function member(id,p)
 local c={key=id,kind='character',loaded=true,platoon=p}
 function c:getHandle()return handle(id)end
 function c:isValid()return objects[id]==self and self.loaded end
 function c:isDead()return false end
 function c:getPlatoon()return self.platoon:getActivePlatoon()end
 function c:getBlackboard()return bb end
 function c:getPosition()return {x=900,y=0,z=0}end
 function c:setDestination()moves=moves+1 end
 objects[id]=c;return {key=id,char=c}
end
local function home(id,pid)
 local b={key=id,kind='building',loaded=true,isValid=function()return true end,
  getHandle=function()return handle(id)end,getPosition=function()return {x=0,y=0,z=0}end}
 objects[id]=b;homes[id]=b
 local p={members={},loaded=true,getPlatoonStringID=function()return pid end}
 function p:getHandle()return handle(pid)end
 local ap={me=p,getSquadSize=function()return #p.members end,getSquadLeader=function()return p.members[1].char end}
 function p:getActivePlatoon()return self.loaded and ap or nil end
 p.members={member(pid..'-leader',p),member(pid..'-second',p)}
 b.platoon=p;groups[pid]=p;return b,p
end
local first,p1=home('home-A','patrol-A')
local second,p2=home('home-B','patrol-B')
local world={}
function getGameWorld()return world end
package.loaded['Core.NPC.LiveState']={call=function(o,m,...)
 if o and type(o[m])=='function'then local ok,v=pcall(o[m],o,...);if ok then return v end end
 end,
 clock=function()return time end,readyWorld=function()return not world.loading and world or nil end,
 revision=function()return revision end,halted=function()return false end,safeToOrder=function()return true end,
 copy=function(x)return {x=x.x,y=x.y,z=x.z}end}
package.loaded['Core.NPC.Transport']={members=function(_,p)return p.members end,valid=function()return true end,
 resetMembers=function()resets=resets+1 end,
 distance2D=function()return 900 end,preflight=function()return {}end,spawn=function()spawns=spawns+1;return p1 end}
package.loaded['Core.NPC.ExistingSquads']={find=function(b)return b.platoon end,inspect=function()return true end}
package.loaded['Core.NPC.Appearance']={apply=function()gear=gear+1 end}
package.loaded['Core.NPC.Supplies']={sync=function(c,w)
 assert(c==objects[c.key] and c.loaded and w==world,'supply queue must resolve the current actor')
 supplies=supplies+1;return true,'UNCHANGED'
end}
package.loaded['Core.NPC.Duty']={tick=function()end,status=function()return 'TEST'end}
package.loaded['Core.NPC.RoleAI']={isWorkingPackage=function(_,name)return name==label end,
 package=function()return '8104-KenshiShop.mod',label end,
 ensure=function()work=work+1;workThisFrame=workThisFrame+1 end,status=function()return 'READY'end}
package.loaded['Core.NPC.Catalog']={ensure=function()catalog=catalog+1 end,prepare=function()return true end}
package.loaded['Core.Ownership.Registry']={onSpawned=function()end,onArrived=function()end,onRestored=function()end}
local Controller=require('Core.NPC.Controller')
local function driver()return Controller.new({shop='police',role='patrol',template='311-KenshiShop.mod',faction='400-KenshiShop.mod',count=3})end
local a,b=driver(),driver()
local total=0
local function test(name,fn)fn();total=total+1;print('PASS '..name)end
local function noNewOrders()
 assert(moves==0 and spawns==0 and gear==0,'saved native squads must never receive new delivery movement, spawning or outfits')
end
local function delivered(d,h)
 assert(d.status(h):find('DELIVERED',1,true),'saved patrol with casualties must resume work away from home')
end

test('multiple saved squad drivers share one monitor hook and stagger work by frame',function()
 assert(a.resume(first));assert(b.resume(second));assert(hooks()==1)
 runFrames(1);assert(work==1 and hooks()==2,'one shared supply hook is added lazily')
 runFrames(1);assert(work==2 and hooks()==2)
 runFrames(8);delivered(a,first);delivered(b,second)
 assert(supplies==4 and hooks()==1,'supply queue detaches after all four audits')
 noNewOrders()
end)
test('building unload pauses monitoring and reload preserves completed delivery',function()
 first.loaded=false;run(10);first.loaded=true;run(10)
 delivered(a,first);delivered(b,second);noNewOrders()
end)
test('load callback cancels queued old handles before restoring native squad',function()
 -- At the next 10-minute audit, A is the first due monitor. Stop just after
 -- it queues supplies, before the supply owner receives another frame.
 time=time+10
 local before=supplies
 for _=1,40 do runFrames(1);if hooks()==2 then break end end
 assert(hooks()==2)
 assert(a.resume(first))
 for _,m in ipairs(p1.members)do m.char.loaded=false;objects[m.key]=nil end
 p1.members={member('reloaded-A-leader',p1),member('reloaded-A-second',p1)}
 runFrames(120)
 delivered(a,first);delivered(b,second)
 assert(supplies>before and hooks()==1)
 noNewOrders()
end)
test('game clock rollback recovers existing native squads and clears stale audit deadlines',function()
 time=5;runFrames(160)
 delivered(a,first);delivered(b,second)
 assert(resets>=5,'resume and clock rollback must invalidate shared membership snapshots')
 assert(work>0 and catalog>0 and hooks()==1)
 noNewOrders()
end)
test('resetting one driver cancels only its work and preserves the other monitor',function()
 a.resetSession();assert(hooks()==1)
 assert(a.status(first)=='NOT_SCHEDULED')
 local before=work;run(1);assert(work>before)
 delivered(b,second);noNewOrders()
end)
test('resetting final driver removes shared monitor and all queued supply work',function()
 b.resetSession();assert(next(frames)==nil)
 runFrames(50);assert(next(frames)==nil)
 noNewOrders()
end)
test('same-minute native reload cannot read a platoon destroyed by the previous world',function()
 local h,old=home('reload-tower','reload-patrol')
 local d=driver();assert(d.resume(h));run(0);delivered(d,h)
 local stale=0
 function old:getPlatoonStringID()stale=stale+1;error('destroyed platoon')end
 function old:getHandle()stale=stale+1;error('destroyed platoon')end
 function old:getActivePlatoon()stale=stale+1;error('destroyed platoon')end
 world.loading=true;run(0);assert(stale==0)
 for _,m in ipairs(old.members)do objects[m.key]=nil end
 local loaded,current=home(h.key,'reload-patrol')
 world.loading=false;revision=revision+1
 run(0);run(0);delivered(d,loaded)
 assert(stale==0 and current~=old)
 noNewOrders();d.resetSession();assert(next(frames)==nil)
end)
test('a protected new squad member resumes delivery when safe without stopping its monitor',function()
 local building,p=home('mixed-delivery','new-patrol')
 local lead,second=p.members[1].char,p.members[2].char
 local leadX,secondX,secondBusy=250,250,true
 function lead:getPosition()return {x=leadX,y=0,z=0}end
 function second:getPosition()return {x=secondX,y=0,z=0}end
 package.loaded['Core.NPC.LiveState'].halted=function(c)
  return c==second and secondBusy,'TEST_TEMPORARY_COMBAT'
 end
 local transport=package.loaded['Core.NPC.Transport']
 transport.distance2D=function(x,y)return math.abs(x.x-y.x)end
 transport.fmt=function(pos)return tostring(pos.x)end
 transport.preflight=function()return {method='test',spawn={x=250,y=0,z=0}}end
 transport.spawn=function()spawns=spawns+1;return p end
 package.loaded['Core.NPC.ExistingSquads'].inspect=function()return false end
 local d=Controller.new({shop='police',role='patrol',template='311-KenshiShop.mod',faction='400-KenshiShop.mod',count=2})
 local beforeMoves,beforeSpawns=moves,spawns
 assert(d.start(building))
 run(0);assert(moves==beforeMoves+1,'first delivery orders only the safe actor')
 leadX=150;secondBusy=false
 run(1);assert(moves==beforeMoves+2,'retry orders the formerly protected actor')
 leadX,secondX=0,0
 run(1);delivered(d,building)
 assert(spawns==beforeSpawns+1 and moves==beforeMoves+2)
 d.resetSession();assert(next(frames)==nil)
end)
print('Controller integration checks: '..total)
