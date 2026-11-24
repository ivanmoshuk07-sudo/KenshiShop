-- Alpha.76 native movement-safety checks for delivery/load only.
-- A failed or missing state check never authorizes a forced order or teleport.
local M={}
local revision,closing=0,false
function M.newWorld() revision=revision+1;closing=false end
function M.closeWorld() closing=true end
function M.revision() return revision end
function M.call(obj,method,...)
 if not obj then return nil end
 local ok,fn=pcall(function()return obj[method]end)
 if not ok or type(fn)~='function' then return nil end
 local good,val=pcall(fn,obj,...)
 if good then return val end
 return nil
end
function M.readyWorld()
 if closing then return nil end
 local w=getGameWorld()
 if not w then return nil end
 -- Use GameWorld's flags. The engine's isLoadingFromASaveGame dereferences
 -- MainBarGUI and crashes on early frames before the main bar exists.
 local ok,initialized,resetting=pcall(function()return w.initialized,w.gameResetting end)
 if ok and initialized==true and resetting==false then return w end
end
function M.clock()
 local w=assert(getGameWorld(),'WORLD_MISSING')
 local stamp=assert(w:getTimeStamp_inGameHours(),'GAME_CLOCK_MISSING')
 local h=assert(stamp:getTotalHours(),'GAME_CLOCK_INVALID')
 assert(type(h)=='number' and h==h,'GAME_CLOCK_NOT_NUMERIC')
 return h*60
end
function M.copy(pos) return {x=pos.x,y=pos.y,z=pos.z} end
function M.halted(c)
 -- Treat unavailable status information as unsafe for disruptive commands.
 for _,m in ipairs({'isDead','isDown','isUnconcious','isCrippled','isBeingCarried'})do
  local v=M.call(c,m)
  if v==nil then return true,'UNKNOWN_'..m end
  if v then return true,m end
 end
 local combat=M.call(c,'isInCombatMode',true,true)
 if combat==nil then return true,'UNKNOWN_COMBAT' end
 if combat then return true,'COMBAT' end
 local fleeing=M.call(c,'isFleeing')
 if fleeing==nil then return true,'UNKNOWN_FLEEING' end
 if fleeing then return true,'FLEEING' end
 local carried=M.call(c,'getCarryingObject')
 local empty=carried and M.call(carried,'isNull')
 if empty==nil then return true,'UNKNOWN_CARRYING' end
 if not empty then return true,'CARRYING_PERSON' end
 return false,'OK'
end
function M.safeToOrder(ms)
 for _,m in ipairs(ms)do
  local halted,reason=M.halted(m.char)
  if halted then return false,m.key..':'..reason end
 end
 return true
end
return M
