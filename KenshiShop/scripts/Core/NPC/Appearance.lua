-- alpha.42: only robotics seller remains skeleton. Other roles keep random FCS custom races.
-- Fallback for existing members of an active live squad; no changes to NPC orders/stats.
local M={}
local SKELETON='17946-stick_people.mod'
local function isSkeleton(character)
 local yes,r=pcall(character.getRace,character)
 return yes and r and r.robot==true
end
local function takeOffHelmet(inv)
 if not AttachSlot or AttachSlot.ATTACH_HAT==nil then return false,'HAT_ENUM_UNAVAILABLE' end
 local ok,section=pcall(inv.getSectionOfType,inv,AttachSlot.ATTACH_HAT)
 if not ok then return false,'HAT_SLOT_ERROR '..tostring(section) end
 if not section then return true,'helmet_none(slot_absent)' end
 local got,item=pcall(section.getItem,section)
 if not got then return false,'HAT_READ_ERROR '..tostring(item) end
 if not item then return true,'helmet_none' end
 local removed,yes=pcall(inv.removeItemAutoDestroy,inv,item,1)
 if not removed or not yes then return false,'HAT_REMOVE_ERROR '..tostring(yes) end
 local verified,remaining=pcall(section.getItem,section)
 if not verified then return false,'HAT_VERIFY_ERROR '..tostring(remaining) end
 if remaining then return false,'HAT_STILL_PRESENT' end
 return true,'helmet_removed=1'
end
-- Read the native RaceData.noHats flag, not a guessed race name.
-- Safe to call on existing saved KenshiShop NPCs: no race or other equipment changes.
function M.enforceNoHats(character)
 local ok,r=pcall(character.getRace,character)
 if not ok or not r then return false,'RACE_READ_FAILED' end
 local yes,forbidden=pcall(function()return r.noHats end)
 if not yes then return false,'NO_HATS_FLAG_UNAVAILABLE' end
 if forbidden~=true then return true,'hat_allowed_by_race' end
 local inv=character.inventory
 if not inv then return false,'INVENTORY_UNAVAILABLE' end
 return takeOffHelmet(inv)
end
function M.apply(character,world,shop)
 if not character or not world or not world.gamedata then return false,'APPEARANCE_API_MISSING' end
 if shop~='robotics' then
  -- Preserve FCS random race and gear, except hats explicitly forbidden by that race.
  local ok,r=pcall(character.getRace,character)
  if not ok or not r then return false,'NPC_RACE_READ_FAILED' end
  local rid='UNKNOWN'
  local dataOK,data=pcall(function()return r.data end)
  if dataOK and data then
   local keyOK,key=pcall(function()return data.stringID end)
   if keyOK and key then rid=tostring(key) end
  end
  local forbidden,hat= M.enforceNoHats(character)
  if not forbidden then return false,'race='..rid..' '..tostring(hat) end
  return true,'race='..rid..' custom_FCS_race_preserved; '..tostring(hat)
 end
 local raceInfo='skeleton_from_FCS'
 if not isSkeleton(character) then
  local t=(itemType and itemType.RACE) or 7
  local got,data=pcall(world.gamedata.getData,world.gamedata,SKELETON,t)
  if not got or not data then return false,'RACE_DATA_MISSING '..SKELETON..' type='..t end
  local changed,reason=pcall(character.setRace,character,data)
  if not changed then return false,'RACE_SET_FAILED '..tostring(reason) end
  if not isSkeleton(character) then return false,'RACE_NOT_SKELETON_AFTER_SET' end
  raceInfo='race_converted'
 end
 local inv=character.inventory
 if not inv then return false,'INVENTORY_UNAVAILABLE' end
 local done,head=takeOffHelmet(inv)
 if not done then return false,head end
 return true,raceInfo..' '..head
end
return M
