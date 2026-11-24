-- KenshiShop 0.3.0-alpha.22-skeleton-squads: independent shop interior plus scheduled NPC squads.
local SID='100-KenshiShop.mod'
local Log=require('Diagnostics')
local Retirement=require('Core.Ownership.Retirement')
local Interior=require('Core.Bar.Building.Interior')
local ConstructionGate=require('Core.Ownership.ConstructionGate')
local LoadAudit=require('Core.Bar.Building.LoadAudit')
local LiveFurniture=require('Core.Bar.Building.LiveFurniture')
local Restore=require('Core.Bar.Building.FurnitureRestore')
local NPC=require('Core.Bar.NPC.init')
local M={sid=SID,npcStart=NPC.start,npcResume=NPC.resume,npcStatus=NPC.status,npcCheck=NPC.check,name='bar',manifest=require('Core.Bar.Manifest'),interior=Interior, furnitureLoad=LoadAudit.loaded}
local pending={}
local frameHook=nil
local LIMIT_FRAMES=480
function M.enqueue(building)
 local d=building and building:getGameData()
 if not d or tostring(d.stringID)~=SID then return false end
 local h=building:getHandle()
 local key=h:toString()
 if not pending[key] then pending[key]={handle=h,frames=0,reason=nil} end
 if frameHook then return true end
 frameHook=Events.on('MyGUI::Gui::eventFrameStart',function()
  for k,s in pairs(pending) do
   s.frames=s.frames+1
   local ok,problem=pcall(function()
    if Retirement.retired(k) then pending[k]=nil;return end
    local b=s.handle:getBuilding()
    if not b or not b:isValid() then pending[k]=nil;return end
    local ready,why=ConstructionGate.ready(b)
    if not ready then
     if why~=s.reason then
      s.reason=why
      Log.console('BAR_CONSTRUCTION_WAIT building='..k..' reason='..tostring(why)..' no_furniture_or_NPC')
     end
     if s.frames>=LIMIT_FRAMES then
      Log.error('BAR_CONSTRUCTION_TIMEOUT building='..k..' reason='..tostring(why)..' frames='..s.frames..' stopped_no_spawn')
      pending[k]=nil
     end
     return
    end
    pending[k]=nil
    Log.console('BAR_CONSTRUCTION_READY building='..k..' after_materials_verified=true frames='..s.frames)
    local result
    if b:getNumInternalBuildings()>=Interior.expectedInternalCount() then
     result={status='INTERIOR_ALREADY_FURNISHED'}
     Log.info('INTERIOR_REUSED shop=bar: existing furniture untouched')
    else
     result=Interior.complete(b)
    end
    if result and result.status=='INTERIOR_ALREADY_FURNISHED' then
     Log.console('NPC_SPAWN_SKIP shop=bar building='..k..' reason=EXISTING_INTERIOR_ALREADY_FURNISHED; spawn_suppressed_on_load')
    elseif result and (result.status=='INTERIOR_DONE' or result.status=='INTERIOR_OWNER_PARTIAL') then
     Log.info('INTERIOR_BAR_RESULT '..tostring(result.status)..'; scheduling skeleton squads in game clock')
     local queued,detail=Restore.request(b,'POST_CREATE')
     Log.console('BAR_SPLIT_POST_CREATE status='..(queued and 'QUEUED' or 'ERROR')..' '..tostring(detail))
     if result.status=='INTERIOR_OWNER_PARTIAL' then
      Log.error('BAR_FURN_OWNER_CHECK_FAILED building='..k..' review BAR_FURN_OWNER_MISMATCH; NPC spawning remains independent')
     end
     Log.console('NPC_AUTO_START shop=bar building='..k..' after_interior_ready; first_after_1_game_minute; next_after_5_more_minutes')
     NPC.start(b)
    else
     Log.error('INTERIOR_BAR_NOT_READY '..tostring(result and result.status)..' no_NPC_spawn')
    end
   end)
   if not ok then pending[k]=nil;Log.error('CONSTRUCTION_BAR_ERROR '..k..' '..tostring(problem)) end
  end
  if not next(pending) and frameHook then
   local old=frameHook;frameHook=nil;Events.off(old)
  end
 end)
 return true
end
function M.resetSession()
 if frameHook then Events.off(frameHook);frameHook=nil end
 pending={}
 NPC.resetSession()
 Interior.resetSession()
 LoadAudit.resetSession()
 LiveFurniture.resetSession()
 Restore.resetSession()
end
return M
