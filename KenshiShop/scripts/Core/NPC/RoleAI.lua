-- Native FCS goals: role work and emergency care. Lua only performs the handoff.
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local Nodes=require('Core.NPC.NativeNodes')
local Goals=require('Core.NPC.NativeGoals')
local M={}
function M.isWorkingPackage(cfg,name)
 local _,label=M.package(cfg)
 return label~=nil and (name==label or name==label:gsub('KS84','KS83') or name==label:gsub('KS84','KS82') or name==({trader=(cfg.shop=='bar' or cfg.shop=='robotics') and 'KS Native Trader 24h' or 'KS Native Trader 06-23',guard='KS Native Indoor guards',chief='KS Native Police chief',patrol='KS Native Town patrol'})[cfg.role])
end
function M.package(cfg)
 if cfg.role=='trader' then
  if cfg.shop=='bar' or cfg.shop=='robotics' then return '8400-KenshiShop.mod','KS84 Trader 24h' end
  return '8401-KenshiShop.mod','KS84 Trader 06-23'
 elseif cfg.role=='guard' then return '8402-KenshiShop.mod','KS84 Indoor guards'
 elseif cfg.role=='chief' then return '8403-KenshiShop.mod','KS84 Police chief'
 elseif cfg.role=='patrol' then return '8404-KenshiShop.mod','KS84 Town patrol' end
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
 if r.done then return true end
 if r.tries>=3 then return false end
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
 local bb=Live.call(lead,'getBlackboard')
 local old=bb and Live.call(bb,'getCurrentAIPackageName')
 if type(old)~='string' then return fail(s,r,'BLACKBOARD_UNAVAILABLE') end
 local nodeOK,nodeWhy=Nodes.ensure(s,s.building)
 if not nodeOK then
  if r.nodeWhy~=nodeWhy then say(s,'WAIT_NODES',nodeWhy);r.nodeWhy=nodeWhy end
  return false
 end
 local world=getGameWorld()
 -- Native town goals must use this settlement, including restored squads.
 local town=Live.call(s.building,'getTown')
 if not town then return fail(s,r,'HOME_TOWN_UNAVAILABLE')end
 local ownList={owns}
 for _,mate in ipairs(ms)do
  local memberOwns=Live.call(mate.char,'getOwnerships')
  if not memberOwns then return fail(s,r,'MEMBER_OWNERSHIPS_UNAVAILABLE')end
  ownList[#ownList+1]=memberOwns
 end
 local homeTown=Live.call(Live.call(town,'getHandle'),'toString')
 if not homeTown then return fail(s,r,'HOME_TOWN_HANDLE_UNAVAILABLE')end
 for _,o in ipairs(ownList)do
  local current=Live.call(Live.call(o._homeTown,'getHandle'),'toString')
  if current~=homeTown then
   local yes,err=pcall(o.setHomeTown,o,town,1)
   if not yes or Live.call(Live.call(o._homeTown,'getHandle'),'toString')~=homeTown then return fail(s,r,'HOME_TOWN_ASSIGN '..tostring(err))end
  end
 end
 local targetOK,targetError=pcall(function()bb.targetTown=town end)
 if not targetOK then return fail(s,r,'TARGET_TOWN_ASSIGN '..tostring(targetError))end
 local data=world and Live.call(world.gamedata,'getData',id,72)
 if not data then return fail(s,r,'PACKAGE_MISSING '..id) end
 if old~=label then
  r.upgraded=true
  local yes,err=pcall(bb.replaceAIPackage,bb,data)
  if not yes then return fail(s,r,'ASSIGN_FAILED '..tostring(err)) end
  r.setup={}
 end
 -- Verify and finish every member even if an earlier attempt partially succeeded.
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
   local orders=Live.call(mate.char,'getOrdersReciever')
   if orders and (s.cfg.role=='guard' or s.cfg.role=='patrol' or s.cfg.role=='chief')then pcall(function()orders.aggroMode=1 end)end
   Live.call(orders,'setNeedGOAP')
  end
 end
 if Live.call(bb,'getCurrentAIPackageName')~=label then return fail(s,r,'PACKAGE_VERIFY_FAILED') end
 r.done=true
 say(s,'READY','package='..id..' label='..label..' native_care=58,57,148 gameplay=UNVERIFIED')
 return true
end
function M.status(s)
 local r=s.work
 return not r and 'PENDING' or (r.done and 'PACKAGE_READY' or (r.tries>=3 and 'FAILED' or 'WAIT_SAFE'))
end
return M
