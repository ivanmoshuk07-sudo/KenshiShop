-- KenshiShop alpha.34. Delayed one-shot/three-try read-only bar furniture audit.
local Log=require('Diagnostics')
local M={}
local states={}
local MAX_ATTEMPTS=3
local STEP_FRAMES=45
function M.loaded(b)
 local h=b:getHandle()
 local k=h:toString()
 if states[k] and states[k].hook then
  local old=states[k].hook;Events.off(old)
 end
 local s={key=k,handle=h,frame=0,tries=0}
 states[k]=s
 local ok,id=pcall(Events.on,'MyGUI::Gui::eventFrameStart',function()
  s.frame=s.frame+1
  if s.frame~=1 and s.frame%STEP_FRAMES~=0 then return end
  local valid,building=pcall(s.handle.getBuilding,s.handle)
  if not valid or not building then
   Log.error('BAR_FURN_LOAD_AUDIT building='..k..' UNLOADED; no_modifications')
   if s.hook then Events.off(s.hook);s.hook=nil end
   states[k]=nil;return
  end
  s.tries=s.tries+1
  local good,pass,report=pcall(function() return require('Core.Ownership.Furniture').auditBar(building) end)
  if good then
   Log.console('BAR_FURN_LOAD_AUDIT building='..k..' attempt='..s.tries
    ..' status='..(pass and 'PASS' or 'INCOMPLETE')..' '..tostring(report)..' read_only=true')
  else
   Log.error('BAR_FURN_LOAD_AUDIT building='..k..' attempt='..s.tries
    ..' EXCEPTION='..tostring(pass)..' read_only=true')
  end
  if (good and pass) or s.tries>=MAX_ATTEMPTS then
   if s.hook then Events.off(s.hook);s.hook=nil end
   states[k]=nil
  end
 end)
 if ok and id then s.hook=id
 else states[k]=nil;Log.error('BAR_FURN_AUDIT_HOOK_FAIL '..k..' '..tostring(id))end
end
function M.resetSession()
 for _,s in pairs(states)do if s.hook then Events.off(s.hook) end end
 states={}
end
return M
