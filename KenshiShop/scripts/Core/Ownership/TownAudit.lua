-- KenshiShop alpha.33. Read-only town/owner observations. No native setters.
-- A missing/not-yet-loaded Town is reported, NEVER repaired from this diagnostic.
local Log=require('Diagnostics')
local M={}
local function call(o,name)
 if not o then return nil end
 local ok,fn=pcall(function()return o[name]end)
 if not ok or type(fn)~='function' then return nil end
 local yes,val=pcall(fn,o)
 if yes then return val end
 return nil
end
local function prop(o,name)
 if not o then return nil end
 local ok,v=pcall(function()return o[name]end)
 return ok and v or nil
end
local function str(h)
 if not h then return 'UNAVAILABLE' end
 return tostring(call(h,'toString') or 'UNAVAILABLE')
end
local function faction(f)
 local data=call(f,'getData')
 return tostring(prop(data,'stringID') or 'UNAVAILABLE')
end
local function platoon(b)
 local h=prop(b,'residentSquad')
 local p=call(h,'getPlatoon')
 return tostring(call(p,'getPlatoonStringID') or 'UNAVAILABLE')
end
function M.snapshot(shop,b,phase,origin,extra,report)
 local owner=call(b,'getFaction')
 -- During native load/construction callbacks a Town* can still be initializing.
 -- Never dereference it from these early callbacks (Lua pcall cannot catch
 -- a native access violation). Read the value-type town handle only.
 local early=(phase=='LOAD_CALLBACK' or phase=='CONSTRUCTION_CALLBACK')
 local town,resident
 if early then resident='DEREFERENCE_DEFERRED'
 else town=call(b,'getTown');resident=platoon(b) end
 local handle=call(b,'getTownHandle')
 local key=str(call(b,'getHandle'))
 local ok,clock=pcall(function()return os.clock()end)
 local ms=ok and math.floor(clock*1000+0.5) or -1
 local name=call(town,'getKnownName')
 local line='TOWN_AUDIT phase='..tostring(phase)..' shop='..tostring(shop)
  ..' building='..key..' origin='..tostring(origin)
  ..' owner='..faction(owner)..' playerOwned='..tostring(call(b,'isThePlayer'))
  ..' townHandle='..str(handle)..' townState='..(early and 'DEREFERENCE_DEFERRED' or (town and 'READY' or 'TOWN_NOT_READY'))
  ..' townIdentity='..tostring(name or 'TOWN_ID_UNAVAILABLE')
  ..' resident='..resident..' cpu_clock_ms='..ms..' '..tostring(extra or '')
 Log.console(line)
 if report then report(line)end
 return line
end
return M
