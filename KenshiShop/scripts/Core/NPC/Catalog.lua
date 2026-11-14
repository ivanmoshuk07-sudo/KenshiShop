-- Resolve original vendor profiles, copy their stock configuration including zeros.
-- Never create, move or change furniture. Native restock alone manages stock containers.
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local M={}
local prepared={}
local qualityBusy=false
local function norm(s)return tostring(s or ''):lower():gsub('[%s%p_]','')end
local function refs(gm,data,cat,kind)
 local n=Live.call(data,'getListSize',cat)
 if type(n)~='number' or n<0 or n>100 then return nil end
 local out={}
 for i=0,n-1 do
  local sid=Live.call(data,'getFromList',cat,i)
  if not sid or (kind and not Live.call(gm,'getData',sid,kind)) then return nil end
  local v=Live.call(data,'getValueFromList',cat,i)
  if not v then return nil end
  out[#out+1]={sid,v[1],v[2],v[3]}
 end
 return out
end
local function replace(d,cat,list)
 d:clearList(cat);for _,v in ipairs(list)do d:addToList(cat,v[1],v[2],v[3],v[4])end
end
local function listNames(gm,d)
 local found=refs(gm,d,'vendors',49);if not found or #found==0 then return nil end
 local names={}
 for _,v in ipairs(found)do local item=Live.call(gm,'getData',v[1],49);names[#names+1]=norm(item and item.name)end
 return table.concat(names,','),found
end
local function score(gm,d,shop)
 local names=listNames(gm,d);if not names then return 0 end
 local n=norm(d.name)
 if shop=='armour' and d.stringID=='50249-rebirth.mod' then return 100 end
 if shop=='weapons' then
  local leader=Live.call(d,'getFromList','leader',0)
  local ld=leader and Live.call(gm,'getData',leader,1)
  if ld and norm(ld.name)=='quin' then return 100 end
  if n:find('scraphouse',1,true) then return 90 end
  if names:find('scraphouse',1,true) then return 80 end
 elseif shop=='armour' then
  if n:find('armourking',1,true) then return 90 end
 elseif shop=='engineering' then
  if n:find('mechanicalshop',1,true) then return 90 end
  if n:find('techshop',1,true) or n:find('techhuntershop',1,true) then return 80 end
  if names:find('research',1,true) and not names:find('lore',1,true) then return 50 end
 end
 return 0
end
local function source(gm,shop)
 -- Stable FCS IDs from the supplied offline vanilla shop catalogue. Display
 -- names can be translated, and mainList enumeration need not expose squads.
 local ids=({weapons={'56154-rebirth.mod'},armour={'50249-rebirth.mod'},
  engineering={'44855-rebirth.mod','64652-rebirth.mod','2242-gamedata.base'}})[shop] or {}
 for _,sid in ipairs(ids)do
  local d=Live.call(gm,'getData',sid,52)
  if d and d.type==52 and listNames(gm,d)then return d,'NATIVE_ID' end
 end
 local best,value,ambiguous=nil,0,false
 local ok,err=pcall(function()
  local count=0
  for d in pairs(gm.mainList)do
   count=count+1;if count>100000 then error('DATA_SCAN_CAP')end
   if d and d.type==52 and not tostring(d.stringID):find('KenshiShop.mod',1,true) then
    local n=score(gm,d,shop)
    if n>value then best=d;value=n;ambiguous=false
    elseif n>0 and n==value and best.stringID~=d.stringID then ambiguous=true end
   end
  end
 end)
 if not ok then return nil,'SOURCE_SCAN '..tostring(err) end
 if ambiguous then return nil,'SOURCE_AMBIGUOUS' end
 return best,best and 'ORIGINAL_TRADER' or 'SOURCE_NOT_FOUND'
end
local LISTS={'vendors','weapon level','weapons','armour level','armour vendor','weapon vendor','weapon manufacturer','crossbow vendor','robotics vendor','special items','special map items'}
local function scalar(k)
 k=tostring(k):lower()
 return k:find('vendor',1,true) or k:find('weapon',1,true) or k:find('armour',1,true)
  or k:find('armor',1,true) or k:find('robotics level',1,true) or k:find('crossbow level',1,true)
  or k:find('artifacts',1,true) or k:find('special items',1,true) or k:find('special map items',1,true)
end
function M.prepare(cfg)
 if cfg.role~='trader' then return true end
 local world=getGameWorld();local gm=world and world.gamedata
 if not gm then return false,'DATABASE_UNAVAILABLE' end
 local cached=prepared[cfg.template]
 if cached and cached.gm==gm then return true,cached end
 local own=Live.call(gm,'getData',cfg.template,52)
 if not own then return false,'TEMPLATE_MISSING' end
 local donor,why
 if cfg.shop=='weapons' or cfg.shop=='armour' or cfg.shop=='engineering' then donor,why=source(gm,cfg.shop)end
 local lists=donor and refs(gm,donor,'vendors',49) or refs(gm,own,'vendors',49)
 if cfg.shop=='weapons' and not donor then
  -- Never silently certify the small UC vendor again. NPC delivery is independent.
  return false,'SCRAPHOUSE_'..tostring(why)
 end
 if not lists or #lists==0 then return false,'VENDORS_UNAVAILABLE' end
 if cfg.shop=='armour' and not donor then
  -- Log-verified vanilla Armour King vendor; bypass the old generic armour list.
  local sid='50319-rebirth.mod'
  if not Live.call(gm,'getData',sid,49)then return false,'ARMOUR_KING_MISSING'end
  lists={{sid,100,0,0}}
 end
 if cfg.shop=='engineering' then
  -- The former Empire lore list is not an engineering/research catalogue.
  local filtered={};local hasConstruction=false
  for _,v in ipairs(lists)do
   local item=Live.call(gm,'getData',v[1],49)
   if not norm(item and item.name):find('lore',1,true) then filtered[#filtered+1]=v end
   if v[1]=='1502-gamedata.base' then hasConstruction=true end
  end
  if not hasConstruction and Live.call(gm,'getData','1502-gamedata.base',49)then filtered[#filtered+1]={'1502-gamedata.base',100,0,0}end
  lists=filtered
  -- Technology and blueprints use the original Scraphouse vendor records and
  -- their live weights (including other mods), rather than guessed item IDs.
  local scrap=Live.call(gm,'getData','56154-rebirth.mod',52)
  local tech=scrap and refs(gm,scrap,'vendors',49)
  if not donor or not tech then return false,'ENGINEERING_TECH_SOURCE_MISSING' end
  local present={};for _,v in ipairs(lists)do present[v[1]]=true end
  for _,sid in ipairs({'49375-rebirth.mod','56149-rebirth.mod'})do
   if not present[sid]then
    local found
    for _,v in ipairs(tech)do if v[1]==sid then found=v;break end end
    if not found then return false,'ENGINEERING_TECH_LIST_MISSING '..sid end
    lists[#lists+1]=found
   end
  end
 end
 local changes={};local backups={};local numbers={}
 local ok,err=pcall(function()
  for _,cat in ipairs(LISTS)do
   local values=cat=='vendors' and lists or (donor and refs(gm,donor,cat))
   if values then
    backups[cat]=assert(refs(gm,own,cat),'BACKUP_FAILED '..cat)
    changes[cat]=values
   end
  end
  for cat,values in pairs(changes)do replace(own,cat,values)end
  if donor then
   for _,kind in ipairs({'idata','fdata'})do
    for k,v in pairs(donor[kind])do
     if scalar(k) and type(v)=='number' then
      numbers[#numbers+1]={kind,k,own[kind][k]};own[kind][k]=v
     end
    end
   end
  end
 end)
 if not ok then
  for cat,values in pairs(backups)do pcall(replace,own,cat,values)end
  for _,v in ipairs(numbers)do pcall(function()own[v[1]][v[2]]=v[3]end)end
  return false,'PROFILE_COPY_FAILED '..tostring(err)
 end
 local faction=donor and Live.call(donor,'getFromList','faction',0)
 local quality=faction and Live.call(gm,'getData',faction,10)
 local profile={gm=gm,source=donor and donor.stringID or 'EXPLICIT_NATIVE_LIST',lists=lists,quality=quality}
 prepared[cfg.template]=profile
 local labels={};for _,v in ipairs(lists)do local data=Live.call(gm,'getData',v[1],49);labels[#labels+1]=v[1]..':'..tostring(data and data.name)end
 Log.console('NPC_CATALOG83 shop='..cfg.shop..' source='..profile.source..' lists='..table.concat(labels,',')..' quality=FULL_VENDOR_PROFILE_ZERO_VALUES_PRESERVED')
 return true,profile
end
-- Native stock generation reads faction grade weights. Borrow only the quality
-- fields during this synchronous call and restore them even on native failure.
function M.withQuality(s,profile,fn)
 local original=Live.call(Live.call(s.platoon,'getFaction'),'getData')
 local quality=profile.quality
 if not original or not quality or original==quality or qualityBusy then return fn()end
 local backup={};qualityBusy=true
 local ok,result=pcall(function()
  for i=0,5 do
   local key='armors '..i;local value=quality.idata[key]
   if type(value)=='number' and type(original.idata[key])=='number' then
    backup[#backup+1]={key,original.idata[key]};original.idata[key]=value
   end
  end
  return fn()
 end)
 for _,v in ipairs(backup)do original.idata[v[1]]=v[2]end
 qualityBusy=false
 if not ok then error(result)end
 return result
end
function M.ensure(s,ms)
 if s.cfg.role~='trader' then return true end
 local r=s.catalog or {tries=0};s.catalog=r
 if r.done then
  -- Ordinary native refresh is time-gated by Kenshi; this never forces stock.
  local ap=Live.call(s.platoon,'getActivePlatoon')
  if ap and r.profile and Live.safeToOrder(ms) then
   pcall(M.withQuality,s,r.profile,function()ap:refreshInventory(false)end)
  end
  return true
 end
 if r.nextTry and s.now and s.now<r.nextTry then return false end
 local safe=Live.safeToOrder(ms);if not safe then return false end
 local ok,profile=M.prepare(s.cfg)
 if not ok then
  r.tries=r.tries+1;r.nextTry=(s.now or Live.clock())+10
  if r.tries<=3 then Log.error('NPC_CATALOG83_FAIL shop='..s.cfg.shop..' '..tostring(profile))end
  return false
 end
 local ap=Live.call(s.platoon,'getActivePlatoon')
 if not ap or not s.work or not s.work.done then return false end
 local yes,err=pcall(function()
  assert(ap:getHasVendorList()==true,'NO_VENDOR_LIST')
  assert(ap:getIsTrader()==true,'NOT_TRADER')
  ap:setupTraderBuildings()
  -- A saved 810x/820x -> 830x handoff marks the one-time stock migration. The new
  -- package persists in the save, so ordinary reloads never force new goods.
  M.withQuality(s,profile,function()
  if s.saved and s.work.upgraded and not r.migrationAttempted then
   r.migrationAttempted=true
   ap:_forceRefreshInventory()
   Log.console('NPC_CATALOG83_MIGRATED shop='..s.cfg.shop..' native_refresh_once=true')
  else ap:refreshInventory(false) end
  end)
 end)
 if not yes then
  r.tries=r.tries+1;r.nextTry=(s.now or Live.clock())+10
  if r.tries<=3 then Log.error('NPC_CATALOG83_SETUP_FAIL '..tostring(err))end
  return false
 end
 r.done=true;r.profile=profile
 Log.console('NPC_CATALOG83_READY shop='..s.cfg.shop..' source='..profile.source..' native_stock=true')
 return true
end
return M
