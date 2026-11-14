local root=assert(arg[1]);package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local frames={};local hookID=0;local time=100
Events={on=function(_,fn)hookID=hookID+1;frames[hookID]=fn;return hookID end,off=function(id)frames[id]=nil end}
local function run(minutes)
 time=time+minutes
 for i=1,40 do for _,fn in pairs(frames)do fn()end end
end
local moves,spawns,gear,work,catalog=0,0,0,0,0
package.loaded.Diagnostics={console=function()end,error=function(msg)error(msg)end}
local handle={toString=function()return 'home'end}
local loaded=true
local building={getHandle=function()return handle end,isValid=function()return true end,getPosition=function()return {x=0,y=0,z=0}end}
handle.getBuilding=function()return loaded and building or nil end
local label='KS Native Town patrol'
local bb={getCurrentAIPackageName=function()return label end}
local function char(id)
 return {getHandle=function()return {toString=function()return id end}end,
 getBlackboard=function()return bb end,getPosition=function()return {x=900,y=0,z=0}end,
 setDestination=function()moves=moves+1 end}
end
local members={{key='leader',char=char('leader')},{key='second',char=char('second')}}
local ap={getSquadSize=function()return #members end,getSquadLeader=function()return members[1].char end}
local platoon={getActivePlatoon=function()return ap end,getPlatoonStringID=function()return 'patrol'end}
function getGameWorld()return {}end
package.loaded['Core.NPC.LiveState']={call=function(o,m,...)if o and o[m]then return o[m](o,...)end end,
 clock=function()return time end,halted=function()return false end,safeToOrder=function()return true end,
 copy=function(x)return {x=x.x,y=x.y,z=x.z}end}
package.loaded['Core.NPC.Transport']={members=function()return members end,valid=function()return true end,
 distance2D=function()return 900 end,preflight=function()return {}end,spawn=function()spawns=spawns+1;return platoon end}
package.loaded['Core.NPC.ExistingSquads']={find=function()return platoon end,inspect=function()return true end}
package.loaded['Core.NPC.Appearance']={apply=function()gear=gear+1 end}
package.loaded['Core.NPC.Supplies']={sync=function()return true,'UNCHANGED'end}
package.loaded['Core.NPC.Duty']={tick=function()end,status=function()return 'TEST'end}
package.loaded['Core.NPC.RoleAI']={isWorkingPackage=function(_,name)return name==label end,package=function()return '8104-KenshiShop.mod',label end,
 ensure=function()work=work+1 end,status=function()return 'READY'end}
package.loaded['Core.NPC.Catalog']={ensure=function()catalog=catalog+1 end,prepare=function()return true end}
package.loaded['Core.Ownership.Registry']={onArrived=function()end,onRestored=function()end}
local driver=require('Core.NPC.Controller').new({shop='police',role='patrol',template='311-KenshiShop.mod',faction='400-KenshiShop.mod',count=3})
assert(driver.resume(building));run(0)
assert(driver.status(building):find('DELIVERED',1,true),'saved patrol with casualties must resume work away from building')
assert(moves==0 and spawns==0 and gear==0)
loaded=false;run(10);loaded=true;run(10)
assert(driver.status(building):find('DELIVERED',1,true),'unload must not reset delivery')
assert(moves==0 and spawns==0)
assert(driver.resume(building));run(0)
assert(moves==0 and spawns==0 and gear==0)
time=5;run(0);run(0);run(0)
assert(moves==0 and spawns==0,'clock rollback must only find existing squad')
assert(work>0 and catalog>0)
driver.resetSession();assert(next(frames)==nil)
print('PASS saved patrol away from home, casualties, unload/reload, load callback, clock rollback, cleanup; zero movement/spawn/outfit calls')
