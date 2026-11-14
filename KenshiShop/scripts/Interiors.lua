-- Compatibility facade for older diagnostics. Runtime is per-store in Core/<Shop>/Building/Interior.lua.
local Registry=require('Core.Registry')
local M={}
function M.complete(b,indices)local s=Registry.byBuilding(b);return s and s.interior.complete(b,indices)end
function M.getAttempt(b)local s=Registry.byBuilding(b);return s and s.interior.getAttempt(b)end
function M.clearEmptyAttempt(b)local s=Registry.byBuilding(b);return s and s.interior.clearEmptyAttempt(b)end
return M
