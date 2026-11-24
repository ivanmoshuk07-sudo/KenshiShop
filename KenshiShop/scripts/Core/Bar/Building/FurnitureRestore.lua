-- KenshiShop alpha.37: bar-only, bounded two-way furniture ownership repair.
-- Exact layout/model/parent/position native match; NO creation, movement or bulk setters.
local Log=require('Diagnostics')
local Audit=require('Core.Ownership.Furniture')
local Retirement=require('Core.Ownership.Retirement')
local M={}
local states={}
local MAX_ATTEMPTS=3
local MAX_FACTION_SQUADS=300
local FRAMES={25,95,185}
local TARGET='400-KenshiShop.mod'
local function safe(obj,method,...)
 if not obj then return nil end
 local ok,fn=pcall(function()return obj[method] end)
 if not ok or type(fn)~='function' then return nil end
 local good,v=pcall(fn,obj,...)
 if good then return v end
 return nil
end
local function id(b)
 local d=safe(b,'getGameData')
 local ok,v=pcall(function()return d and d.stringID end)
 return ok and v and tostring(v) or nil
end
local function key(b)
 local h=safe(b,'getHandle')
 return h and safe(h,'toString') or nil
end
local function factionID(f)
 local d=safe(f,'getData')
 local ok,v=pcall(function()return d and d.stringID end)
 return ok and v and tostring(v) or 'UNKNOWN'
end
local function ownerID(b)return factionID(safe(b,'getFaction')) end
local function findAP(faction,kind)
 local list=safe(faction,'getActivePlatoons')
 local count=list and #list or 0
 if count>MAX_FACTION_SQUADS then return nil,'ACTIVE_SQUAD_SCAN_CAP' end
 for i=1,count do
  local p=list[i]
  -- The platoon comes directly from THIS faction's active-squad list.
  local ap=safe(p,'getActivePlatoon')
  local n=safe(ap,'getSquadSize')
  if ap and type(n)=='number' and n>0 and n<=40 then
   return ap,kind..'_FACTION_ACTIVE_SQUAD'
  end
 end
 if kind=='PLAYER' then
  local ui=getPlayerInterface()
  local character=safe(ui,'getAnyPlayerCharacter')
  -- Fallback is only allowed when the character actually belongs to player faction.
  if character and factionID(safe(character,'getFaction'))==factionID(faction) then
   local ap=safe(character,'getPlatoon')
   local n=safe(ap,'getSquadSize')
   if ap and type(n)=='number' and n>0 and n<=40 then return ap,'PLAYER_CHARACTER_PLATOON' end
  end
 end
 return nil,kind..'_ACTIVE_PLATOON_UNAVAILABLE'
end
local function verify(parent,items,plan,playerID)
 local wrong,unknown=0,0
 for i=1,#plan.owners do
  local b=items[i]
  if not b or safe(b,'isValid')~=true then unknown=unknown+1
  else
   local expected=plan.owners[i]=='PLAYER' and playerID or TARGET
   local isPlayer=plan.owners[i]=='PLAYER'
   if ownerID(b)~=expected or safe(b,'isThePlayer')~=isPlayer then wrong=wrong+1 end
  end
 end
 return wrong,unknown
end
function M.apply(parent,source)
 if id(parent)~='100-KenshiShop.mod' then return false,'NOT_BAR' end
 local k=key(parent)
 if Retirement.retired(k) then return false,'BUILDING_RETIRED' end
 if not k then return false,'PARENT_HANDLE_UNAVAILABLE' end
 if ownerID(parent)~=TARGET or safe(parent,'isThePlayer')~=false then
  return false,'PARENT_NOT_NPC_OWNED'
 end
 local world=getGameWorld()
 local ui=getPlayerInterface()
 local player=ui and safe(ui,'getFaction')
 local npc=world and world.factionMgr and safe(world.factionMgr,'getFactionByStringID',TARGET)
 if not player or not npc or factionID(npc)~=TARGET then return false,'OWNER_FACTIONS_UNAVAILABLE' end
 local playerID=factionID(player)
 if playerID==TARGET or playerID=='UNKNOWN' then return false,'INVALID_PLAYER_FACTION' end
 -- Read-only scan supplies a full, uniquely matched layout; no writes otherwise.
 local _,report,items,plan=Audit.auditBar(parent)
 if not items or not plan or #plan.owners~=101 then return false,'MATCH_NOT_READY '..tostring(report) end
 for i=1,101 do
  if not items[i] or safe(items[i],'isValid')~=true then return false,'MATCH_INCOMPLETE index='..i end
 end
 local beforeWrong,beforeMissing=verify(parent,items,plan,playerID)
 if beforeMissing~=0 then return false,'MATCH_INVALID_ITEMS '..beforeMissing end
 if beforeWrong==0 then
  Log.console('BAR_SPLIT_RESTORE building='..k..' source='..tostring(source)
   ..' already_correct=101 player='..plan.player..' npc='..plan.npc..' shared='..plan.sharedTotal)
  return true,'ALL_CORRECT'
 end
 local npcAP,npcWhy=findAP(npc,'NPC')
 local playerAP,playerWhy=findAP(player,'PLAYER')
 -- Do not risk partial mutations if either destination lacks a valid ActivePlatoon.
 local needPlayer,needNPC=false,false
 for i=1,101 do
  local desired=plan.owners[i]
  local goal=desired=='PLAYER' and playerID or TARGET
  if ownerID(items[i])~=goal or safe(items[i],'isThePlayer')~=(desired=='PLAYER') then
   if desired=='PLAYER' then needPlayer=true else needNPC=true end
  end
 end
 if needNPC and not npcAP then return false,'NPC_AP_NOT_READY '..tostring(npcWhy) end
 if needPlayer and not playerAP then return false,'PLAYER_AP_NOT_READY '..tostring(playerWhy) end
 local fixed,failed=0,0
 -- Change NPC items FIRST; restore seating allocated to player LAST.
 -- Never change seating already at its approved owner.
 for _,phase in ipairs({'NPC','PLAYER'}) do
  for i=1,101 do
   if plan.owners[i]==phase then
    local b=items[i]
    local desired=phase=='PLAYER' and playerID or TARGET
    if ownerID(b)~=desired or safe(b,'isThePlayer')~=(phase=='PLAYER') then
     local f=phase=='PLAYER' and player or npc
     local ap=phase=='PLAYER' and playerAP or npcAP
     local old=ownerID(b)
     local ok,err=pcall(b.setFaction,b,f,ap)
     local new=ownerID(b)
     local isPlayer=safe(b,'isThePlayer')
     if not ok or new~=desired or isPlayer~=(phase=='PLAYER') then
      failed=failed+1
      Log.error('BAR_SPLIT_ITEM_FAIL building='..k..' index='..i..' target='..phase
       ..' before='..old..' actual='..new..' native_ok='..tostring(ok)..' err='..tostring(err))
      return false,'NATIVE_ITEM_FAILED index='..i..' fixed='..fixed
     end
     fixed=fixed+1
     safe(b,'notifyChange')
     Log.info('BAR_SPLIT_ITEM_OK building='..k..' index='..i..' from='..old..' to='..desired)
     -- Never permit child setter to change owner of the parent shop.
     if ownerID(parent)~=TARGET or safe(parent,'isThePlayer')~=false then
      Log.error('BAR_SPLIT_PARENT_CHANGED building='..k..' index='..i)
      return false,'PARENT_CASCADE_DETECTED index='..i
     end
    end
   end
  end
 end
 if fixed>0 then safe(parent,'notifyChange') end
 local remaining,missing=verify(parent,items,plan,playerID)
 local detail='source='..tostring(source)..' fixed='..fixed..' remaining='..remaining
  ..' missing='..missing..' shared='..plan.sharedTotal
  ..' shared_player='..plan.sharedPlayer..' shared_npc='..plan.sharedNPC
  ..' total_player='..plan.player..' total_npc='..plan.npc
  ..' npc_ap='..tostring(npcWhy)..' player_ap='..tostring(playerWhy)
 Log.console('BAR_SPLIT_RESTORE building='..k..' '..detail)
 return remaining==0 and missing==0,detail
end
function M.request(parent,source)
 if id(parent)~='100-KenshiShop.mod' then return false,'NOT_BAR' end
 local k=key(parent)
 if Retirement.retired(k) then return false,'BUILDING_RETIRED' end
 local h=safe(parent,'getHandle')
 if not k or not h then return false,'HANDLE_UNAVAILABLE' end
 local old=states[k]
 -- Repeated owner-ready events in one session never create duplicate polling loops.
 if old and old.hook then return true,'ALREADY_SCHEDULED' end
 local s={key=k,handle=h,source=tostring(source or 'UNKNOWN'),attempts=0,frames=0}
 states[k]=s
 local ok,hook=pcall(Events.on,'MyGUI::Gui::eventFrameStart',function()
  if Retirement.retired(k) then M.retire(k);return end
  s.frames=s.frames+1
  if s.attempts>=MAX_ATTEMPTS or s.frames>FRAMES[MAX_ATTEMPTS]+3 then
   if s.hook then Events.off(s.hook);s.hook=nil end
   states[k]=nil;return
  end
  if s.frames<FRAMES[s.attempts+1] then return end
  s.attempts=s.attempts+1
  local b=safe(s.handle,'getBuilding')
  local applied,passed,detail
  if not b or safe(b,'isValid')~=true then
   applied=false;detail='BUILDING_NOT_READY'
  else
   applied,passed,detail=pcall(M.apply,b,s.source..'_TRY_'..s.attempts)
  end
  local success=applied and passed
  local outcome=applied and tostring(detail) or tostring(passed or detail)
  Log.console('BAR_SPLIT_ATTEMPT building='..k..' attempt='..s.attempts..'/'..MAX_ATTEMPTS
    ..' success='..tostring(success)..' '..outcome)
  if success or s.attempts>=MAX_ATTEMPTS then
   if not success then Log.error('BAR_SPLIT_RESTORE_STOP building='..k..' failed_after_3 reason='..outcome) end
   if s.hook then Events.off(s.hook);s.hook=nil end
   states[k]=nil
  end
 end)
 if ok and hook then s.hook=hook;return true,'SCHEDULED'
 else states[k]=nil;return false,'HOOK_FAILED '..tostring(hook) end
end
function M.retire(k)
 local s=states[k]
 if s and s.hook then Events.off(s.hook) end
 states[k]=nil
end
function M.resetSession()
 for _,s in pairs(states) do if s.hook then Events.off(s.hook) end end
 states={}
end
return M
