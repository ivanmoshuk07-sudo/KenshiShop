-- Independent bar calibration boundary; all original coordinate logic reused unchanged.
local Target='100-KenshiShop.mod'
local Correction=require('PositionCorrection')
local Floor=require('FloorAssignment')
local M={}
function M.create(config)
 assert(config and config.world, 'Missing native furniture factory')
 return Correction.create(config)
end
function M.resolve(classification,floors)
 return Floor.resolve(Target,classification,floors)
end
return M
