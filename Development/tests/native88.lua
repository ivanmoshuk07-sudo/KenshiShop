-- Regression for native parent-relative LocationNode transforms. No game AI.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
package.loaded.Diagnostics={console=function()end}
local Nodes=require('Core.NPC.NativeNodes');local Audit=require('Core.NPC.PostAudit')
local Posts=require('Core.NPC.PostData');local Transform=require('Transform')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function close(a,b)assert(math.abs(a-b)<0.0001,tostring(a)..' != '..tostring(b))end
local world,s,b,created,scale,turn,origin,moves
local function fixture(shop)
 Nodes.resetSession();created={};scale=0.25;turn=false;origin={x=6500,y=1400,z=77500};moves=0
 local q=math.sqrt(0.5)
 b={getRootNode=function()return 'root'end,isPhysical=function()return true end,
 getScale=function()return scale end,getPosition=function()return origin end,
 getOrientation=function()return turn and {w=q,x=0,y=q,z=0} or {w=1,x=0,y=0,z=0}end,
 getFaction=function()return 'npc-faction'end}
 world={gamedata={getData=function(_,id,kind)assert(kind==0);return {stringID=id}end},theFactory={}}
 function getGameWorld()return world end
 function world.theFactory:createLocationNode(auto,data,p,home,owner,r,save,id)
  assert(auto and home==b and owner=='npc-faction' and save==nil)
  local position
  if turn then position={x=origin.x+p.z,y=origin.y+p.y,z=origin.z-p.x}
  else position={x=origin.x+p.x,y=origin.y+p.y,z=origin.z+p.z}end
  created[#created+1]={input=p,rotation=r,position=position,id=id};return 'opaque-'..#created
 end
 world.theFactory.createBuilding=function()error('physical furniture call forbidden')end
 s={key='building',cfg={shop=shop or 'weapons',role='trader'},building=b,now=12*60,work={leader='npc'}}
 return s
end
test('translation is applied exactly once at actual town-sized coordinates',function()
 fixture();assert(Nodes.ensure(s,b));assert(#created==#Posts.weapons)
 for i,row in ipairs(created)do
  local p=Posts.weapons[i];close(row.input.x,p.p[1]*scale);close(row.input.y,p.p[2]*scale)
  close(row.position.x,origin.x+p.p[1]*scale);close(row.position.z,origin.z+p.p[3]*scale)
 end
end)
test('parent rotation is applied by the engine once, with a scaled local offset',function()
 fixture();turn=true;assert(Nodes.ensure(s,b))
 for i,row in ipairs(created)do
  local p=Posts.weapons[i]
  close(row.position.x,origin.x+p.p[3]*scale);close(row.position.z,origin.z-p.p[1]*scale)
  close(row.position.y,origin.y+p.p[2]*scale)
  close(row.rotation.w,p.q[1]);close(row.rotation.x,p.q[2]);close(row.rotation.y,p.q[3]);close(row.rotation.z,p.q[4])
 end
end)
test('alpha.87 world-input contract would place a valid node far outside its layout',function()
 fixture();local p=Posts.weapons[1]
 local old=Transform.world(origin,b:getOrientation(),scale,p)
 local previousActual={x=origin.x+old.x,y=origin.y+old.y,z=origin.z+old.z}
 local expected=Transform.world(origin,b:getOrientation(),scale,p)
 assert(Transform.error(previousActual,expected)>70000)
 local entry,d=Nodes.nearest(s,b,previousActual);assert(entry and d>70000)
end)
test('all six building layouts retain their original local positions and node rotations',function()
 for _,shop in ipairs({'bar','armour','weapons','engineering','robotics','police'})do
  fixture(shop);turn=true;assert(Nodes.ensure(s,b));assert(#created==#Posts[shop])
  for i,row in ipairs(created)do close(row.input.x,Posts[shop][i].p[1]*scale);close(row.rotation.w,Posts[shop][i].q[1])end
 end
end)
test('invalid scale fails with bounded creation attempts and no physical building calls',function()
 fixture();scale=0;for i=1,10 do assert(not Nodes.ensure(s,b))end;assert(#created==0)
 scale=1;assert(not Nodes.ensure(s,b)) -- the three-failure budget has ended
end)
local function character(point,floor)
 local home={toString=function()return 'building'end}
 local target={isNull=function()return false end,toString=function()return 'node-54'end,
 getRootObjectBase=function()return {getPosition=function()return point end,getFloor=function()return floor end}end}
 local ai={findShopkeeperNode=function()return 1,target end}
 local c={getAI=function()return ai end,getHandle=function()return home end,
 getStateBroadcast=function()return {homeBuilding=home}end,
 getOrdersReciever=function()return {getCurrentGoal=function()return {key=function()return 0 end}end}end,
 getCarryingObject=function()return {isNull=function()return true end}end,
 setDestination=function()moves=moves+1 end,addGoal=function()moves=moves+1 end}
 for _,name in ipairs({'isDead','isDown','isUnconcious','isCrippled','isBeingCarried','isInCombatMode','isFleeing'})do c[name]=function()return false end end
 return c,target
end
test('post readback distinguishes a real layout match from a merely non-null node handle',function()
 fixture();local entry=Posts.weapons[1];local point=Transform.world(origin,b:getOrientation(),scale,entry)
 local c=character(point,entry.floor);local row=Audit.probe(s,c,'npc')
 assert(row.result=='POST_FOUND' and row.geometry=='MATCH' and row.floorMatch==true);close(row.distance,0)
 point.x=point.x+50000;row=Audit.probe(s,c,'npc')
 assert(row.result=='POST_FOUND' and row.geometry=='OUTSIDE_LAYOUT' and row.distance>49000 and moves==0)
end)
test('unreadable node positions are not certified as matching the layout',function()
 fixture();local c,h=character({x=0,y=0,z=0},0);h.getRootObjectBase=function()return nil end
 local row=Audit.probe(s,c,'npc');assert(row.geometry=='POSITION_UNAVAILABLE' and moves==0)
end)
test('floor mismatch is reported without mutating the node or commanding the NPC',function()
 fixture();local p=Posts.weapons[1];local c=character(Transform.world(origin,b:getOrientation(),scale,p),p.floor+1)
 local row=Audit.probe(s,c,'npc');assert(row.geometry=='MATCH' and row.floorMatch==false and moves==0)
end)
print('Native local-coordinate regression tests passed: '..passed)
