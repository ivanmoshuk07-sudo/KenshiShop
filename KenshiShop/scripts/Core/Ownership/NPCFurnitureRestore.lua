-- KenshiShop alpha.38: non-bar all-NPC furniture ownership preservation.
-- A full exact-model/location/parent match MUST precede every write.
-- No moving, creating or deleting furniture; bar's special split is untouched.
local Log=require('Diagnostics')
local Audit=require('Core.Ownership.Furniture')
local Retirement=require('Core.Ownership.Retirement')
local M={}
local states={}
local MAX_ATTEMPTS=3
local FRAMES={25,95,185}
local FACTION='400-KenshiShop.mod'
local function call(o,method,...)
 if not o then return nil end
 local ok,fn=pcall(function()return o[method]end)
 if not ok or type(fn)~='function' then return nil end
 local yes,v=pcall(fn,o,...)
 if yes then return v end
 return nil
end
local function sid(obj)
 local d=call(obj,'getGameData')
 local ok,v=pcall(function()return d and d.stringID end)
 return ok and v and tostring(v) or nil
end
local function key(obj)
 local h=call(obj,'getHandle')
 return h and call(h,'toString') or nil
end
local function factionID(f)
 local d=call(f,'getData')
 local ok,v=pcall(function()return d and d.stringID end)
 return ok and v and tostring(v) or nil
end
local function ownerID(b)return factionID(call(b,'getFaction')) end
local function active(f)
 local list=call(f,'getActivePlatoons')
 local n=list and #list or 0
 if n>300 then return nil,'ACTIVE_PLATOON_CAP' end
 for i=1,n do
  local ap=call(list[i],'getActivePlatoon')
  local sz=call(ap,'getSquadSize')
  if ap and type(sz)=='number' and sz>=1 and sz<=40 then
   return ap,'SAME_FACTION_ACTIVE_NPC'
  end
 end
 return nil,'ACTIVE_NPC_NOT_READY'
end
function M.apply(parent,source)
 local shop=sid(parent)
 if shop=='100-KenshiShop.mod' then return false,'BAR_SPLIT_ISOLATED' end
 if not ({['101-KenshiShop.mod']=true,['102-KenshiShop.mod']=true,
          ['103-KenshiShop.mod']=true,['104-KenshiShop.mod']=true,['105-KenshiShop.mod']=true})[shop] then
  return false,'UNSUPPORTED_SHOP'
 end
 local k=key(parent)
 if Retirement.retired(k) then return false,'BUILDING_RETIRED' end
 if not k or call(parent,'isValid')~=true then return false,'INVALID_PARENT' end
 if ownerID(parent)~=FACTION or call(parent,'isThePlayer')~=false then
  return false,'PARENT_OWNER_NOT_READY'
 end
 local world=getGameWorld()
 local npc=world and world.factionMgr and call(world.factionMgr,'getFactionByStringID',FACTION)
 if not npc or factionID(npc)~=FACTION then return false,'NPC_FACTION_NOT_READY' end
 local pass,report,objects,summary=Audit.auditAllNPC(parent)
 if not objects or not summary or summary.matched~=summary.expected then
  return false,'INCOMPLETE_MATCH '..tostring(report)
 end
 if pass then
  Log.console('NPC_FURN_RESTORE shop='..shop..' building='..k..' source='..tostring(source)
   ..' status=PASS already_correct='..summary.expected)
  return true,'ALL_CORRECT'
 end
 -- Verify all indices before any native setter. All objects are from THIS shop.
 for i=1,summary.expected do
  if not objects[i] or call(objects[i],'isValid')~=true then
   return false,'INVALID_CHILD '..i
  end
 end
 local ap,apWhy=active(npc)
 if not ap then return false,apWhy end
 local fixed=0
 for i=1,summary.expected do
  local child=objects[i]
  if ownerID(child)~=FACTION or call(child,'isThePlayer')~=false then
   local previous=ownerID(child)
   local ok,err=pcall(child.setFaction,child,npc,ap)
   local changed=ownerID(child)
   if not ok or changed~=FACTION or call(child,'isThePlayer')~=false then
    Log.error('NPC_FURN_ITEM_FAIL shop='..shop..' building='..k..' index='..i
     ..' before='..tostring(previous)..' after='..tostring(changed)..' error='..tostring(err))
    return false,'NATIVE_SET_FAIL index='..i..' fixed='..fixed
   end
   fixed=fixed+1
   call(child,'notifyChange')
   if ownerID(parent)~=FACTION or call(parent,'isThePlayer')~=false then
    Log.error('NPC_FURN_PARENT_CASCADE shop='..shop..' building='..k..' index='..i)
    return false,'PARENT_CHANGED index='..i
   end
  end
 end
 if fixed>0 then call(parent,'notifyChange') end
 local finalPass,finalReport=Audit.auditAllNPC(parent)
 local detail='source='..tostring(source)..' fixed='..fixed..' '..tostring(finalReport)
 Log.console('NPC_FURN_RESTORE shop='..shop..' building='..k..' '..detail)
 return finalPass,detail
end
function M.request(parent,source)
 if sid(parent)=='100-KenshiShop.mod' then return false,'BAR_SPLIT_ISOLATED' end
 local shop=sid(parent)
 if not ({['101-KenshiShop.mod']=true,['102-KenshiShop.mod']=true,
          ['103-KenshiShop.mod']=true,['104-KenshiShop.mod']=true,['105-KenshiShop.mod']=true})[shop] then
  return false,'UNSUPPORTED_SHOP'
 end
 local k=key(parent)
 if Retirement.retired(k) then return false,'BUILDING_RETIRED' end
 local handle=call(parent,'getHandle')
 if not k or not handle then return false,'HANDLE_UNAVAILABLE' end
 local old=states[k]
 if old and old.hook then return true,'ALREADY_SCHEDULED' end
 local s={key=k,handle=handle,shop=shop,source=source or 'UNKNOWN',frame=0,attempts=0}
 states[k]=s
 local ok,hook=pcall(Events.on,'MyGUI::Gui::eventFrameStart',function()
  if Retirement.retired(k) then M.retire(k);return end
  s.frame=s.frame+1
  if s.attempts>=MAX_ATTEMPTS or s.frame>FRAMES[MAX_ATTEMPTS]+3 then
   if s.hook then Events.off(s.hook);s.hook=nil end
   states[k]=nil;return
  end
  if s.frame<FRAMES[s.attempts+1] then return end
  s.attempts=s.attempts+1
  local b=call(s.handle,'getBuilding')
  local invoked,good,detail
  if not b or call(b,'isValid')~=true or sid(b)~=shop or key(b)~=k then
   invoked=false;detail='BUILDING_UNLOADED_OR_CHANGED'
  else
   invoked,good,detail=pcall(M.apply,b,s.source..'_TRY_'..s.attempts)
  end
  local success=invoked and good
  local outcome=invoked and tostring(detail) or tostring(good or detail)
  Log.console('NPC_FURN_ATTEMPT shop='..shop..' building='..k..' attempt='..s.attempts
   ..'/'..MAX_ATTEMPTS..' success='..tostring(success)..' reason='..outcome)
  if success or s.attempts>=MAX_ATTEMPTS then
   if not success then Log.error('NPC_FURN_RESTORE_STOP shop='..shop..' building='..k
     ..' failed_after_3 reason='..outcome) end
   if s.hook then Events.off(s.hook);s.hook=nil end
   states[k]=nil
  end
 end)
 if ok and hook then s.hook=hook;return true,'SCHEDULED' end
 states[k]=nil
 return false,'FRAME_HOOK_FAIL '..tostring(hook)
end
function M.retire(k)
 local s=states[k]
 if s and s.hook then Events.off(s.hook) end
 states[k]=nil
end
function M.resetSession()
 for _,s in pairs(states)do if s.hook then Events.off(s.hook) end end
 states={}
end
return M
