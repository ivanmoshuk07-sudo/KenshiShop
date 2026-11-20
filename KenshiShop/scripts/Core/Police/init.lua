-- KenshiShop alpha.41: native Watchtower police tower construction, 1 chief squad + 1 patrol squad.
local SID='105-KenshiShop.mod'
local Log=require('Diagnostics')
local Interior=require('Core.Police.Building.Interior')
local ConstructionGate=require('Core.Ownership.ConstructionGate')
local Restore=require('Core.Ownership.NPCFurnitureRestore')
local NPC=require('Core.Police.NPC.init')
local M={sid=SID,npcStart=NPC.start,npcResume=NPC.resume,npcStatus=NPC.status,npcCheck=NPC.check,name='police',manifest=require('Core.Police.Manifest'),interior=Interior}
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
    local b=s.handle:getBuilding()
    if not b or not b:isValid() then pending[k]=nil;return end
    local ready,why=ConstructionGate.ready(b)
    if not ready then
     if why~=s.reason then
      s.reason=why
      Log.console('POLICE_CONSTRUCTION_WAIT building='..k..' reason='..tostring(why)..' no_furniture_or_NPC')
     end
     if s.frames>=LIMIT_FRAMES then
      Log.error('POLICE_CONSTRUCTION_TIMEOUT building='..k..' reason='..tostring(why)..' frames='..s.frames..' stopped_no_spawn')
      pending[k]=nil
     end
     return
    end
    pending[k]=nil
    Log.console('POLICE_CONSTRUCTION_READY building='..k..' after_materials_verified=true frames='..s.frames)
    local result
    if b:getNumInternalBuildings()>=Interior.expectedInternalCount() then
     result={status='INTERIOR_ALREADY_FURNISHED'}
     Log.info('INTERIOR_REUSED shop=police: existing furniture untouched')
    else
     result=Interior.complete(b)
    end
    if result and result.status=='INTERIOR_ALREADY_FURNISHED' then
     Log.console('NPC_SPAWN_SKIP shop=police building='..k..' reason=EXISTING_INTERIOR_ALREADY_FURNISHED; spawn_suppressed_on_load')
    elseif result and (result.status=='INTERIOR_DONE') then
     Log.info('INTERIOR_POLICE_RESULT '..tostring(result.status)..'; scheduling skeleton squads in game clock')
     local queued,detail=Restore.request(b,'POLICE_POST_CREATE')
     Log.console('POLICE_FURN_POST_CREATE status='..(queued and 'QUEUED' or 'ERROR')..' '..tostring(detail))
     Log.console('NPC_AUTO_START shop=police building='..k..' after_interior_ready; first_after_1_game_minute; next_after_5_more_minutes')
     NPC.start(b)
    else
     Log.error('INTERIOR_POLICE_NOT_READY '..tostring(result and result.status)..' no_NPC_spawn')
    end
   end)
   if not ok then pending[k]=nil;Log.error('CONSTRUCTION_POLICE_ERROR '..k..' '..tostring(problem)) end
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
end
return M
