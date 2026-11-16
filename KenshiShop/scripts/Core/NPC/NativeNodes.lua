-- Actual engine LocationNodes, created by the dedicated node factory. These
-- are not furniture/Building objects and have no physical model or collision.
local Live=require('Core.NPC.LiveState')
local Transform=require('Transform')
local Posts=require('Core.NPC.PostData')
local Log=require('Diagnostics')
local Native=require('Core.NPC.NativeBridge')
local M={}
local buildings={}
local function postKey(index,outside)
 if type(outside)=='number' then return 'patrol_street_'..outside end
 return outside and 'street' or index
end
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
-- SDK extension wraps the existing factory result as its RootObject base. NPCs
-- remain in their platoon containers even while inside; their container must
-- never be passed to the generic building/interior factory.
local function typed(s,b,data,pos,rot,floor,outside)
 assert(field(field(data,'bdata'),'is node')==true,'NOT_A_NODE_TEMPLATE')
 local base=Native.create(getGameWorld().theFactory,data,b,b:getFaction(),pos,rot)
 assert(base and base:getDataType()==54,'NODE_TYPE_VERIFY_FAILED')
 local h=base:getHandle();local root=base
 assert(root,'NODE_ROOT_UNAVAILABLE')
 root:setFloor(floor)
 if outside then local empty=root.isInsideBuilding;empty:setNull();root.isInsideBuilding=empty end
 assert(root:getFloor()==floor,'NODE_FLOOR_VERIFY_FAILED')
 assert(outside and root.isInsideBuilding:isNull() or (not outside and root.isInsideBuilding:toString()==s.key),'NODE_INTERIOR_VERIFY_FAILED')
 return {base=base,handle=h,root=root,floor=floor,outside=outside}
end
-- With a parent building, the native factory applies parent rotation and
-- translation itself. Scale the LOCAL offset, but do not convert it to world.
function M.localPose(b,p)
 local scale=b:getScale()
 assert(type(scale)=='number' and scale==scale and scale>0 and scale<math.huge,'NODE_SCALE_INVALID')
 local q=p.q
 return {x=p.p[1]*scale,y=p.p[2]*scale,z=p.p[3]*scale},{w=q[1],x=q[2],y=q[3],z=q[4]}
end
-- World coordinates are calculated here only for read-back diagnostics.
function M.nearest(s,b,pos)
 local best,distance
 for _,p in ipairs(Posts[s.cfg.shop] or {})do
  local allowed=s.cfg.role=='trader' and p.kind==0
    or s.cfg.role~='trader' and (p.kind==1 or p.kind==2)
  if allowed then
   local expected=Transform.world(b:getPosition(),b:getOrientation(),b:getScale(),p)
   local d=Transform.error(expected,pos)
   if not distance or d<distance then best,distance=p,d end
  end
 end
 return best,distance
end
function M.resetSession()buildings={}end
function M.ensure(s,b)
 local world=getGameWorld();local gm=world and world.gamedata
 if not gm or not world.theFactory then return false,'NODE_FACTORY_UNAVAILABLE'end
 if Live.call(b,'isPhysical')~=true then return false,'BUILDING_NOT_PHYSICAL'end
 local root=Live.call(b,'getRootNode')
 if not root then return false,'BUILDING_ROOT_UNAVAILABLE'end
 local physical=tostring(root)
 local r=buildings[s.key]
 if not r or r.gm~=gm or r.physical~=physical then
  r={gm=gm,physical=physical,created={},tries=0};buildings[s.key]=r
 end
 if r.done then return true end
 if r.tries>=3 then return false,'NODE_SETUP_FAILED'end
 local entries=Posts[s.cfg.shop] or {};local pending={}
 for i,p in ipairs(entries)do
  local data=Live.call(gm,'getData',p.id,0)
  if not data then return false,'NODE_TEMPLATE_MISSING '..p.id end
  pending[#pending+1]={index=i,entry=p,data=data,id='KS85_NODE:'..s.key..':'..p.source}
 end
 if #pending==0 then return false,'NODE_COORDINATES_MISSING'end
 local ok,err=pcall(function()
  for _,p in ipairs(pending)do
   if not r.created[p.index]then
    local pos,rot=M.localPose(b,p.entry)
    if Native.available() and not r.bridgeFailed then
     local good,node=pcall(typed,s,b,p.data,pos,rot,p.entry.floor,false)
     if good then r.created[p.index]=node
     else
      r.bridgeFailed=tostring(node)
      Log.console('NPC_NODE_BRIDGE89_FAIL '..r.bridgeFailed..' native_alpha88_posts_retained=true')
     end
    end
    if not r.created[p.index]then
     local node=world.theFactory:createLocationNode(true,p.data,pos,b,b:getFaction(),rot,nil,p.id)
     assert(node and not tostring(node):find('(nil)',1,true),'LOCATION_NODE_CREATE_FAILED')
     r.created[p.index]=true
    end
   end
  end
  -- addToNodeListAutomatically=true registers LocationNodes by parent building.
  -- Building.addUsageNode is for NODE_USE (4), not these post types (0/1/2).
 end)
 if not ok then r.tries=r.tries+1;return false,'NATIVE_NODE_SETUP '..tostring(err)end
 r.done=true
 Log.console('NPC_NATIVE_NODES89 shop='..s.cfg.shop..' building='..s.key..' count='..#pending..' bound_nodes='..tostring(Native.available() and not r.bridgeFailed)..' factory=createLocationNode furniture_changes=0 registration=factory_auto input=scaled_local selection=SEE_WORK_AUDIT')
 return true
end
-- Retrieve a bound node subject. Lua never casts a lightuserdata pointer.
-- Creation is independent of NPC location and does not issue movement orders.
function M.target(s,b,ms,index,outside)
 local yes,why=M.ensure(s,b);if not yes then return nil,why end
 local r=buildings[s.key];local key=postKey(index,outside)
 r.targets=r.targets or {};r.targetTries=r.targetTries or {}
 local saved=r.targets[key] or (not outside and r.created[index])
 if type(saved)=='table' then
  local live=Live.call(saved.handle,'getRootObjectBase')
  if not live then return nil,'NODE_HANDLE_UNAVAILABLE'end
  -- Resolve through the native handle each time; never hand a stale wrapper
  -- to addGoal after an unload or reset.
  saved.base=live
  return saved
 end
 if not Native.available() then return nil,'NATIVE_NODE_BRIDGE_UNAVAILABLE'end
 if r.bridgeFailed then return nil,'NATIVE_NODE_BRIDGE_FAILED '..r.bridgeFailed end
 if (r.targetTries[key] or 0)>=3 then return nil,'TYPED_NODE_FAILED'end
 local p=Posts[s.cfg.shop][index]
 local ok,result=pcall(function()
  local pos,rot=M.localPose(b,p)
  if outside then
   local door=assert(Live.call(b,'getDoor'),'BUILDING_DOOR_UNAVAILABLE')
   local wp=assert(Live.call(door,'getDoorPosOutside_extraFarOut',2),'DOOR_OUTSIDE_UNAVAILABLE')
   if type(outside)=='number' then
    assert(outside>=1 and outside<=1024 and outside%1==0,'PATROL_SLOT_INVALID')
    local near=assert(Live.call(door,'getDoorPosOutside_extraFarOut',1),'DOOR_APPROACH_UNAVAILABLE')
    local dx,dz=wp.x-near.x,wp.z-near.z
    local length=math.sqrt(dx*dx+dz*dz);assert(length>0.001,'DOOR_APPROACH_DIRECTION_INVALID')
    -- A row beside the door's actual outward approach. Spacing derives from
    -- the native door offset, so it follows scale and the building rotation.
    local column=(outside-1)%3-1
    local row=math.floor((outside-1)/3)
    local offset=column*length
    local forward=row*length*1.5
    wp={x=wp.x+dx/length*forward-dz/length*offset,y=wp.y,z=wp.z+dz/length*forward+dx/length*offset}
    if outside>3 then
     -- Hired squads use separate rows of actual native posts. Refuse an
     -- invalid location during the caller's pre-payment post preflight.
     local world=getGameWorld()
     assert(world and world.navmesh,'HIRED_POST_NAVMESH_UNAVAILABLE')
     assert(world.navmesh:getPositionValid(wp)==true,'HIRED_POST_NAVMESH_INVALID')
     local town=assert(Live.call(b,'getTown'),'HIRED_POST_TOWN_UNAVAILABLE')
     assert(town:withinBordersRange(wp,1.0)==true,'HIRED_POST_OUTSIDE_TOWN')
    end
   end
   local origin=b:getPosition();local q=b:getOrientation()
   local n=q.w*q.w+q.x*q.x+q.y*q.y+q.z*q.z;assert(n>0,'INVALID_ROTATION')
   local v={w=0,x=wp.x-origin.x,y=wp.y-origin.y,z=wp.z-origin.z}
   local inv={w=q.w/n,x=-q.x/n,y=-q.y/n,z=-q.z/n}
   local localPos=Transform.quat(Transform.quat(inv,v),q)
   pos={x=localPos.x,y=localPos.y,z=localPos.z};rot={w=1,x=0,y=0,z=0}
  end
  local data=assert(getGameWorld().gamedata:getData(p.id,0),'NODE_TEMPLATE_MISSING')
  local node=typed(s,b,data,pos,rot,outside and 0 or p.floor,outside)
  if not outside then
   local expected=Transform.world(b:getPosition(),b:getOrientation(),b:getScale(),p)
   assert(Transform.error(node.base:getPosition(),expected)<0.75,'TYPED_NODE_POSITION_VERIFY_FAILED')
  end
  node.source=outside and 'native-door-outside' or p.source
  return node
 end)
 if not ok then r.targetTries[key]=(r.targetTries[key] or 0)+1;return nil,tostring(result)end
 r.targets[key]=result
 return result
end
function M.available(s,index,outside,member)
 local r=buildings[s.key];local claim=r and r.claims and r.claims[postKey(index,outside)]
 return not claim or claim.member==member or Live.call(claim.char,'isDead')==true
end
function M.claim(s,index,outside,m)
 local r=assert(buildings[s.key]);r.claims=r.claims or {}
 for k,v in pairs(r.claims)do if v.member==m.key then r.claims[k]=nil end end
 if index then r.claims[postKey(index,outside)]={member=m.key,char=m.char}end
end
return M
