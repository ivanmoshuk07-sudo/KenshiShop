-- Shared supply work is bounded by frames and never retains native characters.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local now,objects,calls,callbacks,off,serial=0,{},0,{},0,0
local fail=false
package.loaded['Core.NPC.Supplies']={sync=function(c,w)
 assert(objects[c.key]==c and w=='world');calls=calls+1
 if fail then return false,'FULL' end
 return true,'UNCHANGED'
end}
package.loaded.Diagnostics={console=function()end,error=function()end}
package.loaded['Core.NPC.LiveState']={
 call=function(o,k,...)
  if not o or type(o[k])~='function'then return nil end
  local ok,v=pcall(o[k],o,...);if ok then return v end
 end,
 clock=function()return now end,readyWorld=function()return 'world'end,
}
Events={on=function(_,fn)serial=serial+1;callbacks[serial]=fn;return serial end,
 off=function(id)callbacks[id]=nil;off=off+1 end}
function getGameWorld()return 'world'end
local Q=require('Core.NPC.SupplyQueue')
local total=0
local function test(name,fn)
 Q.reset();now=0;objects={};calls=0;fail=false
 fn();total=total+1;print('PASS '..name)
end
local function state(id)return {platoonRef={key=id},cfg={shop='police',role='patrol'}}end
local function member(key,id)
 local function handle()
  return {toString=function()return key end,getCharacter=function()return objects[key]end}
 end
 local c={key=key,dead=false,pid=id,isValid=function()return true end,getHandle=handle}
 function c:isDead()return self.dead end
 function c:getPlatoon()return {me={getHandle=function()return {toString=function()return self.pid end}end}}end
 objects[key]=c;return {key=key,char=c}
end
local function frame()
 local run={};for id,fn in pairs(callbacks)do run[#run+1]=fn end
 for _,fn in ipairs(run)do fn()end
end
local function hooks()local n=0;for _ in pairs(callbacks)do n=n+1 end;return n end
test('many squads share one hook and one inventory audit per frame',function()
 local a,b=state('a'),state('b')
 Q.enqueue(a,{member('a1','a'),member('a2','a')},now)
 Q.enqueue(b,{member('b1','b')},now)
 assert(hooks()==1 and calls==0)
 frame();assert(calls==1);frame();assert(calls==2);frame();assert(calls==3 and hooks()==0)
end)
test('repeated controller visits and repeated roster entries do not duplicate work',function()
 local s=state('p');local m=member('a','p')
 Q.enqueue(s,{m,m},now);Q.enqueue(s,{m},now)
 frame();assert(calls==1 and hooks()==0)
 now=9;Q.enqueue(s,{m},now);assert(hooks()==0)
 now=10;Q.enqueue(s,{m},now);frame();assert(calls==2)
end)
test('cancel releases one squad and preserves other queued squads',function()
 local a,b=state('a'),state('b')
 Q.enqueue(a,{member('a','a')},now);Q.enqueue(b,{member('b','b')},now)
 Q.cancel(a);frame();assert(calls==1 and hooks()==0)
 Q.enqueue(a,{member('a2','a')},10);Q.cancel(a);assert(hooks()==0)
end)
test('unloaded dead and transferred characters are skipped without failure',function()
 local s=state('p');local a=member('a','p');local b=member('b','p');local c=member('c','p')
 Q.enqueue(s,{a,b,c},now);objects.a=nil;b.char.dead=true;c.char.pid='foreign'
 frame();frame();frame();assert(calls==0 and next(s.supplyFailures)==nil and hooks()==0)
end)
test('queued copied handle resolves the current character instead of the stale pointer',function()
 local s=state('p');Q.enqueue(s,{member('a','p')},now)
 local replacement=member('a','p');frame();assert(calls==1 and objects.a==replacement.char)
end)
test('three failures pause actor audits until sixty game minute cooldown',function()
 local s=state('p');local m=member('a','p');fail=true
 for _,t in ipairs({0,10,20})do now=t;Q.enqueue(s,{m},now);frame()end
 assert(calls==3 and s.supplyFailures.a==3 and s.supplyResetAt==80)
 now=30;Q.enqueue(s,{m},now);assert(hooks()==0 and calls==3)
 now=80;fail=false;Q.enqueue(s,{m},now);frame();assert(calls==4 and s.supplyFailures.a==0 and not s.supplyResetAt)
end)
test('enqueue clock rollback cancels stale work and restarts audit deadline',function()
 local s=state('p');local m=member('a','p');now=100;Q.enqueue(s,{m},now)
 now=1;Q.enqueue(s,{m},now);frame();assert(calls==1 and s.nextSupplyCheck==11)
end)
test('frame clock rollback invalidates all pending members from that state',function()
 local s=state('p');now=100;Q.enqueue(s,{member('a','p'),member('b','p')},now)
 now=1;frame();assert(calls==0 and hooks()==0 and not s.nextSupplyCheck)
end)
test('hook failure keeps work due and resets clear every pending handle',function()
 local original=Events.on;Events.on=function()error('failed')end
 local s=state('p');local m=member('a','p');assert(Q.enqueue(s,{m},now)==false and not s.nextSupplyCheck)
 Events.on=original;assert(Q.enqueue(s,{m},now));Q.reset();frame();assert(calls==0 and hooks()==0)
end)
print('Supply queue checks: '..total)
