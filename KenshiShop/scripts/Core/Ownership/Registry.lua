-- Read-only registry/dispatcher: each store owns its own lifecycle state.
local modules={
 bar=require('Core.Bar.Building.Ownership'),
 engineering=require('Core.Engineering.Building.Ownership'),
 armour=require('Core.Armour.Building.Ownership'),
 weapons=require('Core.Weapons.Building.Ownership'),
 robotics=require('Core.Robotics.Building.Ownership'),
 police=require('Core.Police.Building.Ownership'),
 crematorium=require('Core.Crematorium.Ownership'),
}
local history={}
local MAX_LINES=400
local M={}
-- Shared log buffer only. NPC and shop ownership states are NOT shared.
function M.record(s)
 history[#history+1]=s
 if #history>MAX_LINES then table.remove(history,1) end
end
function M.onConstruction(shop,building)
 local m=modules[shop]
 if not m then return false,'NO_SHOP_OWNERSHIP_MODULE' end
 m.onConstruction(building)
 return true
end
function M.onRestored(shop,role,building,platoon)
 local m=modules[shop]
 if not m then return false,'NO_SHOP_OWNERSHIP_MODULE' end
 return m.restored(role,building,platoon)
end
function M.onSpawned(shop,role,building,platoon)
 local m=modules[shop]
 if not m then return false,'NO_SHOP_OWNERSHIP_MODULE' end
 return m.spawned(role,building,platoon)
end
function M.onArrived(shop,role,building,platoon)
 local m=modules[shop]
 if not m then return false,'NO_SHOP_OWNERSHIP_MODULE' end
 return m.arrived(role,building,platoon)
end
function M.onLoaded(shop,building)
 local m=modules[shop]
 if not m then return false,'NO_SHOP_OWNERSHIP_MODULE' end
 m.onLoaded(building)
 return true
end
function M.onFactionChanged(shop,building)
 local m=modules[shop]
 if not m then return false,'NO_SHOP_OWNERSHIP_MODULE' end
 return m.onFactionChanged(building)
end
-- Existing trader controller calls this on its game-clock audit; no extra hook.
function M.monitorResident(shop,building,now)
 local m=modules[shop]
 if not m or not m.monitorResident then return false,'SHOP_MONITOR_UNAVAILABLE' end
 return m.monitorResident(building,now)
end
function M.retire(shop,buildingID)
 local m=modules[shop]
 if not m then return end
 m.retire(buildingID)
 if shop=='bar' then
  require('Core.Bar.Building.FurnitureRestore').retire(buildingID)
  require('Core.Bar.Building.LiveFurniture').retire(buildingID)
 else
  require('Core.Ownership.NPCFurnitureRestore').retire(buildingID)
  require('Core.Ownership.NPCFurnitureHandles').retire(buildingID)
  require('Core.Ownership.NPCFurnitureCreate').retire(buildingID)
 end
end
function M.audit(shop,building)
 local m=modules[shop]
 if not m then return 'OWN_SHOP_UNAVAILABLE '..tostring(shop) end
 return m.audit(building)
end
function M.logs(n)
 n=math.max(1,math.min(MAX_LINES,math.floor(tonumber(n) or 80)))
 local result={}
 for i=math.max(1,#history-n+1),#history do result[#result+1]=history[i] end
 return result
end
function M.resetSession()
 for _,m in pairs(modules)do m.resetSession()end
 history={}
end
return M
