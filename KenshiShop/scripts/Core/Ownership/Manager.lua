-- KenshiShop alpha.32: early, bounded SHOP ownership handoff.
-- The owning faction is verified before resident/member checks; furniture and NPC AI untouched.
-- Uses a freshly observed building handle and an existing ACTIVE shop-trader platoon.
local Log=require('Diagnostics')
local Transport=require('Core.NPC.Transport')
local TownAudit=require('Core.Ownership.TownAudit')
local ConstructionGate=require('Core.Ownership.ConstructionGate')
local M={}
local Residence=require('Core.NPC.Residence')
local OWNER_POLL_FRAMES=4    -- first safe frame; small bounded interval for active platoon readiness
local OWNER_TIMEOUT_FRAMES=480 -- never spin indefinitely when faction/squad fails to load
local MAX_OWNER_SET_CALLS=3
local ROLE_STEP_FRAMES=65
local MAX_ROLE_CHECKS=3
local MAX_FACTION_SQUADS=300
local MAX_RECOVERY_CYCLES=3
-- Only the four split shop types have a separate 1-NPC owner and 2-NPC guard squad.
-- Police, robotics and single-squad shops retain their original ownership logic.
local SPLIT_SHOPS={bar=true,engineering=true,armour=true,weapons=true}
-- Stable fallback merchant anchors. Alpha.37 additionally probes one active non-merchant NPC
-- of the target faction (NOT a foreign-faction platoon). No NPCs are changed.
local APPROVED_ANCHORS={
 ['300-KenshiShop.mod']=1, ['303-KenshiShop.mod']=1,
 ['305-KenshiShop.mod']=1, ['307-KenshiShop.mod']=1,
 ['309-KenshiShop.mod']=1,
}
local function try(fn,...)
 if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,...)
 if ok then return v end
 return nil
end
local function sid(d)
 if not d then return nil end
 local ok,x=pcall(function()return d.stringID end)
 return ok and x and tostring(x) or nil
end
local function key(b)return b:getHandle():toString() end
local function factionID(f)
 if not f then return 'NONE' end
 return sid(try(f.getData,f)) or 'UNKNOWN'
end
local function platoonID(p)return p and (try(p.getPlatoonStringID,p) or 'UNKNOWN') or 'NONE' end
local function templateID(p)
 if not p then return nil end
 return try(function()return sid(p.squadTemplate)end)
end
local function homeID(p)
 local own=p and try(p.getOwnerships,p)
 return own and try(function()return own._homeBuilding:toString()end) or nil
end
local function resident(b)
 local h=try(function()return b.residentSquad end)
 return h and try(h.getPlatoon,h) or nil
end
local function cpuClock()
 local v=try(function()return os.clock()end)
 return type(v)=='number' and v or nil
end
local function elapsed(s)
 local now=cpuClock()
 return now and s.startedCPU and math.max(0,math.floor((now-s.startedCPU)*1000+0.5)) or -1
end
function M.new(cfg,report)
 assert(cfg.shop and cfg.building and cfg.squads and #cfg.squads>0)
 local ownerSpec
 for _,spec in ipairs(cfg.squads)do if spec.owner then assert(not ownerSpec,'MULTIPLE_OWNERS');ownerSpec=spec end end
 assert(ownerSpec,'OWNER_ROLE_MISSING')
 for _,spec in ipairs(cfg.squads)do assert(type(spec.count)=='number' and spec.count>=1 and spec.count<=12,'EXPECTED_SQUAD_COUNT_REQUIRED '..spec.role)end
 local states={}
 local Public={}
 local function emit(s,event,detail,once)
  if once and s.once[once] then return end
  if once then s.once[once]=true end
  local line='OWN_'..event..' shop='..cfg.shop..' building='..s.key..' '..tostring(detail or '')
  Log.console(line)
  if report then report(line)end
 end
 local function townSnap(s,b,phase,extra)
  TownAudit.snapshot(cfg.shop,b,phase,s.origin,extra,report)
 end
 local function stop(s)
  if s.hook then Events.off(s.hook);s.hook=nil end
 end
 local function building(s)
  local b=try(s.handle.getBuilding,s.handle)
  if not b or try(b.isValid,b)~=true then return nil end
  if sid(try(b.getGameData,b))~=cfg.building then return nil end
  return b
 end
 local function faction(spec)
  local w=getGameWorld()
  return w and w.factionMgr and try(w.factionMgr.getFactionByStringID,w.factionMgr,spec.faction) or nil
 end
 local function locate(s,b,spec)
  local cached=s.groups[spec.role]
  if cached and templateID(cached)==spec.template then
   -- Spawned platoon may not have its home attached until later, but is attested by the factory.
   if s.attested[spec.role] or homeID(cached)==s.key then return cached,'attested' end
  end
  s.groups[spec.role]=nil
  if spec.owner then
   local p=resident(b)
   if p and templateID(p)==spec.template and homeID(p)==s.key then
    s.groups[spec.role]=p;return p,'resident_handle'
   end
  end
  local f=faction(spec)
  if not f then return nil,'FACTION_NOT_READY' end
  for _,method in ipairs({'getActivePlatoons','getUnloadedPlatoons'})do
   local list=try(f[method],f)
   if list then
    local count=try(function()return #list end) or 0
    if count>MAX_FACTION_SQUADS then return nil,'FACTION_SCAN_CAP '..count end
    for i=1,count do
     local p=list[i]
     if p and templateID(p)==spec.template and homeID(p)==s.key then
      s.groups[spec.role]=p;return p,method
     end
    end
   end
  end
  return nil,'SQUAD_NOT_REGISTERED'
 end
 local function readyOwner(s,b)
  local p,source=locate(s,b,ownerSpec)
  if not p then return nil,nil,source end
  local active=try(p.getActivePlatoon,p)
  if not active then return nil,nil,'ACTIVE_PLATOON_NOT_READY' end
  local count=try(active.getSquadSize,active)
  if type(count)~='number' or count~=ownerSpec.count then
   return nil,nil,'ACTIVE_MEMBERS_NOT_READY '..tostring(count)..'/'..ownerSpec.count
  end
  return p,active,source
 end
 -- Faction's OWN, currently active, persistent shop-merchant platoon is the
 -- only allowed temporary anchor. NEVER invent a platoon or use a nil ActivePlatoon.
 -- Not tied to the newly constructed shop; the normal resident is assigned later.
 local function findExistingAnchor(s)
  local f=faction(ownerSpec)
  if not f then return nil,nil,'ANCHOR_FACTION_NOT_READY' end
  local list=try(f.getActivePlatoons,f)
  if not list then return nil,nil,'ANCHOR_LIST_NOT_READY' end
  local n=try(function()return #list end)
  if type(n)~='number' or n>MAX_FACTION_SQUADS then return nil,nil,'ANCHOR_SCAN_CAP' end
  local merchant=nil
  local anyNPC=nil
  for i=1,n do
   local p=list[i]
   local template=templateID(p)
   local ap=try(p.getActivePlatoon,p)
   local members=ap and try(ap.getSquadSize,ap)
   -- This is a real ActivePlatoon observed from owner faction list.
   -- Never borrow from player/foreign factions; no native call with nil AP.
   if p and ap and type(members)=='number' and members>=1 and members<=40 then
    local required=APPROVED_ANCHORS[template]
    if required and members==required and try(p.isPersistentSquad,p)==true
       and homeID(p) and homeID(p)~=s.key then
     if not merchant then merchant={p,ap,'anchor:'..tostring(template)} end
    elseif not required and not anyNPC then
     -- Bounded experiment: one guard/patrol/non-merchant platoon from OUR faction.
     anyNPC={p,ap,'any_npc:'..tostring(template or 'UNNAMED')}
    end
   end
  end
  if anyNPC and not s.anyNPCFailed then
   emit(s,'ANY_NPC_ANCHOR_CANDIDATE','template='..tostring(templateID(anyNPC[1]))
    ..' platoon='..platoonID(anyNPC[1])..' members='..tostring(try(anyNPC[2].getSquadSize,anyNPC[2]))
    ..' faction='..ownerSpec.faction..' test=one_safe_setFaction_call', 'any_anchor_candidate')
   return anyNPC[1],anyNPC[2],anyNPC[3]
  end
  emit(s,'ANY_NPC_ANCHOR_UNAVAILABLE','no_other_active_own_faction_NPC; merchant_fallback=true'
    ..' foreign_faction=NOT_TESTED_SAFETY', 'any_anchor_unavailable')
  if merchant then return merchant[1],merchant[2],merchant[3] end
  return nil,nil,'ANCHOR_NOT_READY'
 end
 local function finishTiming(s,b,mode,source,memberCount)
  local fromBuild=s.constructionCPU and cpuClock()
  local buildMS=(fromBuild and math.max(0,math.floor((fromBuild-s.constructionCPU)*1000+0.5))) or -1
  local info='origin='..s.origin..' mode='..mode..' source='..tostring(source)
   ..' owner='..factionID(try(b.getFaction,b))..' playerOwned='..tostring(try(b.isThePlayer,b))
   ..' frames='..s.frames..' cpu_ms='..elapsed(s)..' native_calls='..s.nativeCalls
   ..' active_members='..tostring(memberCount or 'n/a')..' since_construction_cpu_ms='..buildMS
  emit(s,'TRANSFER_TIMING',info,'timing')
  s.ownerOK=true;s.ownerFrame=s.frames
  s.stage='OWNER_OK';s.nextRole=s.frames+ROLE_STEP_FRAMES
  if cfg.shop=='bar' then
   -- AFTER parent ownership was restored: bar-only, bounded 50/50 furniture repair.
   local ok,restorer=pcall(require,'Core.Bar.Building.FurnitureRestore')
   if ok then
    local accepted,queued,detail=pcall(restorer.request,b,'OWNER_READY_'..s.origin)
    emit(s,'BAR_SPLIT_QUEUE',accepted and tostring(detail) or ('ERROR '..tostring(queued)),
     'bar_split_'..s.origin)
   end
  else
   -- The owner may be assigned before construction reaches completion.
   -- Do not run interior scans until the building itself is finished.
   local interiorReady,why=ConstructionGate.ready(b)
   if interiorReady then
    local ok,restorer=pcall(require,'Core.Ownership.NPCFurnitureRestore')
    if ok then
     local invoked,queued,detail=pcall(restorer.request,b,'OWNER_READY_'..s.origin)
     emit(s,'NPC_FURN_QUEUE',invoked and tostring(detail) or ('ERROR '..tostring(queued)),
      'npc_furn_'..s.origin)
    else
     emit(s,'NPC_FURN_QUEUE','MODULE_UNAVAILABLE '..tostring(restorer),'npc_furn_error')
    end
   else
    emit(s,'NPC_FURN_WAIT','reason='..tostring(why)..' no_interior_mutations; post_create_will_recheck',
     'npc_furn_wait_'..s.origin)
   end
  end
 end
 local function ownerProbe(s,b)
  local current=factionID(try(b.getFaction,b))
  local playerOwned=try(b.isThePlayer,b)
  if current==ownerSpec.faction and playerOwned==false then
   s.everNPCOwned=true
   finishTiming(s,b,'ALREADY_OWNED','saved_or_prior_transfer')
   return true
  end
  local constructed,constructionWhy=ConstructionGate.ownerReady(b)
  if not constructed then
   if s.waitReason~=constructionWhy then
    s.waitReason=constructionWhy
    emit(s,'CONSTRUCTION_WAIT','origin='..s.origin..' '..tostring(constructionWhy)..' '..ConstructionGate.details(b)..' no_owner_change','construction_'..tostring(constructionWhy))
   end
   return false
  end
  if s.nativeCalls>=MAX_OWNER_SET_CALLS then
   emit(s,'TRANSFER_FAILED','reason=SET_ATTEMPT_LIMIT owner='..current..' calls='..s.nativeCalls,'owner_limit')
   s.stage='OWNER_FAILED';stop(s);return false
  end
  local p,ap,why=readyOwner(s,b)
  local borrowed=false
  local ownReason=why
  if not p then
   p,ap,why=findExistingAnchor(s)
   borrowed=p~=nil
   if not p then why=tostring(ownReason)..' + '..tostring(why) end
  end
  if not p then
   if s.waitReason~=why then
    s.waitReason=why
    emit(s,'TRANSFER_WAIT','origin='..s.origin..' reason='..tostring(why)..' frames='..s.frames,'wait_'..tostring(why))
   end
   return false
  end
  local f=faction(ownerSpec)
  if not f then
   if s.waitReason~='FACTION_NOT_READY' then
    s.waitReason='FACTION_NOT_READY'
    emit(s,'TRANSFER_WAIT','origin='..s.origin..' reason=FACTION_NOT_READY frames='..s.frames,'wait_faction')
   end
   return false
  end
  local count=try(ap.getSquadSize,ap)
  -- No unsafe change inside the native construction/deserialisation callback:
  -- onSpawned / onLoaded only arms the first-frame transfer.
  s.nativeCalls=s.nativeCalls+1
  emit(s,'MATERIAL_GATE','origin='..s.origin..' '..tostring(constructionWhy)..' '..ConstructionGate.details(b),'material_gate')
  townSnap(s,b,'BEFORE_TRANSFER','via='..(borrowed and 'EXISTING_ANCHOR' or 'OWN_SQUAD')
    ..' platoon='..platoonID(p))
  if borrowed then
   emit(s,'ANCHOR_SELECTED','temporary=true platoon='..platoonID(p)
    ..' home='..tostring(homeID(p))..' template='..tostring(templateID(p))
    ..' no_spawn; reassignment_to_store_trader_on_ready', 'anchor_selected')
  end
  emit(s,'TRANSFER_BEGIN','origin='..s.origin..' owner_before='..current
   ..' playerOwned='..tostring(playerOwned)..' frame='..s.frames
   ..' cpu_ms='..elapsed(s)..' native_attempt='..s.nativeCalls,'transfer_begin_'..s.nativeCalls)
  s.transferInProgress=true
  local ok,err=pcall(b.setFaction,b,f,ap)
  s.transferInProgress=false
  local after=factionID(try(b.getFaction,b))
  local afterPlayer=try(b.isThePlayer,b)
  if ok and after==ownerSpec.faction and afterPlayer==false then
   s.everNPCOwned=true
   townSnap(s,b,'AFTER_TRANSFER','via='..(borrowed and 'EXISTING_ANCHOR' or 'OWN_SQUAD'))
   emit(s,'TRANSFER_OK','via='..(borrowed and 'EXISTING_ANCHOR' or 'OWN_SQUAD')
    ..' origin='..s.origin..' before='..current..' after='..after
    ..' native_attempt='..s.nativeCalls..' frame='..s.frames..' cpu_ms='..elapsed(s)
    ..' platoon='..platoonID(p),'transfer_ok')
   if borrowed and tostring(why):find('any_npc:',1,true) then
    emit(s,'ANY_NPC_ANCHOR_RESULT','status=PASS template='..tostring(templateID(p))
     ..' platoon='..platoonID(p)..' faction='..ownerSpec.faction
     ..' parent_owner='..after,'any_anchor_result')
   end
   finishTiming(s,b,borrowed and 'ANCHOR_APPLIED' or 'APPLIED',why,count)
   return true
  end
  townSnap(s,b,'TRANSFER_ERROR','via='..(borrowed and 'EXISTING_ANCHOR' or 'OWN_SQUAD'))
  if borrowed and tostring(why):find('any_npc:',1,true) then
   emit(s,'ANY_NPC_ANCHOR_RESULT','status=FAIL template='..tostring(templateID(p))
    ..' parent_owner='..after..' playerOwned='..tostring(afterPlayer)
    ..' no_more_any_npc_probes_this_event', 'any_anchor_result')
   s.anyNPCFailed=true
  end
  emit(s,'TRANSFER_ERROR','attempt='..s.nativeCalls..' after='..after
   ..' playerOwned='..tostring(afterPlayer)..' error='..tostring(err),'transfer_error_'..s.nativeCalls)
  if s.nativeCalls>=MAX_OWNER_SET_CALLS then
   s.stage='OWNER_FAILED';emit(s,'TRANSFER_FAILED','native_attempts='..s.nativeCalls,'owner_failed');stop(s)
  end
  return false
 end
 -- All assigned staff are residents, including the city's permanent patrol.
 local function roleSquadType(spec)
  return (SquadType and SquadType.SQ_RESIDENT) or 1
 end
 local function ensureRole(s,b,spec)
  local p,source=locate(s,b,spec)
  if not p then return false,source end
  local owns=try(p.getOwnerships,p)
  if not owns then return false,'PLATOON_OWNERSHIPS_NOT_READY' end
  local f=faction(spec)
  if not f then return false,'FACTION_NOT_READY' end
  if try(p.isPersistentSquad,p)~=true then
   local ok,err=pcall(p.setPersistentSquad,p,true)
   if not ok or try(p.isPersistentSquad,p)~=true then return false,'PERSISTENT_SET_FAIL '..tostring(err) end
  end
  local town=try(b.getTown,b)
  if not town then return false,'TOWN_NOT_READY' end
  if cfg.shop=='police' and spec.role=='patrol' then
   if try(p.getSquadType,p)~=roleSquadType(spec) then
    local ok=pcall(p.setSquadType,p,roleSquadType(spec));if not ok then return false,'PATROL_TYPE_NOT_READY'end
   end
  end
  local h=homeID(p)
  if h~=s.key then
   local ok,err=pcall(owns.setHomeBuilding,owns,b:getHandle(),roleSquadType(spec))
   if not ok or homeID(p)~=s.key then return false,'HOME_SET_FAIL '..tostring(err)end
  end
  if not try(function()return owns._homeTown end) then
   local ok,err=pcall(owns.setHomeTown,owns,town,roleSquadType(spec))
   if not ok then return false,'HOME_TOWN_SET_FAIL '..tostring(err)end
  end
  local active=try(p.getActivePlatoon,p)
  if not active then return false,'ACTIVE_NOT_READY' end
  if not s.residentsVerified[spec.role] then
   local n=try(active.getSquadSize,active)
   if n~=spec.count then return false,'MEMBERS_COUNT_NOT_READY '..tostring(n)..'/'..spec.count end
   local members,err=Transport.members(getGameWorld(),p,n)
   if not members or err or #members~=n then return false,'MEMBERS_NOT_READY '..tostring(err) end
   for _,m in ipairs(members)do
    local o=try(m.char.getOwnerships,m.char)
    if not o then return false,'MEMBER_OWNERSHIPS_NOT_READY '..m.key end
    local home=try(function()return o._homeBuilding:toString()end)
    if home~=s.key then
     local ok,err2=pcall(o.setHomeBuilding,o,b:getHandle(),roleSquadType(spec))
     if not ok then return false,'MEMBER_HOME_SET_FAILED '..m.key..' '..tostring(err2)end
    end
    if not try(function()return o._homeTown end) then pcall(o.setHomeTown,o,town,roleSquadType(spec))end
   end
   s.residentsVerified[spec.role]=true
   emit(s,'MEMBERS_HOME_OK','role='..spec.role..' members='..n..'/'..n,'members_'..spec.role)
  end
  if spec.owner and not SPLIT_SHOPS[cfg.shop] then
   -- Original single-platoon and police path is intentionally unchanged.
   local current=resident(b)
   if not current or (platoonID(current)~=platoonID(p) and cfg.shop~='police') then
    local ok=pcall(b.setResidentSquad,b,p)
    local nextResident=resident(b)
    if not ok or not nextResident or platoonID(nextResident)~=platoonID(p) then
     emit(s,'RESIDENT_WARNING','expected='..platoonID(p)..' actual='..platoonID(nextResident),'resident_warning')
    end
   end
  end
  return true,'source='..source..' persistent_home_verified'
 end
 -- Creating the *guard* platoon can silently replace native residentSquad.
 -- Rebind only after both real groups are present and individually home-verified.
 -- The native setter may be deferred/rejected: never claim success without readback.
 local function verifySplitResident(s,b)
  local trader,why=locate(s,b,ownerSpec)
  if not trader then return false,'OWNER_TRADER_NOT_FOUND '..tostring(why) end
  local guardSpec
  for _,spec in ipairs(cfg.squads) do if spec.role=='guard' then guardSpec=spec end end
  if not guardSpec then return false,'GUARD_SPEC_MISSING' end
  local guard,reason=locate(s,b,guardSpec)
  if not guard then return false,'GUARD_NOT_FOUND '..tostring(reason) end
  local id=platoonID(trader)
  local present=platoonID(resident(b))
  if present==id then
   emit(s,'SHOP_RESIDENT_VERIFIED','trader='..id..' guard='..platoonID(guard)..' native_resident='..present,'shop_resident_verified')
   return true,'TRADER_IS_NATIVE_RESIDENT'
  end
  -- Separate budgets: squad discovery might become ready late. Never call
  -- the native rebind more than three times across the complete audit.
  if (s.residentSetCalls or 0)>=3 then return false,'TRADER_RESIDENT_REBIND_LIMIT' end
  s.residentSetCalls=(s.residentSetCalls or 0)+1
  local ok,err=Residence.bind(b,trader,guard)
  local after=platoonID(resident(b))
  emit(s,'SHOP_RESIDENT_REBIND','attempt='..s.residentSetCalls..'/3 expected='..id
   ..' guard='..platoonID(guard)..' before='..present..' after='..after
   ..' call='..tostring(ok)..' error='..(ok and 'NONE' or tostring(err)),
   'shop_rebind_'..s.residentSetCalls)
  if after==id then
   emit(s,'SHOP_RESIDENT_VERIFIED','trader='..id..' guard='..platoonID(guard)..' native_resident='..after,'shop_resident_verified')
   return true,'TRADER_NATIVE_RESIDENT_REBOUND'
  end
  if s.residentSetCalls>=3 then
   emit(s,'SHOP_RESIDENT_UNVERIFIED','expected='..id..' actual='..after
    ..' guards_and_trader_home_independently_verified; no_further_mutation','resident_unverified')
  end
  return false,'TRADER_NATIVE_RESIDENT_NOT_YET_VERIFIED '..after
 end
 local function roleStep(s,b)
  if s.frames<s.nextRole then return end
  s.roleChecks=s.roleChecks+1;s.nextRole=s.frames+ROLE_STEP_FRAMES
  local all=true
  for _,spec in ipairs(cfg.squads)do
   if not s.rolePassed[spec.role] then
    local ok,yes,why=pcall(ensureRole,s,b,spec)
    if ok and yes then
     s.rolePassed[spec.role]=true
     emit(s,'ROLE_OK','role='..spec.role..' '..tostring(why)..' frame='..s.frames,'role_ok_'..spec.role)
    else
     all=false
     emit(s,'ROLE_WAIT','role='..spec.role..' attempt='..s.roleChecks..' reason='..tostring(ok and why or yes),'role_wait_'..spec.role..'_'..s.roleChecks)
    end
   end
  end
  if all and SPLIT_SHOPS[cfg.shop] then
   local good,reason=verifySplitResident(s,b)
   if not good then
    all=false
    emit(s,'SHOP_RESIDENT_WAIT','check='..s.roleChecks..'/3 reason='..reason,'shop_resident_wait_'..s.roleChecks)
   end
  end
  if all and cfg.shop=='police' then
   -- Both exact squads are individually verified persistent + assigned to THIS home.
   -- Native Building::residentSquad supports only one pointer. Do not overwrite it
   -- three times when it belongs to the other valid police squad.
   local chief=locate(s,b,ownerSpec)
   local patrolSpec=nil
   for _,spec in ipairs(cfg.squads)do if spec.role=='patrol' then patrolSpec=spec end end
   local patrol=patrolSpec and locate(s,b,patrolSpec)
   local current=resident(b)
   local currentID=platoonID(current)
   if not chief or not patrol then
    all=false
    emit(s,'POLICE_HOME_WAIT','chief='..platoonID(chief)..' patrol='..platoonID(patrol)
     ..' reason=SQUAD_NOT_READY','police_home_wait_'..s.roleChecks)
   elseif currentID~=platoonID(chief) and currentID~=platoonID(patrol) then
    -- Only attempt to repair when native resident is an unexpected third squad.
    s.residentSetCalls=(s.residentSetCalls or 0)+1
    if s.residentSetCalls<=3 then
     local ok,err=pcall(b.setResidentSquad,b,chief)
     currentID=platoonID(resident(b))
     emit(s,'POLICE_RESIDENT_REPAIR','attempt='..s.residentSetCalls..'/3 called='..tostring(ok)
      ..' error='..tostring(ok and 'NONE' or err)..' actual='..currentID,'police_resident_repair_'..s.residentSetCalls)
    end
    if currentID~=platoonID(chief) and currentID~=platoonID(patrol) then all=false end
   end
   if all then
    emit(s,'POLICE_HOME_ASSOCIATION_OK','chief='..platoonID(chief)..' patrol='..platoonID(patrol)
     ..' native_resident='..currentID..' shared_home_verified=2/2 AI_DEFERRED','police_home_ok')
   end
  end
  if all then
   townSnap(s,b,'ROLE_COMPLETE','status=PASS')
   s.stage='PASS';emit(s,'AUDIT_PASS','ownership_and_resident_roles_confirmed; furniture_not_rechecked','role_done');stop(s)
  elseif s.roleChecks>=(SPLIT_SHOPS[cfg.shop] and MAX_ROLE_CHECKS+3 or MAX_ROLE_CHECKS) then
   townSnap(s,b,'ROLE_COMPLETE','status=INCOMPLETE')
   s.stage='OWNER_OK_ROLE_INCOMPLETE'
   emit(s,'ROLE_AUDIT_INCOMPLETE','owner_correct=true attempts='..s.roleChecks..' next_event_retry; furniture_not_rechecked','role_incomplete')
   stop(s)
  end
 end
 local function tick(s)
  s.frames=s.frames+1
  local b=building(s)
  if not b then
   s.stage='UNLOADED';emit(s,'BUILDING_UNLOADED','no_native_mutation; stopped','unloaded');stop(s);return
  end
  if s.frames==1 then townSnap(s,b,'NEXT_FRAME','frame=1') end
  if not s.ownerOK then
   if s.frames==1 or s.frames%OWNER_POLL_FRAMES==0 then ownerProbe(s,b)end
   if not s.ownerOK and s.frames>=OWNER_TIMEOUT_FRAMES then
    s.stage='OWNER_NOT_READY'
    emit(s,'TRANSFER_TIMEOUT','origin='..s.origin..' frames='..s.frames..' cpu_ms='..elapsed(s)
     ..' reason='..tostring(s.waitReason)..' no_respawn; next_load_or_spawn_event','owner_timeout')
    stop(s)
   end
  elseif s.stage~='OWNER_FAILED' then
   -- The engine may silently re-assign the shop while finishing a zone load.
   -- Verify native ownership during this short bounded role audit, independently
   -- of Building::_NV_setFaction notifications.
   if s.frames%OWNER_POLL_FRAMES==0 then
    local actual=factionID(try(b.getFaction,b))
    local player=try(b.isThePlayer,b)
    if actual~=ownerSpec.faction or player~=false then
     s.recoveries=s.recoveries+1
     emit(s,'OWNER_REVERTED','origin='..s.origin..' actual='..actual
      ..' playerOwned='..tostring(player)..' frame='..s.frames
      ..' recovery='..s.recoveries..'/'..MAX_RECOVERY_CYCLES,
      'reverted_'..s.recoveries)
     if s.recoveries>MAX_RECOVERY_CYCLES then
      s.stage='OWNER_REVERTED_LIMIT';stop(s);return
     end
     s.ownerOK=false;s.stage='OWNER_RECOVERY';s.rolePassed={};s.roleChecks=0
     return
    end
   end
   roleStep(s,b)
  end
 end
 local function begin(b,reason,platoon,role)
  if not b then return nil end
  local k=key(b)
  local prior=states[k]
  -- Duplicate load events can appear before all native data is ready.
  -- Invalidate old role/squad caches and never carry active pointers across loads.
  if prior then stop(prior) end
  local s={key=k,handle=b:getHandle(),origin=reason,startedCPU=cpuClock(),frames=0,
   stage=reason,ownerOK=false,nativeCalls=0,groups={},attested={},once={},rolePassed={},
   residentsVerified={},roleChecks=0,waitReason=nil,everNPCOwned=prior and prior.everNPCOwned or false,
   recoveries=prior and prior.recoveries or 0,cycle=(prior and prior.cycle or 0)+1}
  if platoon and role then s.groups[role]=platoon;s.attested[role]=reason=='SPAWN' end
  if reason=='CONSTRUCTION' then s.constructionCPU=s.startedCPU
  elseif prior and prior.constructionCPU then s.constructionCPU=prior.constructionCPU end
  states[k]=s
  if reason=='LOAD' then townSnap(s,b,'LOAD_CALLBACK','read_only=true') end
  if reason=='CONSTRUCTION' then townSnap(s,b,'CONSTRUCTION_CALLBACK','read_only=true') end
  emit(s,'TRANSFER_TRIGGER','origin='..reason..' owner_now='..factionID(try(b.getFaction,b))
   ..' playerOwned='..tostring(try(b.isThePlayer,b))..' cpu_clock='..tostring(s.startedCPU), 'trigger')
  local ok,id=pcall(Events.on,'MyGUI::Gui::eventFrameStart',function()
   local success,err=pcall(tick,s)
   if not success then
    s.stage='ERROR';emit(s,'AUDIT_EXCEPTION','reason='..tostring(err),'exception');stop(s)
   end
  end)
  if ok and id then s.hook=id else s.stage='HOOK_FAILED';emit(s,'HOOK_FAIL',tostring(id),'hook_failed')end
  return s
 end
 function Public.onConstruction(b)
  -- Construction callback only ARMS a first-safe-frame transfer. Never mutate
  -- building from native constructor/construction events.
  local s=begin(b,'CONSTRUCTION')
  emit(s,'CONSTRUCTION_OBSERVED','owner_now='..factionID(try(b.getFaction,b))
   ..' first_safe_frame_tries_existing_active_anchor; own_squad_fallback', 'construction')
 end
 function Public.spawned(role,b,p)
  for _,spec in ipairs(cfg.squads)do
   if spec.role==role then
    local previous=states[key(b)]
    local s=begin(b,'SPAWN',p,role)
    if previous and previous.constructionCPU then
     s.constructionCPU=previous.constructionCPU
     emit(s,'SQUAD_READY','role='..role..' construction_event_saved=true; resident_rebind_when_ready','squad_'..role)
    end
    return true
   end
  end
  return false
 end
 function Public.restored(role,b,p)
  for _,spec in ipairs(cfg.squads)do
   if spec.role==role and p and templateID(p)==spec.template and homeID(p)==key(b) then
    local s=states[key(b)]
    if s and s.hook then
     s.groups[role]=p;s.attested[role]=false
     emit(s,'SQUAD_READY','role='..role..' origin=LOAD; native_saved_squad','squad_'..role)
    else begin(b,'RESTORED',p,role)end
    return true
   end
  end
  return false
 end
 function Public.arrived(role,b,p)
  local s=states[key(b)]
  if s and s.hook then
   s.groups[role]=p
  else begin(b,'ARRIVAL',p,role)end
  return true
 end
 function Public.onLoaded(b)
  -- Always discard previous active platoons, even if the last session's frame hook remains.
  begin(b,'LOAD')
 end
 function Public.onFactionChanged(b)
  local s=states[key(b)]
  if not s or s.transferInProgress then return false end
  local current=factionID(try(b.getFaction,b))
  if current==ownerSpec.faction and try(b.isThePlayer,b)==false then return false end
  if not s.everNPCOwned or s.hook then return false end
  if s.recoveries>=MAX_RECOVERY_CYCLES then
   emit(s,'RECOVERY_LIMIT','actual='..current..' max='..MAX_RECOVERY_CYCLES,'recovery_limit')
   return false
  end
  local count=s.recoveries+1
  local next=begin(b,'FACTION_CHANGE')
  next.recoveries=count
  return true
 end
 -- Runs on the EXISTING trader monitor (10-minute game-clock heartbeat),
 -- never creates another frame listener. Native writes are capped at three
 -- per building/session INCLUDING the initial ownership audit.
 function Public.monitorResident(b,now)
  if not SPLIT_SHOPS[cfg.shop] then return false,'NOT_SPLIT_SHOP' end
  local k=key(b)
  local s=states[k]
  if not s or not s.ownerOK or not s.rolePassed.trader or not s.rolePassed.guard then
   return false,'ROLES_NOT_VERIFIED'
  end
  if try(b.isValid,b)~=true or sid(try(b.getGameData,b))~=cfg.building then
   return false,'BUILDING_UNAVAILABLE'
  end
  if factionID(try(b.getFaction,b))~=ownerSpec.faction or try(b.isThePlayer,b)~=false then
   return false,'FACTION_UNVERIFIED'
  end
  if type(now)~='number' or now~=now then return false,'CLOCK_INVALID' end
  local watch=s.residentWatch or {nextAt=0,previous=nil,drift=false,limited=false}
  s.residentWatch=watch
  if watch.previous and now<watch.previous then watch.nextAt=now end
  watch.previous=now
  if now<watch.nextAt then return false,'RATE_LIMIT' end
  watch.nextAt=now+30 -- 30 in-game minutes; no new timer, no per-frame mutation
  local trader,reason=locate(s,b,ownerSpec)
  if not trader or homeID(trader)~=k or try(trader.isPersistentSquad,trader)~=true then
   return false,'TRADER_NOT_HOME_VERIFIED '..tostring(reason)
  end
  local tactive=try(trader.getActivePlatoon,trader)
  if not tactive or try(tactive.getSquadSize,tactive)~=ownerSpec.count then
   return false,'TRADER_MEMBERS_UNAVAILABLE'
  end
  local guardSpec
  for _,spec in ipairs(cfg.squads)do if spec.role=='guard' then guardSpec=spec;break end end
  local guard,reason2=guardSpec and locate(s,b,guardSpec)
  if not guard or homeID(guard)~=k or try(guard.isPersistentSquad,guard)~=true then
   return false,'GUARD_NOT_HOME_VERIFIED '..tostring(reason2)
  end
  local gactive=try(guard.getActivePlatoon,guard)
  if not gactive or try(gactive.getSquadSize,gactive)~=guardSpec.count then
   return false,'GUARD_MEMBERS_UNAVAILABLE'
  end
  local want=platoonID(trader)
  local current=platoonID(resident(b))
  if current==want then
   if watch.drift then
    emit(s,'SHOP_RESIDENT_WATCH_RECOVERED','resident='..current..' total_native_writes='..tostring(s.residentSetCalls or 0))
   elseif not watch.okOnce then
    emit(s,'SHOP_RESIDENT_WATCH_OK','resident='..current..' interval_game_minutes=30')
   end
   watch.drift=false;watch.okOnce=true
   return true,'TRADER_STILL_RESIDENT'
  end
  if not watch.drift then
   emit(s,'SHOP_RESIDENT_DRIFT','expected='..want..' actual='..current..' guard='..platoonID(guard))
  end
  watch.drift=true
  if (s.residentSetCalls or 0)>=3 then
   if not watch.limited then
    emit(s,'SHOP_RESIDENT_WATCH_LIMIT','expected='..want..' actual='..current..' max_native_writes=3 no_more_changes')
    watch.limited=true
   end
   return false,'WRITE_BUDGET_EXHAUSTED'
  end
  s.residentSetCalls=(s.residentSetCalls or 0)+1
  local ok,err=Residence.bind(b,trader,guard)
  local after=platoonID(resident(b))
  emit(s,'SHOP_RESIDENT_WATCH_REBIND','write='..s.residentSetCalls..'/3 expected='..want
    ..' before='..current..' after='..after..' call='..tostring(ok)
    ..' error='..(ok and 'NONE' or tostring(err)))
  if after==want then
   watch.drift=false;watch.okOnce=true
   emit(s,'SHOP_RESIDENT_WATCH_RECOVERED','resident='..after..' total_native_writes='..s.residentSetCalls)
   return true,'RECOVERED'
  end
  return false,'REBIND_UNVERIFIED'
 end
 function Public.audit(b)
  local k=key(b);local s=states[k]
  local parts={'OWN_AUDIT shop='..cfg.shop..' building='..k,
   'building_owner='..factionID(try(b.getFaction,b))..' playerOwned='..tostring(try(b.isThePlayer,b)),
   'resident_platoon='..platoonID(resident(b)),
   'protection='..(s and s.stage or 'NOT_OBSERVED')}
  if s then
   parts[#parts+1]='origin='..s.origin..' frames='..s.frames..' cpu_ms='..elapsed(s)
    ..' native_calls='..s.nativeCalls..' owner_ok='..tostring(s.ownerOK)
  end
  for _,spec in ipairs(cfg.squads)do
   local p,why=locate(s or {key=k,groups={},attested={}},b,spec)
   parts[#parts+1]=spec.role..'='..(p and platoonID(p)..' template='..tostring(templateID(p))
    ..' persistent='..tostring(try(p.isPersistentSquad,p))..' home='..tostring(homeID(p))
    ..' active='..tostring(try(p.getActivePlatoon,p)~=nil)..' source='..tostring(why) or ('MISSING '..tostring(why)))
  end
  return table.concat(parts,' | ')
 end
 function Public.resetSession()
  for _,s in pairs(states)do stop(s)end
  states={}
 end
 return Public
end
return M
