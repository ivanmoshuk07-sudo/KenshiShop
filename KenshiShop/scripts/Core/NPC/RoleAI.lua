-- Native FCS goals: role work and emergency care. Lua only performs the handoff.
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local Nodes=require('Core.NPC.NativeNodes')
local Goals=require('Core.NPC.NativeGoals')
local Home=require('Core.NPC.HomeAssignment')
local Service=require('Core.NPC.ServiceTown')
local Origin=require('Core.NPC.OriginTown')
local M={}
function M.isWorkingPackage(cfg,name)
 local _,label=M.package(cfg)
 if not label then return false end
 for _,version in ipairs({'KS86','KS85','KS84','KS83','KS82'})do
  if name==label:gsub('KS86',version)then return true end
 end
 return name==({trader=(cfg.shop=='bar' or cfg.shop=='robotics') and 'KS Native Trader 24h' or 'KS Native Trader 06-23',guard='KS Native Indoor guards',chief='KS Native Police chief',patrol='KS Native Town patrol'})[cfg.role]
end
function M.package(cfg)
 if cfg.role=='trader' then
  if cfg.shop=='bar' or cfg.shop=='robotics' then return '8600-KenshiShop.mod','KS86 Trader 24h' end
  return '8601-KenshiShop.mod','KS86 Trader 06-23'
 elseif cfg.role=='guard' then return '8602-KenshiShop.mod','KS86 Indoor guards'
 elseif cfg.role=='chief' then return '8603-KenshiShop.mod','KS86 Police chief'
 elseif cfg.role=='patrol' then return '8604-KenshiShop.mod','KS86 Town patrol' end
end
local function say(s,event,why)
 Log.console('NPC_ROLE_'..event..' shop='..s.cfg.shop..' role='..s.cfg.role..' building='..s.key..' '..tostring(why or ''))
end
local function fail(s,r,why)
 r.tries=r.tries+1;say(s,'FAIL',tostring(why)..' attempt='..r.tries..'/3')
 return false
end
function M.ensure(s,ms)
 local id,label=M.package(s.cfg)
 if not id then return false end
 local ap=Live.call(s.platoon,'getActivePlatoon')
 local lead=ap and Live.call(ap,'getSquadLeader')
 local h=lead and Live.call(lead,'getHandle')
 local key=h and Live.call(h,'toString')
 if not key then return false end
 local r=s.work
 if not r or r.leader~=key then r={leader=key,tries=0,setup={}};s.work=r end
 local bb=Live.call(lead,'getBlackboard')
 local current=bb and Live.call(bb,'getCurrentAIPackageName')
 if r.installed and current==label and Service.verify(s,bb) then r.done=true;return true end
 if r.installed and current~=label then
  r.done=false
  if r.foreign~=current then say(s,'DEFER','NATIVE_PACKAGE_CHANGED '..tostring(current));r.foreign=current end
  return false -- do not replace a later native contract/emergency package
 end
 r.done=false
 if r.tries>=3 then return false end
 if r.installed and (r.missionDrifts or 0)>=3 then
  if not r.driftLimit then say(s,'FAIL','MISSION_REBIND_LIMIT max=3');r.driftLimit=true end
  return false
 end
 if not ms or #ms<1 or #ms>s.cfg.count or Live.call(ap,'getSquadSize')~=#ms then return false end
 local found=false
 for _,mate in ipairs(ms)do
  if mate.key==key then found=true end
  local busy,why=Live.halted(mate.char)
  local orders=Live.call(mate.char,'getOrdersReciever')
  if Live.call(orders,'hasOrders')~=false then busy=true;why='NATIVE_ORDERS_OR_UNKNOWN'end
  local active=Live.call(Live.call(orders,'getCurrentGoal'),'key')
  if ({[25]=true,[57]=true,[58]=true,[60]=true,[105]=true,[142]=true,[148]=true})[active] then busy=true;why='NATIVE_CARE_'..active end
  local carried=Live.call(mate.char,'getCarryingObject')
  if busy or not carried or Live.call(carried,'isNull')~=true then
   if not r.busyLogged then say(s,'DEFER',why or 'CARRYING_OR_UNKNOWN');r.busyLogged=true end
   return false
  end
 end
 if not found then return false end
 r.busyLogged=false
 local owns=Live.call(s.platoon,'getOwnerships')
 local ok,home=pcall(function()return owns._homeBuilding:toString()end)
 if not ok or home~=s.key then return false end -- ownership lifecycle may still be loading
 local old=bb and Live.call(bb,'getCurrentAIPackageName')
 if type(old)~='string' then return fail(s,r,'BLACKBOARD_UNAVAILABLE') end
 r.initialPackage=r.initialPackage or old
 local world=getGameWorld()
 local data=world and Live.call(world.gamedata,'getData',id,72)
 if not data then return fail(s,r,'PACKAGE_MISSING '..id) end
 -- Initialize member AI BEFORE installing the final package. An initializer
 -- must not later overwrite the selected work package or its home context.
 for _,mate in ipairs(ms)do
  if not r.setup[mate.key] then
   -- One-time cleanup of only alpha.82/.83 goals marked by this mod.
   -- Native goals and player orders are never globally cleared.
   for _,task in ipairs({1,30,5})do
    local _,removed=Goals.remove(mate.char,task)
    local active,orders=Goals.current(mate.char)
    if removed and active==task then Live.call(orders,'clearCurrentGoal',false)end
   end
   local yes,err=pcall(mate.char.setupPlatoonAI,mate.char)
   if not yes then return fail(s,r,'SETUP_FAILED '..mate.key..' '..tostring(err)) end
   r.setup[mate.key]=true
  end
 end
 if not r.homeDone then
  local yes,why=Home.ensure(s,ms,bb)
  if not yes then
   if why=='HOME_FACTION_NOT_READY' or why=='BUILDING_TOWN_UNAVAILABLE' then
    if r.homeWhy~=why then say(s,'WAIT_HOME',why);r.homeWhy=why end
    return false
   end
   return fail(s,r,'HOME_ASSIGN '..tostring(why))
  end
  r.homeDone=true
 end
 local nodeOK,nodeWhy=Nodes.ensure(s,s.building)
 if not nodeOK then
  if r.nodeWhy~=nodeWhy then say(s,'WAIT_NODES',nodeWhy);r.nodeWhy=nodeWhy end
  return false
 end
 if Live.call(bb,'getCurrentAIPackageName')~=label then
  -- AI-only migration preserves approved stock, including saved care packages.
  r.upgraded=false
  local yes,err=pcall(bb.replaceAIPackage,bb,data)
  if not yes then return fail(s,r,'ASSIGN_FAILED '..tostring(err)) end
 end
 if Live.call(bb,'getCurrentAIPackageName')~=label then return fail(s,r,'PACKAGE_VERIFY_FAILED') end
 if r.installed then r.missionDrifts=(r.missionDrifts or 0)+1 end
 local bound,why=Service.bind(s,bb)
 if not bound then return fail(s,r,'SERVICE_ASSIGN '..tostring(why)) end
 for _,mate in ipairs(ms)do
  local orders=Live.call(mate.char,'getOrdersReciever')
  local yes,err=pcall(function()orders:setNeedGOAP()end)
  if not yes then return fail(s,r,'GOAP_WAKE_FAILED '..mate.key..' '..tostring(err))end
 end
 r.done=true;r.installed=true
 say(s,'READY','package='..id..' label='..label..' service='..tostring(Origin.id(s.building:getTown()))..' native_care=58,57,148 gameplay=UNVERIFIED')
 return true
end
function M.status(s)
 local r=s.work
 local status=not r and 'PENDING' or (r.done and 'PACKAGE_READY' or ((r.tries>=3 or r.driftLimit) and 'FAILED' or 'WAIT_SAFE'))
 local own=Live.call(s.platoon,'getOwnerships')
 local ap=Live.call(s.platoon,'getActivePlatoon')
 local bb=Live.call(Live.call(ap,'getSquadLeader'),'getBlackboard')
 return status..' origin='..tostring(Origin.id(Origin.field(own,'_homeTown')))
  ..' service='..tostring(Origin.id(Live.call(s.building,'getTown')))
  ..' mission='..tostring(Origin.handleID(Live.call(bb,'getMissionTown',false)))
end
return M
