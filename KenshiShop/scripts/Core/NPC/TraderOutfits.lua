-- alpha.23: exact apparel per shop. Only called for a trader leader, NEVER for guards/patrol.
-- Existing character stats, weapons, inventory lists and vendor definitions remain untouched.
local M={}
local outfits={
 bar={ {sid='2163-gamedata.base',slot='ATTACH_BODY',label='Traders Leathers'},
       {sid='2159-gamedata.base',slot='ATTACH_LEGS',label='Samurai Clothpants'} },
 engineering={ {sid='684-gamedata.base',slot='ATTACH_BODY',label='Sleeveless Longcoat'},
               {sid='2159-gamedata.base',slot='ATTACH_LEGS',label='Samurai Clothpants'} },
 armour={ {sid='2283-gamedata.base',slot='ATTACH_BODY',label='Mercenary Leather Armour'},
          {sid='2159-gamedata.base',slot='ATTACH_LEGS',label='Samurai Clothpants'} },
 weapons={ {sid='2182-gamedata.base',slot='ATTACH_BODY',label='Plate Jacket'},
           {sid='2159-gamedata.base',slot='ATTACH_LEGS',label='Samurai Clothpants'} },
 robotics={ {sid='2165-gamedata.base',slot='ATTACH_BODY',label='Longcoat'},
            {sid='2159-gamedata.base',slot='ATTACH_LEGS',label='Samurai Clothpants'} },
}
local function worn(inventory,slot)
 local okay,sec=pcall(inventory.getSectionOfType,inventory,slot)
 if not okay or not sec then return nil,'SLOT_UNAVAILABLE '..tostring(slot) end
 local got,item=pcall(sec.getItem,sec)
 if not got then return nil,'SLOT_READ_ERROR '..tostring(item) end
 return item,nil
end
local function replaceOne(inventory,factory,gameData,entry)
 local slot=AttachSlot and AttachSlot[entry.slot]
 if slot==nil then return false,'UNKNOWN_SLOT '..entry.slot end
 local current,err=worn(inventory,slot)
 if err then return false,err end
 local newItem=factory:createItem(gameData,nil,nil,nil,40,nil)
 if not newItem then return false,'ITEM_CREATION_FAILED '..entry.sid end
 -- Add the new item first. Never destroy the old item if the inventory cannot accept the replacement.
 if not inventory:addItem(newItem,1,false,false) then return false,'INVENTORY_FULL '..entry.sid end
 if current then
  local removed=inventory:removeItemAutoDestroy(current,1)
  if not removed then return false,'OLD_ITEM_REMOVE_FAILED '..entry.slot end
 end
 if not inventory:equipItem(newItem) then return false,'EQUIP_FAILED '..entry.sid end
 local equipped,why=worn(inventory,slot)
 if why then return false,why end
 if not equipped then return false,'EQUIP_UNVERIFIED '..entry.sid end
 return true,entry.label
end
function M.apply(character,shop)
 local entries=outfits[shop]
 if not entries then return false,0,0,'UNKNOWN_SHOP '..tostring(shop) end
 if not character or not character.inventory then return false,0,#entries,'INVENTORY_MISSING' end
 local world=getGameWorld()
 if not world or not world.theFactory or not world.gamedata then return false,0,#entries,'WORLD_API_MISSING' end
 local armourType=(itemType and itemType.ARMOUR) or 3
 local found={}
 -- Validate both records BEFORE changing a single item.
 for i,e in ipairs(entries) do
  local ok,data=pcall(world.gamedata.getData,world.gamedata,e.sid,armourType)
  if not ok or not data then return false,0,#entries,'ARMOUR_DATA_NOT_FOUND '..e.sid..' type='..armourType end
  found[i]=data
 end
 local changed=0
 local descriptions={}
 for i,entry in ipairs(entries) do
  local ok,success,desc=pcall(replaceOne,character.inventory,world.theFactory,found[i],entry)
  if not ok then return false,changed,#entries,'OUTFIT_EXCEPTION '..entry.label..' '..tostring(success) end
  if not success then return false,changed,#entries,'OUTFIT_ERROR '..entry.label..' '..tostring(desc) end
  changed=changed+1;descriptions[#descriptions+1]=desc
 end
 return true,changed,#entries,table.concat(descriptions,' + ')
end
return M
