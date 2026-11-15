-- Keep native NPC home town; assign the player's service building separately.
local Live=require('Core.NPC.LiveState')
local Origin=require('Core.NPC.OriginTown')
local Log=require('Diagnostics')
local M={}
local function factionID(o)
 return Origin.field(Live.call(Live.call(o,'getFaction'),'getData'),'stringID')
end
function M.ensure(s,ms,bb)
 local p,b=s.platoon,s.building
 if Origin.id(b)~=s.key then return false,'BUILDING_HANDLE_UNAVAILABLE' end
 if factionID(p)~=s.cfg.faction or factionID(b)~=s.cfg.faction then return false,'HOME_FACTION_NOT_READY' end
 local service=Live.call(b,'getTown')
 if not Origin.id(service) then return false,'BUILDING_TOWN_UNAVAILABLE' end
 if Live.call(Live.call(service,'getFaction'),'isThePlayer')~=true then return false,'SERVICE_TOWN_NOT_PLAYER' end
 local owns=Live.call(p,'getOwnerships')
 local origin,source=Origin.select(Live.call(p,'getFaction'),Live.call(b,'getPosition'),Origin.field(owns,'_homeTown'))
 if not origin then return false,source end
 local kind=(SquadType and SquadType.SQ_RESIDENT) or 1
 local ok,err=pcall(function()
  assert(owns,'PLATOON_OWNERSHIPS_UNAVAILABLE')
  if p:getSquadType()~=kind then p:setSquadType(kind)end
  assert(p:getSquadType()==kind,'RESIDENT_TYPE_NOT_APPLIED')
  origin=Origin.assign(owns,origin,kind)
  -- Older builds passed player_town_template as the native base town data.
  -- Match the real origin so native persistent-squad validation agrees.
  local data=assert(origin:getGameData(),'ORIGIN_DATA_UNAVAILABLE')
  if Origin.field(p.myBaseHomeTownData,'stringID')~=data.stringID then p.myBaseHomeTownData=data end
  assert(Origin.field(p.myBaseHomeTownData,'stringID')==data.stringID,'ORIGIN_BASE_DATA_NOT_APPLIED')
  local seen={[owns]=Origin.id(origin)}
  for _,mate in ipairs(ms)do
   local c=mate.char
   local state=assert(c:getStateBroadcast(),'MEMBER_STATE_UNAVAILABLE '..mate.key)
   state.homeBuilding=b:getHandle()
   assert(Origin.handleID(state.homeBuilding)==s.key,'MEMBER_STATE_HOME_NOT_APPLIED '..mate.key)
   local own=assert(c:getOwnerships(),'MEMBER_OWNERSHIPS_UNAVAILABLE '..mate.key)
   if not seen[own]then seen[own]=Origin.id(Origin.assign(own,origin,kind))end
   own:setHomeBuilding(b:getHandle(),kind)
   -- Native setHomeBuilding also tries setHomeTown. Its player-status guard
   -- must preserve the existing NPC origin; do not bypass it.
   assert(Origin.handleID(own._homeBuilding)==s.key,'MEMBER_HOME_NOT_APPLIED '..mate.key)
   assert(Origin.id(own._homeTown)==seen[own],'MEMBER_ORIGIN_CHANGED '..mate.key)
  end
  owns:setHomeBuilding(b:getHandle(),kind)
  assert(Origin.handleID(owns._homeBuilding)==s.key,'HOME_BUILDING_NOT_APPLIED')
  assert(Origin.id(owns._homeTown)==Origin.id(origin),'PLATOON_ORIGIN_CHANGED')
  bb.targetTown=service -- compatibility context; not the mission resolver
  assert(Origin.id(bb.targetTown)==Origin.id(service),'TARGET_TOWN_NOT_APPLIED')
 end)
 if not ok then return false,tostring(err) end
 Log.console('NPC_HOME86 shop='..s.cfg.shop..' role='..s.cfg.role..' building='..s.key
  ..' origin='..Origin.id(origin)..' service='..Origin.id(service)..' source='..source
  ..' resident_type='..kind..' member_homes='..#ms..' verified=true')
 return true
end
return M
