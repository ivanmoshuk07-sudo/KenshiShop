-- Repair only the parent building's resident pointer; never touch furniture.
local Live=require('Core.NPC.LiveState')
local M={}
local function pid(p)return Live.call(p,'getPlatoonStringID')end
function M.bind(b,trader,guard)
 local function read()
  local ok,h=pcall(function()return b.residentSquad end)
  return ok and Live.call(h,'getPlatoon') or nil
 end
 local want=pid(trader);if not want then return false,'TRADER_MISSING' end
 if pid(read())==want then return true,'ALREADY_TRADER' end
 local before=read()
 -- A foreign resident is never overwritten through raw fields.
 local eligible=not before or (guard and pid(before)==pid(guard))
 if not eligible then return false,'UNEXPECTED_RESIDENT' end
 local owns=Live.call(trader,'getOwnerships')
 local ok,home=pcall(function()return owns._homeBuilding:toString()end)
 local key=Live.call(Live.call(b,'getHandle'),'toString')
 if not ok or home~=key then return false,'HOME_UNVERIFIED' end
 local bf,pf=Live.call(b,'getFaction'),Live.call(trader,'getFaction')
 local function faction(f)
  local d=Live.call(f,'getData');return d and d.stringID
 end
 if not bf or not pf or faction(bf)~=faction(pf) then return false,'FACTION_UNVERIFIED' end
 local called=pcall(b.setResidentSquad,b,trader)
 if pid(read())==want then return true,'NATIVE_SETTER' end
 local h=Live.call(trader,'getHandle')
 if not h then return false,'HANDLE_UNAVAILABLE' end
 local yes,err=pcall(function()
  b.residentSquad=h
  b.residentSquadTemplate=trader.squadTemplate
 end)
 if not yes then return false,'FIELDS_FAILED '..tostring(err) end
 return pid(read())==want,called and 'VERIFIED_HANDLE_FALLBACK' or 'HANDLE_FALLBACK'
end
function M.ensure(s,b)
 if s.cfg.role~='trader' then return true end
 local guards={bar='7800-KenshiShop.mod',engineering='7801-KenshiShop.mod',armour='7802-KenshiShop.mod',weapons='7803-KenshiShop.mod'}
 local template=guards[s.cfg.shop]
 if not template then return true end
 local guard=require('Core.NPC.ExistingSquads').find(b,{template=template,faction=s.cfg.faction})
 return M.bind(b,s.platoon,guard or nil)
end
return M
