-- Behavioral tests with fake engine objects; these do not simulate the Kenshi AI.
local root=assert(arg[1],'scripts path required')
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local passed=0
local function test(name,fn) fn();passed=passed+1;print('PASS '..name)end
local Log={console=function()end,error=function()end}
package.loaded.Diagnostics=Log
package.loaded['Core.NPC.NativeNodes']={ensure=function()return true end}
local Live=require('Core.NPC.LiveState')
local Work=require('Core.NPC.RoleAI')
local label,replaceCount,setupCount,failMember,busy,carrying
local town={getHandle=function()return {toString=function()return 'town'end}end}
local faction={getData=function()return {stringID='400-KenshiShop.mod'}end}
local owns={_homeBuilding={toString=function()return 'home'end},_homeTown=town}
function owns:setHomeBuilding(h)self._homeBuilding=h end
function owns:setHomeTown(t)self._homeTown=t end
local bb={getCurrentTownLocation=function()return town end,getCurrentAIPackageName=function()return label end,
 replaceAIPackage=function(_,data)label=data.name;replaceCount=replaceCount+1 end}
local function member(key)
 local state={}
 local c={getStateBroadcast=function()return state end,getHandle=function()return {toString=function()return key end}end,
  getOwnerships=function()return owns end,
  getOrdersReciever=function()return {goals={},setNeedGOAP=function()end,hasOrders=function()return false end}end,
  getBlackboard=function()return bb end,
  getCarryingObject=function()return {isNull=function()return not carrying end}end,
  setupPlatoonAI=function() if failMember==key then error('temporarily unavailable')end;setupCount=setupCount+1 end}
 for _,name in ipairs({'isDead','isDown','isUnconcious','isCrippled','isBeingCarried','isInCombatMode','isFleeing'})do c[name]=function()return busy end end
 return {key=key,char=c}
end
local a,b=member('leader'),member('mate')
local ap={getSquadLeader=function()return a.char end,getSquadSize=function()return 2 end}
local p={getSquadType=function()return 1 end,getFaction=function()return faction end,getActivePlatoon=function()return ap end,getOwnerships=function()return owns end}
local gm={getData=function(_,id)return {name='KS85 Indoor guards'}end}
function getGameWorld()return {gamedata=gm}end
local function state()
 label='KS Medic Robotics Rescue';replaceCount=0;setupCount=0;failMember=nil;busy=false;carrying=false
 return {cfg={shop='bar',role='guard',count=2,faction='400-KenshiShop.mod'},key='home',platoon=p,building={getHandle=function()return {toString=function()return 'home'end}end,getFaction=function()return faction end,getTown=function()return town end}}
end
test('roles choose 24h/day/guard/chief/patrol packages',function()
 for _,x in ipairs({{'bar','trader','8500'},{'robotics','trader','8500'},{'engineering','trader','8501'},
  {'weapons','trader','8501'},{'armour','trader','8501'},{'bar','guard','8502'},
  {'police','chief','8503'},{'police','patrol','8504'}})do
  local id=Work.package({shop=x[1],role=x[2]});assert(id==x[3]..'-KenshiShop.mod')
 end
end)
test('handoff once; successful audit is idempotent',function()
 local s=state();assert(Work.ensure(s,{a,b}));assert(Work.ensure(s,{a,b}));assert(replaceCount==1 and setupCount==2)
end)
test('combat defers handoff without spending retry budget',function()
 local s=state();busy=true;for i=1,8 do assert(not Work.ensure(s,{a,b}))end
 assert(replaceCount==0 and s.work.tries==0);busy=false;assert(Work.ensure(s,{a,b}))
end)
test('carrying a rescued character defers handoff',function()
 local s=state();carrying=true;assert(not Work.ensure(s,{a,b}));assert(replaceCount==0)
end)
test('native/player orders defer package replacement without using retry budget',function()
 local s=state();local old=a.char.getOrdersReciever
 a.char.getOrdersReciever=function()return {hasOrders=function()return true end}end
 assert(not Work.ensure(s,{a,b}));assert(replaceCount==0 and s.work.tries==0)
 a.char.getOrdersReciever=old;assert(Work.ensure(s,{a,b}))
end)
test('an incorrect restored home town is repaired before native wandering is enabled',function()
 local s=state();owns._homeTown={getHandle=function()return {toString=function()return 'wrong-town'end}end}
 local calls=0
 owns.setHomeTown=function(self,t,kind)assert(t==town and kind==1);self._homeTown=t;calls=calls+1 end
 assert(Work.ensure(s,{a,b}));assert(calls==1 and bb.targetTown==town)
 owns.setHomeTown=nil
end)
test('partial member setup retries without replacing package again',function()
 local s=state();failMember='mate';assert(not Work.ensure(s,{a,b}));assert(setupCount==1)
 failMember=nil;assert(Work.ensure(s,{a,b}));assert(replaceCount==1 and setupCount==2)
end)
test('saved matching package still finishes member setup',function()
 local s=state();label='KS85 Indoor guards';assert(Work.ensure(s,{a,b}));assert(replaceCount==0 and setupCount==2)
end)
test('saved alpha.81 and alpha.82 packages are recognized, then migrated once',function()
 for _,old in ipairs({'KS Native Indoor guards','KS82 Indoor guards','KS83 Indoor guards'})do
  local s=state();label=old
  assert(Work.isWorkingPackage(s.cfg,label));assert(Work.ensure(s,{a,b}))
  assert(s.work.upgraded and label=='KS85 Indoor guards' and replaceCount==1)
  assert(Work.ensure(s,{a,b}) and replaceCount==1)
 end
end)
test('setup failures stop after three attempts',function()
 local s=state();failMember='leader';for i=1,10 do assert(not Work.ensure(s,{a,b}))end
 assert(s.work.tries==3 and replaceCount==0)
end)
local Catalog=require('Core.NPC.Catalog')
local function data(sid,name,refs,kind)
 local d={stringID=sid,name=name,type=kind or 52,refs=refs or {},idata={},fdata={},lists={}}
 function d:rows(cat)return cat=='vendors' and self.refs or self.lists[cat] or {} end
 function d:getListSize(cat)return #self:rows(cat) end
 function d:getFromList(cat,i)local v=self:rows(cat)[i+1];return v and v[1]end
 function d:getValueFromList(cat,i)local v=self:rows(cat)[i+1];return {v[2],v[3],v[4]}end
 function d:clearList(cat)if cat=='vendors'then self.refs={}else self.lists[cat]={}end end
 function d:addToList(cat,sid,x,y,z)local rows=self:rows(cat);rows[#rows+1]={sid,x,y,z}end
 return d
end
local own=data('307-KenshiShop.mod','KS Weapons',{{'fallback',100,0,0}})
local native=data('native','Scrap House',{{'scraplist',80,2,3}})
own.idata['gear artifacts base value']=500;native.idata['gear artifacts base value']=0;native.idata['vendor money']=100000;native.fdata['vendors refresh time']=24
local fallback=data('fallback','weapons',{},49);local scrap=data('scraplist','Scraphouse stock',{},49)
local faction=data('400-KenshiShop.mod','Our faction',{},10)
local skeletons=data('42088-rebirth.mod','Skeletons',{},10)
for i,v in ipairs({0,0,2,80,110,50})do skeletons.idata['armors '..(i-1)]=v end
local records={[own.stringID]=own,native=native,fallback=fallback,scraplist=scrap,[faction.stringID]=faction,[skeletons.stringID]=skeletons}
gm={mainList={[own]=true,[native]=true},getData=function(_,sid)return records[sid]end}
test('catalog copies native stock refs, weights and quality; source unchanged',function()
 assert(Catalog.prepare({role='trader',shop='weapons',template=own.stringID}))
 assert(own.refs[1][1]=='scraplist' and own.refs[1][2]==80 and own.refs[1][3]==2 and own.refs[1][4]==3)
 assert(own.idata['gear artifacts base value']==0);assert(own.idata['vendor money']==100000 and native.refs[1][1]=='scraplist')
end)
test('catalog rejects missing referenced data',function()
 local bad=data('bad','KS missing',{{'nonexistent',1,0,0}});records.bad=bad
 assert(not Catalog.prepare({role='trader',shop='bar',template='bad'}))
end)
test('catalog uses normal native refresh, setup once; repeated normal refresh remains native time-gated',function()
 local n,setup=0,0
 local active={getHasVendorList=function()return true end,getIsTrader=function()return true end,
  setupTraderBuildings=function()setup=setup+1 end,refreshInventory=function(_,first)assert(first==false);n=n+1 end}
 local s={work={done=true},cfg={role='trader',shop='weapons',template=own.stringID},platoon={getActivePlatoon=function()return active end}}
 assert(Catalog.ensure(s,{}));assert(Catalog.ensure(s,{}));assert(n==2 and setup==1)
end)
test('non-traders never get vendor setup',function()assert(Catalog.ensure({cfg={role='guard'}},{}))end)
test('stable native IDs work with translated names and no squad enumeration',function()
 local scrap=data('56154-rebirth.mod','Хламилище',{{'52319-rebirth.mod',100,0,0},{'56149-rebirth.mod',7,0,0},{'49375-rebirth.mod',30,0,0}})
 local mech=data('44855-rebirth.mod','Механическая лавка',{{'1502-gamedata.base',100,0,0}})
 local weapon=data('weap83','Свой продавец',{{'fallback',1,0,0}})
 local eng=data('eng83','Свой инженер',{{'fallback',1,0,0}})
 scrap.lists['special items']={{'rare-item',2,4,100}}
 weapon.lists['weapon level']={{'obsolete-level',1,0,0}}
 records[scrap.stringID]=scrap;records[mech.stringID]=mech;records.weap83=weapon;records.eng83=eng
 for _,sid in ipairs({'52319-rebirth.mod','56149-rebirth.mod','49375-rebirth.mod','1502-gamedata.base'})do records[sid]=data(sid,'Локализованный набор',{},49)end
 gm.mainList={}
 local ok,profile=Catalog.prepare({role='trader',shop='weapons',template='weap83'})
 assert(ok and profile.source=='56154-rebirth.mod' and #weapon.refs==3)
 assert(weapon.lists['special items'][1][2]==2 and #weapon.lists['weapon level']==0)
 local yes,engineering=Catalog.prepare({role='trader',shop='engineering',template='eng83'})
 assert(yes and engineering.source=='44855-rebirth.mod' and #eng.refs==3)
 assert(eng.refs[2][1]=='49375-rebirth.mod' and eng.refs[2][2]==30)
 assert(eng.refs[3][1]=='56149-rebirth.mod' and eng.refs[3][2]==7)
 assert(#scrap.refs==3 and #mech.refs==1 and scrap.lists['special items'][1][2]==2)
end)
test('bar contains native food, drink, medical and expedition lists, donor unchanged',function()
 local original=data('58699-rebirth.mod','Бар Края Мира',{{'1973-gamedata.base',100,0,0},{'44862-rebirth.mod',80,2,3},{'posters',10,0,0}})
 records[original.stringID]=original
 for _,sid in ipairs({'1973-gamedata.base','44862-rebirth.mod','posters'})do records[sid]=data(sid,'Набор',{},49)end
 local bar=data('bar84','Свой бар',{{'1973-gamedata.base',100,0,0}});records.bar84=bar
 local ok,profile=Catalog.prepare({role='trader',shop='bar',template='bar84'})
 assert(ok and profile.source==original.stringID and #bar.refs==3)
 assert(bar.refs[2][1]=='44862-rebirth.mod' and bar.refs[2][2]==80 and bar.refs[2][3]==2)
 assert(#original.refs==3 and original.refs[2][1]=='44862-rebirth.mod')
end)
test('bar cannot report ready if its required travel supplies record is absent',function()
 local record=records['44862-rebirth.mod'];records['44862-rebirth.mod']=nil
 records['missing-bar84']=data('missing-bar84','Бар',{{'1973-gamedata.base',100,0,0}})
 assert(not Catalog.prepare({role='trader',shop='bar',template='missing-bar84'}))
 records['44862-rebirth.mod']=record
end)
print('Behavioral tests passed: '..passed)
