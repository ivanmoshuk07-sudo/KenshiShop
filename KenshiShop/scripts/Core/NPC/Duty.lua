-- Native movement/hold/combat goals on verified coordinates. No furniture mutations.
local Live=require('Core.NPC.LiveState')
local T=require('Core.NPC.Transport')
local Transform=require('Transform')
local Posts=require('Core.NPC.PostData')
local Goals=require('Core.NPC.NativeGoals')
local Route=require('Core.NPC.CityRoute')
local Log=require('Diagnostics')
local M={}
local function emit(s,r,state,detail)
 if r.state==state then return end;r.state=state
 Log.console('NPC_DUTY shop='..s.cfg.shop..' role='..s.cfg.role..' building='..s.key..' state='..state..' '..tostring(detail or ''))
end
local function sameBuilding(c,b)
 local ok,h=pcall(function()return c.isInsideBuilding end)
 return ok and Live.call(h,'toString')==Live.call(Live.call(b,'getHandle'),'toString')
end
local function scope(s,b,pos,target)
 local home=Live.call(b,'getPosition')
 if s.cfg.role=='patrol' then return Route.inside(Live.call(b,'getTown'),home,pos) end
 return (target and sameBuilding(target,b)) or (T.valid(home) and T.valid(pos) and T.distance2D(home,pos)<=60)
end
local function defend(s,b,m,r,world)
 if s.cfg.role=='trader' then return false end
 local c=m.char
 if r.enemyHand then
  local enemy=Live.call(r.enemyHand,'getCharacter')
  local pos=Live.call(enemy,'getPosition')
  if not enemy or Live.call(enemy,'isValid')~=true or Live.call(enemy,'isDead')~=false
   or Live.call(enemy,'isDown')~=false or not scope(s,b,pos,enemy) then
   local _,removed=Goals.remove(c,5)
   local key,o=Goals.current(c)
   if removed and key==5 then Live.call(o,'clearCurrentGoal',false);Live.call(o,'setNeedGOAP') end
   r.enemyHand=nil
  else return true end
 end
 local safe=Goals.safe(c);if not safe then return false end
 local set=world.charUpdateListMain;if not set then return false end
 local origin=Live.call(c,'getPosition');if not T.valid(origin) then return false end
 local sensory=Live.call(c,'getSensoryData');if not sensory then return false end
 local nearest,best=nil,120
 local ok=pcall(function()
  local count=0
  for enemy in pairs(set)do
   count=count+1;if count>12000 then error('SCAN_CAP')end
   if enemy~=c and Live.call(enemy,'isValid')==true and Live.call(enemy,'isDead')==false
    and Live.call(enemy,'isDown')==false and Live.call(c,'isEnemy',enemy,true)==true then
    local pos=Live.call(enemy,'getPosition')
    if T.valid(pos) then
     local distance=T.distance2D(origin,pos)
     if distance<best and scope(s,b,pos,enemy) and Live.call(sensory,'canISeeThisGuy',enemy)==true then
      nearest=enemy;best=distance
     end
    end
   end
  end
 end)
 if not ok or not nearest then return false end
 local yes=Goals.set(c,5,nil,nearest,3)
 if yes then
  r.enemyHand=Live.call(nearest,'getHandle')
  Log.console('NPC_DEFENCE shop='..s.cfg.shop..' role='..s.cfg.role..' member='..m.key..' state=ENGAGED native_task=5 scope=HOME')
 end
 return yes
end
local function post(b,shop,role,slot)
 local entries=Posts[shop] or {};local found=0
 for _,entry in ipairs(entries)do
  if entry.role==role then
   found=found+1
   if found==slot then
    local pos=Transform.world(b:getPosition(),b:getOrientation(),b:getScale(),entry)
    return pos,entry.floor
   end
  end
 end
 return nil
end
local function reached(c,p)
 local loc=Live.call(c,'getPosition')
 return T.valid(loc) and T.distance2D(loc,p)<=8 and math.abs(loc.y-p.y)<=10
end
local function navigable(world,c,p)
 return Live.call(world.navmesh,'getPositionValid',p)==true and Live.call(c,'pathExists',p)==true
end
local function projectPost(world,c,p)
 if navigable(world,c,p)then return p end
 -- Tilt/height rounding can put a recorded post just off the navmesh. Adjust
 -- only the destination height, within the same floor, never any furniture.
 for _,dy in ipairs({1,-1,2,-2,4,-4,8,-8})do
  local candidate=Live.copy(p);candidate.y=p.y+dy
  if navigable(world,c,candidate)then return candidate end
 end
end
function M.tick(s,ms,b)
 local d=s.duty or {members={},nextRoute=0};s.duty=d
 local world=getGameWorld();local now=s.now or Live.clock()
 local work=s.work
 if not work or not work.done then return false end
 local routeTarget
 if s.cfg.role=='patrol' then
  if not d.route and now>=d.nextRoute then
   d.route,d.routeError=Route.build(b,ms[1].char,world);d.nextRoute=now+5;d.index=1
  end
  if not d.route then
   emit(s,d,'WAIT_CITY_ROUTE',d.routeError);return false
  end
  routeTarget=d.route[d.index]
  local all=true
  for _,m in ipairs(ms)do if not reached(m.char,routeTarget)then all=false end end
  if all then
   d.dwellUntil=d.dwellUntil or now+1
   if now>=d.dwellUntil then
    d.index=d.index%#d.route+1;routeTarget=d.route[d.index];d.dwellUntil=nil
   end
  end
 end
 local day=math.floor(now/60)%24
 local open=s.cfg.role~='trader' or s.cfg.shop=='bar' or s.cfg.shop=='robotics' or (day>=6 and day<23)
 local assigned=0
 for i,m in ipairs(ms)do
  local r=d.members[m.key] or {};d.members[m.key]=r
  if not open then
   Goals.clearRoutine(m.char);emit(s,r,'OFF_SHIFT','member='..m.key)
  elseif defend(s,b,m,r,world) then
   emit(s,r,'DEFENDING','member='..m.key)
  else
   local safe,reason=Goals.safe(m.char)
   if not safe then
    r.lastMoveAt=nil;r.lastMovePos=nil
    emit(s,r,'NATIVE_BUSY','member='..m.key..' reason='..tostring(reason))
   else
    local p,floor
    if routeTarget then p=routeTarget else p,floor=post(b,s.cfg.shop,s.cfg.role,i)end
    if not p or not T.valid(p) then emit(s,r,'NO_POST','member='..m.key)
    elseif routeTarget and not scope(s,b,p) then
     Goals.clearRoutine(m.char);d.route=nil;d.nextRoute=now+1;emit(s,r,'ROUTE_REJECTED','member='..m.key)
    else
     if not routeTarget then
      local projected=projectPost(world,m.char,p)
      if projected then p=projected end
     end
     local at=reached(m.char,p)
     -- Validate real engine navigation before creating a movement goal. No teleport fallback.
     if not at and not navigable(world,m.char,p) then
      Goals.clearRoutine(m.char);emit(s,r,'POST_UNREACHABLE','member='..m.key..' point='..T.fmt(p))
      if routeTarget then d.index=d.index%#d.route+1 end
     else
      local ok,why=Goals.routine(m.char,p,at)
      -- Recovery also works if a native binding rejects the goal. A failed
      -- registration must not make the proven delivery movement unreachable.
       if not at then
        local current=Live.call(m.char,'getPosition')
        if not r.target or T.distance2D(r.target,p)>1 then r.lastMoveAt=nil;r.retries=0;r.target=Live.copy(p)end
        if not r.lastMoveAt or not r.lastMovePos or T.distance2D(current,r.lastMovePos)>4 then
         r.lastMoveAt=now;r.lastMovePos=Live.copy(current)
        elseif now-r.lastMoveAt>=2 and (r.retries or 0)<3 then
         -- Same proven native movement call as delivery; only when the NPC is
         -- idle/safe, the route is valid, and its ordinary goal made no progress.
         local called,err=pcall(m.char.setDestination,m.char,p,false)
         r.retries=(r.retries or 0)+1;r.lastMoveAt=now
         Log.console('NPC_POST_RECOVERY member='..m.key..' attempt='..r.retries..'/3 native_move='..tostring(called)..' '..tostring(err or ''))
        end
       else r.lastMoveAt=nil;r.lastMovePos=nil;r.retries=0 end
      if ok then
       assigned=assigned+1
       emit(s,r,at and 'AT_POST' or 'MOVING_TO_POST','member='..m.key..' point='..T.fmt(p)..' floor='..tostring(floor or 'street'))
      else emit(s,r,at and 'AT_POST_HOLD_UNAVAILABLE' or 'GOAL_FAILED','member='..m.key..' '..tostring(why)) end
     end
    end
   end
  end
 end
 return assigned==#ms
end
function M.status(s)
 local d=s.duty;if not d then return 'PENDING'end
 local counts={};for _,r in pairs(d.members)do counts[r.state or 'PENDING']=(counts[r.state or 'PENDING'] or 0)+1 end
 local names={};for name,n in pairs(counts)do names[#names+1]=name..':'..n end;table.sort(names)
 return table.concat(names,',')
end
return M
