-- Native FCS retreat sends squads to their own hometown, including while
-- unloaded. Lua detaches the service home and verifies departure.
local Config=require('Core.Police.Services.Config')
local Roster=require('Core.Police.Services.Roster')
local Store=require('Core.Police.Services.Store')
local Live=require('Core.NPC.LiveState')
local Origin=require('Core.NPC.OriginTown')
local Transport=require('Core.NPC.Transport')
local Activate=require('Core.NPC.NativeActivation')
local Posts=require('Core.NPC.PostJobs')

local M={}
local RETREAT='11303-KenshiShop.mod'
local CHECK_MINUTES=5
local MISSING_MINUTES=10

local function dataID(data)return Origin.field(data,'stringID')end
local function factionID(p)return dataID(Live.call(Live.call(p,'getFaction'),'getData'))end
local function template(p)return dataID(Origin.field(p,'squadTemplate'))end
local function home(p)return Origin.field(Live.call(p,'getOwnerships'),'_homeBuilding')end
local function pid(p)return Live.call(p,'getPlatoonStringID')end
local function retreatData(world)
 return Live.call(Origin.field(world,'gamedata'),'getData',RETREAT,72)
end

local function serviceTown(ctx)
 local town=ctx.townObject or Live.call(ctx.building,'getTown')
 if Origin.id(town)==ctx.town and Live.call(town,'isValid')==true
   and Live.call(Live.call(town,'getFaction'),'isThePlayer')==true then return town end
end

function M.plan(ctx,buildings)
 if not serviceTown(ctx) then return nil,'EVACUATION_TOWN_UNAVAILABLE' end
 if not retreatData(getGameWorld()) then return nil,'NATIVE_RETREAT_PACKAGE_UNAVAILABLE' end
 local groups,complete,why=Roster.platoons()
 if not complete then return nil,why end
 local squads,known={},{}
 local saved=Store.get()
 for _,row in pairs(saved.roster)do
  if row.town==ctx.town and row.pid and buildings[row.building] and not row.dead then known[row.pid]=true end
 end
 for id,row in pairs(saved.patrols)do
  if row.town==ctx.town and buildings[row.building] then known[id]=true end
 end
 for _,group in ipairs(groups)do
  for _,p in ipairs(group)do
   local key=Origin.handleID(home(p))
   local sid=template(p)
   local id=pid(p)
   if buildings[key] and Config.templates[sid] then
    if factionID(p)~=Config.faction or type(id)~='string' or id=='' then
     return nil,'EVACUATION_PLATOON_UNVERIFIED'
    end
    if Origin.field(p,'isDead')~=true and not Origin.npc(Origin.field(Live.call(p,'getOwnerships'),'_homeTown')) then
     return nil,'EVACUATION_NATIVE_HOMETOWN_UNAVAILABLE '..id
    end
    squads[id]={building=key,template=sid,handle=Origin.id(p)}
   elseif Config.templates[sid] and factionID(p)==Config.faction and Origin.field(p,'isDead')~=true then
    local nativeTown=Origin.id(Origin.field(Live.call(p,'getBlackboard'),'targetTown'))
    if nativeTown==ctx.town or (known[id] and not key) then
     return nil,'EVACUATION_SERVICE_HOME_LOADING '..tostring(id)
    end
   end
  end
 end
 local chiefPlatoon=Origin.field(Live.call(ctx.chief,'getPlatoon'),'me')
 local chief=squads[pid(chiefPlatoon)]
 if not chief or chief.building~=ctx.key or Config.templates[chief.template].role~='chief' then
  return nil,'EVACUATION_CHIEF_PLATOON_UNVERIFIED'
 end
 return squads
end

local function members(w,p,cfg)
 local ap=Live.call(p,'getActivePlatoon')
 if not ap then return nil end
 local count=Live.call(ap,'getSquadSize')
 local list,why=Transport.members(w,p,cfg.count)
 if not list or #list~=count then return nil,why or 'EVACUATION_ACTIVE_ROSTER_INCOMPLETE' end
 for _,m in ipairs(list)do
  if factionID(m.char)~=Config.faction or Live.call(m.char,'isPlayerCharacter')~=false then
   return nil,'EVACUATION_MEMBER_FACTION_CHANGED'
  end
 end
 return list
end

local function canDetach(ms)
 for _,m in ipairs(ms or {})do
  if Live.call(m.char,'isDead')~=true then
   local halted,why=Live.halted(m.char)
   if halted then return false,why end
   local orders=Live.call(m.char,'getOrdersReciever')
   if type(Live.call(orders,'hasOrders'))~='boolean' then return false,'EVACUATION_MEMBER_ORDERS_UNAVAILABLE' end
   local job=Live.call(Live.call(orders,'getCurrentGoal'),'key')
   if job==57 or job==58 or job==106 or job==148 then return false,'EVACUATION_MEMBER_HELPING_WOUNDED' end
  end
 end
 return true
end

local function outside(town,object)
 local pos=Live.call(object,'getPosition')
 return Transport.valid(pos) and (pos.x~=0 or pos.y~=0 or pos.z~=0)
  and Live.call(town,'withinBordersRange',pos,1.04)==false
end

local function clearHandle(owner,field,expected,write)
 local handle=assert(owner[field],'EVACUATION_HOME_HANDLE_UNAVAILABLE')
 if Origin.handleID(handle)==expected then
  handle:setNull() -- KenshiLua exposes a value copy, so write it back.
  if write then write(handle) else owner[field]=handle end
  assert(Live.call(owner[field],'isNull')==true,'EVACUATION_HOME_CLEAR_UNVERIFIED')
 end
end

local function packageID(package)return dataID(Origin.field(package,'packageData'))end

local function leave(w,town,p,row,state,unloaded)
 local cfg=Config.templates[row.template]
 if not cfg or template(p)~=row.template or factionID(p)~=Config.faction then
  return false,'EVACUATION_PLATOON_CHANGED'
 end
 local own=Live.call(p,'getOwnerships')
 local h=Origin.field(own,'_homeBuilding')
 local building=Origin.handleID(h)
 if not h or (building and building~=row.building) then return false,'EVACUATION_SERVICE_HOME_CHANGED' end
 local ms,why=members(w,p,cfg)
 if why or (not ms and not unloaded) then return false,why or 'EVACUATION_PLATOON_LOADING' end
 local dead=Origin.field(p,'isDead')==true
 local bb=Live.call(p,'getBlackboard')
 local package=Live.call(bb,'getCurrentPackage')
 local origin=Origin.field(own,'_homeTown')
 local originID=Origin.id(origin)
 local alreadyRetreating=packageID(package)==RETREAT
 local targetBound=alreadyRetreating and Origin.handleID(Origin.field(package,'missionTown'))==originID
   and Origin.id(Origin.field(bb,'targetTown'))==originID
 if not dead and not Origin.npc(origin) then return false,'EVACUATION_NATIVE_HOMETOWN_UNAVAILABLE' end
 if not dead and not alreadyRetreating then
  if Live.call(bb,'hasContractJob')~=false then return false,'EVACUATION_NATIVE_CONTRACT_ACTIVE' end
  local safe,reason=canDetach(ms)
  if not safe then return false,reason end
 end
 -- Do not keep reinstalling a package if the engine rejects or replaces it.
 -- Verification still runs, and a reload creates a fresh bounded attempt.
 if not dead and not alreadyRetreating and (state.attempts or 0)>=3 then
  return false,'EVACUATION_NATIVE_RETREAT_RETRY_LIMIT'
 end
 local ok,problem=pcall(function()
  local kind=assert(p:getSquadType(),'EVACUATION_SQUAD_TYPE_UNAVAILABLE')
  for _,m in ipairs(ms or {})do
   if Live.call(m.char,'isDead')~=true then
    if not alreadyRetreating then
     -- The confirmed evacuation supersedes any old delivery order to
     -- this exact NPC. Remove a tagged shift post, if one is present.
     local orders=m.char:getOrdersReciever()
     if orders:hasOrders() then
      orders:clearOrders()
      assert(not orders:hasOrders(),'EVACUATION_DELIVERY_ORDER_CLEAR_FAILED')
     end
     local _,post=Posts.find(m.char)
     if Posts.ours(post) then
      local cleared,reason=Posts.clear(m.char)
      assert(cleared,reason)
     end
    end
    local member=assert(m.char:getOwnerships(),'EVACUATION_MEMBER_OWNERSHIPS_UNAVAILABLE')
    local previous=Origin.id(member._homeTown)
    local broadcast=assert(m.char:getStateBroadcast(),'EVACUATION_MEMBER_STATE_UNAVAILABLE')
    clearHandle(broadcast,'homeBuilding',row.building)
    clearHandle(member,'_homeBuilding',row.building,function(empty)member:setHomeBuilding(empty,kind)end)
    assert(Origin.id(member._homeTown)==previous,'EVACUATION_MEMBER_HOMETOWN_CHANGED')
   end
  end
  clearHandle(own,'_homeBuilding',row.building,function(empty)own:setHomeBuilding(empty,kind)end)
  assert(Origin.id(own._homeTown)==originID,'EVACUATION_NATIVE_HOMETOWN_CHANGED')
  if p.canRefresh==true then p.canRefresh=false end
  if p.regenerates==true then p.regenerates=false end
  if dead then return end
  if not alreadyRetreating then
   local data=assert(retreatData(w),'NATIVE_RETREAT_PACKAGE_UNAVAILABLE')
   state.attempts=(state.attempts or 0)+1
   bb:replaceAIPackage(data)
   package=bb:getCurrentPackage()
   assert(packageID(package)==RETREAT,'EVACUATION_NATIVE_RETREAT_UNVERIFIED')
  end
  if not targetBound then
   package.missionTown=origin:getHandle()
   bb.targetTown=origin
   assert(Origin.handleID(package.missionTown)==originID and Origin.id(bb.targetTown)==originID,
    'EVACUATION_RETREAT_TARGET_UNVERIFIED')
   if ms then state.activation={} end
  end
  if ms and state.activation then
   local living={}
   for _,m in ipairs(ms)do if Live.call(m.char,'isDead')==false then living[#living+1]=m end end
   local active,reason=Activate.ensure(state.activation,living)
   assert(active,reason)
   state.activation=nil
  end
 end)
 if not ok then return false,tostring(problem) end
 if dead then return true end
 if not ms then return outside(town,p),'EVACUATION_UNLOADED_SQUAD_EN_ROUTE' end
 for _,m in ipairs(ms)do
  if Live.call(m.char,'isDead')~=true and not outside(town,m.char) then
   return false,'EVACUATION_SQUAD_EN_ROUTE'
  end
 end
 return true
end

function M.step(ctx,squads,progress,now)
 local town=serviceTown(ctx)
 if not town then return false,'EVACUATION_TOWN_UNAVAILABLE' end
 if progress.last and now>=progress.last and now-progress.last<CHECK_MINUTES then
  return false,progress.wait
 end
 progress.last=now
 progress.squads=progress.squads or {}
 local groups,complete,why=Roster.platoons()
 if not complete then progress.wait=why;return false,why end
 local targets={}
 for list,group in ipairs(groups)do
  for _,p in ipairs(group)do
   local id=pid(p)
   if squads[id] and not targets[id] then targets[id]={platoon=p,unloaded=list==2} end
  end
 end
 local world=getGameWorld()
 local waiting,pending=nil,0
 for id,row in pairs(squads)do
  local state=progress.squads[id] or {};progress.squads[id]=state
  local target=targets[id]
  if target then
   state.missingAt=nil
   local done,reason=leave(world,town,target.platoon,row,state,target.unloaded)
   if not done then pending=pending+1;waiting=reason end
  else
   -- A transient empty roster at game load is not an evacuation result.
   if not state.missingAt or state.missingAt>now then state.missingAt=now end
   if now-state.missingAt<MISSING_MINUTES then pending=pending+1;waiting='EVACUATION_NATIVE_ROSTER_SETTLING' end
  end
 end
 progress.wait=waiting
 return pending==0,waiting
end

return M
