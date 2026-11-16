-- Shared snapshot/handle contracts. No Kenshi binaries or AI are executed.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local Index=require('Core.NPC.MemberIndex')
local count=0
local function test(name,fn)Index.reset();fn();count=count+1;print('PASS '..name)end
local function fixture()
 local f={now=100,scans=0,visits=0,current={},actors={},platoons={}}
 function f:platoon(id)
  self.platoons[id]=self.platoons[id] or {getPlatoonStringID=function()return id end}
  return self.platoons[id]
 end
 function f:actor(key,id)
  local p=self:platoon(id);local stale=false
  local c={}
  function c:isValid()return not stale end
  function c:getPlatoon()assert(not stale,'STALE_CHARACTER_POINTER');return {me=p}end
  function c:getHandle()
   assert(not stale,'STALE_CHARACTER_POINTER')
   -- Native getHandle returns an owned value, independent of the Character*.
   return {isNull=function()return false end,toString=function()return key end,
    getCharacter=function()return f.current[key]end}
  end
  function c:invalidate()stale=true end
  self.current[key]=c;self.actors[#self.actors+1]=c
  return c
 end
 local set=setmetatable({},{__pairs=function()
  f.scans=f.scans+1
  if f.scanError then error(f.scanError)end
  local i=0
  return function()
   i=i+1;local c=f.actors[i]
   if c then f.visits=f.visits+1;return c,true end
  end
 end})
 local mt={__eq=function(a,b)return a.identity==b.identity end}
 function f:world(identity)
  return setmetatable({identity=identity or self,
   charUpdateListMain=set,getTimeStamp_inGameHours=function()
    if f.clockError then error('CLOCK_UNAVAILABLE')end
    return {getTotalHours=function()return f.now/60 end}
   end},mt)
 end
 f.w=f:world()
 return f
end
test('all eleven squads share one world snapshot per game minute',function()
 local f=fixture()
 for i=1,11 do f:actor('npc-'..i,'squad-'..i)end
 for i=1,11 do
  local ms,why=Index.members(f:world(),f:platoon('squad-'..i),1)
  assert(ms and not why and #ms==1 and ms[1].key=='npc-'..i)
 end
 assert(f.scans==1 and f.visits==11)
 f.now=101
 for i=1,11 do assert(Index.members(f.w,f:platoon('squad-'..i),1))end
 assert(f.scans==2 and f.visits==22)
end)
test('cached owned hands resolve current characters without retaining stale native pointers',function()
 local f=fixture();local old=f:actor('actor','squad');local p=f:platoon('squad')
 assert(Index.members(f.w,p,1));old:invalidate()
 f.actors={};local current=f:actor('actor','squad')
 local ms=assert(Index.members(f.w,p,1))
 assert(ms[1].char==current and f.scans==1)
end)
test('force fresh sees newly allocated members at the same game time',function()
 local f=fixture();f:actor('a','squad');local p=f:platoon('squad')
 assert(#assert(Index.members(f.w,p,3))==1)
 f:actor('b','squad')
 assert(#assert(Index.members(f.w,p,3))==1 and f.scans==1)
 local ms=assert(Index.members(f.w,p,3,true))
 assert(#ms==2 and ms[1].key=='a' and ms[2].key=='b' and f.scans==2)
end)
test('unloaded or reassigned handles trigger one fresh scan instead of returning stale membership',function()
 local f=fixture();f:actor('a','squad');f:actor('b','squad');local p=f:platoon('squad')
 assert(#assert(Index.members(f.w,p,2))==2)
 f.current.a=nil;table.remove(f.actors,1)
 assert(#assert(Index.members(f.w,p,2))==1 and f.scans==2)
 local c=f.current.b;local other=f:platoon('other')
 c.getPlatoon=function()return {me=other}end
 assert(#assert(Index.members(f.w,p,2))==0 and f.scans==3)
end)
test('clock rewind, world identity change, reset and unavailable clock invalidate snapshots',function()
 local f=fixture();f:actor('a','squad');local p=f:platoon('squad')
 assert(Index.members(f.w,p,1));f.now=99;assert(Index.members(f.w,p,1));assert(f.scans==2)
 assert(Index.members(f:world({}),p,1));assert(f.scans==3)
 Index.reset();assert(Index.members(f.w,p,1));assert(f.scans==4)
 f.clockError=true
 assert(Index.members(f.w,p,1));assert(Index.members(f.w,p,1));assert(f.scans==6)
end)
test('failed fresh snapshots do not authorize a later stale cache result',function()
 local f=fixture();f:actor('a','squad');local p=f:platoon('squad')
 assert(Index.members(f.w,p,1));f.scanError='ITERATION_FAILED'
 local ms,why=Index.members(f.w,p,1,true)
 assert(not ms and why:find('SCAN_EXCEPTION',1,true))
 ms,why=Index.members(f.w,p,1)
 assert(not ms and why:find('SCAN_EXCEPTION',1,true) and f.scans==3)
 f.scanError=nil;assert(Index.members(f.w,p,1));assert(f.scans==4)
end)
test('missing character set, invalid platoon and excessive counts fail explicitly',function()
 local f=fixture();local p=f:platoon('squad')
 local ms,why=Index.members({},p,1);assert(not ms and why=='CHARACTER_SET_UNAVAILABLE')
 ms,why=Index.members(f.w,{},1);assert(not ms and why=='PLATOON_ID_UNAVAILABLE')
 for i=1,4 do f:actor(tostring(i),'squad')end
 ms,why=Index.members(f.w,p,1);assert(not ms and why=='MEMBER_COUNT_EXCESS 4')
 assert(#assert(Index.members(f.w,p,4))==4)
end)
test('invalid native handles and the global safety cap cannot publish partial snapshots',function()
 local f=fixture();local c=f:actor('a','squad');local p=f:platoon('squad')
 c.getHandle=function()return {toString=function()return 'a'end}end
 local ms,why=Index.members(f.w,p,1)
 assert(not ms and why:find('CHARACTER_HANDLE_UNAVAILABLE',1,true))
 f=fixture();p=f:platoon('squad')
 for i=1,12001 do f:actor(tostring(i),'squad')end
 ms,why=Index.members(f.w,p,12001)
 assert(not ms and why:find('CHARACTER_SCAN_SAFETY_CAP',1,true) and f.visits==12001)
end)
test('an unresolved vanilla platoon cannot block valid groups or certify its own partial roster',function()
 local f=fixture();local bad=f:actor('bad','vanilla');f:actor('other','vanilla')
 local good=f:actor('good','ks');bad.getHandle=function()return nil end
 local ms=assert(Index.members(f.w,f:platoon('ks'),1))
 assert(#ms==1 and ms[1].char==good and f.scans==1)
 local why;ms,why=Index.members(f.w,f:platoon('vanilla'),2)
 assert(not ms and why=='CHARACTER_HANDLE_UNAVAILABLE' and f.scans==2)
 ms=assert(Index.members(f.w,f:platoon('ks'),1))
 assert(#ms==1 and ms[1].char==good and f.scans==2)
end)
test('invalid resolved actors trigger refresh then fail closed before current identity getters',function()
 local f=fixture();local c=f:actor('a','squad');local p=f:platoon('squad')
 assert(Index.members(f.w,p,1))
 local getHandle,getPlatoon=c.getHandle,c.getPlatoon;local handles,platoons=0,0
 c.isValid=function()return false end
 c.getHandle=function(self)handles=handles+1;return getHandle(self)end
 c.getPlatoon=function(self)platoons=platoons+1;return getPlatoon(self)end
 local ms,why=Index.members(f.w,p,1)
 -- The refreshed snapshot touches these once. Neither resolve attempt may
 -- inspect identity/platoon after isValid has rejected the current actor.
 assert(not ms and why=='MEMBER_CACHE_STALE' and f.scans==2 and handles==1 and platoons==1)
 c.isValid=function()return true end
 ms=assert(Index.members(f.w,p,1));assert(ms[1].char==c and f.scans==2)
end)
print('Shared membership index tests passed: '..count..'; no game AI execution')
