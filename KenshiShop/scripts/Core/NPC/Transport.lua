-- KenshiShop alpha.22: finite, isolated NPC spawning and navigation helpers.
local M={}
function M.valid(p)
 return p and type(p.x)=='number' and type(p.y)=='number' and type(p.z)=='number'
  and p.x==p.x and p.y==p.y and p.z==p.z
  and math.abs(p.x)<10000000 and math.abs(p.y)<10000000 and math.abs(p.z)<10000000
end
function M.distance2D(a,b)
 local dx,dz=a.x-b.x,a.z-b.z
 return math.sqrt(dx*dx+dz*dz)
end
function M.fmt(p)return string.format('%.1f,%.1f,%.1f',p.x,p.y,p.z)end
local function outside(town,pos)
 local ok,within=pcall(town.withinBordersRange,town,pos,1.04)
 return ok and not within
end
local function navsafe(world,p)
 if not world.navmesh then return false end
 local ok,yes=pcall(world.navmesh.getPositionValid,world.navmesh,p)
 return ok and yes==true
end
function M.selectOutside(building,world)
 local town=assert(building:getTown(),'TOWN_MISSING')
 local bp=assert(building:getPosition(),'BUILDING_POSITION_MISSING')
 assert(M.valid(bp),'BUILDING_POSITION_INVALID')
 local ok,pos=pcall(town.getPositionOutsideTownGates,town,55)
 if ok and M.valid(pos) and outside(town,pos) and navsafe(world,pos) then return pos,'gate' end
 local center=assert(town:getPosition(),'TOWN_POSITION_MISSING')
 assert(M.valid(center),'TOWN_POSITION_INVALID')
 local rad=tonumber(town:getRadius()) or 0
 local dx,dz=bp.x-center.x,bp.z-center.z
 local start
 if math.atan2 then start=math.atan2(dz,dx)
 elseif dx>0 then start=math.atan(dz/dx)
 elseif dx<0 then start=math.atan(dz/dx)+(dz>=0 and math.pi or -math.pi)
 elseif dz>0 then start=math.pi/2 else start=-math.pi/2 end
 -- 3 finite rings * 16 directions; no random far-away teleport.
 for ring=1,3 do
  local radius=math.max(160,rad+55+65*(ring-1))
  for i=0,15 do
   local a=start+i*math.pi/8
   local p={x=center.x+radius*math.cos(a),y=bp.y,z=center.z+radius*math.sin(a)}
   if outside(town,p) and navsafe(world,p) then return p,'ring'..ring end
  end
 end
 error('NO_VALID_OUTSIDE_NAVMESH_POSITION')
end
-- Strict gate point selection, used only after exhausted delivery attempts.
function M.safeGatePoint(building,world,source)
 local town=assert(building:getTown(),'GATE_TOWN_MISSING')
 assert(world and world.navmesh,'GATE_NAVMESH_MISSING')
 assert(town:hasGates()==true,'GATE_NOT_PRESENT')
 for _,dist in ipairs({20,35,50,70})do
  local ok,p=pcall(town.getPositionOutsideTownGates,town,dist)
  if ok and M.valid(p) and (not source or M.distance2D(p,source)>=40) then
   local out=outside(town,p)
   if out and navsafe(world,p) then return p,'outside_gate_distance='..dist end
  end
 end
 error('NO_SAFE_GATE_NAV_POINT')
end
function M.preflight(building,config)
 assert(building and building:isValid(),'BUILDING_INVALID')
 local world=assert(getGameWorld(),'WORLD_MISSING')
 assert(world.gamedata and world.theFactory and world.factionMgr,'ENGINE_API_MISSING')
 local town=assert(building:getTown(),'TOWN_MISSING')
 local template=assert(world.gamedata:getData(config.template,52),'SQUAD_TEMPLATE_MISSING')
 local faction=assert(world.factionMgr:getFactionByStringID(config.faction),'FACTION_MISSING')
 local spawn,method=M.selectOutside(building,world)
 return {world=world,town=town,template=template,faction=faction,spawn=spawn,method=method}
end
function M.spawn(p,building,config)
 -- Native persistent squad, exact FCS leader/squad template. One squad per role.
 -- The 11th supplied parameter (AItarget) MUST be a real KenshiLua.hand.
 -- Alpha.21 passed nil there and every spawn failed with 'bad argument #12'.
 -- Use the parent building handle; target town remains the shop's town.
 return p.world.theFactory:createRandomSquad(
 p.faction,p.spawn,p.town,config.count,building,p.template,
 nil,nil,nil,true,building:getHandle(),p.town,1.0,
 -- The chief remains the only building resident; police patrol is a roaming squad.
 -- KenshiLua SquadType: SQ_RESIDENT=1, SQ_ROAMING=2.
 ((config.shop=='police' and config.role=='patrol')
  and ((SquadType and SquadType.SQ_ROAMING) or 2)
  or ((SquadType and SquadType.SQ_RESIDENT) or 1)),false)
end
-- KenshiLua exposes world.charUpdateListMain as iterable ogre_unordered_set<Character*>.
-- Do not use undocumented ActivePlatoon.characterHandles (lightuserdata).
function M.members(world,platoon,expected)
 local set=world and world.charUpdateListMain
 if not set then return nil,'CHARACTER_SET_UNAVAILABLE' end
 local id=platoon and platoon:getPlatoonStringID()
 if not id or id=='' then return nil,'PLATOON_ID_UNAVAILABLE' end
 local out,seen={},{}
 local ok,err=pcall(function()
  local scanned=0
  for char in pairs(set) do
   scanned=scanned+1
   if scanned>12000 then error('CHARACTER_SCAN_SAFETY_CAP') end
   if char then
    local good,match=pcall(function()
     local ap=char:getPlatoon()
     return ap and ap.me and ap.me:getPlatoonStringID()==id
    end)
    if good and match then
     local key
     local hk,h=pcall(function()return char:getHandle():toString()end)
     if hk and h then key=tostring(h) end
     if not key then key='member-'..tostring(char.squadMemberID or tostring(char)) end
     if not seen[key] then seen[key]=true;out[#out+1]={key=key,char=char} end
    end
   end
  end
 end)
 if not ok then return nil,'SCAN_EXCEPTION '..tostring(err) end
 if #out>expected+2 then return nil,'MEMBER_COUNT_EXCESS '..#out end
 table.sort(out,function(a,b)return a.key<b.key end)
 return out,nil
end
return M
