-- Native handoff/query API boundaries, not an emulation of the game's AI.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local logs={};package.loaded.Diagnostics={console=function(s)logs[#logs+1]=s end}
local Activate=require('Core.NPC.NativeActivation')
local Audit=require('Core.NPC.PostAudit')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function h(id)return {isNull=function()return id==nil end,toString=function()return id end}end
local calls,fail,active,busy,score,post,queries,state,c
local function fixture()
 calls={};fail=false;active=14;busy=false;score=1;post=h('post-54');queries=0;logs={}
 local home={homeBuilding=h('building')}
 local ai={resultsCache={resetAllCaches=function()calls[#calls+1]='cache'end}}
 local function finder(_,target,asking)
  assert(target:toString()=='npc' and asking==true);queries=queries+1;return score,post
 end
 ai.findShopkeeperNode=finder;ai.findGuardNodeForBuilding_indoorOnly=finder;ai.findGuardNodeForBuilding_inOrOut=finder
 local orders={setNeedGOAP=function()calls[#calls+1]='goap'end,getCurrentGoal=function()return {key=function()return active end}end}
 c={getAI=function()return ai end,getHandle=function()return h('npc')end,getStateBroadcast=function()return home end,
 getOrdersReciever=function()return orders end,getCarryingObject=function()return h(nil)end,
 reThinkCurrentAIAction=function()if fail then error('not ready')end;calls[#calls+1]='rethink'end,
 setDestination=function()error('movement forbidden')end,addJob=function()error('jobs forbidden')end,addGoal=function()error('goals forbidden')end}
 for _,method in ipairs({'isDead','isDown','isUnconcious','isCrippled','isBeingCarried','isInCombatMode','isFleeing'})do c[method]=function()return busy end end
 state={cfg={role='trader',shop='bar'},key='building',now=12*60,work={done=true,leader='npc'}}
 return {{key='npc',char=c}}
end
test('native activation clears stale target caches then rethinks and wakes exactly once',function()
 local ms=fixture();local r={}
 assert(Activate.ensure(r,ms));assert(table.concat(calls,',')=='cache,rethink,goap')
 for i=1,100 do assert(Activate.ensure(r,ms))end
 assert(#calls==3)
end)
test('partial activation retries do not reinitialize an already completed member',function()
 local ms=fixture();local second={getAI=c.getAI,getOrdersReciever=c.getOrdersReciever,
 reThinkCurrentAIAction=function()if fail then error('pending')end;calls[#calls+1]='rethink2'end}
 ms[2]={key='second',char=second};local r={};fail=true
 -- First NPC is independently successful while the second one fails.
 ms[1].char.reThinkCurrentAIAction=function()calls[#calls+1]='rethink'end
 assert(not Activate.ensure(r,ms));assert(r.activation.npc==0 and r.activation.second==nil)
 fail=false;assert(Activate.ensure(r,ms));assert(table.concat(calls,',')=='cache,rethink,goap,cache,cache,rethink2,goap')
end)
test('mission context revisions refresh once per native binding, not on every monitor tick',function()
 local ms=fixture();local r={};assert(Activate.ensure(r,ms));r.missionDrifts=1
 assert(Activate.ensure(r,ms));assert(Activate.ensure(r,ms));assert(#calls==6)
end)
test('unavailable activation API reports failure without coordinate/job fallback',function()
 local ms=fixture();c.getAI=function()return nil end
 local ok,why=Activate.ensure({},ms);assert(not ok and why:find('AI_UNAVAILABLE',1,true));assert(#calls==0)
end)
test('native finder score 1 with null hand does not certify a usable post',function()
 fixture();post=h(nil);local row=Audit.probe(state,c,'npc')
 assert(row.score==1 and row.post==nil and row.result=='NO_SELECTABLE_POST' and queries==1)
end)
test('query returns the actual native post; caller never supplies post coordinates',function()
 fixture();local row=Audit.probe(state,c,'npc')
 assert(row.post=='post-54' and row.result=='POST_FOUND' and row.active==14 and row.home=='building')
 assert(#calls==0)
end)
test('trader guard and chief use their corresponding native target finders',function()
 fixture()
 for role,method in pairs({trader='findShopkeeperNode',guard='findGuardNodeForBuilding_indoorOnly',chief='findGuardNodeForBuilding_inOrOut'})do
  state.cfg.role=role;local row=Audit.probe(state,c,'npc');assert(row.finder==method and row.result=='POST_FOUND')
 end
 assert(queries==3)
end)
test('combat and native care are observed without asking for a replacement post',function()
 fixture();busy=true;assert(Audit.probe(state,c,'npc').result:find('DEFER_',1,true));busy=false;active=58
 assert(Audit.probe(state,c,'npc').result=='NATIVE_CARE' and queries==0 and #calls==0)
end)
test('a mismatching broadcast home cannot produce a positive post audit',function()
 fixture();c:getStateBroadcast().homeBuilding=h('neighbour')
 assert(Audit.probe(state,c,'npc').result=='BROADCAST_HOME_MISMATCH' and queries==0)
end)
test('night shifts do not produce misleading missing-post reports for daytime traders',function()
 fixture();state.cfg.shop='weapons';state.now=23*60
 assert(Audit.probe(state,c,'npc').result=='OFF_SHIFT' and queries==0)
 state.cfg.shop='bar';assert(Audit.probe(state,c,'npc').result=='POST_FOUND')
end)
test('patrol audit distinguishes leader task 36 from follower task 141',function()
 fixture();state.cfg.role='patrol'
 assert(Audit.probe(state,c,'npc').expected==36)
 assert(Audit.probe(state,c,'follower').expected==141 and queries==0)
end)
test('post observation is limited to three samples with game-clock spacing and zero orders',function()
 local ms=fixture();Audit.observe(state,ms)
 for i=1,100 do Audit.observe(state,ms)end
 assert(queries==1 and #logs==1)
 state.now=state.now+2;Audit.observe(state,ms);state.now=state.now+2;Audit.observe(state,ms)
 state.now=state.now+10000;Audit.observe(state,ms)
 assert(queries==3 and #logs==3 and #calls==0)
end)
print('Native activation/post audit tests passed: '..passed)
