-- Native FCS goals: role work and emergency care. Lua only performs the handoff.
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local M={}
function M.package(cfg)
 if cfg.role=='trader' then
  if cfg.shop=='bar' or cfg.shop=='robotics' then return '8100-KenshiShop.mod','KS Native Trader 24h' end
  return '8101-KenshiShop.mod','KS Native Trader 06-23'
 elseif cfg.role=='guard' then return '8102-KenshiShop.mod','KS Native Indoor guards'
 elseif cfg.role=='chief' then return '8103-KenshiShop.mod','KS Native Police chief'
 elseif cfg.role=='patrol' then return '8104-KenshiShop.mod','KS Native Town patrol' end
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
 local world=getGameWorld()
 local data=world and Live.call(world.gamedata,'getData',id,72)
 if not data then return fail(s,r,'PACKAGE_MISSING '..id) end
 if old~=label then
  local yes,err=pcall(bb.replaceAIPackage,bb,data)
  if not yes then return fail(s,r,'ASSIGN_FAILED '..tostring(err)) end
  r.setup={}
 end
 -- Verify and finish every member even if an earlier attempt partially succeeded.
 for _,mate in ipairs(ms)do
  if not r.setup[mate.key] then
   local yes,err=pcall(mate.char.setupPlatoonAI,mate.char)
   if not yes then return fail(s,r,'SETUP_FAILED '..mate.key..' '..tostring(err)) end
   r.setup[mate.key]=true
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
