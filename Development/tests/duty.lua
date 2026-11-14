-- Native AI integration boundaries: no Lua movement loop, real logical nodes,
-- persistent stock grades, safe migration, and no physical furniture changes.
local root=assert(arg[1]);package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
package.loaded.Diagnostics={console=function()end,error=function()end}
local Nodes=require('Core.NPC.NativeNodes');local Duty=require('Core.NPC.Duty');local Catalog=require('Core.NPC.Catalog')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local world
function getGameWorld()return world end
local function fixture(shop)
 Nodes.resetSession();local calls={created=0,attached=0,physical=0};local ids={}
 world={gamedata={getData=function(_,sid,kind)assert(kind==0);return {stringID=sid}end},theFactory={}}
 local faction={};local rootToken={}
 local b={getRootNode=function()return rootToken end,getPosition=function()return {x=20,y=10,z=30}end,getOrientation=function()return {w=1,x=0,y=0,z=0}end,
  getScale=function()return 1 end,isPhysical=function()return true end,getFaction=function()return faction end,
  updateUsageNodes=function()end,forceValidUsageNodesValidation=function()end}
 function b:addUsageNode(id)calls.attached=calls.attached+1;assert(ids[id]);ids[id].attached=true end
 function world.theFactory:createLocationNode(auto,data,pos,home,owner,rot,save,id)
  assert(auto and home==b and owner==faction and save==nil and rot.w and pos.x)
  assert(data.stringID=='1180-gamedata.base' or data.stringID=='1186-gamedata.base' or data.stringID=='1184-gamedata.base')
  assert(not ids[id],'duplicate node ID');ids[id]={position=pos};calls.created=calls.created+1;return {}
 end
 function world.theFactory:createBuilding()calls.physical=calls.physical+1;error('furniture mutation')end
 return {cfg={shop=shop or 'weapons',role='trader'},key='home',building=b},b,calls,ids
end
test('trader and separate guard share exactly one native node set, zero furniture calls',function()
 local s,b,calls,ids=fixture();assert(Nodes.ensure(s,b));s.cfg.role='guard'
 for i=1,100 do assert(Nodes.ensure(s,b))end
 assert(calls.created==15 and calls.attached==15 and calls.physical==0)
 for _,v in pairs(ids)do assert(v.attached)end
end)
test('node positions transform existing posts into world space without moving furniture',function()
 local s,b,_,ids=fixture();assert(Nodes.ensure(s,b));local p
 for _,v in pairs(ids)do if math.abs(v.position.x-63.1220436)<0.0001 then p=v.position end end
 assert(p)
 assert(math.abs(p.x-63.1220436)<0.0001 and math.abs(p.y-14.64026594)<0.0001)
end)
test('partial node attachment failure never recreates a successfully created node',function()
 local s,b,calls=fixture();local add=b.addUsageNode;local fail=true
 function b:addUsageNode(id)if fail then fail=false;error('temporarily unavailable')end;return add(self,id)end
 assert(not Nodes.ensure(s,b));assert(calls.created==1)
 assert(Nodes.ensure(s,b));assert(calls.created==15 and calls.attached==15)
end)
test('unloaded buildings defer without using the finite node failure budget',function()
 local s,b,calls=fixture();local physical=false;b.isPhysical=function()return physical end
 for i=1,20 do assert(not Nodes.ensure(s,b))end
 assert(calls.created==0);physical=true;assert(Nodes.ensure(s,b))
end)
test('unsupported native node API stops after three failures without a movement fallback',function()
 local s,b,calls=fixture();local attempts=0
 world.theFactory.createLocationNode=function()attempts=attempts+1;error('unsupported API')end
 for i=1,20 do assert(not Nodes.ensure(s,b))end
 assert(attempts==3 and calls.physical==0 and calls.created==0)
end)
test('patrol shares all nine logical police nodes with the chief; no Lua route',function()
 local s,b,calls=fixture('police');s.cfg.role='patrol';assert(Nodes.ensure(s,b));assert(calls.created==9)
end)
test('repeated duty audits only observe native care, work and combat; issue zero commands',function()
 local moves,goals,attacks,clears=0,0,0,0;local active=37
 local c={getOrdersReciever=function()return {getCurrentGoal=function()return {key=function()return active end}end}end,
  setDestination=function()moves=moves+1 end,addGoal=function()goals=goals+1 end,
  attackTarget=function()attacks=attacks+1 end,clearAllAIGoals=function()clears=clears+1 end}
 local s={cfg={role='patrol'}}
 for _,task in ipairs({37,139,20,268,288,57,58,148,12})do
  active=task;for i=1,100 do Duty.tick(s,{{key='npc',char=c}})end
  assert(Duty.status(s)=='NATIVE_TASK_'..task..':1')
 end
 assert(moves==0 and goals==0 and attacks==0 and clears==0)
end)
test('Armour King grade chances persist after return and cover independent engine restocks',function()
 local own={idata={}};local runtime={idata={}};local donor={stringID='42088-rebirth.mod',idata={}}
 for i,v in ipairs({0,0,2,80,110,50})do donor.idata['armors '..(i-1)]=v;own.idata['armors '..(i-1)]=1;runtime.idata['armors '..(i-1)]=1 end
 world={factionMgr={getFactionByStringID=function()return {getData=function()return runtime end}end}}
 local gm={getData=function(_,sid,kind)assert(kind==10);return sid=='400-KenshiShop.mod' and own or donor end}
 assert(Catalog.syncQuality(gm))
 -- Simulate a later native refresh, after syncQuality has already returned.
 for i=0,5 do assert(own.idata['armors '..i]==donor.idata['armors '..i]);assert(runtime.idata['armors '..i]==donor.idata['armors '..i])end
 assert(donor.idata['armors 5']==50 and runtime.idata['armors 1']==0)
end)
test('zero grade weights in a loaded original profile cannot be certified as correct',function()
 local own={idata={}};local native={idata={}}
 for i=0,5 do native.idata['armors '..i]=0 end
 local gm={getData=function(_,id)return id=='400-KenshiShop.mod' and own or native end}
 assert(not Catalog.syncQuality(gm));assert(own.idata['armors 5']==nil)
end)
test('saved stock migration refreshes once, ordinary reload respects native restock time',function()
 local prepare=Catalog.prepare;Catalog.prepare=function()return true,{source='fixture'}end
 local forced,ordinary=0,0
 local ap={getHasVendorList=function()return true end,getIsTrader=function()return true end,setupTraderBuildings=function()end,
  _forceRefreshInventory=function()forced=forced+1 end,refreshInventory=function(_,first)assert(first==false);ordinary=ordinary+1 end}
 local p={getActivePlatoon=function()return ap end}
 local s={cfg={role='trader',shop='bar'},saved=true,now=1,work={done=true,upgraded=true},platoon=p}
 assert(Catalog.ensure(s,{}));assert(Catalog.ensure(s,{}));assert(forced==1)
 local loaded={cfg=s.cfg,saved=true,now=2,work={done=true},platoon=p}
 assert(Catalog.ensure(loaded,{}));assert(forced==1 and ordinary==2)
 Catalog.prepare=prepare
end)
print('Native integration boundary tests passed: '..passed)
