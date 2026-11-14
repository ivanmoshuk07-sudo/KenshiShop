-- Behavioral tests with fake engine objects; these do not simulate the Kenshi AI.
local root=assert(arg[1],'scripts path required')
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local passed=0
local function test(name,fn) fn();passed=passed+1;print('PASS '..name)end
local Log={console=function()end,error=function()end}
package.loaded.Diagnostics=Log
local Live=require('Core.NPC.LiveState')
local Work=require('Core.NPC.RoleAI')
local label,replaceCount,setupCount,failMember,busy,carrying
local bb={getCurrentAIPackageName=function()return label end,
 replaceAIPackage=function(_,data)label=data.name;replaceCount=replaceCount+1 end}
local function member(key)
 local c={getHandle=function()return {toString=function()return key end}end,
  getBlackboard=function()return bb end,
  getCarryingObject=function()return {isNull=function()return not carrying end}end,
  setupPlatoonAI=function() if failMember==key then error('temporarily unavailable')end;setupCount=setupCount+1 end}
 for _,name in ipairs({'isDead','isDown','isUnconcious','isCrippled','isBeingCarried','isInCombatMode','isFleeing'})do c[name]=function()return busy end end
 return {key=key,char=c}
end
local a,b=member('leader'),member('mate')
local ap={getSquadLeader=function()return a.char end,getSquadSize=function()return 2 end}
local p={getActivePlatoon=function()return ap end,getOwnerships=function()return {_homeBuilding={toString=function()return 'home'end}}end}
local gm={getData=function(_,id)return {name='KS Native Indoor guards'}end}
function getGameWorld()return {gamedata=gm}end
local function state()
 label='KS Medic Robotics Rescue';replaceCount=0;setupCount=0;failMember=nil;busy=false;carrying=false
 return {cfg={shop='bar',role='guard',count=2},key='home',platoon=p}
end
test('roles choose 24h/day/guard/chief/patrol packages',function()
 for _,x in ipairs({{'bar','trader','8100'},{'robotics','trader','8100'},{'engineering','trader','8101'},
  {'weapons','trader','8101'},{'armour','trader','8101'},{'bar','guard','8102'},
  {'police','chief','8103'},{'police','patrol','8104'}})do
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
test('partial member setup retries without replacing package again',function()
 local s=state();failMember='mate';assert(not Work.ensure(s,{a,b}));assert(setupCount==1)
 failMember=nil;assert(Work.ensure(s,{a,b}));assert(replaceCount==1 and setupCount==2)
end)
test('saved matching package still finishes member setup',function()
 local s=state();label='KS Native Indoor guards';assert(Work.ensure(s,{a,b}));assert(replaceCount==0 and setupCount==2)
end)
test('setup failures stop after three attempts',function()
 local s=state();failMember='leader';for i=1,10 do assert(not Work.ensure(s,{a,b}))end
 assert(s.work.tries==3 and replaceCount==1)
end)
local Catalog=require('Core.NPC.Catalog')
local function data(sid,name,refs,kind)
 local d={stringID=sid,name=name,type=kind or 52,refs=refs or {},idata={},fdata={}}
 function d:getListSize()return #self.refs end
 function d:getFromList(_,i)return self.refs[i+1][1]end
 function d:getValueFromList(_,i)local v=self.refs[i+1];return {v[2],v[3],v[4]}end
 function d:clearList()self.refs={}end
 function d:addToList(_,sid,x,y,z)self.refs[#self.refs+1]={sid,x,y,z}end
 return d
end
local own=data('307-KenshiShop.mod','KS Weapons',{{'fallback',100,0,0}})
local native=data('native','Scraphouse',{{'scraplist',80,2,3}})
native.idata['vendor money']=100000;native.fdata['vendors refresh time']=24
local fallback=data('fallback','weapons',{},49);local scrap=data('scraplist','Scraphouse stock',{},49)
local records={[own.stringID]=own,native=native,fallback=fallback,scraplist=scrap}
gm={mainList={[own]=true,[native]=true},getData=function(_,sid)return records[sid]end}
test('catalog copies native stock refs, weights and quality; source unchanged',function()
 assert(Catalog.prepare({role='trader',shop='weapons',template=own.stringID}))
 assert(own.refs[1][1]=='scraplist' and own.refs[1][2]==80 and own.refs[1][3]==2 and own.refs[1][4]==3)
 assert(own.idata['vendor money']==100000 and native.refs[1][1]=='scraplist')
end)
test('catalog rejects missing referenced data',function()
 local bad=data('bad','KS missing',{{'nonexistent',1,0,0}});records.bad=bad
 assert(not Catalog.prepare({role='trader',shop='bar',template='bad'}))
end)
test('catalog uses normal native refresh, once per loaded state',function()
 local n,setup=0,0
 local active={getHasVendorList=function()return true end,getIsTrader=function()return true end,
  setupTraderBuildings=function()setup=setup+1 end,refreshInventory=function(_,first)assert(first==false);n=n+1 end}
 local s={cfg={role='trader',shop='weapons',template=own.stringID},platoon={getActivePlatoon=function()return active end}}
 assert(Catalog.ensure(s,{}));assert(Catalog.ensure(s,{}));assert(n==1 and setup==1)
end)
test('non-traders never get vendor setup',function()assert(Catalog.ensure({cfg={role='guard'}},{}))end)
print('Behavioral tests passed: '..passed)
