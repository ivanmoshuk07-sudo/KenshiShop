-- Load the small SDK module only when needed. It uses the existing installed
-- KenshiLua/KenshiLib. The module owns scoped medical detours for NoSever.
local M={};local module,attempted,errorText
local function load()
 if attempted then return module,errorText end;attempted=true
 local source=debug and debug.getinfo and debug.getinfo(1,'S').source or ''
 local path=source:gsub('^@',''):gsub('\\','/')
 local root=path:match('^(.*)/scripts/Core/NPC/NativeBridge%.lua$') or 'mods/KenshiShop'
 if type(package.loadlib)~='function' then errorText='NATIVE_MODULE_LOADER_UNAVAILABLE';return end
 local loader,err=package.loadlib(root..'/native/KenshiShopNative.dll','luaopen_KenshiShopNative')
 if not loader then errorText='NATIVE_MODULE_LOAD '..tostring(err);return end
 local ok,result=pcall(loader)
 if not ok or type(result)~='table' or result.abi~=1 or type(result.createNode)~='function' then
  errorText='NATIVE_MODULE_ABI_UNAVAILABLE '..tostring(result);return
 end
 module=result;return module
end
function M.available()local m=load();return m~=nil end
function M.create(factory,data,b,faction,p,q)
 local m,why=load();assert(m,why or errorText or 'NATIVE_MODULE_UNAVAILABLE')
 local base,err=m.createNode(factory,data,b,faction,p.x,p.y,p.z,q.w,q.x,q.y,q.z)
 assert(base,err or 'NATIVE_NODE_MARSHAL_FAILED');return base
end
function M.protectLimbs(med,race)
 local m,why=load()
 if not m then return false,why or errorText end
 if m.limbProtectionABI~=1 or type(m.protectLimbs)~='function' then return false,'NOSEVER_NATIVE_API_MISSING'end
 return m.protectLimbs(med,race)
end
function M.unprotectLimbs(med)
 local m=load()
 if m and type(m.unprotectLimbs)=='function' then return m.unprotectLimbs(med)end
 return false,'NOSEVER_NATIVE_API_MISSING'
end
return M
