-- alpha.69: safe compatibility diagnostics for the engineering shop's
-- independent 1-person trader and 2-person guard platoons.
-- The obsolete 3-person teleport test was disabled before alpha.68.
-- Do NOT revive its teleport, destination setters, or per-frame movement hooks.
local Split=require('Core.NPC.SplitAudit')
local M={}
function M.check(building)
 local report,state=Split.check(building)
 local id=building:getGameData()
 if not id or tostring(id.stringID)~='101-KenshiShop.mod' then
  return 'RECOVERY_CHECK engineering ready=false reason=NOT_ENGINEERING_BUILDING no_spawn'
 end
 return 'RECOVERY_CHECK engineering split_state='..tostring(state)..' '..report..' no_spawn no_teleport'
end
function M.start()
 return 'RECOVERY_START_DISABLED integrated_delivery_active; separate trader/guard squads; no_second_controller'
end
function M.status()
 return 'RECOVERY_STATUS legacy_manual_teleport_DISABLED; use KS.recoveryCheck(index), KS.npcStatus(index), KS.npcLogs(120)'
end
function M.cancel()return 'RECOVERY_CANCEL nothing_running; manual_controller_disabled' end
function M.history()return 'RECOVERY_LOG_EMPTY legacy_controller_disabled; use KS.npcLogs(120)' end
return M
