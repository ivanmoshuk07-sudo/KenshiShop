-- Read-only shop registry. No shared spawn state.
local slots={
 ['100-KenshiShop.mod']=require('Core.Bar.init'),
 ['101-KenshiShop.mod']=require('Core.Engineering.init'),
 ['102-KenshiShop.mod']=require('Core.Armour.init'),
 ['103-KenshiShop.mod']=require('Core.Weapons.init'),
 ['104-KenshiShop.mod']=require('Core.Robotics.init'),
 ['105-KenshiShop.mod']=require('Core.Police.init'),
 ['106-KenshiShop.mod']=require('Core.Crematorium.init'),
}
local M={}
function M.byID(sid)return slots[tostring(sid)] end
function M.byBuilding(b)
 if not b then return nil end
 local d=b:getGameData()
 return d and slots[tostring(d.stringID)] or nil
end
function M.each()return pairs(slots) end
function M.resetSession()for _,s in pairs(slots)do s.resetSession() end end
return M
