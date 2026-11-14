-- KenshiShop alpha.78: restore original kit replenishment (without appearance edits).
-- Read native ItemFunction classes (first aid=1, skeleton repair=12), no unconditional duplicates.
-- All methods are protected; full inventories are NOT destroyed or expanded.
local M={}
local CONTENTS={
 {functionID=1,sid='1359-gamedata.base',label='first_aid'},
 {functionID=12,sid='18020-gamedata.base',label='robotics_repair'},
}
local function tryMethod(o,method,...)
 local ok,fn=pcall(function() return o and o[method] end)
 if not ok or type(fn)~='function' then return false,'METHOD_MISSING_'..method end
 local yes,result=pcall(fn,o,...)
 return yes,result
end
function M.sync(character,world)
 if not character or not world or not world.gamedata or not world.theFactory then
  return false,'MEDICAL_API_UNAVAILABLE'
 end
 local inv=character.inventory
 if not inv then return false,'INVENTORY_UNAVAILABLE' end
 local changes={}
 local itemTypeID=(itemType and itemType.ITEM) or 4
 -- Validate and fill independently: an unavailable kit does not delete or replace the other.
 for _,entry in ipairs(CONTENTS) do
  local readOK,present=tryMethod(inv,'hasItemFunction',entry.functionID)
  if not readOK then return false,'SUPPLY_CHECK_FAILED '..entry.label..' '..tostring(present) end
  if not present then
   local found,data=tryMethod(world.gamedata,'getData',entry.sid,itemTypeID)
   if not found or not data then return false,'SUPPLY_DATA_MISSING '..entry.sid end
   local made,item=tryMethod(world.theFactory,'createItem',data,nil,nil,nil,50,nil)
   if not made or not item then return false,'SUPPLY_CREATE_FAILED '..entry.sid end
   local added,accepted=tryMethod(inv,'addItem',item,1,false,false)
   if not added or not accepted then return false,'SUPPLY_INVENTORY_FULL '..entry.label end
   local verify,exists=tryMethod(inv,'hasItemFunction',entry.functionID)
   if not verify or not exists then return false,'SUPPLY_VERIFY_FAILED '..entry.label end
   changes[#changes+1]=entry.label..'=1'
  end
 end
 return true,(#changes>0 and table.concat(changes,' ') or 'UNCHANGED')
end
return M
