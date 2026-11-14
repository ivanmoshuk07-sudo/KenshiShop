-- Native residence handoff, using the same ownership and StateBroadcastData
-- APIs as Squad Autonomy. Never write ownership pointers or player-faction flags.
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local M={}
local function field(o,k)
 local ok,v=pcall(function()return o[k]end)
 if ok then return v end
end
local function identity(o)
 local h=Live.call(o,'getHandle')
 if not h or Live.call(h,'isNull')==true then return nil end
 return Live.call(h,'toString')
end
local function home(o)return Live.call(field(o,'_homeBuilding'),'toString')end
local function townID(o)return identity(field(o,'_homeTown'))end
local function factionID(o)
 local data=Live.call(Live.call(o,'getFaction'),'getData')
 return field(data,'stringID')
end
function M.ensure(s,ms,bb)
 local p,b=s.platoon,s.building
 local expected=identity(b)
 if not expected or expected~=s.key then return false,'BUILDING_HANDLE_UNAVAILABLE' end
 if factionID(p)~=s.cfg.faction or factionID(b)~=s.cfg.faction then
  return false,'HOME_FACTION_NOT_READY'
 end
 local buildingTown=Live.call(b,'getTown')
 local expectedTown=identity(buildingTown)
 if not expectedTown then return false,'BUILDING_TOWN_UNAVAILABLE' end
 -- A current town is usable only when it is the target building's town.
 -- Restored patrols/rescuers may currently be elsewhere; never move their home.
 local current=Live.call(bb,'getCurrentTownLocation')
 local town=identity(current)==expectedTown and current or buildingTown
 local source=town==current and 'BLACKBOARD_CURRENT' or 'BUILDING_TOWN'
 local kind=(SquadType and SquadType.SQ_RESIDENT) or 1
 if Live.call(p,'getSquadType')==nil then return false,'SQUAD_TYPE_UNAVAILABLE' end
 local ok,err=pcall(function()
  if p:getSquadType()~=kind then p:setSquadType(kind)end
  assert(p:getSquadType()==kind,'RESIDENT_TYPE_NOT_APPLIED')
  local owns=assert(p:getOwnerships(),'PLATOON_OWNERSHIPS_UNAVAILABLE')
  -- Call the native building setter even for a restored matching handle. It
  -- refreshes the native home context; raw _homeBuilding assignments are avoided.
  owns:setHomeBuilding(b:getHandle(),p:getSquadType())
  assert(home(owns)==s.key,'HOME_BUILDING_NOT_APPLIED')
  if townID(owns)~=expectedTown then owns:setHomeTown(town,p:getSquadType())end
  local actual=townID(owns)
  assert(actual==expectedTown,'HOME_TOWN_NOT_APPLIED expected='..expectedTown..' actual='..tostring(actual)
   ..' isMyTown='..tostring(Live.call(owns,'isMyTown',town))..' source='..source)
  local seen={[owns]=true}
  for _,mate in ipairs(ms)do
   local c=mate.char
   local own=assert(c:getOwnerships(),'MEMBER_OWNERSHIPS_UNAVAILABLE '..mate.key)
   if not seen[own]then
    if home(own)~=s.key then own:setHomeBuilding(b:getHandle(),p:getSquadType())end
    if townID(own)~=expectedTown then own:setHomeTown(town,p:getSquadType())end
    seen[own]=true
   end
   assert(home(own)==s.key and townID(own)==expectedTown,'MEMBER_HOME_NOT_APPLIED '..mate.key)
   local state=assert(c:getStateBroadcast(),'MEMBER_STATE_UNAVAILABLE '..mate.key)
   state.homeBuilding=b:getHandle()
   assert(Live.call(state.homeBuilding,'toString')==s.key,'MEMBER_STATE_HOME_NOT_APPLIED '..mate.key)
  end
  bb.targetTown=town
  assert(identity(bb.targetTown)==expectedTown,'TARGET_TOWN_NOT_APPLIED')
 end)
 if not ok then return false,tostring(err) end
 Log.console('NPC_HOME85 shop='..s.cfg.shop..' role='..s.cfg.role..' building='..s.key
  ..' town='..expectedTown..' source='..source..' resident_type='..kind..' member_homes='..#ms..' verified=true')
 return true
end
return M
