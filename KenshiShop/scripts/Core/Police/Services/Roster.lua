-- Confirmed native deaths only. Save records contain IDs and scalar metadata;
-- copied home building handles stay in this session-local cache.
local Config=require('Core.Police.Services.Config')
local Store=require('Core.Police.Services.Store')
local Transport=require('Core.NPC.Transport')
local M={}
local LIMIT=12000
local buildings={}
local function field(o,k)
 local ok,v=pcall(function()return o and o[k]end)
 if ok then return v end
end
local function call(o,k,...)
 local fn=field(o,k)
 if type(fn)~='function' then return nil,false end
 local ok,v=pcall(fn,o,...)
 if ok then return v,true end
 return nil,false
end
local function text(v)return type(v)=='string' and v~='' and v or nil end
local function handleID(h)
 if call(h,'isNull')==true then return nil end
 return text(call(h,'toString'))
end
local function id(o)return handleID(call(o,'getHandle'))end
local function dataID(d)return text(field(d,'stringID'))end
local function factionID(o)return dataID(call(call(o,'getFaction'),'getData'))end
local function world()
 local fn=rawget(_G,'getGameWorld')
 if type(fn)~='function' then return nil end
 local ok,w=pcall(fn);return ok and w or nil
end
local function platoonID(p)return text(call(p,'getPlatoonStringID'))end
local function platoon(c)
 -- Character.getPlatoon returns ActivePlatoon, whose me is the saved Platoon.
 local ap=call(c,'getPlatoon')
 return field(ap,'me') or (platoonID(ap) and ap or nil)
end
local function lists(w)
 local faction=call(field(w,'factionMgr'),'getFactionByStringID',Config.faction)
 if not faction then return {},false,'FACTION_UNAVAILABLE' end
 local out,complete={},true
 for _,method in ipairs({'getActivePlatoons','getUnloadedPlatoons'})do
  local list,ok=call(faction,method)
  if ok and list then
   local success,values=pcall(function()
    local n=#list;assert(n>=0 and n%1==0 and n<=LIMIT,'PLATOON_SCAN_LIMIT')
    local copy={}
    for i=1,n do local p=list[i];if p then copy[#copy+1]=p end end
    return copy
   end)
   if success then out[#out+1]=values else complete=false end
  else complete=false end
 end
 if complete then return out,true end
 return out,false,'FACTION_ROSTER_UNAVAILABLE'
end
local function homeHandle(p,c)
 local h=field(call(p,'getOwnerships'),'_homeBuilding')
 if handleID(h) then return h end
 h=field(call(c,'getOwnerships'),'_homeBuilding')
 if handleID(h) then return h end
end
local function rememberBuilding(o,key)
 local h=call(o,'getHandle')
 if handleID(h)==key then buildings[key]=h end
end
local function seedHandle(w)
 -- There is no Lua hand constructor. getHandle and _homeBuilding return
 -- owned value copies in KenshiLua; fromString may safely mutate a fresh copy.
 local grouped=lists(w)
 for _,list in ipairs(grouped)do for _,p in ipairs(list)do
  local h=call(p,'getHandle')
  if handleID(h) then return h end
  h=homeHandle(p)
  if handleID(h) then return h end
 end end
 local set=field(w,'charUpdateListMain')
 if set then
  local ok,h=pcall(function()
   local n=0
   for c in pairs(set)do
    n=n+1;if n>LIMIT then break end
    local candidate=call(c,'getHandle')
    if handleID(candidate) then return candidate end
   end
  end)
  if ok then return h end
 end
end
function M.building(key)
 key=text(key);if not key then return nil end
 local function current(h)
  local o=call(h,'getBuilding')
  if o and call(o,'isValid')==true and id(o)==key then return o end
 end
 local found=current(buildings[key]);if found then return found end
 local h=seedHandle(world())
 if h then
  local _,ok=call(h,'fromString',key)
  if ok and handleID(h)==key then
   buildings[key]=h;return current(h)
  end
 end
end
function M.reset()
 buildings={}
 -- A save can change at the same game minute; time gating must not retain
 -- handles from the preceding world while service controllers are absent.
 if type(Transport.resetMembers)=='function' then Transport.resetMembers()end
end
function M.findPlatoon(pid)
 pid=text(pid);if not pid then return nil,'PLATOON_ID_UNAVAILABLE' end
 local w=world();if not w then return nil,'WORLD_UNAVAILABLE' end
 local grouped,complete,reason=lists(w)
 for _,list in ipairs(grouped)do for _,p in ipairs(list)do
  if platoonID(p)==pid then return p end
 end end
 return nil,complete and 'TRUE_NOT_FOUND' or reason
end
function M.config(p)
 local cfg=Config.copy(dataID(field(p,'squadTemplate')))
 if cfg and cfg.serviceHired then
  local pid=platoonID(p)
  local saved=pid and Store.get().patrols[pid]
  cfg.existingID=pid
  if type(saved)=='table' and type(saved.base)=='number' then cfg.streetSlotBase=saved.base end
 end
 return cfg
end
local function guardSlot(name)
 if type(name)~='string' then return nil end
 local floor=tonumber(name:match('^KS: Охрана %((%d+) этаж%)$'))
 if floor==1 or floor==2 then return floor end
end
local function leaderID(p)
 local ap=call(p,'getActivePlatoon')
 return id(call(ap,'getSquadLeader')) or handleID(field(p,'squadleader'))
end
function M.observe(s,ms)
 if not Store.ready() then return false,'STORE_NOT_READY' end
 if type(s)~='table' or type(ms)~='table' then return false,'ROSTER_ARGUMENTS_INVALID' end
 local cfg=s.cfg
 if not cfg or not Config.copy(cfg.template) or factionID(s.platoon)~=Config.faction then return false,'FOREIGN_PLATOON' end
 local pid=platoonID(s.platoon)
 local b=s.building
 local key=id(b)
 local town=id(call(b,'getTown'))
 if not pid or not key or not town or (s.key and s.key~=key) then return false,'ROSTER_HOME_UNAVAILABLE' end
 rememberBuilding(b,key)
 local roster=Store.get().roster
 local ordered,seen,used={},{},{}
 for _,m in ipairs(ms)do
  local member=id(m.char)
  if member and not seen[member] then
   seen[member]=true;ordered[#ordered+1]={key=member,char=m.char}
   local old=roster[member]
   local slot=cfg.role=='guard' and guardSlot(call(m.char,'getName')) or nil
   slot=slot or (type(old)=='table' and old.slot)
   if type(slot)=='number' then used[slot]=true end
  end
 end
 table.sort(ordered,function(a,b)return a.key<b.key end)
 local lead=leaderID(s.platoon)
 for _,m in ipairs(ordered)do
  local row=roster[m.key]
  if type(row)~='table' then row={id=m.key,dead=false};roster[m.key]=row end
  local name=text(call(m.char,'getName'))
  local slot=cfg.role=='guard' and guardSlot(name) or nil
  slot=slot or row.slot
  if type(slot)~='number' then slot=1;while used[slot]do slot=slot+1 end;used[slot]=true end
  row.id=m.key;row.pid=pid;row.building=key;row.town=town;row.squadTemplate=cfg.template;row.slot=slot
  row.charTemplate=dataID(call(m.char,'getGameData')) or row.charTemplate
  row.race=dataID(field(call(m.char,'getRace'),'data')) or row.race
  row.name=name or row.name
  if cfg.role=='guard' then row.floor=slot-1 end
  if lead then row.leader=lead==m.key end
  -- Observation never revives an already confirmed death or clears receipts.
  if call(m.char,'isDead')==true then row.dead=true end
 end
 return true,#ordered
end
function M.death(c)
 if not Store.ready() then return false,'STORE_NOT_READY' end
 if call(c,'isDead')~=true then return false,'DEATH_UNCONFIRMED' end
 local key=id(c);if not key then return false,'CHARACTER_ID_UNAVAILABLE' end
 local row=Store.get().roster[key]
 if type(row)~='table' then
  local p=platoon(c)
  local cfg=M.config(p)
  if not cfg or factionID(c)~=Config.faction or factionID(p)~=Config.faction then return false,'FOREIGN_CHARACTER' end
  local h=homeHandle(p,c)
  local home=handleID(h)
  local b=call(h,'getBuilding') or (home and M.building(home))
  if not b then return false,'ROSTER_HOME_UNAVAILABLE' end
  local ok,why=M.observe({cfg=cfg,platoon=p,building=b,key=home},{ {char=c,key=key} })
  if not ok then return false,why end
  row=Store.get().roster[key]
 end
 -- The death event can arrive just after duty assigns a persistent floor
 -- name or a native race change, before the next controller observation.
 row.charTemplate=dataID(call(c,'getGameData')) or row.charTemplate
 row.race=dataID(field(call(c,'getRace'),'data')) or row.race
 row.name=text(call(c,'getName')) or row.name
 local cfg=Config.copy(row.squadTemplate)
 local slot=cfg and cfg.role=='guard' and guardSlot(row.name)
 if slot then row.slot=slot;row.floor=slot-1 end
 row.dead=true
 return true,row
end
function M.scan(fresh)
 if not Store.ready() then return false,'STORE_NOT_READY' end
 local w=world();if not w then return false,'WORLD_UNAVAILABLE' end
 local grouped,complete,reason=lists(w)
 local seen,count={},0
 for _,list in ipairs(grouped)do for _,p in ipairs(list)do
  local pid=platoonID(p)
  if pid and not seen[pid] then
   seen[pid]=true
   local cfg=M.config(p)
   if cfg and factionID(p)==Config.faction then
    local h=homeHandle(p)
    local key=handleID(h)
    if key then
     -- Ownerships returns a copied hand, including for unloaded platoons.
     buildings[key]=h
     local b=call(h,'getBuilding')
     if b and call(p,'getActivePlatoon') then
      -- One fresh global membership pass covers every platoon in this scan;
      -- subsequent consumers share it instead of rewalking all loaded NPCs.
      local ok,ms=pcall(Transport.members,w,p,cfg.count,fresh==true)
      if ok and ms then
       fresh=false
       local observed,n=M.observe({cfg=cfg,platoon=p,building=b,key=key},ms)
       if observed then count=count+n end
      end
     end
    end
   end
  end
 end end
 local parade=field(w,'deathParade')
 if parade then
  local ok=pcall(function()
   local n=0
   for _,c in pairs(parade)do
    n=n+1;if n>LIMIT then error('CORPSE_SCAN_LIMIT')end
    if call(c,'isDead')==true then M.death(c)end
   end
  end)
  if not ok then return false,'CORPSE_ROSTER_UNAVAILABLE' end
 end
 return complete,complete and count or reason
end
return M
