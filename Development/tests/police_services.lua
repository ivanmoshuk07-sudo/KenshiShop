-- Whole-service transaction/reload boundaries with real Store and Orders.
-- These tests do not execute game code or certify native NPC movement.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local Store=require('Core.Police.Services.Store')
local Config=require('Core.Police.Services.Config')
local events,logs,notices={},{},{}
Events={on=function(name,fn)events[name]=events[name] or {};table.insert(events[name],fn);return fn end}
local function emit(name,...)
 for _,fn in ipairs(events[name] or {})do fn(...)end
end
package.loaded.Diagnostics={console=function(s)logs[#logs+1]=s end,error=function(s)error(s)end}
local clock,bank,spawns,adopts,finishes,postChecks,scans=100,100000,0,0,0,0,0
local blockPosts,waitFinish,unknownMember,scanAvailable=false,false,false,true
local native,buildings={},{}
local function hand(key,object)
 return {toString=function()return key end,isNull=function()return key==nil end,
 getBuilding=function()return object end,getCharacter=function()return object end}
end
local npcFaction={getData=function()return {stringID=Config.faction}end}
local wallet={getMoney=function()return bank end,
 takeMoney=function(_,n)if bank<n then return false end;bank=bank-n;return true end,
 addMoney=function(_,n)bank=bank+n end}
local playerFaction={isThePlayer=function()return true end,factionOwnerships=wallet}
local town={getHandle=function()return hand('city')end,getFaction=function()return playerFaction end}
local function building(key,sid)
 local b={getHandle=function()return hand(key,buildings[key])end,getGameData=function()return {stringID=sid}end,
 isValid=function()return true end,getFaction=function()return npcFaction end,getTown=function()return town end}
 function b:setResidentSquad(p)self.residentSquad={getPlatoon=function()return p end}end
 buildings[key]=b;return b
end
local tower=building('tower',Config.tower)
local shop=building('shop','102-KenshiShop.mod')
local chief={getGameData=function()return {stringID='7310-KenshiShop.mod'}end,getFaction=function()return npcFaction end,
 isDead=function()return false end,getOwnerships=function()return {_homeBuilding=hand('tower',tower)}end}
local player={isPlayerCharacter=function()return true end,getFaction=function()return playerFaction end,getMoney=function()return bank end}
local function member(key)
 return {key=key,char={isDead=function()return false end,getHandle=function()return hand(key)end}}
end
local original={members={member('survivor')},getPlatoonStringID=function()return 'original'end}
native.original=original
local world={showPlayerAMessage_withLog=function(_,text)notices[#notices+1]=text end}
function getGameWorld()return world end
local Live={call=function(o,m,...)if o and type(o[m])=='function'then return o[m](o,...)end end,clock=function()return clock end}
package.loaded['Core.NPC.LiveState']=Live
local Roster={}
function Roster.scan()scans=scans+1;return scanAvailable,'SCAN_UNAVAILABLE'end
function Roster.reset()end
function Roster.building(key)return buildings[key]end
function Roster.findPlatoon(pid)return native[pid],native[pid] and nil or 'TRUE_NOT_FOUND'end
function Roster.observe()return true end
function Roster.death(c)if c and c.dead then Store.get().roster[c.id].dead=true;return true end end
function Roster.losses(city)
 local rows={}
 for _,r in pairs(Store.get().roster)do if r.town==city and r.dead and not r.replacedBy and not r.order then rows[#rows+1]=r end end
 table.sort(rows,function(a,b)return a.id<b.id end);return rows
end
package.loaded['Core.Police.Services.Roster']=Roster
local menu={start=function(api)menuAPI=api;return true end,attach=function()return true end,resetSession=function()end}
package.loaded['Core.Police.Services.Dialogue']=menu
local function driver()
 return {adopt=function(_,p,options)
  adopts=adopts+1;p.lastOptions=options;return true
 end,resetSession=function()end}
end
package.loaded['Core.NPC.Controller']={new=function()return driver()end}
for _,cfg in pairs(Config.templates)do if cfg.driver then package.loaded[cfg.driver]=driver()end end
package.loaded['Core.NPC.RoleAI']={ensure=function(s)s.work=s.work or {};s.work.done=true;return true end}
package.loaded['Core.NPC.PostDuty']={candidates=function()return {1}end}
package.loaded['Core.NPC.NativeNodes']={target=function(_,_,_,_,slot)
 postChecks=postChecks+1;if blockPosts then return nil,'INVALID_POST'end;return {slot=slot}
end}
package.loaded['Core.NPC.Transport']={preflight=function()return {}end,
 members=function(_,p)return p.members end,
 spawn=function()
  spawns=spawns+1;local pid='hired'..spawns
  local p={members={member(pid..'-1'),member(pid..'-2'),member(pid..'-3')},getPlatoonStringID=function()return pid end}
  native[pid]=p;tower:setResidentSquad(p);return p
 end}
local Recruit={}
function Recruit.prepare(record,b,p)return {record=record,building=b,platoon=p,cfg=Config.copy(record.squadTemplate)}end
function Recruit.spawn(plan)
 spawns=spawns+1;local key='new'..spawns;local m=member(key);table.insert(plan.platoon.members,m)
 local receipt={char=m.char,member=unknownMember and nil or key,key=key,pid='original',platoon=plan.platoon,pending=waitFinish,stages={}}
 plan.receipt=receipt;return receipt
end
function Recruit.finish(plan,r)
 finishes=finishes+1;r.member=r.key;r.stages.race=true
 if waitFinish then return false,'HOME_LOADING'end
 r.pending=false;r.state={cfg=plan.cfg,work={leader='survivor',setup={[r.member]=true}}};return true
end
function Recruit.restore(record,b,p,id,stages)
 local plan=Recruit.prepare(record,b,p)
 local receipt={member=id,key=id,pid='original',platoon=p,stages=stages or {}}
 plan.receipt=receipt;return plan,receipt
end
package.loaded['Core.Police.Services.Recruit']=Recruit
local Services=require('Core.Police.Services')
assert(Services.start())
local function data()return {sdata={},addString=function(self,key,value)self.sdata[key]=value end}end
local function fixture()
 Services.resetSession();native={original=original};original.members={member('survivor')}
 tower:setResidentSquad(original)
 clock=100;bank=100000;spawns=0;adopts=0;finishes=0;postChecks=0;logs={};notices={}
 blockPosts=false;waitFinish=false;unknownMember=false;scanAvailable=true
 emit('PlayerInterface::loadFromSerialise',{},data())
 Store.get().roster.dead={id='dead',pid='original',building='shop',town='city',squadTemplate='7802-KenshiShop.mod',
  charTemplate='7306-KenshiShop.mod',race='7101-KenshiShop.mod',name='KS: Охрана (2 этаж)',dead=true}
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function click(action)assert(Services.request(action,chief,player));Services.tick()end
local function recover()
 clock=clock+11;for i=1,60 do Services.tick()end
end
test('checking losses is free and one paid replacement does not recreate a survivor',function()
 fixture();click('check');assert(bank==100000 and spawns==0)
 local survivor=original.members[1];click('replace')
 assert(bank==90000 and spawns==1 and original.members[1]==survivor and Store.get().roster.dead.replacedBy=='new1')
 click('replace');assert(bank==90000 and spawns==1)
end)
test('each extra squad costs once and uses separate three-post rows',function()
 fixture();click('hire');click('hire')
 assert(bank==60000 and spawns==2 and adopts==2 and postChecks==6)
 assert(Store.get().patrols.hired1.base==3 and Store.get().patrols.hired2.base==6)
 assert(tower.residentSquad:getPlatoon()==original,'factory-created hired patrol must not replace the tower resident')
 recover();recover();assert(adopts==2,'observation must not repeatedly reset hired AI')
end)
test('missing posts funds and incomplete roster checks never charge or allocate',function()
 fixture();blockPosts=true;click('hire');assert(bank==100000 and spawns==0)
 blockPosts=false;bank=19999;click('hire');assert(bank==19999 and spawns==0)
 bank=100000;scanAvailable=false;click('replace');assert(bank==100000 and spawns==0)
end)
test('save reload restores hired survivors and permits another genuinely new purchase',function()
 fixture();click('hire');local p=native.hired1;table.remove(p.members,3)
 local save=data();emit('PlayerInterface::serialise',{},save)
 Services.resetSession();emit('PlayerInterface::loadFromSerialise',{},save);recover()
 assert(adopts==2 and bank==80000 and spawns==1,'surviving hired NPCs must reattach after reload')
 click('hire');assert(bank==60000 and spawns==2,'runtime nonce reuse must not match an old paid order')
end)
test('pending replacement persists newly learned actor identity before a later stage is ready',function()
 fixture();waitFinish=true;unknownMember=true;click('replace')
 local order=Store.get().orders['1'];assert(order.status=='pending' and order.member=='new1' and bank==90000)
 local save=data();emit('PlayerInterface::serialise',{},save)
 Services.resetSession();emit('PlayerInterface::loadFromSerialise',{},save)
 waitFinish=false;recover()
 assert(Store.get().orders['1'].status=='complete' and Store.get().roster.dead.replacedBy=='new1')
 assert(bank==90000 and spawns==1)
end)
test('corrupt and new campaign state cannot reuse earlier paid claims',function()
 fixture();click('hire');local corrupt=data();corrupt.sdata.KenshiShopChiefStateV1='invalid'
 emit('PlayerInterface::loadFromSerialise',{},corrupt);click('hire')
 assert(bank==80000 and spawns==1 and not Store.ready())
 emit('PlayerInterface::loadFromSerialise',{},data());click('check')
 assert(Store.ready() and next(Store.get().orders)==nil and bank==80000)
end)
test('a new campaign becomes save-scoped on its first ordinary native save',function()
 fixture();Services.resetSession();assert(not Store.ready())
 emit('PlayerInterface::serialise',{},data());assert(Store.ready())
end)
print('Chief service payment/reload integration tests passed: '..count)
