local Diagnostics = require('Diagnostics')
local shops = {
    ['100-KenshiShop.mod']='bar', ['101-KenshiShop.mod']='engineering',
    ['102-KenshiShop.mod']='armour', ['103-KenshiShop.mod']='weapons',
    ['104-KenshiShop.mod']='robotics',
    ['105-KenshiShop.mod']='police'
}
local M = {}
function M.observe(building, event)
    if not building then return end
    local data = building:getGameData()
    if not data then return end
    local shop = shops[data.stringID]
    if not shop then return end
    local p = building:getPosition()
    local handle = building:getHandle():toString()
    Diagnostics.info(string.format('%s shop=%s handle=%s position=%.3f,%.3f,%.3f',
        event, shop, handle, p.x, p.y, p.z))
end
return M
