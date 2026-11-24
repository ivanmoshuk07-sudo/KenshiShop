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
local clock,bank,spawns,adopts,finishes,postChecks,scans,memberReads,lookups=100,100000,0,0,0,0,0,0,0
local blockPosts,waitFinish,unknownMember,scanAvailable=false,false,false,true
local lastSpawnRecord,lastSpawnTemplate
local dialogueAttaches,rosterObservations=0,0
local native,buildings,monitors,stopped={},{},{},{}
local priorPatrols,patrolsAvailable={},true
local dutyReady,readyWorld=true,true
local monitorBuildings={}
local function hand(key,object)
 return {toString=function()return key end,isNull=function()return key==nil end,
 getBuilding=function()return object end,getCharacter=function()return object end,getPlatoon=function()return object end}
end
local npcFaction={getData=function()return {stringID=Config.faction}end}
local wallet={getMoney=function()return bank end,
 takeMoney=function(_,n)if bank<n then return false end;bank=bank-n;return true end,
 addMoney=function(_,n)bank=bank+n end}
local playerFaction={isThePlayer=function()return true end,factionOwnerships=wallet}
local town={getHandle=function()return hand('city')end,getFaction=function()return playerFaction end}
local function building(key,sid,homeTown)
 local b={getHandle=function()return hand(key,buildings[key])end,getGameData=function()return {stringID=sid}end,
 isValid=function()return true end,getFaction=function()return npcFaction end,getTown=function()return homeTown or town end}
 function b:setResidentSquad(p)
  if not self.refuseResidentSet then self.residentSquad=hand(p and p:getPlatoonStringID(),p) end
 end
 buildings[key]=b;return b
end
local tower=building('tower',Config.tower)
local shop=building('shop','102-KenshiShop.mod')
local chief={getGameData=function()return {stringID='7310-KenshiShop.mod'}end,getFaction=function()return npcFaction end,
 isDead=function()return false end,getOwnerships=function()return {_homeBuilding=hand('tower',tower)}end}
function chief:getHandle()return hand(self.key or 'chief',self)end
local player={isPlayerCharacter=function()return true end,getFaction=function()return playerFaction end,getMoney=function()return bank end}
function player:getHandle()return hand('player',self)end
local function member(key)
 return {key=key,char={isDead=function()return false end,getHandle=function()return hand(key)end}}
end
local function squad(pid,template,home,actors)
 local p={members=actors or {},squadTemplate={stringID=template},home=home}
 function p:getPlatoonStringID()return pid end
 function p:getHandle()return hand(pid,self)end
 function p:getFaction()return npcFaction end
 function p:getOwnerships()
  return {_homeBuilding=self.home and self.home:getHandle() or hand(nil)}
 end
 return p
end
local original=squad('original','311-KenshiShop.mod',tower,{member('survivor')})
native.original=original
local world={showPlayerAMessage_withLog=function(_,text)notices[#notices+1]=text end}
function getGameWorld()return world end
local Live={call=function(o,m,...)if o and type(o[m])=='function'then return o[m](o,...)end end,clock=function()return clock end,
 readyWorld=function()return readyWorld and world or nil end}
package.loaded['Core.NPC.LiveState']=Live
local Roster={}
function Roster.scan()scans=scans+1;return scanAvailable,'SCAN_UNAVAILABLE'end
function Roster.reset()end
function Roster.hiredInTown()if patrolsAvailable then return priorPatrols end;return nil,'NATIVE_CENSUS_PENDING'end
function Roster.building(key)return buildings[key]end
function Roster.findPlatoon(pid)lookups=lookups+1;return native[pid],native[pid] and nil or 'TRUE_NOT_FOUND'end
function Roster.observe()rosterObservations=rosterObservations+1;return true end
function Roster.death(c)if c and c.dead then Store.get().roster[c.id].dead=true;return true end end
package.loaded['Core.Police.Services.Roster']=Roster
package.loaded['Core.NPC.ExistingSquads']={find=function(b,cfg)
 for _,p in pairs(native)do
  if p.squadTemplate and p.squadTemplate.stringID==cfg.template and p.home==b then return p end
 end
end}
local menu={start=function(api)menuAPI=api;return true end,
 attach=function()dialogueAttaches=dialogueAttaches+1;return true end,resetSession=function()end}
package.loaded['Core.Police.Services.Dialogue']=menu
local function driver()
 local pid
 return {adopt=function(b,p,options)
  adopts=adopts+1;p.lastOptions=options;pid=p:getPlatoonStringID();monitors[pid]=true;monitorBuildings[pid]=b;return true
 end,resetSession=function()if pid then monitors[pid]=nil;stopped[pid]=(stopped[pid] or 0)+1 end end}
end
package.loaded['Core.NPC.Controller']={new=function()return driver()end}
for _,cfg in pairs(Config.templates)do if cfg.driver then package.loaded[cfg.driver]=driver()end end
package.loaded['Core.NPC.RoleAI']={ensure=function(s)s.work=s.work or {};s.work.done=true;return true end}
package.loaded['Core.NPC.PostDuty']={candidates=function()return {1}end,day=function()return true end}
package.loaded['Core.NPC.NativeNodes']={target=function(_,_,_,_,slot)
 postChecks=postChecks+1;if blockPosts then return nil,'INVALID_POST'end;return {slot=slot}
end}
package.loaded['Core.NPC.Transport']={preflight=function()return {}end,
 members=function(_,p,_,fresh)assert(fresh==true,'paid readback must bypass shared membership cache');memberReads=memberReads+1;return p.members end,
 spawn=function()
  spawns=spawns+1;local pid='hired'..spawns
  local p=squad(pid,Config.hired,nil,{member(pid..'-1'),member(pid..'-2'),member(pid..'-3')})
  native[pid]=p;return p
 end}
local Recruit={}
function Recruit.prepare(record,b,p)return {record=record,building=b,platoon=p,cfg=Config.copy(record.squadTemplate)}end
function Recruit.spawn(plan)
 lastSpawnRecord=plan.record.id;lastSpawnTemplate=plan.cfg.template
 spawns=spawns+1;local key='new'..spawns;local m=member(key)
 local p=plan.platoon
 if not p then
  local pid='replacement-'..spawns
  p={members={},getPlatoonStringID=function()return pid end};native[pid]=p
 end
 table.insert(p.members,m)
 local receipt={char=m.char,member=unknownMember and nil or key,key=key,pid=p:getPlatoonStringID(),platoon=p,pending=waitFinish,stages={}}
 plan.receipt=receipt;return receipt
end
function Recruit.finish(plan,r)
 finishes=finishes+1;r.member=r.key;r.stages.race=true
 if waitFinish then return false,'HOME_LOADING'end
 r.pending=false;r.state={cfg=plan.cfg,work={leader='survivor',setup={[r.member]=true}}};return true
end
function Recruit.restore(record,b,p,id,stages)
 local plan=Recruit.prepare(record,b,p)
 local receipt={member=id,key=id,pid=p:getPlatoonStringID(),platoon=p,stages=stages or {}}
 plan.receipt=receipt;return plan,receipt
end
package.loaded['Core.Police.Services.Recruit']=Recruit
local mayDepart,mayReturn,departChecks,propertyReturns=true,true,0,0
package.loaded['Core.Police.Services.Evacuees']={
 plan=function(ctx,ids)
  assert(ctx.town=='city' and ids.tower and ids.shop)
  return {original={template='310-KenshiShop.mod',building='tower'}}
 end,
 step=function(ctx,squads)
  assert(ctx.town=='city' and squads.original.building=='tower')
  departChecks=departChecks+1
  return mayDepart,'WAITING_FOR_DEPARTURE'
 end,
}
package.loaded['Core.Police.Services.PropertyReturn']={
 prepare=function()return {buildings={tower=true,shop=true},property={tower=true,shop=true,bed=true}}end,
 staffedShopKeys=function()return {tower='police',shop='armour'}end,
 apply=function(ctx,buildings,property,squads)
  assert(ctx.town=='city' and buildings.tower and property.bed and squads.original)
  propertyReturns=propertyReturns+1
  return mayReturn,'WAITING_FOR_PROPERTY'
 end,
}
local Services=require('Core.Police.Services')
assert(Services.start())
local function data()return {sdata={},addString=function(self,key,value)self.sdata[key]=value end}end
local function fixture()
 Services.resetSession();native={original=original};original.members={member('survivor')};original.home=tower
 monitors={};stopped={};monitorBuildings={};tower.refuseResidentSet=false
 tower:setResidentSquad(original);dutyReady=true;readyWorld=true
 clock=100;bank=100000;spawns=0;adopts=0;finishes=0;postChecks=0;logs={};notices={}
 lastSpawnRecord=nil;lastSpawnTemplate=nil
 dialogueAttaches=0;rosterObservations=0;priorPatrols={};patrolsAvailable=true
 blockPosts=false;waitFinish=false;unknownMember=false;scanAvailable=true
 mayDepart=true;mayReturn=true;departChecks=0;propertyReturns=0
 emit('PlayerInterface::loadFromSerialise',{},data())
 Store.get().roster.dead={id='dead',pid='original',building='shop',town='city',squadTemplate='7802-KenshiShop.mod',
  charTemplate='7306-KenshiShop.mod',race='7101-KenshiShop.mod',name='KS: Охрана (2 этаж)',dead=true}
end
local function loss(key,changes)
 local row={id=key,pid='original',building='shop',town='city',squadTemplate='7802-KenshiShop.mod',
  charTemplate='7306-KenshiShop.mod',race='7101-KenshiShop.mod',name='Сотрудник',dead=true}
 for k,v in pairs(changes or {})do row[k]=v end
 Store.get().roster[key]=row;return row
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function exerciseDuty()
 if not dutyReady then return end
 for pid,b in pairs(monitorBuildings)do
  local p=native[pid]
  if p and p.members and monitors[pid] then
   local assignment={}
   for _,m in ipairs(p.members)do assignment[m.key]={mode='DAY'}end
   Services.hiredDuty({pid=pid,key=b:getHandle():toString(),now=clock,postDuty={members=assignment}},p.members)
  end
 end
end
local function click(action,selectedID,fresh)
 assert(Services.request(action,chief,player,selectedID,fresh));Services.tick();exerciseDuty()
end
local function recover()
 clock=clock+11;for i=1,64 do Services.tick()end
 exerciseDuty()
end
test('checking losses is free and one paid replacement does not recreate a survivor',function()
 fixture();assert(#assert(Services.listLosses(chief,player))==1 and bank==100000 and spawns==0)
 local survivor=original.members[1];click('replace','dead')
 assert(bank==90000 and spawns==1 and original.members[1]==survivor and Store.get().roster.dead.replacedBy=='new1')
 click('replace','dead');assert(bank==90000 and spawns==1)
end)
test('loss list is free and returns isolated numbered human labels with persistent IDs',function()
 fixture();Store.get().roster.dead.floor=1
 loss('opaque-second-8194',{name='KS: Охрана (2 этаж)',floor=1})
 loss('alive',{dead=false});loss('uncertain',{dead='true'});loss('claimed',{order='pending-order'})
 loss('replaced',{replacedBy='replacement'});loss('foreign',{town='other-city'})
 loss('unknown-template',{squadTemplate='not-a-service-template'})
 local before=scans;local rows=assert(Services.listLosses(chief,player))
 assert(scans==before+1 and #rows==2 and bank==100000 and spawns==0 and Store.get().seq==0)
 assert(rows[1].id=='dead' and rows[2].id=='opaque-second-8194' and rows[1].label~=rows[2].label)
 assert(rows[1].role=='guard' and rows[1].shop=='armour' and rows[1].business=='Магазин брони' and rows[1].floor==2)
 assert(rows[1].label:find('1. ',1,true)==1 and rows[1].label:find('2 этаж',1,true))
 for _,row in ipairs(rows)do
  assert(not row.label:find(row.id,1,true) and getmetatable(row)==nil)
  for _,value in pairs(row)do assert(type(value)~='table' and type(value)~='userdata' and type(value)~='function')end
 end
 rows[2].id='changed';rows[2].name='changed';rows[2].label='changed'
 assert(Store.get().roster['opaque-second-8194'].id=='opaque-second-8194' and Store.get().roster['opaque-second-8194'].name=='KS: Охрана (2 этаж)')
 local again=assert(Services.listLosses(chief,player));assert(again[2].id=='opaque-second-8194' and again[2].label~='changed')
 Store.get().roster.dead.name=nil
 local unnamed=assert(Services.listLosses(chief,player))
 assert(unnamed[1].name=='Охранник' and not unnamed[1].label:find('dead',1,true))
end)
test('choosing the second loss creates only that role and leaves the first loss available',function()
 fixture();loss('second',{name='Торговец',squadTemplate='305-KenshiShop.mod',charTemplate='7303-KenshiShop.mod'})
 local rows=assert(Services.listLosses(chief,player));assert(#rows==2 and rows[2].id=='second' and bank==100000)
 click('replace',rows[2].id)
 assert(bank==90000 and spawns==1 and lastSpawnRecord=='second' and lastSpawnTemplate=='305-KenshiShop.mod')
 assert(Store.get().roster.second.replacedBy=='new1' and not Store.get().roster.dead.replacedBy)
 assert(Store.get().orders['1'].subject=='replace:second' and Store.get().orders['1'].metadata.deadID=='second')
 local remaining=assert(Services.listLosses(chief,player));assert(#remaining==1 and remaining[1].id=='dead')
end)
test('queued selection keeps its persistent ID when other rows disappear and ordering changes',function()
 fixture();loss('second')
 local rows=assert(Services.listLosses(chief,player));local selectedID=rows[2].id
 assert(Services.request('replace',chief,player,selectedID))
 Store.get().roster.dead=nil;loss('third')
 local reordered=assert(Services.listLosses(chief,player));assert(reordered[1].id==selectedID)
 Services.tick()
 assert(bank==90000 and spawns==1 and lastSpawnRecord=='second' and Store.get().roster.second.replacedBy=='new1')
 assert(not Store.get().roster.third.replacedBy)
end)
test('missing invalid and stale IDs never choose a different loss',function()
 fixture();loss('second')
 for _,value in ipairs({false,42,{},''})do
  local ok,why=Services.request('replace',chief,player,value)
  assert(not ok and why=='LOSS_SELECTION_REQUIRED')
 end
 local ok,why=Services.request('replace',chief,player);assert(not ok and why=='LOSS_SELECTION_REQUIRED')
 assert(Services.request('replace',chief,player,'second'));Store.get().roster.second=nil;Services.tick()
 click('replace','never-existed');assert(bank==100000 and spawns==0 and Store.get().seq==0)
 assert(not Store.get().roster.dead.replacedBy and notices[#notices]:find('Деньги не списаны',1,true))
end)
test('processing rescans and rejects changed or already paid loss records without a charge',function()
 local changes={{dead=false},{town='other-city'},{order='pending-order'},{replacedBy='somebody'},
  {squadTemplate='unknown-template'},{id='different-identity'}}
 for _,change in ipairs(changes)do
  fixture();assert(Services.request('replace',chief,player,'dead'))
  for k,v in pairs(change)do Store.get().roster.dead[k]=v end
  local before=scans;Services.tick();assert(scans==before+1 and bank==100000 and spawns==0 and Store.get().seq==0)
 end
 fixture();Store.get().orders.paid={id='paid',kind='replace',subject='replace:dead',status='pending',pid='original',member='already-created',metadata={town='city'}}
 assert(#assert(Services.listLosses(chief,player))==0)
 click('replace','dead');assert(bank==100000 and spawns==0 and Store.get().seq==0)
end)
test('each chief lists and validates losses only for its own city',function()
 fixture()
 local otherTown={getHandle=function()return hand('other-city')end,getFaction=function()return playerFaction end}
 local otherTower=building('other-tower',Config.tower,otherTown)
 building('other-shop','102-KenshiShop.mod',otherTown)
 local otherChief={key='other-chief',getHandle=chief.getHandle,getGameData=chief.getGameData,getFaction=chief.getFaction,isDead=chief.isDead,
  getOwnerships=function()return {_homeBuilding=hand('other-tower',otherTower)}end}
 loss('foreign',{town='other-city',building='other-shop'})
 local localRows=assert(Services.listLosses(chief,player));local foreignRows=assert(Services.listLosses(otherChief,player))
 assert(#localRows==1 and localRows[1].id=='dead' and #foreignRows==1 and foreignRows[1].id=='foreign')
 click('replace',foreignRows[1].id);assert(bank==100000 and spawns==0)
 assert(Services.request('replace',otherChief,player,localRows[1].id));Services.tick();assert(bank==100000 and spawns==0)
 assert(Services.request('replace',otherChief,player,foreignRows[1].id));Services.tick()
 assert(bank==90000 and spawns==1 and lastSpawnRecord=='foreign' and not Store.get().roster.dead.replacedBy)
end)
test('loss list reports known losses with a partial scan and requires verification before saying all are present',function()
 fixture();local before=scans
 assert(Services.listLosses({},player)==nil and Services.listLosses(chief,{})==nil and scans==before)
 scanAvailable=false;local rows,why=Services.listLosses(chief,player)
 assert(rows and #rows==1 and rows[1].id=='dead')
 Store.get().roster.dead=nil;rows,why=Services.listLosses(chief,player)
 assert(rows==nil and why=='SCAN_UNAVAILABLE' and bank==100000 and spawns==0 and Store.get().seq==0)
 scanAvailable=true;assert(#assert(Services.listLosses(chief,player))==0)
 Services.resetSession();rows,why=Services.listLosses(chief,player)
 assert(rows==nil and why=='SERVICE_STORE_NOT_READY' and bank==100000 and spawns==0)
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
 bank=100000;scanAvailable=false;click('replace','dead');assert(bank==100000 and spawns==0)
end)
test('hired checkout waits for observed native duty before closing the paid order',function()
 fixture();dutyReady=false;click('hire')
 assert(Store.get().orders['1'].status=='pending' and monitors.hired1 and bank==80000 and spawns==1)
 assert(tower.residentSquad:getPlatoon()==original)
 dutyReady=true;exerciseDuty()
 assert(Store.get().orders['1'].status=='complete' and bank==80000 and spawns==1)
end)
test('three legacy paid squads reattach when the last hire displaced the tower resident',function()
 fixture();dutyReady=false
 for _=1,3 do click('hire') end
 local state=Store.get();state.orders['2'].metadata.residentPID='hired1';state.orders['3'].metadata.residentPID='hired2'
 for _,row in pairs(state.patrols)do row.adopted=nil end
 tower:setResidentSquad(native.hired3);tower.refuseResidentSet=true
 local save=data();emit('PlayerInterface::serialise',{},save);emit('PlayerInterface::loadFromSerialise',{},save)
 local before=adopts;recover()
 assert(tower.residentSquad:getPlatoon()==original and adopts==before+3 and bank==40000 and spawns==3)
 assert(Store.get().orders['3'].status=='pending')
 dutyReady=true;exerciseDuty();assert(Store.get().orders['3'].status=='complete' and bank==40000 and spawns==3)
end)
test('a queued purchase is idle during load and stale participants cannot spend',function()
 fixture();assert(Services.request('hire',chief,player));readyWorld=false
 Services.tick();assert(bank==100000 and spawns==0)
 emit('PlayerInterface::loadFromSerialise',{},data());readyWorld=true
 Services.tick();assert(bank==100000 and spawns==0)
 local expired=setmetatable({getHandle=function()return hand('expired')end},{__index=chief})
 assert(Services.request('hire',expired,player));Services.tick();assert(bank==100000 and spawns==0)
end)
test('a new hire does not need a complete census of unloaded staff',function()
 fixture();scanAvailable=false;click('hire');assert(bank==80000 and spawns==1)
end)
test('confirmed departure survives reload and removes only one city after NPCs and property are verified',function()
 fixture();click('hire');loss('other-loss',{town='other-city',building='other-shop'})
 mayDepart=false;mayReturn=false
 click('evacuate')
 assert(Store.evacuation('city') and Store.retiredBuilding('tower') and Store.retiredPlatoon('original'))
 assert(not Store.retiredBuilding('other-shop') and propertyReturns==0)
 click('hire');assert(bank==80000 and spawns==1)
 recover();assert(departChecks==1 and propertyReturns==0 and Store.get().roster.dead)
 local save=data();emit('PlayerInterface::serialise',{},save)
 emit('PlayerInterface::loadFromSerialise',{},save)
 mayDepart=true;recover()
 assert(departChecks==2 and propertyReturns==1 and Store.evacuation('city'))
 mayReturn=true;recover()
 assert(departChecks==2 and propertyReturns==2 and not Store.evacuation('city'))
 assert(not Store.get().roster.dead and Store.get().roster['other-loss'])
 assert(next(Store.get().patrols)==nil and next(Store.get().orders)==nil)
 assert(Store.retiredBuilding('tower') and Store.retiredPlatoon('original'))
 local differentTower=building('next-tower',Config.tower)
 local newResident=squad('new-original','311-KenshiShop.mod',differentTower)
 differentTower:setResidentSquad(newResident)
 local nextChief=setmetatable({key='new-chief',getOwnerships=function()return {_homeBuilding=hand('next-tower',differentTower)}end},{__index=chief})
 assert(Services.request('hire',nextChief,player));Services.tick()
 assert(bank==60000 and spawns==2)
end)
test('save reload restores hired survivors and permits another genuinely new purchase',function()
 fixture();click('hire');local p=native.hired1;table.remove(p.members,3)
 local save=data();emit('PlayerInterface::serialise',{},save)
 Services.resetSession();emit('PlayerInterface::loadFromSerialise',{},save);recover()
 assert(adopts==2 and bank==80000 and spawns==1,'surviving hired NPCs must reattach after reload')
 click('hire');assert(bank==60000 and spawns==2,'runtime nonce reuse must not match an old paid order')
end)
test('pending replacement persists newly learned actor identity before a later stage is ready',function()
 fixture();waitFinish=true;unknownMember=true;click('replace','dead')
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
 emit('PlayerInterface::loadFromSerialise',{},data());assert(#assert(Services.listLosses(chief,player))==0)
 assert(Store.ready() and next(Store.get().orders)==nil and bank==80000)
end)
test('a new campaign becomes save-scoped on its first ordinary native save',function()
 fixture();Services.resetSession();assert(not Store.ready())
 emit('PlayerInterface::serialise',{},data());assert(Store.ready())
end)
test('completed hired history is absent from periodic actor reads and platoon lookups',function()
 fixture();click('hire')
 local beforeReads,beforeLookups,beforeScans=memberReads,lookups,scans
 recover();local firstScans=scans
 for i=1,5 do recover()end
 assert(firstScans==beforeScans+1 and scans==firstScans,'full roster reconciliation is not a ten-minute poll')
 assert(memberReads==beforeReads and lookups==beforeLookups and adopts==1)
 assert(Store.get().orders['1'].status=='complete','historical receipts must remain saved')
end)
test('full reconciliation is rare and confirmed death events do not trigger another scan',function()
 fixture();recover();local before=scans
 Store.get().roster.dead.dead=false
 emit('Character::declareDead',{id='dead',dead=true})
 assert(Store.get().roster.dead.dead and scans==before)
 for i=1,10 do recover()end
 assert(scans==before,'event and ordinary observations replace repeated full death scans')
 recover();assert(scans==before+1,'rare reconciliation still discovers missed or historical corpses')
end)
test('recovery distributes saved paid squads over separate frames and removes completed work',function()
 fixture();click('hire');click('hire')
 local save=data();emit('PlayerInterface::serialise',{},save)
 Services.resetSession();emit('PlayerInterface::loadFromSerialise',{},save)
 local before=adopts
 Services.tick();assert(adopts==before) -- First frame reconciles the roster.
 Services.tick();assert(adopts==before+1)
 Services.tick();assert(adopts==before+2)
 local reads=memberReads;recover();assert(adopts==before+2 and memberReads==reads)
end)
test('load clears transient work and restores only actual pending replacement receipts',function()
 fixture();waitFinish=true;click('replace','dead')
 local order=Store.get().orders['1'];assert(order.status=='pending')
 -- Many completed historical receipts must not become recovery work.
 for i=1,1000 do Store.get().orders['history-'..i]={id='history-'..i,kind='replace',status='complete',subject='old-'..i,metadata={}}end
 local save=data();emit('PlayerInterface::serialise',{},save)
 Services.resetSession();emit('PlayerInterface::loadFromSerialise',{},save)
 waitFinish=false;local before=finishes;recover()
 assert(finishes==before+1 and Store.get().orders['1'].status=='complete' and spawns==1 and bank==90000)
 recover();assert(finishes==before+1 and Store.get().orders['history-1000'].status=='complete')
end)
local function replaceExtinctHired()
 fixture();click('hire');local oldPID='hired1'
 native[oldPID]=nil
 for i=1,3 do loss('hired-loss-'..i,{pid=oldPID,building='tower',squadTemplate=Config.hired})end
 click('replace','hired-loss-1')
 local newPID='replacement-2'
 assert(Store.get().orders['2'].status=='complete' and Store.get().patrols[newPID])
 return oldPID,newPID
end
test('extinct hired replacements update the paid receipt and stop only the old native owner monitor',function()
 local oldPID,newPID=replaceExtinctHired()
 assert(not Store.get().patrols[oldPID] and Store.get().orders['1'].pid==newPID)
 assert(not monitors[oldPID] and monitors[newPID] and stopped[oldPID]==1)
 assert(Store.get().roster['hired-loss-2'].pid==newPID and Store.get().roster['hired-loss-3'].pid==newPID)
 local before=adopts;local save=data();emit('PlayerInterface::serialise',{},save)
 emit('PlayerInterface::loadFromSerialise',{},save);recover();recover()
 assert(adopts==before+1 and monitors[newPID] and not monitors[oldPID])
 assert(Store.get().orders['1'].pid==newPID and Store.get().orders['1'].status=='complete')
 assert(bank==70000 and spawns==2 and tower.residentSquad:getPlatoon()==original)
 recover();assert(adopts==before+1 and bank==70000 and spawns==2)
end)
test('beta5 migrated patrol saves repair stale hire receipt IDs before recovery without charging again',function()
 local oldPID,newPID=replaceExtinctHired()
 -- Recreate the already-published inconsistent ledger, with no legacy row.
 Store.get().orders['1'].pid=oldPID
 Store.get().patrols[newPID].pid=oldPID
 local save=data();emit('PlayerInterface::serialise',{},save)
 local before=adopts;emit('PlayerInterface::loadFromSerialise',{},save);recover();recover()
 assert(Store.get().orders['1'].pid==newPID and Store.get().patrols[newPID].pid==newPID)
 assert(adopts==before+1 and monitors[newPID] and bank==70000 and spawns==2)
 local repaired=data();emit('PlayerInterface::serialise',{},repaired)
 emit('PlayerInterface::loadFromSerialise',{},repaired);recover();assert(monitors[newPID])
 assert(bank==70000 and spawns==2 and Store.get().orders['1'].pid==newPID)
end)
test('completed hired patrols survive chief replacement and preserve the new tower resident',function()
 fixture();click('hire');click('hire')
 local newChief=squad('new-chief','310-KenshiShop.mod',tower)
 native.original=nil;native['new-chief']=newChief;tower:setResidentSquad(newChief)
 local before=adopts;local save=data();emit('PlayerInterface::serialise',{},save)
 emit('PlayerInterface::loadFromSerialise',{},save);recover();recover()
 assert(adopts==before+2 and monitors.hired1 and monitors.hired2)
 assert(tower.residentSquad:getPlatoon()==newChief and bank==60000 and spawns==2)
 assert(Store.get().orders['1'].metadata.residentPID=='original','completed history need not rewrite its creation context')
 recover();assert(adopts==before+2 and tower.residentSquad:getPlatoon()==newChief)
end)
test('completed patrol recovery never overwrites a foreign or temporarily absent tower resident',function()
 for _,foreign in ipairs({true,false})do
  fixture();click('hire')
  local resident=foreign and {getPlatoonStringID=function()return 'foreign-owner'end} or nil
  tower:setResidentSquad(resident)
  local before=adopts;local save=data();emit('PlayerInterface::serialise',{},save)
  emit('PlayerInterface::loadFromSerialise',{},save);recover()
  assert(adopts==before+1 and monitors.hired1 and tower.residentSquad:getPlatoon()==resident)
  assert(bank==80000 and spawns==1)
 end
end)
test('a truncated ledger still attaches the native chief menu and preserves failed data on save',function()
 fixture();local bad=data();bad.sdata.KenshiShopChiefStateV1='KSCS1:T1:S999:cut'
 emit('PlayerInterface::loadFromSerialise',{},bad)
 assert(not Store.ready() and Store.status().held)
 Services.observe({cfg={role='chief'}},{{key='chief',char=chief}})
 assert(dialogueAttaches==1 and rosterObservations==1)
 scanAvailable=false
 local rows,why=Services.listLosses(chief,player);assert(not rows and why=='ROSTER_HISTORY_INCOMPLETE')
 loss('newly-observed')
 rows,why=Services.listLosses(chief,player)
 assert(#rows==1 and rows[1].id=='newly-observed' and why=='SERVICE_STORE_NOT_READY')
 click('replace','newly-observed');assert(bank==100000 and spawns==0)
 Store.get().roster['newly-observed']=nil
 scanAvailable=true;assert(#assert(Services.listLosses(chief,player))==0)
 click('hire');assert(bank==100000 and spawns==0 and next(Store.get().orders)==nil)
 local held=data();emit('PlayerInterface::serialise',{},held)
 assert(type(held.sdata.KenshiShopChiefStateV1Recovery)=='string')
 emit('PlayerInterface::loadFromSerialise',{},held)
 assert(not Store.ready() and Store.status().held)
 Services.observe({cfg={role='chief'}},{{key='chief',char=chief}})
 assert(dialogueAttaches==2 and bank==100000 and spawns==0)
end)
test('a new campaign first save recovers hook readiness after a prior corrupt campaign',function()
 fixture();local bad=data();bad.sdata.KenshiShopChiefStateV1='KSCS1:T1:S999:cut'
 emit('PlayerInterface::loadFromSerialise',{},bad);assert(not Store.ready())
 Services.resetSession();emit('PlayerInterface::serialise',{},data())
 assert(Store.ready());click('hire')
 assert(bank==80000 and spawns==1 and Store.get().orders['1'].status=='complete')
end)
local function clippedSave()
 local function envelope(tag,raw)
  local a,b=1,0
  local hex=raw:gsub('.',function(char)
   a=(a+char:byte())%65521;b=(b+a)%65521
   return string.format('%02x',char:byte())
  end)
  return tag..#raw..':'..(b*65536+a)..':'..hex
 end
 local legacy='KSCS1:T5:S6:ordersT0:S7:patrolsT0:S6:rosterT1:S4:tailS2522:'
  ..string.rep('x',2522)..'S3:seqN1:0S7:versionN1:1'
 local clipped=envelope('KSCS2:',legacy):sub(1,4095)
 for _=1,6 do clipped=envelope('KSHOLD2:',clipped):sub(1,4095)end
 local result=data();local archive=envelope('KSHOLD2:',clipped)
 local size,digest=envelope('KSHOLD2:',archive):match('^KSHOLD2:(%d+):(%d+):')
 local key='KenshiShopChiefStateV1Recovery'
 result.sdata[key]='KSCH3:'..size..':'..digest
 for start=1,#archive,3000 do result.sdata[key..'Chunk'..(1+(start-1)//3000)]=archive:sub(start,start+2999)end
 return result
end
test('explicit new hire opens a separate ledger only after funds and native preflight',function()
 fixture();emit('PlayerInterface::loadFromSerialise',{},clippedSave());assert(Services.newLedgerOffered())
 click('hire');assert(bank==100000 and spawns==0 and not Store.ready())
 bank=15574;click('hire',nil,true);assert(bank==15574 and spawns==0 and not Store.ready())
 bank=100000;patrolsAvailable=false;click('hire',nil,true);assert(bank==100000 and spawns==0 and not Store.ready())
 patrolsAvailable=true;blockPosts=true;click('hire',nil,true);assert(bank==100000 and spawns==0 and not Store.ready())
 priorPatrols={{pid='old-live',building='tower',town='city'}}
 native['old-live']={getPlatoonStringID=function()return 'old-live'end}
 blockPosts=false;click('hire',nil,true)
 assert(Store.ready() and Store.legacyOrdersArchived() and bank==80000 and spawns==1)
 assert(Store.get().patrols['old-live'].base==3 and Store.get().patrols['old-live'].order==nil)
 assert(Store.get().patrols.hired1.base==6 and Store.get().orders['1'].cost==20000)
 recover();assert(monitors['old-live'] and bank==80000 and spawns==1)
 local save=data();emit('PlayerInterface::serialise',{},save);emit('PlayerInterface::loadFromSerialise',{},save)
 assert(Store.ready() and Store.legacyOrdersArchived() and not Services.newLedgerOffered())
 click('hire');assert(bank==60000 and spawns==2 and Store.get().patrols.hired2.base==9)
end)
test('a confirmed casualty replacement can be the first new order',function()
 fixture();emit('PlayerInterface::loadFromSerialise',{},clippedSave());loss('verified')
 local rows,why=Services.listLosses(chief,player)
 assert(#rows==1 and rows[1].id=='verified' and why==nil)
 click('replace','verified',true)
 assert(Store.ready() and Store.legacyOrdersArchived() and bank==90000 and spawns==1)
 assert(Store.get().orders['1'].kind=='replace' and lastSpawnRecord=='verified')
end)
test('replacement in an unidentified old hired squad never opens the ledger or charges',function()
 fixture();emit('PlayerInterface::loadFromSerialise',{},clippedSave())
 loss('unbound-hired',{pid='missing-hired',squadTemplate=Config.hired,building='tower'})
 click('replace','unbound-hired',true)
 assert(not Store.ready() and not Store.legacyOrdersArchived() and bank==100000 and spawns==0)
end)
test('a later verified save reenables purchases after a transient native save failure',function()
 fixture();local bad=data();bad.addString=function()error('temporary native write failure')end
 emit('PlayerInterface::serialise',{},bad);assert(Store.ready())
 click('hire');assert(bank==100000 and spawns==0)
 emit('PlayerInterface::serialise',{},data());click('hire')
 assert(bank==80000 and spawns==1)
end)
print('Chief service payment/reload integration tests passed: '..count)
