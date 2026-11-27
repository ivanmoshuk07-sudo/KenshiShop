local Config=require('Core.Police.Services.Config')
local Controller=require('Core.NPC.Controller')
local ConstructionGate=require('Core.Ownership.ConstructionGate')
local Live=require('Core.NPC.LiveState')
local driver=Controller.new(Config.copy(Config.undertaker))
local start,resume=driver.start,driver.resume

function driver.start(building)
 local ready,why=ConstructionGate.ready(building)
 if not ready then return false,why end
 local town=Live.call(building,'getTown')
 if Live.call(Live.call(town,'getFaction'),'isThePlayer')~=true then
  return false,'CREMATORIUM_REQUIRES_PLAYER_TOWN'
 end
 return start(building)
end

function driver.resume(building)
 local ready,why=ConstructionGate.ready(building)
 if not ready and (why~='BUILD_STATE_UNAVAILABLE' or Live.call(building,'isCreated')~=true) then return false,why end
 return resume(building)
end

return driver
