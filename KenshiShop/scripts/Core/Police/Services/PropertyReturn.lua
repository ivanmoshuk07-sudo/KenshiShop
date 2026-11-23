-- A confirmed departure returns ownership through Building::setFaction.
-- Only stable native handles go in the saved plan. Every retry resolves and
-- validates them before using a building pointer on the game thread.
local Config=require('Core.Police.Services.Config')
local Live=require('Core.NPC.LiveState')
local Ownership=require('Core.Ownership.Registry')
local Retirement=require('Core.Ownership.Retirement')
local Layouts=require('Layouts')
local Transform=require('Transform')
local Log=require('Diagnostics')
local M={}
local MAX_OBJECTS=4000
local MAX_PLAYER_SQUADS=300
local function field(o,name)
 local ok,v=pcall(function()return o[name]end)
 if ok then return v end
end
local function invoke(o,name,...)
 local fn=field(o,name)
 if type(fn)~='function' then return false end
 return pcall(fn,o,...)
end
local call=Live.call
local function id(h)
 if h and call(h,'isNull')~=true then return call(h,'toString')end
end
local function key(o)return id(call(o,'getHandle'))end
local function ownerID(f)return field(call(f,'getData'),'stringID')end
local function owner(b)return ownerID(call(b,'getFaction'))end
local function template(b)return field(call(b,'getGameData'),'stringID')end
local function townID(b)return id(call(b,'getTownHandle')) or key(call(b,'getTown'))end
local function resolve(tower,wanted)
 -- getHandle returns a value copy, never the live Building member.
 local h=call(tower,'getHandle')
 if invoke(h,'fromString',wanted) and id(h)==wanted then
  local b=call(h,'getBuilding')
  if call(b,'isValid')==true and key(b)==wanted then return b end
 end
end
local function scope(ctx)
 local tower=ctx.building
 if call(tower,'isValid')~=true or template(tower)~=Config.tower then return nil,'TOWER_UNLOADED'end
 local town=call(tower,'getTown')
 if key(town)~=ctx.town then return nil,'TOWN_NOT_VERIFIED'end
 local faction=call(town,'getFaction')
 if call(faction,'isThePlayer')~=true then return nil,'TOWN_NOT_PLAYER_OWNED'end
 local playerID=ownerID(faction)
 if type(playerID)~='string' or playerID==Config.faction then return nil,'PLAYER_FACTION_NOT_VERIFIED'end
 return {tower=tower,town=town,playerFaction=faction,playerID=playerID}
end
local function readBuildings(o,method,element,...)
 if not lektor or type(lektor.new)~='function' then return nil,'LEKTOR_UNAVAILABLE'end
 local ok,list=pcall(lektor.new,element)
 if not ok or not list then return nil,'BUILDING_LIST_UNAVAILABLE'end
 if not invoke(o,method,list,...) then return nil,'BUILDING_LIST_UNAVAILABLE_'..method end
 if #list>MAX_OBJECTS then return nil,'BUILDING_LIST_LIMIT'end
 return list
end
local function keep(pool,b)
 if call(b,'isValid')~=true then return end
 local k=key(b)
 if k then pool[k]=b end
end
local function collect(faction,town,pool)
 local own=field(faction,'factionOwnerships')
 local direct,why=readBuildings(own,'getOwnedBuildingPtrs','Building*',town)
 if not direct then return false,why end
 for i=1,#direct do keep(pool,direct[i])end
 -- Native faction pointers can omit interior objects. Resolve ownership
 -- handles as well and use exact parent/town membership below.
 local hands,err=readBuildings(own,'getOwnedBuildingsH','hand')
 if not hands then return false,err end
 for i=1,#hands do keep(pool,call(hands[i],'getBuilding'))end
 return true
end
local function modFaction()
 local world=getGameWorld()
 local faction=call(field(world,'factionMgr'),'getFactionByStringID',Config.faction)
 if ownerID(faction)==Config.faction then return faction end
end
function M.staffedShopKeys(ctx)
 local s,why=scope(ctx)
 if not s then return nil,why end
 local npc=modFaction()
 if not npc then return nil,'MOD_FACTION_UNAVAILABLE'end
 local owned,err=readBuildings(field(npc,'factionOwnerships'),'getOwnedBuildingPtrs','Building*',s.town)
 if not owned then return nil,err end
 local result={}
 for i=1,#owned do
  local b=owned[i]
  if call(b,'isValid')~=true then return nil,'SCOPED_BUILDING_UNAVAILABLE'end
  local layout=Layouts[template(b)]
  if layout then
   local k=key(b)
   if not k or townID(b)~=ctx.town or owner(b)~=Config.faction then return nil,'SCOPED_SHOP_UNVERIFIED'end
   if not Retirement.retired(k) then result[k]=layout.name end
  end
 end
 if not result[key(s.tower)] then return nil,'TOWER_NOT_IN_SCOPED_OWNERSHIP'end
 return result
end
local function collectLayoutOutside(parent,candidates,result,playerID,town)
 -- Exterior fixtures can have neither a furniture parent nor a town handle.
 -- Match just the authored exterior slots by native template and transform.
 local layout=Layouts[template(parent)]
 for _,item in ipairs(layout.objects)do
  if item.outside then
   local ok,point=pcall(Transform.world,call(parent,'getPosition'),call(parent,'getOrientation'),call(parent,'getScale'),item)
   if not ok then return false,'EXTERIOR_LAYOUT_UNAVAILABLE'end
   local match
   for _,b in ipairs(candidates[item.id] or {})do
    local p=call(b,'getPosition')
    local nativeTown=townID(b)
    local current=owner(b)
    if p and (not nativeTown or nativeTown==town) and (current==playerID or current==Config.faction)
     and Transform.error(point,p)<=0.10 then
     if match then return false,'EXTERIOR_FIXTURE_AMBIGUOUS'end
     match=key(b)
    end
   end
   if match then result[match]=true end
  end
 end
 return true
end
function M.prepare(ctx,expectedBuildings)
 local s,why=scope(ctx)
 if not s then return nil,why end
 local npc=modFaction()
 if not npc then return nil,'MOD_FACTION_UNAVAILABLE'end
 local pool={}
 for _,f in ipairs({npc,s.playerFaction})do
  local ok,err=collect(f,s.town,pool)
  if not ok then return nil,err end
 end
 keep(pool,s.tower)
 for k in pairs(expectedBuildings or {})do
  if not pool[k] then keep(pool,resolve(s.tower,k))end
  if not pool[k] or not Layouts[template(pool[k])] or townID(pool[k])~=ctx.town then
   return nil,'EXPECTED_SHOP_UNAVAILABLE '..k
  end
 end
 local result={buildings={},property={}}
 local children,detached={},{}
 for k,b in pairs(pool)do
  local current=owner(b)
  local sid=template(b)
  local parent=key(call(b,'furnitureParentBuilding'))
  if parent then
   if not children[parent] then children[parent]={}end
   children[parent][k]=true
  elseif sid then
   if not detached[sid] then detached[sid]={}end
   detached[sid][#detached[sid]+1]=b
  end
  if townID(b)==ctx.town and not Retirement.retired(k) then
   local layout=Layouts[sid]
   if layout then
    if current~=Config.faction and current~=s.playerID then return nil,'SHOP_OWNER_CHANGED '..k end
    result.buildings[k]=true
    result.property[k]=true
   elseif current==Config.faction and not parent then
    result.property[k]=true
   end
  end
 end
 if not result.buildings[key(s.tower)] then return nil,'TOWER_NOT_IN_SCOPE'end
 for k in pairs(result.buildings)do
  local parent=pool[k]
  local mounted,err=readBuildings(parent,'getMountedBuildings','Building*')
  if not mounted then return nil,err end
  local attached=children[k] or {}
  for i=1,#mounted do
   local b=mounted[i]
   keep(pool,b)
   local childID=key(b)
   if childID and childID~=k then attached[childID]=true end
  end
  local n=0
  for childID in pairs(attached)do
   local b=pool[childID]
   if not b then return nil,'INTERIOR_CHILD_UNAVAILABLE '..childID end
   n=n+1
   local current=owner(b)
   if current~=s.playerID and current~=Config.faction then return nil,'INTERIOR_OWNER_CHANGED '..childID end
   result.property[childID]=true
  end
  -- Detect partial zone loading instead of confirming an incomplete return.
  local inside=call(parent,'getNumInternalBuildings')
  if type(inside)~='number' or n<inside then return nil,'INTERIOR_NOT_READY '..k end
  local ok,outsideWhy=collectLayoutOutside(parent,detached,result.property,s.playerID,ctx.town)
  if not ok then return nil,outsideWhy..' '..k end
 end
 local size=0
 for _ in pairs(result.property)do size=size+1 end
 if size>MAX_OBJECTS then return nil,'PROPERTY_PLAN_LIMIT'end
 return result
end
local function active(ctx,s)
 local player=ctx.player
 if call(player,'isPlayerCharacter')==true and owner(player)==s.playerID then
  local ap=call(player,'getPlatoon')
  if ap and (call(ap,'getSquadSize') or 0)>0 then return ap end
 end
 local list=call(s.playerFaction,'getActivePlatoons')
 if not list or #list>MAX_PLAYER_SQUADS then return nil end
 for i=1,#list do
  local ap=call(list[i],'getActivePlatoon')
  if ap and (call(ap,'getSquadSize') or 0)>0 then return ap end
 end
end
local function retireProtection(b,k)
 local layout=Layouts[template(b)]
 if layout then Ownership.retire(layout.name,k) end
end
local function clearResident(b,k,squads,residentHandles)
 local h=field(b,'residentSquad')
 local p=call(h,'getPlatoon')
 local row=squads and squads[call(p,'getPlatoonStringID')]
 local handleID=id(h)
 if p then
  local faction=ownerID(call(p,'getFaction'))
  if not faction then return false end
  if faction~=Config.faction then return true end
  if not row or row.building~=k or field(field(p,'squadTemplate'),'stringID')~=row.template then return false end
 elseif handleID and residentHandles[handleID]~=k then
  return false
 end
 if handleID then
  -- KenshiLua's setResidentSquad requires a non-null Platoon*. Use a
  -- value-type empty hand through the exposed resident property instead.
  if not invoke(h,'setNull') then return false end
  b.residentSquad=h
  if call(field(b,'residentSquad'),'isNull')~=true then return false end
 end
 local tmpl=field(field(b,'residentSquadTemplate'),'stringID')
 if Config.templates[tmpl] then
  b.residentSquadTemplate=nil
  if field(b,'residentSquadTemplate')~=nil then return false end
 end
 return true
end
function M.apply(ctx,buildings,property,squads)
 local s,why=scope(ctx)
 if not s then return false,why end
 if type(buildings)~='table' or type(property)~='table' or not buildings[key(s.tower)] then
  return false,'PROPERTY_PLAN_UNAVAILABLE'
 end
 local objects,ordered={},{}
 for k in pairs(property)do
  local b=resolve(s.tower,k)
  if not b then return false,'PROPERTY_UNLOADED '..k end
  local nativeTown=townID(b)
  local parent=key(call(b,'furnitureParentBuilding'))
  if buildings[k] and (not Layouts[template(b)] or nativeTown~=ctx.town or not Retirement.retired(k))
   or (not buildings[k] and ((nativeTown and nativeTown~=ctx.town) or (parent and not property[parent]))) then
   return false,'PROPERTY_SCOPE_CHANGED '..k
  end
  local current=owner(b)
  if current~=Config.faction and current~=s.playerID then return false,'PROPERTY_OWNER_CHANGED '..k end
  if buildings[k] and current~=s.playerID then
   local resident=call(field(b,'residentSquad'),'getPlatoon')
   if resident and ownerID(call(resident,'getFaction'))~=Config.faction then
    return false,'FOREIGN_RESIDENT_PRESERVED '..k
   end
  end
  objects[k]=b
  ordered[#ordered+1]=k
 end
 for k in pairs(buildings)do if not objects[k] then return false,'SHOP_MISSING_FROM_PLAN '..k end end
 local ap=active(ctx,s)
 if not ap then return false,'PLAYER_ACTIVE_PLATOON_UNAVAILABLE'end
 -- Change parent buildings first. Any native cascade to a child already
 -- requested in the plan is harmless; the child's owner is read again below.
 table.sort(ordered,function(a,b)
  if buildings[a]~=buildings[b] then return buildings[a]==true end
  return a<b
 end)
 local residentHandles={}
 for _,row in pairs(squads or {})do
  if row.handle then residentHandles[row.handle]=row.building end
 end
 for k in pairs(buildings)do retireProtection(objects[k],k)end
 local changed=0
 for _,k in ipairs(ordered)do
  local b=objects[k]
  local current=owner(b)
  if current~=Config.faction and current~=s.playerID then return false,'PROPERTY_OWNER_CHANGED '..k end
  if current~=s.playerID or call(b,'isThePlayer')~=true then
   local ok=invoke(b,'setFaction',s.playerFaction,ap)
   if not ok or owner(b)~=s.playerID or call(b,'isThePlayer')~=true then
    return false,'PROPERTY_RETURN_UNVERIFIED '..k
   end
   call(b,'notifyChange')
   changed=changed+1
  end
  if buildings[k] and not clearResident(b,k,squads,residentHandles) then return false,'RESIDENT_RELEASE_UNVERIFIED '..k end
 end
 for k,b in pairs(objects)do
  if owner(b)~=s.playerID or call(b,'isThePlayer')~=true then return false,'PROPERTY_READBACK_FAILED '..k end
 end
 Log.console('NPC_CHIEF_PROPERTY_RETURN town='..ctx.town..' verified='..#ordered..' changed='..changed)
 return true
end
return M
