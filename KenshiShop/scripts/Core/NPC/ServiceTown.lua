-- Same mission-town channel used by native defend-player-base contracts.
local O=require('Core.NPC.OriginTown')
local M={}
function M.verify(s,bb)
 local service=O.call(s.building,'getTown')
 local expected=O.id(service)
 local package=O.call(bb,'getCurrentPackage')
 if not expected or O.handleID(O.field(package,'missionTown'))~=expected then return false end
 -- targetTown alone does not participate in this native resolver.
 return O.handleID(O.call(bb,'getMissionTown',false))==expected
  and O.handleID(O.call(bb,'getMissionTown',true))==expected
end
function M.bind(s,bb)
 local ok,err=pcall(function()
  local town=assert(s.building:getTown(),'SERVICE_TOWN_MISSING')
  assert(O.call(O.call(town,'getFaction'),'isThePlayer')==true,'SERVICE_TOWN_NOT_PLAYER')
  local package=assert(bb:getCurrentPackage(),'CURRENT_PACKAGE_MISSING')
  package.missionTown=town:getHandle()
  assert(M.verify(s,bb),'MISSION_TOWN_NOT_APPLIED expected='..tostring(O.id(town))
   ..' actual='..tostring(O.handleID(O.call(bb,'getMissionTown',false))))
 end)
 return ok,ok and nil or tostring(err)
end
return M
