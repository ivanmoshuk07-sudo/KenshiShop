-- Per-shop game-clock queue. No real-time or frame-time approximations.
local Log=require('Diagnostics')
local M={}
local FIRST_DELAY=1/60 -- first squad, absolute in-game HOURS
local NEXT_INTERVAL=5/60 -- interval after previous squad, game-hours
local function now()
 local w=assert(getGameWorld(),'WORLD_MISSING')
 local obj=assert(w:getTimeStamp_inGameHours(),'INGAME_CLOCK_UNAVAILABLE')
 local value=assert(obj:getTotalHours(),'INGAME_CLOCK_INVALID')
 assert(type(value)=='number' and value==value,'INVALID_GAME_CLOCK_VALUE')
 return value
end
function M.new(shop,roles)
 assert(#roles>=1,'roles_missing')
 local states={};local M2={}
 local function emit(s,ev,detail,key)
  key=key or ev
  if s.events[key] then return end
  s.events[key]=true
  Log.console('NPC_'..ev..' shop='..shop..' building='..s.key..' '..tostring(detail or ''))
 end
 local function unhook(s)if s.hook then Events.off(s.hook);s.hook=nil end end
 local function tick(s)
  s.frames=s.frames+1
  if s.frames%20~=0 then return end
  local hour=now()
  if hour<s.started then
   emit(s,'CLOCK_ROLLBACK','time_decreased; queue_stopped_to_prevent_duplicates')
   s.stage='CLOCK_ROLLBACK';unhook(s);return
  end
  if s.next>#roles then s.stage='ALL_SPAWNS_ATTEMPTED';unhook(s);return end
  local due=math.max(s.started+FIRST_DELAY+NEXT_INTERVAL*(s.next-1),s.retryAt or 0)
  if hour+0.0000001<due then return end
  local role=roles[s.next]
  emit(s,'SPAWN_DUE','group='..s.next..'/'..#roles..' role='..role.name..' minutes_after_build='..(1+(s.next-1)*5),'due_'..s.next)
  local building=s.handle and s.handle:getBuilding()
  if not building or not building:isValid() then
   emit(s,'WAIT_BUILDING','group='..s.next..' target_unloaded; no_new_spawn','unloaded_'..s.next)
   return
  end
  local good,res,why=pcall(role.driver.start,building)
  if not good then
   emit(s,'DISPATCH_FAIL','group='..s.next..' role='..role.name..' '..tostring(res),'dispatch_'..s.next)
  elseif not res and type(why)=='string' and why:find('^EXISTING_SQUAD') then
   emit(s,'SPAWN_SKIPPED','group='..s.next..' role='..role.name..' '..why,'skipped_'..s.next)
  elseif not res and type(why)=='string' and why:find('^ALREADY_ATTEMPTED') then
   emit(s,'SPAWN_SKIPPED','group='..s.next..' role='..role.name..' '..why,'skipped_'..s.next)
  elseif not res and type(why)=='string' and why:find('^SPAWN_GUARD_UNVERIFIED') then
   emit(s,'SPAWN_GUARD_BLOCKED','group='..s.next..' role='..role.name..' '..why,'blocked_'..s.next)
  elseif not res then
   emit(s,'SPAWN_FAILED','group='..s.next..' role='..role.name..' '..tostring(why),'failed_'..s.next)
  else
   emit(s,'SPAWN_REQUEST_OK','group='..s.next..' role='..role.name,'requested_'..s.next)
  end
  if (not good or (not res and
   not (type(why)=='string' and (why:find('^EXISTING_SQUAD') or why:find('^ALREADY_ATTEMPTED'))))) then
   s.retries[s.next]=(s.retries[s.next] or 0)+1
   if s.retries[s.next]<3 then
    s.retryAt=hour+FIRST_DELAY
    s.stage='SPAWN_RETRY_PENDING'
    emit(s,'SPAWN_RETRY','group='..s.next..' attempt='..s.retries[s.next]..'/3 next_after=1_game_minute','retry_'..s.next..'_'..s.retries[s.next])
    return
   end
   s.stage='SPAWN_ABORTED';unhook(s)
   Log.error('NPC_SPAWN_ABORTED shop='..shop..' building='..s.key..' role='..role.name..' attempts=3 no_duplicate_spawn')
   return
  end
  s.retryAt=nil
  s.next=s.next+1
  if s.next>#roles then s.stage='ALL_SPAWNS_ATTEMPTED';unhook(s)
  else s.stage='WAIT_NEXT_SQUAD' end
 end
 function M2.start(building)
  local h=building:getHandle();local key=h:toString()
  if states[key] then
   if states[key].stage=='CLOCK_ROLLBACK' then
    -- Only an explicit fresh construction/interior completion may re-arm the queue.
    -- Individual driver spawn guards still refuse duplicates.
    unhook(states[key]);states[key]=nil
    Log.console('NPC_SCHEDULE_REARM shop='..shop..' building='..key..' reason=explicit_new_construction')
   else return 'ALREADY_SCHEDULED '..states[key].stage end
  end
  local ok,time=pcall(now)
  if not ok then Log.error('NPC_SCHEDULE_FAIL shop='..shop..' '..tostring(time));return 'CLOCK_ERROR '..tostring(time) end
  local s={key=key,handle=h,started=time,next=1,stage='WAIT_FIRST_SQUAD',events={},frames=0,retries={}}
  states[key]=s
  emit(s,'SCHEDULED','squads='..#roles..' first_after=1_game_minute step=5_game_minutes (second_at_6)')
  local installed,id=pcall(Events.on,'MyGUI::Gui::eventFrameStart',function()
   local good,err=pcall(tick,s)
   if not good then emit(s,'SCHEDULE_ERROR',tostring(err));s.stage='FAILED_TIMER';unhook(s) end
  end)
  if not installed or not id then s.stage='FAILED_HOOK';emit(s,'SCHEDULE_FAIL','cannot_install_hook '..tostring(id));return s.stage end
  s.hook=id
  return s.stage
 end
 function M2.status(b)
  local s=states[b:getHandle():toString()]
  local parts={}
  for _,r in ipairs(roles)do parts[#parts+1]=r.name..'='..r.driver.status(b) end
  return (s and ('queue='..s.stage..' next='..s.next..'/'..#roles) or 'queue=NOT_SCHEDULED')..' | '..table.concat(parts,' | ')
 end
 function M2.check(b)
  local parts={}
  for _,r in ipairs(roles)do parts[#parts+1]=r.name..'='..r.driver.check(b)end
  local ok,clock=pcall(now);parts[#parts+1]='gameClock='..(ok and tostring(clock) or 'ERROR '..tostring(clock))
  return table.concat(parts,' | ')
 end
 function M2.resume(b)
  local s=states[b:getHandle():toString()]
  local parts={}
  if s and s.hook then parts[#parts+1]='queue=RUNNING' end
  for _,r in ipairs(roles)do
   local good,yes,why=pcall(r.driver.resume,b)
   parts[#parts+1]=r.name..'='..(good and tostring(yes)..' '..tostring(why) or 'EXCEPTION '..tostring(yes))
  end
  return table.concat(parts,' | ')
 end
 function M2.resetSession()
  for _,s in pairs(states)do unhook(s)end;states={}
  for _,r in ipairs(roles)do r.driver.resetSession()end
 end
 return M2
end
return M
