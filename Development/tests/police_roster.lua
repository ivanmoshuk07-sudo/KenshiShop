-- Portable native-object mocks: absence and unloaded squads are never deaths.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local Store=require('Core.Police.Services.Store')
local Config=require('Core.Police.Services.Config')
local Roster=require('Core.Police.Services.Roster')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local objects,active,unloaded,world,faction,activeFail,unloadedFail
local function hand(key)
 return {key=key,toString=function(self)return self.key end,isNull=function(self)return self.key==nil end,
  fromString=function(self,value)self.key=value end,
  getBuilding=function(self)local o=objects[self.key];return o and o.kind=='building' and o or nil end,
  getCharacter=function(self)local o=objects[self.key];return o and o.kind=='character' and o or nil end}
end
local function native(key,kind)
 local o={key=key,kind=kind,isValid=function()return true end}
 function o:getHandle()return hand(self.key)end
 objects[key]=o;return o
end
local function building(key,townID)
 local town=native(townID,'town')
 local b=native(key,'building');function b:getTown()return town end
 return b
end
local function squad(key,template,b,loaded)
 local p=native('platoon:'..key,'platoon')
 p.squadTemplate={stringID=template};p.members={};p.loaded=loaded~=false
 function p:getPlatoonStringID()return key end
 function p:getFaction()return faction end
 function p:getOwnerships()return {_homeBuilding=hand(b and b.key)}end
 local ap={me=p}
 function ap:getSquadSize()return #p.members end
 function ap:getSquadLeader()return p.members[1]end
 function p:getActivePlatoon()return self.loaded and ap or nil end
 return p,ap
end
local function member(key,p,name,race,owner)
 local c=native(key,'character');c.dead=false;c.name=name or key;c.platoon=p
 function c:getName()return self.name end
 function c:getGameData()return {stringID='character-'..key}end
 function c:getRace()return {data={stringID=race or 'race-'..key}}end
 function c:getFaction()return owner or faction end
 function c:isDead()return self.dead end
 function c:getPlatoon()return self.platoon and self.platoon:getActivePlatoon()end
 if p then p.members[#p.members+1]=c end
 return c
end
local function observe(p,b,ms)
 local out={};for _,c in ipairs(ms or p.members)do out[#out+1]={key=c.key,char=c}end
 return Roster.observe({cfg=Config.copy(p.squadTemplate.stringID),platoon=p,building=b,key=b.key,now=100},out)
end
local function fixture()
 objects={};active={};unloaded={};activeFail=false;unloadedFail=false
 faction={getData=function()return {stringID=Config.faction}end}
 function faction:getActivePlatoons()if activeFail then error('active not readable')end;return active end
 function faction:getUnloadedPlatoons()if unloadedFail then error('unloaded not readable')end;return unloaded end
 world={charUpdateListMain={},deathParade={},factionMgr={getFactionByStringID=function(_,id)
  assert(id==Config.faction);return faction
 end}}
 function getGameWorld()return world end
 Store.reset();Roster.reset();assert(Store.load({sdata={}}))
 return building('shop-A','town-A')
end
local function plain(value)
 local kind=type(value)
 if kind=='table' then
  assert(getmetatable(value)==nil)
  for k,v in pairs(value)do assert(type(k)=='string' or type(k)=='number' or type(k)=='boolean');plain(v)end
 else assert(kind=='string' or kind=='number' or kind=='boolean',kind)end
end

test('observation and death wait for the current save ledger',function()
 local b=fixture();local p=squad('guard','7800-KenshiShop.mod',b);local c=member('guard',p);c.dead=true
 Store.reset()
 local ok,why=observe(p,b);assert(not ok and why=='STORE_NOT_READY')
 ok,why=Roster.death(c);assert(not ok and why=='STORE_NOT_READY')
 ok,why=Roster.scan();assert(not ok and why=='STORE_NOT_READY')
 assert(next(Store.get().roster)==nil)
end)
test('saved guard names preserve floor roles and native race identities',function()
 local b=fixture();local p=squad('guard','7800-KenshiShop.mod',b)
 local second=member('a-second',p,'KS: Охрана (2 этаж)','custom-race')
 local first=member('z-first',p,'KS: Охрана (1 этаж)','other-race')
 assert(observe(p,b));local rows=Store.get().roster
 assert(rows[second.key].slot==2 and rows[second.key].floor==1 and rows[second.key].race=='custom-race')
 assert(rows[first.key].slot==1 and rows[first.key].floor==0)
 assert(rows[second.key].leader==true and rows[first.key].leader==false)
 assert(rows[first.key].pid=='guard' and rows[first.key].building=='shop-A' and rows[first.key].town=='town-A')
 assert(rows[first.key].squadTemplate=='7800-KenshiShop.mod' and rows[first.key].charTemplate=='character-z-first')
 plain(rows)
end)
test('native observation preserves confirmed deaths replacement links and order receipts',function()
 local b=fixture();local p=squad('guard','7800-KenshiShop.mod',b);local c=member('guard',p)
 assert(observe(p,b));local row=Store.get().roster.guard
 row.dead=true;row.replacedBy='new-guard';row.order='paid-order';row.extra='saved'
 assert(observe(p,b));assert(row.dead and row.replacedBy=='new-guard' and row.order=='paid-order' and row.extra=='saved')
end)
test('missing members missing squads and unloading never confirm a death',function()
 local b=fixture();local p=squad('patrol','311-KenshiShop.mod',b)
 local a=member('a',p);local missing=member('missing',p)
 active={p};assert(observe(p,b));assert(observe(p,b,{a}))
 assert(Store.get().roster.missing.dead==false)
 p.loaded=false;active={};unloaded={p};world.charUpdateListMain={}
 assert(Roster.scan());assert(Roster.findPlatoon('patrol')==p)
 assert(Store.get().roster.missing.dead==false)
 unloaded={};local found,why=Roster.findPlatoon('patrol')
 assert(found==nil and why=='TRUE_NOT_FOUND' and Store.get().roster.missing.dead==false)
end)
test('only a literal true from the native character confirms death',function()
 local b=fixture();local p=squad('trader','300-KenshiShop.mod',b);local c=member('trader',p)
 assert(observe(p,b))
 for _,value in ipairs({false,1,'true'})do c.dead=value;assert(not Roster.death(c));assert(not Store.get().roster.trader.dead)end
 c.isDead=function()error('temporarily unreadable')end;assert(not Roster.death(c))
 c.isDead=function()return true end;assert(Roster.death(c));assert(Store.get().roster.trader.dead)
 c.isDead=function()return false end;assert(observe(p,b));assert(Store.get().roster.trader.dead)
end)
test('loaded faction scans use the native character membership set',function()
 local b=fixture();local p=squad('chief','310-KenshiShop.mod',b);local c=member('chief',p)
 active={p};world.charUpdateListMain[c]=true
 assert(Roster.scan());assert(Store.get().roster.chief.dead==false)
 c.dead=true;assert(Roster.scan());assert(Store.get().roster.chief.dead==true)
end)
test('a fresh reconciliation requests only one global membership refresh for all squads',function()
 local b=fixture();local first=squad('first','7800-KenshiShop.mod',b);local second=squad('second','311-KenshiShop.mod',b)
 local a=member('first-member',first);local c=member('second-member',second)
 active={first,second};world.charUpdateListMain[a]=true;world.charUpdateListMain[c]=true
 local transport=require('Core.NPC.Transport');local original=transport.members;local calls={}
 transport.members=function(w,p,expected,fresh)
  calls[#calls+1]=fresh==true
  return original(w,p,expected,fresh)
 end
 local ok,why=Roster.scan(true);transport.members=original
 assert(ok,why);assert(#calls==2 and calls[1]==true and calls[2]==false)
 assert(Store.get().roster[a.key] and Store.get().roster[c.key])
end)
test('historical native corpses can be recognized without any earlier observation',function()
 local b=fixture();local p=squad('old-guard','7800-KenshiShop.mod',b)
 local c=member('old-corpse',p,'KS: Охрана (2 этаж)','saved-race');c.dead=true
 world.deathParade[hand(c.key)]=c
 assert(Roster.scan());local row=assert(Store.get().roster[c.key])
 assert(row.dead and row.slot==2 and row.floor==1 and row.race=='saved-race' and row.name=='KS: Охрана (2 этаж)')
end)
test('a null platoon home handle permits a valid native character home fallback',function()
 local b=fixture();local p=squad('old-guard','7800-KenshiShop.mod',nil)
 local c=member('old-corpse',p);c.dead=true
 function c:getOwnerships()return {_homeBuilding=hand(b.key)}end
 assert(Roster.death(c));assert(Store.get().roster[c.key].building==b.key)
end)
test('foreign unknown homeless and unconfirmed corpses are excluded',function()
 local b=fixture();local foreign={getData=function()return {stringID='foreign'}end}
 local p=squad('foreign','7800-KenshiShop.mod',b)
 local wrongFaction=member('foreign',p,nil,nil,foreign);wrongFaction.dead=true
 local unknown=squad('unknown','unrelated-template',b);local wrongTemplate=member('unknown',unknown);wrongTemplate.dead=true
 local homeless=squad('homeless','7800-KenshiShop.mod',nil);local noHome=member('homeless',homeless);noHome.dead=true
 local living=member('living',p);local lying=member('nonboolean',p);lying.dead=1
 for _,c in ipairs({wrongFaction,wrongTemplate,noHome,living,lying})do world.deathParade[hand(c.key)]=c end
 assert(Roster.scan());assert(next(Store.get().roster)==nil)
end)
test('a saved known corpse remains recognizable after its original platoon disappears',function()
 local b=fixture();local p=squad('old','300-KenshiShop.mod',b);local c=member('known',p)
 assert(observe(p,b));c.platoon=nil;c.dead=true;world.deathParade[hand(c.key)]=c
 assert(Roster.scan());assert(Store.get().roster.known.dead)
end)
test('death captures a newly saved guard floor name and changed native race',function()
 local b=fixture();local p=squad('guard','7800-KenshiShop.mod',b);local c=member('guard',p)
 assert(observe(p,b));c.name='KS: Охрана (2 этаж)';c.dead=true
 function c:getRace()return {data={stringID='changed-race'}}end
 assert(Roster.death(c));local row=Store.get().roster.guard
 assert(row.slot==2 and row.floor==1 and row.name==c.name and row.race=='changed-race')
end)
test('a missing platoon is definitive only after both native lists were read',function()
 local b=fixture();local p=squad('unloaded','311-KenshiShop.mod',b,false)
 unloaded={p};activeFail=true
 assert(Roster.findPlatoon('unloaded')==p)
 local found,why=Roster.findPlatoon('missing');assert(found==nil and why~='TRUE_NOT_FOUND')
 activeFail=false;unloadedFail=true;found,why=Roster.findPlatoon('missing');assert(found==nil and why~='TRUE_NOT_FOUND')
 unloadedFail=false;active=setmetatable({},{__len=function()error('list unreadable')end})
 found,why=Roster.findPlatoon('missing');assert(found==nil and why~='TRUE_NOT_FOUND')
 active={};found,why=Roster.findPlatoon('missing');assert(found==nil and why=='TRUE_NOT_FOUND')
 active=setmetatable({[1]=squad('other','311-KenshiShop.mod',b),[3]=p},{__len=function()return 3 end})
 unloaded={};assert(Roster.findPlatoon('unloaded')==p)
end)
test('hired patrol configuration restores its own ID and paid street slot base',function()
 local b=fixture();local p=squad('paid','11000-KenshiShop.mod',b)
 Store.get().patrols.paid={base=6}
 local cfg=Roster.config(p)
 assert(cfg.patrolNight and cfg.serviceHired and cfg.existingID=='paid' and cfg.streetSlotBase==6)
 cfg.streetSlotBase=99;assert(Roster.config(p).streetSlotBase==6)
 p.squadTemplate.stringID='311-KenshiShop.mod';cfg=Roster.config(p)
 assert(not cfg.patrolNight and not cfg.serviceHired and cfg.streetSlotBase==nil and cfg.existingID==nil)
end)
test('copied hands resolve the current building and reset clears only runtime caches',function()
 local b=fixture();local p=squad('patrol','311-KenshiShop.mod',b);member('guard',p)
 active={p};assert(observe(p,b));assert(Roster.building('shop-A')==b)
 local newBuilding=building('shop-A','town-A')
 assert(Roster.building('shop-A')==newBuilding)
 local row=Store.get().roster.guard;Roster.reset()
 assert(Store.get().roster.guard==row and Store.ready())
 assert(Roster.building('shop-A')==newBuilding)
 -- Resolving a different saved ID must not mutate an already cached hand.
 local other=building('shop-B','town-B')
 assert(Roster.building('shop-B')==other and Roster.building('shop-A')==newBuilding)
 objects['shop-A']=nil;assert(Roster.building('shop-A')==nil and row.dead==false)
end)
test('roster metadata round-trips as plain records without runtime engine handles',function()
 local b=fixture();local p=squad('patrol','311-KenshiShop.mod',b);local c=member('guard',p)
 active={p};assert(observe(p,b));c.dead=true;assert(Roster.death(c));plain(Store.get())
 local gd={sdata={},addString=function(self,k,v)self.sdata[k]=v end}
 assert(Store.save(gd));Roster.reset();Store.reset();assert(Store.load(gd))
 local row=Store.get().roster.guard
 assert(row.dead and row.pid=='patrol' and row.race=='race-guard' and row.building=='shop-A')
 plain(Store.get())
end)
print('Police confirmed-death roster tests passed: '..count)
