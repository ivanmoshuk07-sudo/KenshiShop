-- Paid replacements allocate one actor, never a replacement squad. Preflight
-- is read-only; a receipt owns every post-allocation retry.
local Config=require('Core.Police.Services.Config')
local Store=require('Core.Police.Services.Store')
local Live=require('Core.NPC.LiveState')
local Origin=require('Core.NPC.OriginTown')
local Transport=require('Core.NPC.Transport')
local Home=require('Core.NPC.HomeAssignment')
local Appearance=require('Core.NPC.Appearance')
local Supplies=require('Core.NPC.Supplies')
local NoSever=require('Core.NPC.NoSever')
local M={}
local function field(o,k)return Origin.field(o,k)end
local function call(o,k,...)
 local fn=field(o,k)
 if type(fn)~='function' then return nil,false end
 local ok,value=pcall(fn,o,...)
 return value,ok
end
local function id(o)return Origin.id(o)end
local function pid(p)
 local value=Live.call(p,'getPlatoonStringID')
 return value and value~='' and tostring(value) or nil
end
local function factionID(o)return field(Live.call(Live.call(o,'getFaction'),'getData'),'stringID')end
local function ownerID(c)return pid(field(Live.call(c,'getPlatoon'),'me'))end
local function raceID(c)return field(field(Live.call(c,'getRace'),'data'),'stringID')end
local function requireMethod(o,name)assert(type(field(o,name))=='function','METHOD_UNAVAILABLE '..name)end
local function roster(record)
 local rows,known={},0
 for _,r in pairs(Store.get().roster)do
  if type(r)=='table' and r.pid==record.pid then
   assert(type(r.id)=='string' and not rows[r.id],'ROSTER_ID_INVALID')
   rows[r.id]=r;known=known+1
  end
 end
 assert(rows[record.id] and rows[record.id].dead==true,'DEATH_NOT_CONFIRMED')
 return rows,known
end
local function missingPlatoon(faction,record,rows,known,cfg)
 -- Both native lists must be readable. In particular, an unloaded squad is
 -- an existing squad even when every member in our last observation died.
 for _,method in ipairs({'getActivePlatoons','getUnloadedPlatoons'})do
  local list,ok=call(faction,method)
  assert(ok and list,'FACTION_ROSTER_UNAVAILABLE '..method)
  assert(#list<=12000,'FACTION_ROSTER_LIMIT')
  for i=1,#list do assert(pid(list[i])~=record.pid,'EXISTING_PLATOON_REQUIRES_ACTIVE_LOOKUP')end
 end
 assert(known>=cfg.count,'PLATOON_ROSTER_INCOMPLETE')
 for _,r in pairs(rows)do assert(r.dead==true,'PLATOON_DEATH_UNCONFIRMED')end
 requireMethod(faction,'createNewEmptyActivePlatoon')
end
local function inspectMembers(world,p,ap,rows,cfg,restore)
 local size=Live.call(ap,'getSquadSize')
 assert(type(size)=='number' and size>=0 and size%1==0,'PLATOON_COUNT_UNAVAILABLE')
 local members,why=Transport.members(world,p,cfg.count)
 assert(members and not why and #members==size,'PLATOON_SCAN_INCOMPLETE '..tostring(why))
 local dead={}
 for _,m in ipairs(members)do
  local r=rows[m.key]
  if r and r.dead==true then
   assert(Live.call(m.char,'isDead')==true,'MEMBER_DEATH_UNCONFIRMED '..m.key)
   dead[#dead+1]=m
  end
 end
 assert(restore and size-#dead<=cfg.count or size-#dead<cfg.count,'PLATOON_HAS_NO_VACANCY')
 if #dead>0 then requireMethod(ap,'removeObject')end
 requireMethod(ap,'setSquadLeader')
 return dead
end
local function prepare(record,building,platoon,restoreID)
 local ok,plan=pcall(function()
  assert(type(record)=='table' and type(record.id)=='string' and type(record.pid)=='string','RECORD_INVALID')
  assert(record.dead==true and (not record.replacedBy or record.replacedBy==restoreID),'DEATH_NOT_AVAILABLE')
  assert(type(record.charTemplate)=='string' and type(record.race)=='string','MEMBER_TEMPLATE_UNAVAILABLE')
  local cfg=assert(Config.copy(record.squadTemplate),'SQUAD_TEMPLATE_UNSUPPORTED')
  assert(building and Live.call(building,'isValid')==true,'BUILDING_INVALID')
  assert(id(building)==record.building,'BUILDING_ID_MISMATCH')
  assert(factionID(building)==Config.faction,'BUILDING_FACTION_MISMATCH')
  local town=assert(Live.call(building,'getTown'),'TOWN_UNAVAILABLE')
  assert(id(town)==record.town,'TOWN_ID_MISMATCH')
  assert(Live.call(Live.call(town,'getFaction'),'isThePlayer')==true,'SERVICE_TOWN_NOT_PLAYER')
  local world=assert(getGameWorld(),'WORLD_UNAVAILABLE')
  local faction=assert(Live.call(world.factionMgr,'getFactionByStringID',Config.faction),'FACTION_UNAVAILABLE')
  assert(field(Live.call(faction,'getData'),'stringID')==Config.faction,'FACTION_ID_MISMATCH')
  if not restoreID then requireMethod(world.theFactory,'createRandomCharacter')end
  local template=assert(Live.call(world.gamedata,'getData',cfg.template,(itemType and itemType.SQUAD_TEMPLATE)or 52),'SQUAD_DATA_UNAVAILABLE')
  local charTemplate=assert(Live.call(world.gamedata,'getData',record.charTemplate,(itemType and itemType.CHARACTER)or 1),'CHARACTER_DATA_UNAVAILABLE')
  local raceData=assert(Live.call(world.gamedata,'getData',record.race,(itemType and itemType.RACE)or 7),'RACE_DATA_UNAVAILABLE')
  assert(field(charTemplate,'stringID')==record.charTemplate,'CHARACTER_DATA_MISMATCH')
  assert(field(raceData,'stringID')==record.race,'RACE_DATA_MISMATCH')
  local rows,known=roster(record)
  local ap,dead
  if platoon then
   assert(restoreID or pid(platoon)==record.pid,'PLATOON_ID_MISMATCH')
   assert(factionID(platoon)==Config.faction,'PLATOON_FACTION_MISMATCH')
   assert(field(field(platoon,'squadTemplate'),'stringID')==cfg.template,'PLATOON_TEMPLATE_MISMATCH')
   ap=assert(Live.call(platoon,'getActivePlatoon'),'PLATOON_UNLOADED')
   assert(pid(field(ap,'me'))==pid(platoon),'ACTIVE_PLATOON_ID_MISMATCH')
   dead=inspectMembers(world,platoon,ap,rows,cfg,restoreID~=nil)
  else
   assert(not restoreID,'RESTORE_PLATOON_UNAVAILABLE')
   missingPlatoon(faction,record,rows,known,cfg)
  end
  local origin,originWhy=Origin.select(faction,Live.call(building,'getPosition'))
  assert(origin,'NPC_ORIGIN_UNAVAILABLE '..tostring(originWhy))
  local spawn,method
  if not restoreID then
   spawn,method=Transport.selectOutside(building,world)
   assert(Transport.valid(spawn),'SPAWN_POSITION_INVALID')
   assert(Live.call(town,'withinBordersRange',spawn,1.04)==false,'SPAWN_NOT_CONFIRMED_OUTSIDE')
   assert(Live.call(world.navmesh,'getPositionValid',spawn)==true,'SPAWN_NAVMESH_INVALID')
  end
  return {record=record,building=building,cfg=cfg,world=world,faction=faction,template=template,
   charTemplate=charTemplate,raceData=raceData,spawn=spawn,method=method,origin=origin,
   platoon=platoon,ap=ap,pid=pid(platoon),oldPID=record.pid,newPlatoon=not platoon,dead=dead or {}}
 end)
 if not ok then return nil,tostring(plan)end
 return plan
end
function M.prepare(record,building,platoon)return prepare(record,building,platoon)end
local function readback(plan,receipt)
 local ap=Live.call(receipt.platoon,'getActivePlatoon')
 if not ap or not receipt.pid or pid(field(ap,'me'))~=receipt.pid then return false,'NEW_PLATOON_INITIALIZING'end
 plan.ap=ap
 local c=receipt.char
 if not c then
  local h=Live.call(receipt.root,'getHandle')
  c=h and Live.call(h,'getCharacter')
  if not c then return false,'NEW_CHARACTER_INITIALIZING'end
  receipt.char=c
 end
 local member=id(c)
 if not member then return false,'NEW_CHARACTER_HANDLE_INITIALIZING'end
 receipt.member=member
 local owner,readOK=call(c,'getPlatoon')
 if not readOK then return false,'NEW_CHARACTER_OWNER_INITIALIZING'end
 if not owner then
  -- Usually the factory already attached the character. An explicit known
  -- empty owner permits one attach; no blind retry can add it twice.
  if not receipt.attachAttempted then
   local fn=field(ap,'addActiveObject')
   if type(fn)~='function' then return false,'NEW_CHARACTER_ATTACH_UNAVAILABLE'end
   receipt.attachAttempted=true
   local ok,accepted=pcall(fn,ap,c)
   if not ok or accepted~=true then return false,'NEW_CHARACTER_ATTACH_UNVERIFIED'end
  end
  owner=Live.call(c,'getPlatoon')
 end
 if pid(field(owner,'me'))~=receipt.pid then return false,'NEW_CHARACTER_OWNER_UNVERIFIED'end
 if factionID(c)~=Config.faction then return false,'NEW_CHARACTER_FACTION_UNVERIFIED'end
 -- Keep the old platoon populated during native allocation. Removing its
 -- last corpse first could let native empty-squad cleanup retire the owner.
 for _,m in ipairs(plan.dead)do
  if ownerID(m.char)==plan.oldPID then
   if Live.call(m.char,'isDead')~=true then return false,'MEMBER_DEATH_CHANGED '..m.key end
   local removed,removeOK=call(ap,'removeObject',m.char)
   if not removeOK or removed~=true or ownerID(m.char)==plan.oldPID then
    return false,'DEAD_MEMBER_DETACH_UNVERIFIED '..m.key
   end
  end
 end
 local lead=Live.call(ap,'getSquadLeader')
 if not lead or Live.call(lead,'isDead')==true then
  local _,setOK=call(ap,'setSquadLeader',c)
  if not setOK or id(Live.call(ap,'getSquadLeader'))~=member then return false,'NEW_LEADER_INITIALIZING'end
 end
 return true
end
function M.spawn(plan)
 if type(plan)~='table' then return nil,'PLAN_INVALID',false end
 if plan.receipt then return plan.receipt end
 if plan.attempted then return nil,plan.error or 'ALLOCATION_ALREADY_ATTEMPTED',true end
 local ok,result=pcall(function()
  assert(plan.record.dead==true and not plan.record.replacedBy,'DEATH_NOT_AVAILABLE')
  assert(Live.call(plan.building,'isValid')==true and factionID(plan.building)==Config.faction,'BUILDING_CHANGED')
  if plan.platoon then
   assert(Live.call(plan.platoon,'getActivePlatoon')==plan.ap,'PLATOON_NO_LONGER_ACTIVE')
   local rows=roster(plan.record)
   plan.dead=inspectMembers(plan.world,plan.platoon,plan.ap,rows,plan.cfg)
  else
   local rows,known=roster(plan.record)
   missingPlatoon(plan.faction,plan.record,rows,known,plan.cfg)
   plan.attempted=true
   plan.platoon=assert(plan.faction:createNewEmptyActivePlatoon(plan.template,true,plan.spawn),'EMPTY_PLATOON_ALLOCATION_FAILED')
   plan.pid=assert(pid(plan.platoon),'NEW_PLATOON_ID_UNAVAILABLE')
   plan.ap=assert(Live.call(plan.platoon,'getActivePlatoon'),'NEW_PLATOON_NOT_ACTIVE')
  end
  -- Mark before entering native allocation: an exception or nil result may
  -- still have created an actor and must never be refunded/retried blindly.
  plan.attempted=true
  local root=assert(plan.world.theFactory:createRandomCharacter(plan.faction,plan.spawn,plan.ap,plan.charTemplate,plan.building,1),'CHARACTER_ALLOCATION_UNVERIFIED')
  local receipt={root=root,platoon=plan.platoon,pid=assert(pid(plan.platoon),'PLATOON_ID_UNAVAILABLE'),pending=true,newPlatoon=plan.newPlatoon}
  plan.receipt=receipt
  local ready,why=readback(plan,receipt)
  receipt.pending=not ready;receipt.reason=why
  return receipt
 end)
 if not ok then plan.error=tostring(result);return nil,plan.error,plan.attempted==true end
 return result
end
function M.restore(record,building,platoon,newMemberID,stages)
 if type(newMemberID)~='string' or newMemberID=='' then return nil,'RESTORE_MEMBER_INVALID'end
 local plan,why=prepare(record,building,platoon,newMemberID)
 if not plan then return nil,why end
 local members,scanWhy=Transport.members(plan.world,platoon,plan.cfg.count)
 if not members or scanWhy then return nil,'RESTORE_MEMBER_SCAN '..tostring(scanWhy)end
 local c
 for _,m in ipairs(members)do if m.key==newMemberID then c=m.char;break end end
 if not c then return nil,'RESTORE_MEMBER_NOT_LOADED'end
 if ownerID(c)~=pid(platoon) or factionID(c)~=Config.faction then return nil,'RESTORE_MEMBER_OWNER_MISMATCH'end
 if field(Live.call(c,'getGameData'),'stringID')~=record.charTemplate then return nil,'RESTORE_MEMBER_TEMPLATE_MISMATCH'end
 if Live.call(c,'isDead')==true then return nil,'RESTORE_MEMBER_DEAD'end
 plan.attempted=true
 plan.newPlatoon=pid(platoon)~=record.pid
 local completed={}
 for key,done in pairs(stages or {})do
  -- Protection belongs to a native MedicalSystem pointer. Its lifetime
  -- changed on load even though appearance/setup completion is durable.
  if done==true and key~='nosever' then completed[key]=true end
 end
 local receipt={root=c,char=c,member=newMemberID,platoon=platoon,pid=pid(platoon),
  stages=completed,pending=true,newPlatoon=plan.newPlatoon}
 plan.receipt=receipt
 return plan,receipt
end
local function stage(receipt,name,fn)
 if receipt.stages[name]then return true end
 local ok,done,why=pcall(fn)
 if not ok or done~=true then return false,name..' '..tostring(ok and why or done)end
 receipt.stages[name]=true;return true
end
function M.finish(plan,receipt)
 if type(plan)~='table' or not receipt or receipt~=plan.receipt then return false,'RECEIPT_INVALID'end
 if receipt.done then return true end
 local ok,ready,why=pcall(readback,plan,receipt)
 if not ok or not ready then receipt.pending=true;return false,tostring(ok and why or ready)end
 local c,key=receipt.char,receipt.member
 local lead=Live.call(plan.ap,'getSquadLeader')
 local state=receipt.state or {cfg=plan.cfg,key=id(plan.building),handle=Live.call(plan.building,'getHandle'),
  building=plan.building,platoon=receipt.platoon,work={setup={},leader=id(lead),tries=0}}
 receipt.state=state;receipt.stages=receipt.stages or {}
 state.work.leader=id(lead)
 if receipt.stages.setup then state.work.setup[key]=true;receipt.setupDone=true end
 local ms={{key=key,char=c}}
 local stages={
  {'race',function()
   if raceID(c)~=plan.record.race then c:setRace(plan.raceData)end
   return raceID(c)==plan.record.race,'RACE_NOT_APPLIED'
  end},
  {'name',function()
   if type(plan.record.name)~='string' or plan.record.name=='' then return true end
   if Live.call(c,'getName')~=plan.record.name then c:setName(plan.record.name)end
   return Live.call(c,'getName')==plan.record.name,'NAME_NOT_APPLIED'
  end},
  {'setup',function()c:setupPlatoonAI();state.work.setup[key]=true;receipt.setupDone=true;return true end},
  {'home',function()
   local bb=Live.call(c,'getBlackboard')
   if not bb then return false,'BLACKBOARD_UNAVAILABLE'end
   return Home.ensure(state,ms,bb)
  end},
  {'appearance',function()return Appearance.apply(c,plan.world,plan.cfg.shop)end},
  {'supplies',function()return Supplies.sync(c,plan.world)end},
  {'nosever',function()
   -- setRace precedes native MedicalSystem registration. Never register a
   -- vanilla race accidentally inherited from the character-only factory.
   if raceID(c)~=plan.record.race then return false,'RACE_CHANGED'end
   NoSever.tick(state,ms)
   if NoSever.isProtectedRace(plan.record.race)then
    return state.noSever and state.noSever[key]and state.noSever[key].active==true,'PROTECTION_NOT_READY'
   end
   return true
  end},
 }
 for _,entry in ipairs(stages)do
  local done,reason=stage(receipt,entry[1],entry[2])
  if not done then receipt.pending=true;receipt.reason=reason;return false,reason end
 end
 receipt.pending=nil;receipt.reason=nil;receipt.done=true
 return true
end
return M
