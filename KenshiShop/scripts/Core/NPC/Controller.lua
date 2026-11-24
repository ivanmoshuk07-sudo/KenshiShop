-- Alpha.81: bounded delivery, then native role AI, vendor setup and kit refills.
local Log=require('Diagnostics')
local T=require('Core.NPC.Transport')
local Live=require('Core.NPC.LiveState')
local Existing=require('Core.NPC.ExistingSquads')
local Appearance=require('Core.NPC.Appearance')
local SupplyQueue=require('Core.NPC.SupplyQueue')
local MonitorQueue=require('Core.NPC.MonitorQueue')
local Work=require('Core.NPC.RoleAI')
local Catalog=require('Core.NPC.Catalog')
local Duty=require('Core.NPC.Duty')
local Residence=require('Core.NPC.Residence')
local NoSever=require('Core.NPC.NoSever')
local ChiefStore=require('Core.Police.Services.Store')
local M={}
local function retiredBuilding(key)
 return ChiefStore.evacuationCorrupt() or ChiefStore.retiredBuilding(key)
end
local function retiredPlatoon(pid)
 return ChiefStore.retiredPlatoon(pid)
end
local ARRIVAL_RADIUS=26
local POLICE_ARRIVAL_RADIUS=80
local function radius(s) return s.cfg.shop=='police' and POLICE_ARRIVAL_RADIUS or ARRIVAL_RADIUS end
local PROGRESS=6
local ORDER_TEST_MINUTES=1
local LOAD_TEST_MINUTES=1
local AUDIT_MINUTES=10
local TELEPORT_WAIT_MINUTES=2
local GATE_VERIFY_MINUTES=0.25
local MAX_ORDERS=3
local function emit(s,event,details,key)
 key=key or event
 if s.once[key] then return end
 s.once[key]=true
 Log.console('NPC_'..event..' shop='..s.cfg.shop..' squad='..s.cfg.role..' building='..s.key..' '..tostring(details or ''))
end
local function building(s)
 local b=Live.call(s.handle,'getBuilding')
 if not b or Live.call(b,'isValid')~=true
  or Live.call(Live.call(b,'getHandle'),'toString')~=s.key then return nil end
 return b
end
local function platoonRef(p,id)
 local pid=id or Live.call(p,'getPlatoonStringID')
 local h=Live.call(p,'getHandle')
 local key=Live.call(h,'toString')
 if type(pid)~='string' or pid=='' or type(key)~='string' or key==''
  or Live.call(h,'isNull')==true then return nil end
 return {pid=pid,handle=h,key=key}
end
local function platoon(s)
 local ref=s.platoonRef
 local p=ref and Live.call(ref.handle,'getPlatoon')
 if p and Live.call(Live.call(p,'getHandle'),'toString')==ref.key then return p end
end
local function fatal(s,reason)
 s.phase='FAILED';s.nextCheck=Live.clock()+AUDIT_MINUTES
 emit(s,'DELIVERY_FAIL','reason='..tostring(reason)..' no_respawn','fatal_'..tostring(reason))
 SupplyQueue.cancel(s)
 if s.hook then MonitorQueue.remove(s.hook);s.hook=nil end
end
-- Original auto-refill for first-aid and robotics kits. Bounded failures per NPC.
local function supplyAudit(s,ms,now)
 SupplyQueue.enqueue(s,ms,now)
end
local function squadMembers(s,world)
 local ap=Live.call(s.platoon,'getActivePlatoon')
 if not ap then return nil,nil,'SQUAD_UNLOADED' end
 local count=Live.call(ap,'getSquadSize')
 local nativeSaved=false
 if s.saved then
  local lead=Live.call(ap,'getSquadLeader')
  local bb=lead and Live.call(lead,'getBlackboard')
  nativeSaved=Work.isWorkingPackage(s.cfg,Live.call(bb,'getCurrentAIPackageName'))
 end
 local fullRequired=s.phase~='DELIVERED' and not nativeSaved and not (s.saved and s.cfg.serviceHired)
 if type(count)~='number' or count<1 or count>s.cfg.count or (fullRequired and count~=s.cfg.count) then
  return nil,nil,'COUNT_MISMATCH '..tostring(count)..'/'..s.cfg.count end
 local ms,err=T.members(world,s.platoon,s.cfg.count)
 if ms and #ms~=count then ms,err=T.members(world,s.platoon,s.cfg.count,true)end
 if not ms or err or #ms~=count then
  return nil,nil,'MEMBER_SCAN_INCOMPLETE '..tostring(ms and #ms or 0)..'/'..s.cfg.count..' '..tostring(err)
 end
 return ms,ap,nil
end
local function invalidateRoster(s,reason)
 local r=s.work
 if r then
  r.done=false;r.homeDone=false;r.rosterDirty=true;r.tries=0;r.busyLogged=nil
  -- RoleAI will reopen its installed cache only for the current KS package;
  -- a later native contract/emergency package must remain protected.
 end
 s.nextCheck=0
 emit(s,'ROSTER_CHANGED','reason='..tostring(reason)..' survivor_setup_preserved=true',
  'roster_'..tostring(s.rosterFingerprint)..'_'..tostring(reason))
end
-- Alpha.74 BAR GUARDS ONLY: large interiors extend beyond the 26-unit
-- building-center radius. The engine's RootObject.isInsideBuilding is a
-- native hand pointing at the ACTUAL containing building. Compare its stable
-- handle to the bar being delivered to; never count a neighbouring building.
local function barGuardInside(s,c)
 if s.cfg.shop~='bar' or s.cfg.role~='guard' then return false end
 local ok,handle=pcall(function()return c.isInsideBuilding end)
 if not ok or not handle or Live.call(handle,'isNull')==true then return false end
 local identity=Live.call(handle,'toString')
 return identity~=nil and tostring(identity)==s.key
end
local function atDeliveryTarget(s,rec)
 return rec and (rec.distance<=radius(s)
  or (s.cfg.shop=='bar' and s.cfg.role=='guard' and rec.nativeInsideBar==true))
end
local function snapshot(s,ms,b,arrivalRadius)
 local target=Live.call(b,'getPosition')
 if not T.valid(target) then return nil,'BUILDING_POSITION_INVALID' end
 local snap,near={},0
 for _,m in ipairs(ms)do
  local p=Live.call(m.char,'getPosition')
  if not T.valid(p) then return nil,'POSITION_INVALID '..m.key end
  local d=T.distance2D(p,target)
  local isInside=barGuardInside(s,m.char)
  local rec={pos=Live.copy(p),distance=d,nativeInsideBar=isInside}
  snap[m.key]=rec
  if atDeliveryTarget(s,rec) then
   near=near+1
   if isInside and d>(arrivalRadius or ARRIVAL_RADIUS) then
    emit(s,'BAR_GUARD_INTERIOR_VERIFIED','member='..m.key..' via=native_isInsideBuilding handle='..s.key
      ..' center_distance='..string.format('%.1f',d)..' counted_for_arrival=true',
      'bar_inside_'..m.key)
   end
  end
 end
 return {byID=snap,near=near,target=Live.copy(target)},nil
end
local function moved(old,now)
 return old and now and T.distance2D(now.pos,old.pos)>PROGRESS
end
local function newOrder(mode)
 return {mode=mode,tries=0,gateTry=0}
end
-- Delivery safety only. No native job/package inspection and no job recovery.
local function dispatch(s,rec,character,reason,last)
 local o=s.orders[rec.id] or newOrder('pending')
 s.orders[rec.id]=o
 local ok,err=pcall(character.setDestination,character,s.target,false)
 if not ok then
  o.mode='failed';emit(s,'ORDER_FAIL','member='..rec.id..' reason='..tostring(err),rec.id..'_order_fail')
  return false
 end
 if last then o.gateTry=o.gateTry+1 else o.tries=o.tries+1 end
 o.mode='await';o.testAt=s.now+ORDER_TEST_MINUTES;o.previous=rec
 emit(s,'ORDER','member='..rec.id..' attempt='..(last and 'POST_GATE' or tostring(o.tries))..' reason='..reason..' target='..T.fmt(s.target),rec.id..'_order_'..o.tries..'_'..o.gateTry)
 return true
end
local function duty(s,ms)
 Duty.tick(s,ms)
 if not s.cfg.serviceHired or not s.work or not s.work.done then return end
 local services=rawget(_G,'KenshiShopPoliceServices')
 if type(services)=='table' and type(services.hiredDuty)=='function' then services.hiredDuty(s,ms) end
end
local function arrived(s,ms,b)
 if not s.arrivalReported then
  s.arrivalReported=true
  emit(s,'GROUP_ARRIVED','all='..#ms..'/'..s.cfg.count..' checked; delivery_complete; native_role_handoff')
  if not s.cfg.serviceHired then
   local ok,err=pcall(function()
    require('Core.Ownership.Registry').onArrived(s.cfg.shop,s.cfg.role,b,s.platoon)
   end)
   if not ok then Log.error('OWN_ARRIVAL_DISPATCH '..s.cfg.shop..' '..tostring(err)) end
  end
 end
 -- Delivery ends. Native goals take over; never reissue a destination here.
 supplyAudit(s,ms,s.now)
 local residentOK=Residence.ensure(s,b)
 if residentOK then Work.ensure(s,ms);Catalog.ensure(s,ms);duty(s,ms)
 else emit(s,'RESIDENT_WAIT','work_handoff_waits_for_trader_resident')end
 s.phase='DELIVERED';s.nextCheck=s.now+1
 -- Low-frequency handoff retries and resource audit; no forced work movement.

end
local function beginOrders(s,ms,snap,reason,eligible)
 s.phase='DELIVER';s.orders={};s.teleDue=nil
 local count=0
 for _,m in ipairs(ms) do
  local rec=snap.byID[m.key]
  if rec and not atDeliveryTarget(s,rec) then
   local halted,why=Live.halted(m.char)
   if not halted and (not eligible or eligible[m.key]) then
    rec.id=m.key
    if dispatch(s,rec,m.char,reason,false) then count=count+1 end
   else
    emit(s,'ORDER_HELD','member='..m.key..' '..tostring(why or 'NOT_ELIGIBLE'),'held_'..m.key)
    s.orders[m.key]=newOrder('protected')
   end
  else
   s.orders[m.key]=newOrder('arrived')
  end
 end
 if count==0 then s.phase='DELIVERY_PAUSED';s.nextCheck=s.now+AUDIT_MINUTES
 else s.nextCheck=s.now+ORDER_TEST_MINUTES end
end
local function fallbackGate(s,ms,ap,snap)
 local candidates,all={},true
 for _,m in ipairs(ms)do
  local o=s.orders[m.key]
  local rec=snap.byID[m.key]
  if o and o.mode=='exhausted' and rec and not atDeliveryTarget(s,rec) and not s.teleportUsed[m.key] then
   local held,reason=Live.halted(m.char)
   if held then
    emit(s,'TELEPORT_HELD','member='..m.key..' '..reason,'gate_held_'..m.key)
    all=false
   else candidates[#candidates+1]={member=m,rec=rec} end
  else all=false end
 end
 if #candidates==0 then return false,'NO_ELIGIBLE_STALLED_NPC' end
 local source=snap.byID[candidates[1].member.key].pos
 local ok,point,desc=pcall(T.safeGatePoint,s.building,getGameWorld(),source)
 if not ok then return false,'GATE_INVALID '..tostring(point) end
 s.gateTargets={};s.gateMoved={}
 if all and #candidates==s.cfg.count then
  -- Exact native ActivePlatoon:teleport(absolute Vector3).
  for _,entry in ipairs(candidates)do
   s.teleportUsed[entry.member.key]=true;s.gateTargets[entry.member.key]=point
  end
  local called,errorText=pcall(ap.teleport,ap,point)
  if not called then return false,'NATIVE_PLATOON_TELEPORT_FAILED '..tostring(errorText) end
  for _,entry in ipairs(candidates)do s.gateMoved[entry.member.key]=true end
 else
  -- Character:teleport(moveBy) uses relative displacement, unlike ActivePlatoon:teleport.
  -- Preserve moving squadmates. One native call for each stalled NPC only.
  for i,entry in ipairs(candidates)do
   local src=entry.rec.pos
   local dst={x=point.x+(i-1)*2,y=point.y,z=point.z+(i-1)*2}
   local delta={x=dst.x-src.x,y=dst.y-src.y,z=dst.z-src.z}
   s.teleportUsed[entry.member.key]=true;s.gateTargets[entry.member.key]=dst
   local called,errorText=pcall(entry.member.char.teleport,entry.member.char,delta)
   if called then s.gateMoved[entry.member.key]=true
   else emit(s,'TELEPORT_FAIL','member='..entry.member.key..' '..tostring(errorText),'tele_fail_'..entry.member.key)end
  end
 end
 s.phase='VERIFY_GATE';s.nextCheck=s.now+GATE_VERIFY_MINUTES
 emit(s,'TELEPORT_REQUESTED','count='..#candidates..' target='..T.fmt(point)..' '..desc..' verify_before_last_order')
 return true
end
local function verifyGate(s,ms,snap)
 local done=0
 local members={};for _,m in ipairs(ms)do members[m.key]=m.char end
 for id,dst in pairs(s.gateTargets or {})do
  local o=s.orders[id];local rec=snap.byID[id]
  if s.gateMoved[id] and rec and members[id] and T.distance2D(rec.pos,dst)<=55 then
   emit(s,'TELEPORT_OK','member='..id..' gate='..T.fmt(dst),'tele_ok_'..id)
   rec.id=id
   if dispatch(s,rec,members[id],'last_order_after_gate',true) then done=done+1 end
  else
   if o then o.mode='failed' end
   emit(s,'TELEPORT_FAIL','member='..id..' verification_failed','gate_verify_fail_'..id)
  end
 end
 if done==0 then return fatal(s,'GATE_TELEPORT_NOT_VERIFIED') end
 s.phase='DELIVER';s.nextCheck=s.now+ORDER_TEST_MINUTES
end
local function deliveryStep(s,ms,ap,snap)
 if s.phase=='VERIFY_GATE' then return verifyGate(s,ms,snap) end
 if s.phase=='WAIT_TELEPORT' then
  if s.now<s.teleDue then return end
  -- No teleport if a previously stalled member resumed movement.
  local count=0
  for _,m in ipairs(ms)do
   local o=s.orders[m.key];local rec=snap.byID[m.key]
   if o and o.mode=='exhausted' and rec and not atDeliveryTarget(s,rec) then
    if moved(o.previous,rec) then
     o.mode='moving';o.previous=rec
     emit(s,'MOVING','member='..m.key..' resumed_before_gate','moving_before_gate_'..m.key)
    else count=count+1 end
   end
  end
  if count>0 then
   local ok,reason=fallbackGate(s,ms,ap,snap)
   if not ok then fatal(s,reason) end
   return
  end
  s.phase='MOVING';s.nextCheck=s.now+AUDIT_MINUTES
  return
 end
 local pending,exhausted=0,0
 for _,m in ipairs(ms)do
  local o=s.orders[m.key] or newOrder('pending');s.orders[m.key]=o
  local rec=snap.byID[m.key];rec.id=m.key
  if atDeliveryTarget(s,rec) then
   o.mode='arrived'
  elseif o.mode=='await' and s.now>=o.testAt then
   local held,why=Live.halted(m.char)
   if held then o.mode='protected';emit(s,'ORDER_HELD','member='..m.key..' '..why,'held_combat_'..m.key)
   elseif moved(o.previous,rec) then
    o.mode='moving';o.previous=rec
    emit(s,'MOVING','member='..m.key..' distance='..string.format('%.1f',rec.distance)..' retry_suspended',m.key..'_moving_'..tostring(o.tries)..'_'..tostring(o.gateTry))
   elseif o.gateTry>0 then
    o.mode='failed';emit(s,'STUCK','member='..m.key..' after_teleport=1; no_more_attempts','final_stuck_'..m.key)
   elseif o.tries<MAX_ORDERS then
    dispatch(s,rec,m.char,'retry_after_failed_test',false)
   else
    o.mode='exhausted';o.previous=rec;exhausted=exhausted+1
    emit(s,'STUCK','member='..m.key..' attempts=3; gate_in_2_game_minutes','stuck_3_'..m.key)
   end
  elseif o.mode=='await' then pending=pending+1
  elseif o.mode=='exhausted' then exhausted=exhausted+1
  elseif o.mode=='protected' then
   local held=Live.halted(m.char)
   if not held and (o.tries or 0)<MAX_ORDERS then
    dispatch(s,rec,m.char,'resume_delivery_after_safe',false)
   end
  end
 end
 if exhausted>0 then
  s.phase='WAIT_TELEPORT';s.teleDue=s.now+TELEPORT_WAIT_MINUTES
  emit(s,'TELEPORT_WAIT','stalled='..exhausted..' game_minutes=2','tele_wait_delivery')
  s.nextCheck=s.teleDue
 elseif pending==0 then
  local active=false;local failed=false
  for _,m in ipairs(ms)do
   local o=s.orders[m.key]
   if o.mode=='await' or o.mode=='pending' then active=true end
   if o.mode=='failed' then failed=true end
  end
  if failed then fatal(s,'NO_MOVEMENT_AFTER_LAST_TEST')
  elseif active then s.nextCheck=s.now+ORDER_TEST_MINUTES
  else
   s.phase='MOVING';s.nextCheck=s.now+AUDIT_MINUTES
  end
 else s.nextCheck=s.now+ORDER_TEST_MINUTES end
end
local function loadProbe(s,ms,snap)
 local safe=Live.safeToOrder(ms)
 if not safe then s.nextCheck=s.now+AUDIT_MINUTES;return end
 local anyAway=false;local idle={};local moving=false
 for _,m in ipairs(ms)do
  local rec=snap.byID[m.key]
  if not atDeliveryTarget(s,rec) then
   anyAway=true
   if moved(s.baseline and s.baseline[m.key],rec) then moving=true
   else idle[m.key]=true end
  end
 end
 if not anyAway then return arrived(s,ms,s.building) end
 if next(idle) then
  emit(s,'LOAD_STATIONARY','saved_unarrived_members; bounded_delivery_resume')
  beginOrders(s,ms,snap,'saved_delivery_resume',idle)
 elseif moving then
  s.phase='MOVING';s.nextCheck=s.now+AUDIT_MINUTES;s.lastAudit=snap.byID
  emit(s,'LOAD_MOVING','existing_squad_already_walking; no_new_order')
 else
  s.phase='DELIVERY_PAUSED';s.nextCheck=s.now+AUDIT_MINUTES
 end
end
local function audit(s,ms,snap)
 if s.phase=='MOVING' then
  local stalled=false
  for _,m in ipairs(ms)do
   local rec=snap.byID[m.key]
   local o=s.orders[m.key]
   if not atDeliveryTarget(s,rec) then
    if not moved((s.lastAudit or {})[m.key] or (o and o.previous),rec) then stalled=true end
   end
  end
  if not stalled then
   s.lastAudit=snap.byID;s.nextCheck=s.now+AUDIT_MINUTES;return
  end
  -- Same bounded transport retry logic; never issue a work/post order.
  for _,m in ipairs(ms)do
   local rec=snap.byID[m.key];rec.id=m.key
   local o=s.orders[m.key]
   if not atDeliveryTarget(s,rec) then
    local held=Live.halted(m.char)
    if not held then
     if not o then dispatch(s,rec,m.char,'saved_movement_stopped',false)
     elseif o.mode=='moving' and not moved((s.lastAudit or {})[m.key] or o.previous,rec) then
      if o.gateTry>0 then o.mode='failed'
      elseif o.tries<MAX_ORDERS then dispatch(s,rec,m.char,'ten_minute_stall',false)
      else o.mode='exhausted';o.previous=rec end
     elseif o.mode=='protected' and (o.tries or 0)<MAX_ORDERS then
      dispatch(s,rec,m.char,'resume_delivery_after_safe',false)
     end
    end
   end
  end
  local anyFailed,anyExhausted,anyAwait=false,false,false
  for _,o in pairs(s.orders)do
   if o.mode=='failed' then anyFailed=true end
   if o.mode=='exhausted' then anyExhausted=true end
   if o.mode=='await' then anyAwait=true end
  end
  if anyFailed then return fatal(s,'MOVEMENT_STOPPED_AFTER_GATE') end
  if anyExhausted then
   s.phase='WAIT_TELEPORT';s.teleDue=s.now+TELEPORT_WAIT_MINUTES;s.nextCheck=s.teleDue
  elseif anyAwait then s.phase='DELIVER';s.nextCheck=s.now+ORDER_TEST_MINUTES
  else s.nextCheck=s.now+AUDIT_MINUTES end
  return
 end
 if s.phase=='FAILED' then s.nextCheck=s.now+AUDIT_MINUTES;return end
 if s.phase=='DELIVERY_PAUSED' then
  -- Only resumes unfinished delivery, with a finite safety budget.
  s.pausedChecks=(s.pausedChecks or 0)+1
  if s.pausedChecks>3 then return fatal(s,'DELIVERY_SAFETY_WAIT_LIMIT_3') end
  local eligible={}
  for _,m in ipairs(ms)do
   if not atDeliveryTarget(s,snap.byID[m.key]) then eligible[m.key]=true end
  end
  if next(eligible) then beginOrders(s,ms,snap,'resume_unfinished_delivery',eligible)
  else s.nextCheck=s.now+AUDIT_MINUTES end
 end
end
function M.new(cfg)
 assert(cfg.shop and cfg.role and cfg.template and cfg.faction and cfg.count)
 local states={}
 local driver={}
 local function stop(s)
  SupplyQueue.cancel(s)
  if s.hook then MonitorQueue.remove(s.hook);s.hook=nil end
 end
 local function waitSaved(s)
  SupplyQueue.cancel(s)
  s.phase='WAIT_SAVED';s.saved=true;s.nextCheck=0;s.previousClock=nil
  s.platoonRef=nil;s.pid=nil;s.orders={};s.baseline=nil;s.lastAudit=nil
  s.work=nil;s.catalog=nil;s.duty=nil;s.postDuty=nil
  s.nextSupplyCheck=nil;s.supplyResetAt=nil;s.supplyFailures=nil;s.supplyClock=nil
  s.teleDue=nil;s.gateTargets=nil;s.gateMoved=nil;s.pausedChecks=nil;s.teleportUsed={}
 end
 local function tick(s)
  if retiredBuilding(s.key) or retiredPlatoon(s.pid) then
   stop(s);states[s.key]=nil;return
  end
  local world=Live.readyWorld();if not world then return end
  local revision=Live.revision()
  if s.worldRevision~=revision then
   waitSaved(s);s.worldRevision=revision;s.once={}
  end
  s.frames=s.frames+1
  local now=Live.clock()
  if s.previousClock and now+0.001<s.previousClock then
   T.resetMembers()
   -- All stores recover their EXISTING squad on clock rewind. A previous
   -- version stopped monitoring four stores and lost unfinished delivery.
   waitSaved(s);s.previousClock=now
   emit(s,'CLOCK_RESET_RECOVER','game_clock_decreased; read_only_saved_squad_lookup; no_new_spawn','clock_reset_recover_'..s.frames)
   return
  end
  s.previousClock=now
  if s.nextCheck and now+0.00001<s.nextCheck then return end
  s.now=now
  local b=building(s)
  if not b then s.nextCheck=now+AUDIT_MINUTES;return end
  s.building=b
  if s.phase=='WAIT_SAVED' then
   -- A building can load before its faction's saved squads are registered.
   -- One deferred lookup per 10 game minutes, never spawn or replace anything.
   local ok,p,why=pcall(Existing.find,b,cfg)
   local ref=ok and p and platoonRef(p)
   if ref and not retiredPlatoon(ref.pid) then
    s.platoonRef=ref;s.pid=ref.pid;s.phase='WAIT_ACTIVE';s.nextCheck=0
    emit(s,'SAVED_FOUND','deferred existing_platoon='..ref.pid..' no_respawn','saved_deferred')
    if not cfg.serviceHired then
     pcall(function() require('Core.Ownership.Registry').onRestored(cfg.shop,cfg.role,b,p) end)
    end
   elseif ok and why and tostring(why):find('^AMBIGUOUS') then
    s.phase='BLOCKED_AMBIGUOUS';s.nextCheck=now+AUDIT_MINUTES
    emit(s,'RESUME_BLOCKED','multiple_saved_squads; no_spawn_no_order','ambiguous')
   else s.nextCheck=now+AUDIT_MINUTES end
   return
  end
  if s.phase=='BLOCKED_AMBIGUOUS' then s.nextCheck=now+AUDIT_MINUTES;return end
  s.platoon=platoon(s)
  if not s.platoon then s.nextCheck=now+AUDIT_MINUTES;return end
  local ms,ap,err=squadMembers(s,world)
  if not ms then
   s.nextCheck=now+AUDIT_MINUTES
   emit(s,'MONITOR_PAUSED',tostring(err),'pause_'..tostring(err))
   return
  end
  -- Register before delivery/work safety gates, including unconscious or
  -- carrying NPCs. Native lifetime/race hooks remove stale registrations.
  NoSever.tick(s,ms)
  local services=rawget(_G,'KenshiShopPoliceServices')
  if type(services)=='table' and type(services.observe)=='function' then
   local ok,why=pcall(services.observe,s,ms)
   if not ok then emit(s,'SERVICE_OBSERVER_FAILED',tostring(why),'service_observer_failed')end
  end
  local keys={};for _,m in ipairs(ms)do keys[#keys+1]=m.key end;table.sort(keys)
  local fingerprint=table.concat(keys,'|')
  if s.rosterFingerprint and s.rosterFingerprint~=fingerprint then invalidateRoster(s,'MEMBER_SET')end
  s.rosterFingerprint=fingerprint
  -- A saved role package proves delivery already ended; a patrol/medic may be away.
  if s.saved and s.phase=='WAIT_ACTIVE' then
   local lead=Live.call(ap,'getSquadLeader')
   local bb=lead and Live.call(lead,'getBlackboard')
   if Work.isWorkingPackage(cfg,Live.call(bb,'getCurrentAIPackageName')) then
    s.counted=#ms;return arrived(s,ms,b)
   end
  end
  if s.phase=='DELIVERED' then
   supplyAudit(s,ms,now)
   local residentOK=Residence.ensure(s,b)
   if residentOK then Work.ensure(s,ms);Catalog.ensure(s,ms)end
   if cfg.role=='trader' then
    pcall(function()require('Core.Ownership.Registry').monitorResident(cfg.shop,b,now)end)
   end
   if residentOK then duty(s,ms)end
   s.nextCheck=now+1
   return
  end
  local snap,why=snapshot(s,ms,b,radius(s))
  if not snap then s.nextCheck=now+AUDIT_MINUTES;emit(s,'SCAN_FAIL',why,'scan_'..why);return end
  s.near=snap.near;s.counted=#ms;s.target=snap.target
  if s.phase=='WAIT_ACTIVE' then
   local newSetup=not s.saved and not s.setupDone
   s.phase=newSetup and 'DELIVER' or 'LOAD_PROBE'
   s.nextCheck=now+(newSetup and 0 or LOAD_TEST_MINUTES)
   s.baseline=snap.byID
   if not newSetup then
    emit(s,'LOAD_PROBE','existing_squad_found; no_respawn_no_regear')
    supplyAudit(s,ms,now)
   else
    -- New NPCs ONLY: appearance and outfit are applied once, never on saved squads.
    for _,m in ipairs(ms)do
     local ok,done,info=pcall(Appearance.apply,m.char,getGameWorld(),cfg.shop)
     if ok and done then emit(s,'APPEARANCE_OK','member='..m.key..' '..tostring(info),'appearance_'..m.key) end
    end
    if cfg.role=='trader' then
     local leader=Live.call(ap,'getSquadLeader')
     if leader then
      local gear=require('Core.NPC.TraderOutfits')
      local ok,done,a,n,msg=pcall(gear.apply,leader,cfg.shop)
      if ok and done then emit(s,'GEAR_OK','merchant_outfit='..cfg.shop..' '..tostring(a)..'/'..tostring(n)..' '..tostring(msg)) end
     end
    end
    supplyAudit(s,ms,now)
    s.setupDone=true
    beginOrders(s,ms,snap,'initial_delivery')
   end
   return
  end
  if snap.near==#ms then
   s.lastAudit=snap.byID
   return arrived(s,ms,b)
  end
  if s.phase=='LOAD_PROBE' then return loadProbe(s,ms,snap) end
  if s.phase=='DELIVER' or s.phase=='WAIT_TELEPORT' or s.phase=='VERIFY_GATE' then
   return deliveryStep(s,ms,ap,snap)
  end
  if s.phase=='MOVING' or s.phase=='DELIVERY_PAUSED' or s.phase=='FAILED' then return audit(s,ms,snap)end
 end
 local function attach(s,delayFrames)
  if s.hook then return true end
  local id,why=MonitorQueue.add(function()
   local good,reason=pcall(tick,s)
   -- Borrowed native wrappers are valid only for this monitored pass. The
   -- next frame resolves both objects again from owned handle values.
   s.platoon=nil;s.building=nil
   if not good then
    Log.error('NPC_MONITOR_EXCEPTION shop='..cfg.shop..' '..tostring(reason))
    s.phase='FAILED';stop(s)
   end
  end,delayFrames)
  if not id then s.phase='HOOK_FAILED';Log.error('NPC_HOOK_FAILED '..cfg.shop..' '..tostring(why));return false end
  s.hook=id;return true
 end
 local function newState(b,ref,saved)
  local key=b:getHandle():toString()
  local s={cfg=cfg,key=key,handle=b:getHandle(),platoonRef=ref,pid=ref and ref.pid,saved=saved,
   phase=ref and 'WAIT_ACTIVE' or 'WAIT_SAVED',
   frames=0,orders={},teleportUsed={},once={},near=0,previousClock=nil,worldRevision=Live.revision()}
  states[key]=s
  if ref then emit(s,saved and 'SAVED_FOUND' or 'SPAWN',saved and ('existing_platoon='..ref.pid..' no_respawn') or 'native_platoon_created') end
  s.nextCheck=0
  -- Preserve the factory's legacy 40-frame registration grace for new squads.
  attach(s,saved and 0 or 40)
  return s
 end
 function driver.start(b)
  if cfg.serviceHired then return false,'HIRED_REQUIRES_PAID_SERVICE' end
  local key=b:getHandle():toString()
  if retiredBuilding(key) then return false,'RETIRED_BUILDING' end
  if cfg.role=='guard' then
   -- Safe migration boundary: legacy saves may still contain trader+2guards in one platoon.
   -- Never create a second guard group alongside an old 3-person mixed group.
   local legacyIds={bar='300-KenshiShop.mod',engineering='303-KenshiShop.mod',armour='305-KenshiShop.mod',weapons='307-KenshiShop.mod'}
   local oldId=legacyIds[cfg.shop]
   if oldId then
    local probe={template=oldId,faction=cfg.faction}
    local existing,reason=Existing.find(b,probe)
    if existing==nil then
     Log.console('NPC_GUARD_SPLIT_WAIT shop='..cfg.shop..' reason=TRADER_LOOKUP_UNVERIFIED '..tostring(reason))
     return false,'SPAWN_GUARD_UNVERIFIED TRADER_LOOKUP '..tostring(reason)
    end
    if existing==false then
     Log.console('NPC_GUARD_SPLIT_WAIT shop='..cfg.shop..' reason=TRADER_NOT_REGISTERED')
     return false,'SPAWN_GUARD_UNVERIFIED TRADER_NOT_REGISTERED'
    end
    local ap=Live.call(existing,'getActivePlatoon')
    local count=ap and Live.call(ap,'getSquadSize')
    if count==3 then
     Log.console('NPC_GUARD_SPLIT_LEGACY_BLOCK shop='..cfg.shop..' building='..key..' old_mixed_squad=3 no_new_guards_no_deletion')
     return false,'EXISTING_SQUAD LEGACY_MIXED_THREE_REQUIRES_REBUILD'
    end
    if count~=1 then
     return false,'SPAWN_GUARD_UNVERIFIED TRADER_COUNT='..tostring(count)
    end
   end
  end
  if states[key] then
   local old=states[key]
   if old.phase=='WAIT_SAVED' then
    -- Verify BEFORE discarding the read-only recovery monitor. An existing
    -- saved squad must retain its monitor and must never be spawned twice.
    local guard,found,why=pcall(Existing.inspect,b,cfg)
    if not guard or found==nil then
     return false,'SPAWN_GUARD_UNVERIFIED '..tostring(guard and why or found)
    end
    if found then return false,'EXISTING_SQUAD '..tostring(why) end
    stop(old);states[key]=nil
   else return false,'ALREADY_ATTEMPTED '..old.phase end
  end
  local ok,yes,reason=pcall(Existing.inspect,b,cfg)
  if not ok or yes==nil then
   Log.console('NPC_SPAWN_GUARD_BLOCKED shop='..cfg.shop..' squad='..cfg.role..' building='..key..' '..tostring(ok and reason or yes))
   return false,'SPAWN_GUARD_UNVERIFIED '..tostring(ok and reason or yes)
  end
  if yes then
   Log.console('NPC_SPAWN_SKIP shop='..cfg.shop..' squad='..cfg.role..' building='..key..' '..tostring(reason)..' no_respawn')
   return false,'EXISTING_SQUAD '..tostring(reason)
  end
  local catalogOK,catalogWhy=Catalog.prepare(cfg)
  if not catalogOK then Log.error('NPC_CATALOG84_PENDING shop='..cfg.shop..' '..tostring(catalogWhy)..' delivery_continues') end
  local good,pre=pcall(T.preflight,b,cfg)
  if not good then return false,'PREFLIGHT_FAILED '..tostring(pre) end
  Log.console('NPC_PREFLIGHT shop='..cfg.shop..' squad='..cfg.role..' building='..key..' template='..cfg.template..' count='..cfg.count..' outside='..pre.method..' at='..T.fmt(pre.spawn))
  local spawned,p=pcall(T.spawn,pre,b,cfg)
  if not spawned or not p then return false,'SPAWN_FAILED '..tostring(p) end
  newState(b,platoonRef(p),false)
  -- Ownership begins when the original squad exists, NOT only after arrival/load.
  local ownOK,ownErr=pcall(function()
   require('Core.Ownership.Registry').onSpawned(cfg.shop,cfg.role,b,p)
  end)
  if not ownOK then Log.error('OWN_SPAWN_DISPATCH '..cfg.shop..' '..tostring(ownErr)) end
  return true,'WAIT_ACTIVE'
 end
 function driver.resume(b)
  T.resetMembers()
  local key=b:getHandle():toString()
  if retiredBuilding(key) then return false,'RETIRED_BUILDING' end
  local s=states[key]
  if s then
   -- Load can register a building whose handle already has a monitor.
   s.handle=b:getHandle();waitSaved(s);s.worldRevision=Live.revision()
   if s.hook then return true,'LOAD_REFRESH_SAVED_LOOKUP; no_respawn' end
   return attach(s),'SESSION_REATTACHED'
  end
  if not Live.readyWorld() then
   newState(b,nil,true)
   return true,'WAIT_WORLD_LOADED'
  end
  local ok,p,reason=pcall(Existing.find,b,cfg)
  if not ok then return false,'LOOKUP_EXCEPTION '..tostring(p) end
  if p==false then
   local s=newState(b,nil,true);s.phase='WAIT_SAVED';s.nextCheck=Live.clock()+AUDIT_MINUTES
   return false,'WAIT_SAVED_PLATOON; no_respawn; deferred_10_game_minute_lookup'
  end
  if not p then
   Log.console('NPC_RESUME_BLOCKED shop='..cfg.shop..' squad='..cfg.role..' '..tostring(reason)..' no_respawn')
   if tostring(reason):find('^AMBIGUOUS') then return false,tostring(reason) end
   local s=newState(b,nil,true);s.phase='WAIT_SAVED';s.nextCheck=Live.clock()+AUDIT_MINUTES
   return false,'WAIT_SAVED_PLATOON '..tostring(reason)
  end
  local ref=platoonRef(p)
  newState(b,ref,true)
  if not cfg.serviceHired then
   local signaled,notifyError=pcall(function()
    require('Core.Ownership.Registry').onRestored(cfg.shop,cfg.role,b,p)
   end)
   if not signaled then Log.error('OWN_RESTORED_DISPATCH '..cfg.shop..' '..tostring(notifyError)) end
  end
  return true,'SAVED_MONITOR_ATTACHED '..tostring(reason)
 end
 function driver.adopt(b,p,options)
  -- Payment/spawn belongs to the chief service. Adopt only the actual native
  -- platoon it produced; this path never creates or replaces living members.
  if not b or Live.call(b,'isValid')~=true or not p then return false,'ADOPT_ARGUMENTS_INVALID' end
  local id=Live.call(p,'getPlatoonStringID')
  if not id or id=='' then return false,'ADOPT_PLATOON_ID_MISSING' end
  if retiredPlatoon(id) or retiredBuilding(Live.call(Live.call(b,'getHandle'),'toString')) then return false,'RETIRED_SERVICE_SQUAD' end
  if cfg.existingID and tostring(id)~=tostring(cfg.existingID) then return false,'ADOPT_ID_MISMATCH' end
  local ref=platoonRef(p,id)
  if not ref then return false,'ADOPT_HANDLE_UNAVAILABLE' end
  local good,template=pcall(function()return p.squadTemplate.stringID end)
  if not good or template~=cfg.template then return false,'ADOPT_TEMPLATE_MISMATCH' end
  local f=Live.call(p,'getFaction');local data=Live.call(f,'getData')
  local ok,faction=pcall(function()return data.stringID end)
  if not ok or faction~=cfg.faction then return false,'ADOPT_FACTION_MISMATCH' end
  options=type(options)=='table' and options or {}
  T.resetMembers()
  local function seed(s)
   if options.work and not s.work then s.work=options.work end
   if options.initializedMember then
    local ap=Live.call(p,'getActivePlatoon')
    local leader=Live.call(Live.call(Live.call(ap,'getSquadLeader'),'getHandle'),'toString')
    s.work=s.work or {leader=leader,tries=0,setup={}}
    s.work.setup=s.work.setup or {};s.work.setup[options.initializedMember]=true
   end
  end
  local key=b:getHandle():toString();local old=states[key]
  if old and old.pid==id then
   if old.worldRevision~=Live.revision() then waitSaved(old);old.phase='WAIT_ACTIVE' end
   old.platoonRef=ref;old.pid=id;old.handle=b:getHandle();old.worldRevision=Live.revision()
   invalidateRoster(old,'PAID_REPLACEMENT')
   seed(old)
   if not old.hook then attach(old)end
   return true,'EXISTING_MONITOR_UPDATED '..id
  end
  if old then stop(old)end
  local next=newState(b,ref,not options.fresh)
  seed(next)
  return next.hook~=nil,'NATIVE_PLATOON_ADOPTED '..id
 end
 function driver.status(b)
  local s=states[b:getHandle():toString()]
  if not s then return 'NOT_SCHEDULED' end
  local w=Live.readyWorld()
  local work=Work.status({work=s.work,platoon=w and platoon(s),building=w and building(s)})
  return s.phase..' work='..work..' duty='..Duty.status(s)..' catalog='..tostring(s.catalog and s.catalog.done or false)..' counted='..tostring(s.counted or '?')..'/'..cfg.count..' near='..tostring(s.near or 0)..' saved='..tostring(s.saved)..' next='..tostring(s.nextCheck)
 end
 function driver.check(b)
  local ok,pre=pcall(T.preflight,b,cfg)
  if not ok then return 'FAIL '..tostring(pre) end
  return 'OK expected='..cfg.count..' template='..cfg.template..' outside='..pre.method
 end
 function driver.stopBuilding(key)
  local s=states[key]
  if s then stop(s);states[key]=nil end
 end
 function driver.resetSession()for _,s in pairs(states)do stop(s)end;states={}end
 return driver
end
return M
