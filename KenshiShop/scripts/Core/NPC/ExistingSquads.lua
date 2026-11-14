-- Read-only saved-platoon lookup. Never create or modify NPCs. Shared by spawn guard and load recovery.
local M={}
local LIMIT=250
local function call(obj,name,...)
 if not obj then return nil,false end
 local ok,fn=pcall(function()return obj[name]end)
 if not ok or type(fn)~='function' then return nil,false end
 local yes,val=pcall(fn,obj,...)
 return val,yes
end
local function dataID(obj)
 local ok,v=pcall(function()return obj and obj.stringID end)
 return ok and v and tostring(v) or nil
end
local function matches(p,key,cfg)
 if not p then return false end
 local ok,data=pcall(function()return p.squadTemplate end)
 if not ok or dataID(data)~=cfg.template then return false end
 local own=call(p,'getOwnerships')
 if not own then return false end
 local success,h=pcall(function()return own._homeBuilding end)
 if not success or not h then return false end
 local hk=call(h,'toString')
 return hk~=nil and tostring(hk)==key
end
function M.find(building,cfg)
 if not building or not cfg or not cfg.template or not cfg.faction then return nil,'INVALID_GUARD_ARGUMENTS' end
 local ok,key=pcall(function()return building:getHandle():toString()end)
 if not ok or not key then return nil,'BUILDING_HANDLE_UNAVAILABLE' end
 local w=getGameWorld()
 if not w or not w.factionMgr then return nil,'FACTION_MANAGER_UNAVAILABLE' end
 local faction=call(w.factionMgr,'getFactionByStringID',cfg.faction)
 if not faction then return nil,'FACTION_UNAVAILABLE' end
 local found={}
 local function add(p,source)
  if not matches(p,key,cfg) then return end
  local id=call(p,'getPlatoonStringID')
  if not id or id=='' then return end
  found[tostring(id)]={platoon=p,id=tostring(id),source=source}
 end
 local yes,h=pcall(function()return building.residentSquad end)
 if yes and h then add(call(h,'getPlatoon'),'resident') end
 local scanned=false
 for _,method in ipairs({'getActivePlatoons','getUnloadedPlatoons'})do
  local list,succeeded=call(faction,method)
  if succeeded and list then
   local nOK,n=pcall(function()return #list end)
   if not nOK or n>LIMIT then return nil,'FACTION_ROSTER_UNREADABLE_OR_TOO_LARGE' end
   scanned=true
   for i=1,n do add(list[i],method) end
  end
 end
 if not scanned then return nil,'FACTION_ROSTER_UNAVAILABLE' end
 local n,one=0,nil
 for _,entry in pairs(found) do n=n+1;one=entry end
 if n>1 then return nil,'AMBIGUOUS_EXISTING_SQUADS count='..n end
 if one then return one.platoon,'EXISTING_SQUAD '..one.id..' source='..one.source end
 return false,'NO_MATCHING_SAVED_SQUAD'
end
function M.inspect(building,cfg)
 local p,reason=M.find(building,cfg)
 if p==false then return false,reason end
 if p then return true,reason end
 if reason and reason:find('^AMBIGUOUS_EXISTING_SQUADS') then return true,reason end
 return nil,reason
end
return M
