-- Deterministic frame budget/fairness checks; no game callbacks are executed.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function fixture()
 local f={hooks={},added=0,removed=0,frame=0}
 Events={on=function(event,fn)
  assert(event=='MyGUI::Gui::eventFrameStart');f.added=f.added+1
  if f.reject then return nil end
  f.hooks[f.added]=fn;return f.added
 end,off=function(id)assert(f.hooks[id]);f.hooks[id]=nil;f.removed=f.removed+1 end}
 package.loaded['Core.NPC.MonitorQueue']=nil
 f.queue=require('Core.NPC.MonitorQueue')
 function f:step(n)
  for _=1,n do
   self.frame=self.frame+1;local hooks={}
   for _,fn in pairs(self.hooks)do hooks[#hooks+1]=fn end
   for _,fn in ipairs(hooks)do fn()end
  end
 end
 return f
end
test('eleven normal squads use one hook, one callback per frame and exact forty-frame intervals',function()
 local f=fixture();local visits={};local byFrame={};local tokens={}
 for i=1,11 do
  visits[i]={};tokens[i]=assert(f.queue.add(function()
   visits[i][#visits[i]+1]=f.frame;byFrame[f.frame]=(byFrame[f.frame] or 0)+1
  end))
 end
 assert(f.added==1);f:step(251)
 for i=1,11 do
  assert(visits[i][1]==i and #visits[i]>=6)
  for j=2,#visits[i]do assert(visits[i][j]-visits[i][j-1]==40)end
 end
 for _,n in pairs(byFrame)do assert(n==1)end
 for _,token in ipairs(tokens)do f.queue.remove(token)end
 assert(not next(f.hooks) and f.removed==1)
end)
test('more than forty squads remain fair without exceeding one callback per frame',function()
 local f=fixture();local visits={};local tokens={};local calls=0
 for i=1,55 do
  visits[i]={};tokens[i]=assert(f.queue.add(function()
   calls=calls+1;visits[i][#visits[i]+1]=f.frame
  end))
 end
 f:step(220);assert(calls==220)
 for i=1,55 do
  assert(#visits[i]==4 and visits[i][1]==i)
  for j=2,#visits[i]do assert(visits[i][j]-visits[i][j-1]==55)end
 end
 for _,token in ipairs(tokens)do f.queue.remove(token)end
end)
test('cancellation removes pending and self-removing work and detaches an idle hook',function()
 local f=fixture();local removed=0;local kept=0
 local a=assert(f.queue.add(function()removed=removed+1 end))
 local b=assert(f.queue.add(function()kept=kept+1 end))
 f.queue.remove(a);f.queue.remove(a);f:step(100)
 assert(removed==0 and kept==3)
 f.queue.remove(b);assert(not next(f.hooks))
 local self
 self=assert(f.queue.add(function()f.queue.remove(self)end))
 f:step(1);assert(not next(f.hooks) and f.added==2 and f.removed==2)
end)
test('new squads enter after one frame without delaying already due squads',function()
 local f=fixture();local rows={};local tokens={}
 for i=1,3 do tokens[i]=assert(f.queue.add(function()rows[#rows+1]={i,f.frame}end))end
 f:step(1)
 tokens[4]=assert(f.queue.add(function()rows[#rows+1]={4,f.frame}end))
 f:step(3)
 assert(rows[1][1]==1 and rows[2][1]==2 and rows[3][1]==3 and rows[4][1]==4)
 for _,token in ipairs(tokens)do f.queue.remove(token)end
end)
test('failed hook registration accepts no orphan work and can retry',function()
 local f=fixture();f.reject=true
 local token,why=f.queue.add(function()error('orphan callback')end)
 assert(not token and why and not next(f.hooks))
 f.reject=false;local calls=0
 token=assert(f.queue.add(function()calls=calls+1 end));f:step(1)
 assert(calls==1);f.queue.remove(token);assert(not next(f.hooks))
end)
test('native factory warmup defers only fresh work while restored work runs immediately',function()
 local f=fixture();local fresh,restored=0,0
 local a=assert(f.queue.add(function()fresh=f.frame end,40))
 local b=assert(f.queue.add(function()restored=restored+1 end))
 f:step(39);assert(fresh==0 and restored==1)
 f:step(1);assert(fresh==40 and restored==1)
 f:step(1);assert(restored==2)
 f.queue.remove(a);f.queue.remove(b);assert(not next(f.hooks))
end)
print('Shared monitor queue tests passed: '..count..'; normal eleven squads retain their frame interval')
