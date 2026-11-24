-- KenshiShop 0.3.0-alpha.22-skeleton-squads: independent shop interior plus scheduled NPC squads.
local SID='104-KenshiShop.mod'
local Log=require('Diagnostics')
local Retirement=require('Core.Ownership.Retirement')
local Interior=require('Core.Robotics.Building.Interior')
local NPC=require('Core.Robotics.NPC.init')
local M={sid=SID,npcStart=NPC.start,npcResume=NPC.resume,npcStatus=NPC.status,npcCheck=NPC.check,name='robotics',manifest=require('Core.Robotics.Manifest'),interior=Interior}
local pending={}
local frameHook=nil
function M.enqueue(building)
 local d=building and building:getGameData()
 if not d or tostring(d.stringID)~=SID then return false end
 local h=building:getHandle()
 pending[h:toString()]=h
 if frameHook then return true end
 frameHook=Events.on('MyGUI::Gui::eventFrameStart',function()
  local previous=frameHook;frameHook=nil
  if previous then Events.off(previous) end
  local work=pending;pending={}
  for key,handle in pairs(work) do
   local ok,problem=pcall(function()
    if Retirement.retired(key) then return end
    local b=handle:getBuilding()
    if not b or not b:isValid() then return end
    local result
    if b:getNumInternalBuildings()>=Interior.expectedInternalCount() then
      result={status='INTERIOR_ALREADY_FURNISHED'}
      Log.info('INTERIOR_REUSED shop=robotics: existing furniture untouched')
    else
      result=Interior.complete(b)
    end
    if result and result.status=='INTERIOR_ALREADY_FURNISHED' then
      Log.console('NPC_SPAWN_SKIP shop=robotics building='..key..' reason=EXISTING_INTERIOR_ALREADY_FURNISHED; spawn_suppressed_on_load')
    elseif result and result.status=='INTERIOR_DONE' then
      Log.info('INTERIOR_ROBOTICS_RESULT '..tostring(result.status)..'; scheduling skeleton squads in game clock')
      local okRestore,whyRestore=require('Core.Ownership.NPCFurnitureRestore').request(b,'POST_CREATE')
      Log.console('NPC_FURN_POST_CREATE shop=robotics building='..key
       ..' status='..tostring(okRestore)..' reason='..tostring(whyRestore))
      Log.console('NPC_AUTO_START shop=robotics building='..key..' after_interior_ready; first_after_1_game_minute; next_after_5_more_minutes')
      NPC.start(b)
    else
      Log.error('INTERIOR_ROBOTICS_NOT_READY '..tostring(result and result.status))
    end
   end)
   if not ok then Log.error('CONSTRUCTION_ROBOTICS_ERROR '..key..' '..tostring(problem)) end
  end
 end)
 return true
end
function M.resetSession()
 if frameHook then Events.off(frameHook);frameHook=nil end
 pending={}
 NPC.resetSession()
 Interior.resetSession()
end
return M
