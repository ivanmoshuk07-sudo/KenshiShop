-- Native vendor configuration. Never fill personal inventories or force a restock.
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local M={}
local prepared={}
local donorNames={weapons={'scraphouse'},armour={'armour king'},
 robotics={'skeleton limb trader','black desert city robotics'}}
local function lower(x)return string.lower(tostring(x or ''))end
local function vendorRefs(gm,data)
 local count=Live.call(data,'getListSize','vendors')
 if type(count)~='number' or count<1 or count>40 then return nil end
 local out={}
 for i=0,count-1 do
  local sid=Live.call(data,'getFromList','vendors',i)
  local d=sid and Live.call(gm,'getData',sid,49)
  if not d then return nil end
  out[#out+1]=sid
 end
 return out
end
local function donor(gm,shop)
 local names=donorNames[shop];if not names then return nil end
 local selected
 local ok=pcall(function()
  local n=0
  for data in pairs(gm.mainList)do
   n=n+1;if n>100000 then error('DATA_SCAN_LIMIT') end
   if data and data.type==52 and not tostring(data.stringID):find('KenshiShop.mod',1,true) then
    local name=lower(data.name)
    for _,needle in ipairs(names)do
     if name:find(needle,1,true) and vendorRefs(gm,data) then
      if selected and selected.stringID~=data.stringID then error('AMBIGUOUS_DONOR') end
      selected=data;break
     end
    end
   end
  end
 end)
 return ok and selected or nil
end
function M.prepare(cfg)
 if cfg.role~='trader' then return true end
 local w=getGameWorld();local gm=w and w.gamedata
 if not gm then return false,'CATALOG_DATABASE_UNAVAILABLE' end
 if prepared[cfg.template]==gm then return true end
 local own=Live.call(gm,'getData',cfg.template,52)
 if not own then return false,'CATALOG_TEMPLATE_MISSING' end
 local source=donor(gm,cfg.shop)
 local refs=source and vendorRefs(gm,source) or vendorRefs(gm,own)
 if not refs then return false,'CATALOG_VENDOR_LIST_MISSING' end
 -- Only this mod's template changes. Original shops remain untouched.
 if source then
  local ok,err=pcall(function()
   local values={}
   for i,sid in ipairs(refs)do
    local v=source:getValueFromList('vendors',i-1)
    values[i]={sid,v[1],v[2],v[3]}
   end
   local backup={}
   local n=own:getListSize('vendors')
   for i=0,n-1 do
    local v=own:getValueFromList('vendors',i)
    backup[#backup+1]={own:getFromList('vendors',i),v[1],v[2],v[3]}
   end
   local function replace(list)
    own:clearList('vendors')
    for _,v in ipairs(list)do own:addToList('vendors',v[1],v[2],v[3],v[4])end
   end
   local yes,why=pcall(replace,values)
   if not yes then pcall(replace,backup);error(why) end
   -- Native stock quality/quantity belong to the donor's vendor configuration.
   for _,field in ipairs({'vendors fill total amount','vendor money','gear artifacts base value',
    'item artifacts base value','crossbow levels','robotics levels'})do
    local value=source.idata[field]
    if type(value)=='number' and value>0 then own.idata[field]=value end
   end
   local refresh=source.fdata['vendors refresh time']
   if type(refresh)=='number' and refresh>0 then own.fdata['vendors refresh time']=refresh end
  end)
  if not ok then return false,'CATALOG_COPY_FAILED '..tostring(err) end
 end
 prepared[cfg.template]=gm
 local labels={}
 for _,sid in ipairs(refs)do
  local data=Live.call(gm,'getData',sid,49)
  labels[#labels+1]=sid..':'..tostring(data and data.name)
 end
 Log.console('NPC_CATALOG shop='..cfg.shop..' source='..tostring(source and source.stringID or 'FCS_FALLBACK')
  ..' lists='..table.concat(labels,',')..' restock=native')
 return true
end
function M.ensure(s,ms)
 if s.cfg.role~='trader' then return true end
 local r=s.catalog or {tries=0};s.catalog=r
 if r.done then return true end
 if r.tries>=3 then return false end
 local safe=Live.safeToOrder(ms);if not safe then return false end
 local ok,why=M.prepare(s.cfg)
 if not ok then r.tries=r.tries+1;Log.error('NPC_CATALOG_FAIL '..tostring(why));return false end
 local ap=Live.call(s.platoon,'getActivePlatoon')
 if not ap then return false end
 -- Existing inventories and their saved refresh time are left to the engine.
 local yes,err=pcall(function()
  assert(ap:getHasVendorList()==true,'NO_NATIVE_VENDOR_LIST')
  assert(ap:getIsTrader()==true,'NOT_NATIVE_TRADER')
  ap:setupTraderBuildings()
  ap:refreshInventory(false)
 end)
 if not yes then r.tries=r.tries+1;Log.error('NPC_CATALOG_SETUP_FAIL '..tostring(err));return false end
 r.done=true
 Log.console('NPC_CATALOG_READY shop='..s.cfg.shop..' native_refresh=true gameplay=UNVERIFIED')
 return true
end
return M
