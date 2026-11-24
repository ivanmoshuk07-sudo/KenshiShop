-- KenshiShop alpha.36: current-session exact handles of NEW bar furniture.
-- Never searches/rewrites neighboring buildings. No pointers survive resetGame.
local M={}
local states={}
local MAX_ITEMS=110
local MAX_ATTEMPTS=3
local function safe(obj,method,...)
 if not obj then return nil end
 local ok,fn=pcall(function()return obj[method]end)
 if not ok or type(fn)~='function' then return nil end
 local good,v=pcall(fn,obj,...)
 if good then return v end
 return nil
end
local function key(b)
 local h=safe(b,'getHandle')
 return h and safe(h,'toString') or nil
end
local function sid(b)
 local d=safe(b,'getGameData')
 local ok,v=pcall(function()return d and d.stringID end)
 return ok and v and tostring(v) or nil
end
local function valid(parent,item)
 local b=safe(item.handle,'getBuilding')
 if not b or safe(b,'isValid')~=true or sid(b)~=item.id then return nil end
 -- The handle was minted by our own factory call for this one parent and index.
 -- Recheck the parent for indoor items before any native setter.
 if not item.outside then
  local p=safe(b,'furnitureParentBuilding')
  if not p or key(p)~=key(parent) then return nil end
 end
 return b
end
function M.register(parent,child,index,owner,id,outside)
 if sid(parent)~='100-KenshiShop.mod' then return false,'NOT_BAR' end
 local k=key(parent)
 local h=safe(child,'getHandle')
 if not k or not h then return false,'HANDLE_UNAVAILABLE' end
 if type(index)~='number' or index<1 or index>MAX_ITEMS then return false,'INDEX_LIMIT' end
 local s=states[k]
 if not s then s={items={},count=0,attempts=0};states[k]=s end
 if s.items[index] then return false,'DUPLICATE_INDEX' end
 s.items[index]={handle=h,index=index,owner=owner,id=tostring(id),outside=outside==true}
 s.count=s.count+1
 return true
end
function M.candidates(parent)
 if sid(parent)~='100-KenshiShop.mod' then return {},0 end
 local s=states[key(parent)]
 local result={}
 if not s then return result,0 end
 for i=1,MAX_ITEMS do
  local item=s.items[i]
  if item then
   local b=valid(parent,item)
   if b then result[#result+1]=b end
  end
 end
 return result,s.count
end
-- Legacy function name retained for callers; routes to the alpha.37 two-way plan.
-- providedAP is ignored: destination-specific APs are selected and verified.
function M.apply(parent,providedAP,source)
 return require('Core.Bar.Building.FurnitureRestore').apply(parent,source or 'LEGACY_CALL')
end
function M.status(parent)
 local s=states[key(parent)]
 if not s then return 'NO_CURRENT_SESSION_HANDLES' end
 return 'registered='..s.count..' attempts='..s.attempts..'/'..MAX_ATTEMPTS
end
function M.resetSession() states={} end
return M
