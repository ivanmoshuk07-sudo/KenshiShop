-- alpha.39: bounded direct NPC ownership transfer for a factory-created child.
-- Never searches by radius, never touches furniture of other buildings.
-- Abort direct setters on first native mismatch; the existing 3-stage exact audit remains fallback.
local Log=require('Diagnostics')
local Retirement=require('Core.Ownership.Retirement')
local M={}
local sessions={}
local FACTION='400-KenshiShop.mod'
local function call(o,k,...)
 if not o then return nil end
 local ok,fn=pcall(function()return o[k]end)
 if not ok or type(fn)~='function' then return nil end
 local yes,res=pcall(fn,o,...)
 if yes then return res end
 return nil
end
local function key(b)
 local h=call(b,'getHandle');return h and call(h,'toString') or nil
end
local function factionID(f)
 local d=call(f,'getData')
 local ok,id=pcall(function()return d and d.stringID end)
 return ok and id and tostring(id) or nil
end
local function owner(b)return factionID(call(b,'getFaction'))end
local function getActiveNPC(npc)
 local list=call(npc,'getActivePlatoons')
 if not list then return nil,'ROSTER_UNAVAILABLE' end
 local n=#list
 if n>300 then return nil,'ROSTER_LIMIT' end
 for i=1,n do
  local platoon=list[i];local ap=call(platoon,'getActivePlatoon')
  local count=call(ap,'getSquadSize')
  if ap and type(count)=='number' and count>=1 and count<=40 then
   return ap,'ACTIVE_NPC_SQUAD'
  end
 end
 return nil,'NPC_NOT_READY'
end
function M.apply(parent,child,shop,index)
 if shop=='bar' then return false,'BAR_EXCLUDED' end
 if not parent or not child or call(child,'isValid')~=true then return false,'CHILD_INVALID' end
 local k=key(parent)
 if Retirement.retired(k) then return false,'BUILDING_RETIRED' end
 if not k or not key(child) then return false,'HANDLE_MISSING' end
 local state=sessions[k]
 if not state then state={blocked=false,attempts=0};sessions[k]=state end
 if state.blocked then return false,'DIRECT_TRANSFER_BLOCKED' end
 if owner(child)==FACTION and call(child,'isThePlayer')==false then return true,'ALREADY_NPC' end
 if owner(parent)~=FACTION or call(parent,'isThePlayer')~=false then return false,'PARENT_NOT_NPC_YET' end
 local w=getGameWorld()
 local npc=w and w.factionMgr and call(w.factionMgr,'getFactionByStringID',FACTION)
 if not npc or factionID(npc)~=FACTION then return false,'FACTION_UNAVAILABLE' end
 local ap,source=getActiveNPC(npc)
 if not ap then return false,'NO_ANCHOR '..source end
 local linked=call(child,'furnitureParentBuilding')
 if linked and key(linked)~=k then state.blocked=true;return false,'PARENT_LINK_MISMATCH' end
 state.attempts=state.attempts+1
 local before=owner(child)
 local ok,err=pcall(child.setFaction,child,npc,ap)
 local after=owner(child)
 if not ok or after~=FACTION or call(child,'isThePlayer')~=false
    or owner(parent)~=FACTION or call(parent,'isThePlayer')~=false then
  state.blocked=true
  Log.error('NPC_FURN_CREATE_TRANSFER_FAIL shop='..tostring(shop)..' building='..k..' index='..index
   ..' before='..tostring(before)..' after='..tostring(after)..' reason='..tostring(err)
   ..' later_exact_repair_only')
  return false,'SET_FACTION_UNVERIFIED'
 end
 call(child,'notifyChange')
 Log.info('NPC_FURN_CREATE_TRANSFER_OK shop='..tostring(shop)..' building='..k
   ..' index='..index..' before='..tostring(before)..' after='..tostring(after)
   ..' exact_child=true')
 return true,'NPC_OWNED'
end
function M.resetSession()sessions={}end
function M.retire(key)sessions[key]=nil end
return M
