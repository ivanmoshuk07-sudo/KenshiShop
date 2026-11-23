-- The service ledger owns the saved list. Lifecycle code uses this lookup
-- without depending on the police service or its native event handlers.
local M={}
local isRetired
function M.setPredicate(predicate)
 isRetired=predicate
end
function M.retired(key)
 return type(key)=='string' and isRetired~=nil and isRetired(key)==true
end
return M
