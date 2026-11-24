-- A confirmed departure can resume from native save data. Each retry resolves
-- the old tower and squads again. No engine object is stored in the plan.
local Store=require('Core.Police.Services.Store')
local Roster=require('Core.Police.Services.Roster')
local Live=require('Core.NPC.LiveState')
local Evacuees=require('Core.Police.Services.Evacuees')
local PropertyReturn=require('Core.Police.Services.PropertyReturn')
local M={}
local attempts={}
local RETRY_MINUTES=5
local function id(object)return Live.call(Live.call(object,'getHandle'),'toString')end

function M.begin(ctx)
 if not Store.evacuationReady() then return false,'EVACUATION_SAVE_UNAVAILABLE' end
 if Store.evacuation(ctx.town) then return false,'EVACUATION_ALREADY_STARTED' end
 local property,why=PropertyReturn.prepare(ctx)
 if not property then return false,why end
 local squads,reason=Evacuees.plan(ctx,property.buildings)
 if not squads then return false,reason end
 -- Record the exact scope before stopping normal duty or changing ownership.
 return Store.beginEvacuation(ctx.town,{
  anchor=ctx.key,buildings=property.buildings,property=property.property,squads=squads,
 })
end

function M.reset() attempts={} end

function M.tick(now,report,notify,stopServices)
 if not Store.evacuationReady() then return end
 for townID,plan in pairs(Store.get().evacuations or {})do
  local retry=attempts[townID]
  if not retry or now<retry.at or now-retry.at>=RETRY_MINUTES then
   retry=retry or {progress={}}
   retry.at=now;attempts[townID]=retry
   local function step()
    local tower=Roster.building(plan.anchor)
    local town=Live.call(tower,'getTown')
    if id(town)~=townID or Live.call(Live.call(town,'getFaction'),'isThePlayer')~=true then
     return false,'EVACUATION_TOWN_LOADING'
    end
    local ctx={building=tower,key=plan.anchor,town=townID,townObject=town}
    if not retry.stopped then stopServices(townID,plan);retry.stopped=true end
    if not plan.departed then
     local left,why=Evacuees.step(ctx,plan.squads,retry.progress,now)
     if not left then return false,why end
     plan.departed=true
    end
    local returned,why=PropertyReturn.apply(ctx,plan.buildings,plan.property,plan.squads)
    if not returned then return false,why end
    return Store.finishEvacuation(townID)
   end
   local ok,done,why=pcall(step)
   if ok and done then
    attempts[townID]=nil
    report('EVACUATION_COMPLETE','town='..townID)
    notify('Сотрудники покинули город. Здания и мебель переданы игроку, записи города очищены.')
   else
    local status=tostring(ok and why or done)
    if retry.status~=status then report('EVACUATION_PENDING','town='..townID..' reason='..status);retry.status=status end
   end
   -- One saved departure per update, even if several cities are pending.
   return
  end
 end
end

return M
