-- KenshiShop 0.3.0-alpha.23-appearance-only: six isolated building dispatchers (five original shops unchanged).
local Registry=require('Core.Registry')
local Log=require('Diagnostics')
local Construction=require('Construction')
local Ownership=require('Core.Ownership.Registry')
local M={version='1.0-beta.4'}
local started=false
local npcLoadedLogged={}
function M.start()
 if started then return end
 started=true
 local serviceOK,serviceStatus=pcall(function()return require('Core.Police.Services').start()end)
 if not serviceOK or serviceStatus~=true then Log.error('NPC_CHIEF_SERVICE_START '..tostring(serviceStatus))end
 Events.on('Building::_NV_notifyConstructionComplete',function(building)
  local ok,errorText=pcall(function()
   local shop=Registry.byBuilding(building)
   if shop then
    local observed,err=pcall(Ownership.onConstruction,shop.name,building)
    if not observed then Log.error('OWN_CONSTRUCTION_DISPATCH '..shop.name..' '..tostring(err)) end
    Log.info('CONSTRUCTION_MATCH '..shop.sid..' (independent '..shop.name..' queue)')
    shop.enqueue(building)
   end
  end)
  if not ok then Log.error('CONSTRUCTION_DISPATCH '..tostring(errorText)) end
 end)
 local ok,err=pcall(Events.on,'GameWorld::resetGame',function()
  require('Core.NPC.NativeNodes').resetSession()
  Registry.resetSession()
  Ownership.resetSession()
  require('Core.Ownership.NPCFurnitureRestore').resetSession()
  require('Core.Ownership.NPCFurnitureHandles').resetSession()
  require('Core.Ownership.NPCFurnitureCreate').resetSession()
  npcLoadedLogged={}
  Log.info('GAME_RESET: interior and NPC transient controllers cleared')
 end)
 if not ok then Log.error('GAME_RESET_HOOK_UNAVAILABLE '..tostring(err)) end
 Events.on('Building::_NV_onBuildingLoaded',function(building)
  local success,problem=pcall(function()
   local shop=Registry.byBuilding(building)
   if shop then
    Construction.observe(building,'building_loaded_no_furnish')
    -- Independent, bounded ownership/protection audit: no NPC creation.
    local audited,ownerError=pcall(Ownership.onLoaded,shop.name,building)
    if not audited then Log.error('OWN_LOAD_DISPATCH '..shop.name..' '..tostring(ownerError)) end
    local h=building:getHandle()
    local key=h and h:toString()
    if key and not npcLoadedLogged[key] then
      npcLoadedLogged[key]=true
      Log.console('NPC_BUILDING_LOADED shop='..shop.name..' building='..key..' no_auto_respawn; resume_existing_tracking_only')
    end
    -- Reattach saved NPC squads (read-only lookup); no spawn, appearance or outfit changes.
    local resumed,why=pcall(shop.npcResume,building)
    if not resumed then Log.error('NPC_RESUME_LOAD_EXCEPTION '..shop.name..' '..tostring(why)) end
    if shop.name=='bar' and shop.furnitureLoad then
      local okAudit,errAudit=pcall(shop.furnitureLoad,building)
      if not okAudit then Log.error('BAR_FURN_AUDIT_DISPATCH '..tostring(errAudit)) end
    end
   end
  end)
  if not success then Log.error('LOAD_DISPATCH '..tostring(problem)) end
 end)
 -- Ownership protection observes native faction changes AFTER the engine applies them.
 -- This never spawns NPC or edits movement; bounded repair runs on later frames.
 local factionHook,id=pcall(Events.on,'Building::_NV_setFaction',function(building)
  local ok,err=pcall(function()
   local shop=Registry.byBuilding(building)
   if shop then Ownership.onFactionChanged(shop.name,building) end
  end)
  if not ok then Log.error('OWN_FACTION_EVENT '..tostring(err)) end
 end)
 if not factionHook or not id then Log.error('OWN_FACTION_HOOK_UNAVAILABLE '..tostring(id)) end
 Log.info('version='..M.version..' architecture=per-shop Building/NPC; all-visible-members movement audit; no unsafe respawn; FCS role audit')
end
return M
