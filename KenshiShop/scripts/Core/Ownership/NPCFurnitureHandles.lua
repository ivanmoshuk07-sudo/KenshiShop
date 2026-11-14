-- Alpha.38: per-shop, current-session exact handles for non-bar interior objects.
-- Diagnostics only. The factory and native furniture are not altered.
local M={}
local saved={}
local ALLOWED={
 ['101-KenshiShop.mod']=true,['102-KenshiShop.mod']=true,
 ['103-KenshiShop.mod']=true,['104-KenshiShop.mod']=true,['105-KenshiShop.mod']=true,
}
local function call(o,method,...)
 if not o then return nil end
 local ok,fn=pcall(function()return o[method]end)
 if not ok or type(fn)~='function' then return nil end
 local yes,val=pcall(fn,o,...)
 return yes and val or nil
end
local function id(b)
 local d=call(b,'getGameData')
 local ok,s=pcall(function()return d and d.stringID end)
 return ok and s and tostring(s) or nil
end
local function key(b)
 local h=call(b,'getHandle')
 return h and call(h,'toString') or nil
end
function M.register(parent,child,index,model,outside)
 if not ALLOWED[id(parent)] then return false,'BAR_OR_UNKNOWN_SHOP' end
 local k,h=key(parent),call(child,'getHandle')
 if not k or not h then return false,'HANDLE_UNAVAILABLE' end
 if type(index)~='number' or index<1 or index>160 or math.floor(index)~=index then
  return false,'INVALID_INDEX'
 end
 local s=saved[k]
 if not s then s={sid=id(parent),items={},count=0};saved[k]=s end
 if s.items[index] then return false,'DUPLICATE_INDEX' end
 s.items[index]={handle=h,model=tostring(model),outside=outside==true}
 s.count=s.count+1
 return true
end
function M.candidates(parent)
 local s=saved[key(parent)]
 local result={}
 if not s or s.sid~=id(parent) then return result,0 end
 for i=1,160 do
  local row=s.items[i]
  if row then
   local b=call(row.handle,'getBuilding')
   if b and call(b,'isValid')==true and id(b)==row.model then
    -- Inside objects must still be linked to their ORIGINAL building.
    local p=call(b,'furnitureParentBuilding')
    if (row.outside and (not p or key(p)==key(parent)))
       or (not row.outside and p and key(p)==key(parent)) then
     result[#result+1]=b
    end
   end
  end
 end
 return result,s.count
end
function M.resetSession()saved={}end
return M
