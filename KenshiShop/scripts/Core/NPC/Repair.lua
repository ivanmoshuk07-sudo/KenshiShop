-- KenshiShop alpha.80: original alpha.71 WorkStage native AI handoff, three vanilla goals: Medic 58, Robotics 57, Rescue 148.
-- FCS Robotics definition 7603 is BYTE-FOR-BYTE equivalent to alpha.71.
-- The old role packages had trading/guard/patrol goals and MUST NOT be brought back.
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local M={}
local ID='7604-KenshiShop.mod' -- existing repair-only package now includes two vanilla goals
local LABEL='KS Medic Robotics Rescue'
local MAX=3
local function say(s,event,msg)
 Log.console('NPC_REPAIR_'..event..' shop='..s.cfg.shop..' squad='..s.cfg.role..' building='..s.key..' '..(msg or ''))
end
local function memberPackage(c)
 local bb=Live.call(c,'getBlackboard')
 if not bb then return nil,nil,'BLACKBOARD_UNAVAILABLE' end
 local name=Live.call(bb,'getCurrentAIPackageName')
 if type(name)~='string' then return bb,nil,'PACKAGE_STATUS_UNAVAILABLE' end
 return bb,name,nil
end
local function leaderKey(s)
 local ap=Live.call(s.platoon,'getActivePlatoon')
 local lead=ap and Live.call(ap,'getSquadLeader')
 local h=lead and Live.call(lead,'getHandle')
 local id=h and Live.call(h,'toString')
 return id and tostring(id) or nil
end
local function carrying(c)
 local hand=Live.call(c,'getCarryingObject')
 if not hand then return nil,'CARRY_STATUS_UNAVAILABLE' end
 local null=Live.call(hand,'isNull')
 if null==nil then return nil,'CARRY_STATUS_UNAVAILABLE' end
 return not null, (null and 'NOT_CARRYING' or 'CARRYING_PERSON')
end
local function protected(c)
 local held,why=Live.halted(c)
 if held then return true,why end
 local carryingNow,carryWhy=carrying(c)
 if carryingNow==nil then return true,carryWhy end
 if carryingNow then return true,carryWhy end
 return false,'SAFE'
end

local function fail(s,r,why)
 r.tries=r.tries+1
 say(s,'FAIL','reason='..tostring(why)..' attempt='..r.tries..'/'..MAX)
 if r.tries>=MAX then say(s,'ABORT','bounded_retries_exhausted=true no_other_AI_changed=true') end
 return false
end
function M.ensure(s,ms)
 local r=s.repair or {tries=0,done=false};s.repair=r
 if r.done or r.tries>=MAX then return r.done end
 if not ms or #ms~=s.cfg.count then return fail(s,r,'SQUAD_MEMBERS_UNAVAILABLE') end
 local ap=s.platoon and Live.call(s.platoon,'getActivePlatoon')
 local lead=ap and Live.call(ap,'getSquadLeader')
 if not lead then return fail(s,r,'LEADER_UNAVAILABLE') end
 local leaderId=leaderKey(s)
 if not leaderId then return fail(s,r,'LEADER_HANDLE_UNAVAILABLE') end
 local leaderInMembers=false
 for _,mate in ipairs(ms) do if mate.key==leaderId then leaderInMembers=true;break end end
 if not leaderInMembers then return fail(s,r,'LEADER_NOT_IN_SQUAD') end
 local bb,old,err=memberPackage(lead)
 if err then return fail(s,r,err) end
 if old==LABEL then
  r.done=true
  say(s,'PRESERVED','package='..old..' native_tasks=Medic_58,Robotics_57,Rescue_148 existing=true gameplay=UNVERIFIED')
  return true
 end
 -- Original alpha.71 WorkStage never replaced a package during unsafe combat/carrying.
 for _,mate in ipairs(ms) do
  local busy,why=protected(mate.char)
  if busy then
   if not r.busyLogged then say(s,'DEFER','reason=SQUAD_BUSY '..tostring(why));r.busyLogged=true end
   return false
  end
 end
 r.busyLogged=false
 local world=getGameWorld()
 local data=world and world.gamedata and Live.call(world.gamedata,'getData',ID,72)
 if not data then return fail(s,r,'AI_PACKAGE_NOT_FOUND '..ID) end
 -- EXACT native replacement mechanism from original WorkStage.lua (alpha.71).
 local yes,whyReplace=pcall(bb.replaceAIPackage,bb,data)
 if not yes then return fail(s,r,'PACKAGE_ASSIGN_FAILED '..tostring(whyReplace)) end
 say(s,'JOB_REQUEST','package='..ID..' old='..tostring(old)..' reason=restored_native_handoff')
 local yesSetup,whySetup=pcall(lead.setupPlatoonAI,lead)
 if not yesSetup then return fail(s,r,'NATIVE_SETUP_FAILED '..tostring(whySetup)) end
 for _,mate in ipairs(ms) do
  if mate.key~=leaderId then
   local ok,why=pcall(mate.char.setupPlatoonAI,mate.char)
   if not ok then return fail(s,r,'MEMBER_SETUP_FAILED '..tostring(why)) end
  end
 end
 local _,after,errVerify=memberPackage(lead)
 if errVerify or after~=LABEL then
  return fail(s,r,'PACKAGE_NOT_VERIFIED '..tostring(errVerify or after))
 end
 r.done=true
 say(s,'JOB_VERIFY','state=PACKAGE_PRESENT package='..after..' tasks=Medic_58,original_Robotics_57,Rescue_148 gameplay=UNVERIFIED')
 return true
end
return M
