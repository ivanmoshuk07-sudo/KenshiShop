-- Save-scoped police service ledger. Only plain Lua data is serialized; no
-- file I/O, executable deserialization, engine objects or event hooks here.
local M={}
local KEY='KenshiShopChiefStateV1'
local RECOVERY_KEY=KEY..'Recovery'
local ORDERS_KEY=KEY..'Orders'
local ORDERS_FAILURE_KEY=ORDERS_KEY..'Failure'
local EVACUATION_KEY=KEY..'Departures'
local MAGIC='KSCS1:'
local ENVELOPE='KSCS2:'
local RECOVERY='KSHOLD2:'
local CHUNK_MANIFEST='KSCH3:'
local UNRESOLVED='KSCS_SAVE_FAILED:'
local MAX_BYTES=2*1024*1024
local MAX_TRANSPORT=MAX_BYTES*2+128
-- Native saves have reloaded strings clipped to 4095 bytes even when the
-- in-memory GameData readback was exact. Keep every written field below it.
local CHUNK_BYTES=3000
local MAX_CHUNKS=math.ceil(MAX_TRANSPORT/CHUNK_BYTES)
local MAX_DEPTH=12
local MAX_ENTRIES=20000
local state,ready,held,diagnostic
local departure,departureReady,departureHeld
local newOrders,newOrdersHeld
local function blank()return {version=1,seq=0,roster={},orders={},patrols={}}end
function M.reset()
 state=blank();ready=false;held=nil
 newOrders=false;newOrdersHeld=nil
 departure={evacuations={},buildings={},squads={}};departureReady=false;departureHeld=nil
 state.evacuations=departure.evacuations
 diagnostic={error=nil,source='NONE',format='NONE',bytes=0,preserved=false,historyMarker=false}
end
M.reset()
function M.get()return state end
function M.ready()return ready and departureReady end
function M.legacyOrdersArchived()return newOrders end
function M.canStartNewOrders()
 return not ready and not newOrders and departureReady and held~=nil
  and diagnostic.legacyClip==true and diagnostic.prefixError=='STORE_TRUNCATED'
end
function M.startNewOrders()
 if not M.canStartNewOrders() then return false,'STORE_NEW_ORDERS_UNAVAILABLE' end
 state.orders={};state.patrols={};state.seq=0;state.partialRoster=true
 newOrders=true;ready=true
 diagnostic.legacyError=diagnostic.error;diagnostic.error=nil;diagnostic.source='NEW_ORDERS'
 return true
end
function M.status()
 return {ready=M.ready(),error=diagnostic.error,source=diagnostic.source,format=diagnostic.format,
  bytes=diagnostic.bytes,held=held~=nil,preserved=diagnostic.preserved,saveError=diagnostic.saveError,
  historyMarker=diagnostic.historyMarker,partialRoster=state.partialRoster==true,
  departureError=diagnostic.departureError,prefixError=diagnostic.prefixError,
  legacyError=diagnostic.legacyError,newOrders=newOrders}
end
function M.diagnostics()
 local d=M.status()
 return 'ready='..tostring(d.ready)..' error='..tostring(d.error or 'NONE')..' source='..d.source
  ..' format='..d.format..' bytes='..d.bytes..' held='..tostring(d.held)..' preserved='..tostring(d.preserved)
  ..' history_marker='..tostring(d.historyMarker)..' partial_roster='..tostring(d.partialRoster)
  ..' departure_error='..tostring(d.departureError or 'NONE')
  ..' prefix_error='..tostring(d.prefixError or 'NONE')
  ..' new_orders='..tostring(d.newOrders)..' legacy_error='..tostring(d.legacyError or 'NONE')
end
local function fail(message)error(message,0)end
local function finite(n)return n==n and n~=math.huge and n~=-math.huge end
local function checksum(source)
 local a,b=1,0
 for i=1,#source do a=(a+source:byte(i))%65521;b=(b+a)%65521 end
 return b*65536+a
end
local function envelope(source,prefix)
 if type(source)~='string' then fail('STORE_ENCODING_INVALID')end
 if #source>MAX_BYTES then fail('STORE_BYTES_LIMIT')end
 local hex={}
 for i=1,#source do hex[i]=string.format('%02x',source:byte(i))end
 return prefix..#source..':'..string.format('%.0f',checksum(source))..':'..table.concat(hex)
end
local function unwrap(source,prefix)
 if type(source)~='string' then fail('STORE_ENCODING_INVALID')end
 if #source>MAX_TRANSPORT then fail('STORE_BYTES_LIMIT')end
 if source:sub(1,#prefix)~=prefix then fail('STORE_ENCODING_INVALID')end
 local size,digest,hex=source:sub(#prefix+1):match('^(%d+):(%d+):([0-9a-fA-F]*)$')
 if not size or #size>8 or #digest>10 then fail('STORE_ENVELOPE_INVALID')end
 size,digest=tonumber(size),tonumber(digest)
 if size>MAX_BYTES then fail('STORE_BYTES_LIMIT')end
 if #hex~=size*2 then fail('STORE_ENVELOPE_LENGTH')end
 local bytes={}
 for i=1,#hex,2 do bytes[#bytes+1]=string.char(tonumber(hex:sub(i,i+1),16))end
 local raw=table.concat(bytes)
 if checksum(raw)~=digest then fail('STORE_CHECKSUM_INVALID')end
 return raw
end
local function format(source)
 if type(source)~='string' then return source==nil and 'NONE' or 'INVALID_TYPE'end
 if source:sub(1,#CHUNK_MANIFEST)==CHUNK_MANIFEST then return 'CHUNK_MANIFEST'end
 if source:sub(1,#ENVELOPE)==ENVELOPE then return 'ASCII_HEX'end
 if source:sub(1,#RECOVERY)==RECOVERY then return 'RECOVERY_ENVELOPE'end
 if source:sub(1,#MAGIC)==MAGIC then return 'LEGACY'end
 if source:sub(1,#UNRESOLVED)==UNRESOLVED then return 'SAVE_FAILURE_MARKER'end
 return 'UNKNOWN'
end
local function schema(value)
 if type(value)~='table' or value.version~=1 then fail('STORE_VERSION_UNSUPPORTED')end
 if type(value.seq)~='number' or not finite(value.seq) or value.seq<0 or value.seq%1~=0 then fail('STORE_SEQUENCE_INVALID')end
 for _,key in ipairs({'roster','orders','patrols'})do
  if type(value[key])~='table' then fail('STORE_CONTAINER_INVALID '..key)end
 end
end
local rank={boolean=1,number=2,string=3}
local function numberText(value)
 if not finite(value) then fail('STORE_NUMBER_INVALID')end
 -- Lua 5.4 integers can exceed the exact range of an IEEE double. Preserve
 -- them as integers where supported rather than rounding through %.17g.
 if math.type and math.type(value)=='integer' then return tostring(value)end
 return string.format('%.17g',value)
end
local function encode(value)
 local chunks,total,entries,active={},0,0,{}
 local function append(text)
  total=total+#text;if total>MAX_BYTES then fail('STORE_BYTES_LIMIT')end
  chunks[#chunks+1]=text
 end
 local write
 write=function(item,depth)
  local kind=type(item)
  if kind=='string' then append('S'..#item..':');append(item)
  elseif kind=='number' then local text=numberText(item);append('N'..#text..':');append(text)
  elseif kind=='boolean' then append(item and 'B1' or 'B0')
  elseif kind=='table' then
   if depth>MAX_DEPTH then fail('STORE_DEPTH_LIMIT')end
   if getmetatable(item)~=nil or active[item] then fail('STORE_NONPLAIN_TABLE')end
   local keys={}
   for key in pairs(item)do
    if not rank[type(key)] then fail('STORE_KEY_TYPE_INVALID')end
    if type(key)=='number' then numberText(key)end
    keys[#keys+1]=key;entries=entries+1
    if entries>MAX_ENTRIES then fail('STORE_ENTRIES_LIMIT')end
   end
   table.sort(keys,function(a,b)
    local ta,tb=type(a),type(b)
    if ta~=tb then return rank[ta]<rank[tb]end
    if ta=='boolean' then return a==false and b==true end
    return a<b
   end)
   active[item]=true;append('T'..#keys..':')
   for _,key in ipairs(keys)do write(key,depth+1);write(item[key],depth+1)end
   active[item]=nil
  else fail('STORE_VALUE_TYPE_INVALID '..kind)end
 end
 append(MAGIC);write(value,1)
 return table.concat(chunks)
end
local function decode(source,clipped)
 if type(source)~='string' then fail('STORE_ENCODING_INVALID')end
 if #source>MAX_BYTES then fail('STORE_BYTES_LIMIT')end
 if source:sub(1,#MAGIC)~=MAGIC then fail('STORE_ENCODING_INVALID')end
 local at,entries=#MAGIC+1,0
 local function length(limit)
  local first=at
  while at<=#source do
   local byte=source:byte(at)
   if byte<48 or byte>57 then break end
   at=at+1
   if at-first>8 then fail('STORE_LENGTH_INVALID')end
  end
  if at>#source then fail('STORE_TRUNCATED')end
  if at==first or source:sub(at,at)~=':' then fail('STORE_LENGTH_INVALID')end
  local value=tonumber(source:sub(first,at-1));at=at+1
  if not value or value>limit then fail('STORE_LENGTH_LIMIT')end
  return value
 end
 local read
 read=function(depth)
  if at>#source then fail('STORE_TRUNCATED')end
  local tag=source:sub(at,at);at=at+1
  if tag=='S' or tag=='N' then
   local size=length(tag=='N' and 64 or MAX_BYTES)
   if at+size-1>#source then fail('STORE_TRUNCATED')end
   local text=source:sub(at,at+size-1);at=at+size
   if tag=='S' then return text end
   if text=='' or text:find('[^0-9eE+%.%-]') then fail('STORE_NUMBER_INVALID')end
   local value=tonumber(text)
   if not value or not finite(value) then fail('STORE_NUMBER_INVALID')end
   return value
  elseif tag=='B' then
   if at>#source then fail('STORE_TRUNCATED')end
   local value=source:sub(at,at);at=at+1
   if value=='0' then return false elseif value=='1' then return true end
   fail('STORE_BOOLEAN_INVALID')
  elseif tag=='T' then
   if depth>MAX_DEPTH then fail('STORE_DEPTH_LIMIT')end
   local count=length(MAX_ENTRIES);entries=entries+count
   if entries>MAX_ENTRIES then fail('STORE_ENTRIES_LIMIT')end
   local result,seen={},{}
   for _=1,count do
    local key=read(depth+1)
    if not rank[type(key)] then fail('STORE_KEY_TYPE_INVALID')end
    if seen[key] then fail('STORE_DUPLICATE_KEY')end
    seen[key]=true;result[key]=read(depth+1)
   end
   return result
  end
  fail('STORE_TAG_INVALID')
 end
 if clipped then
  local function literal(token)
   local found=source:sub(at,at+#token-1)
   if #found<#token and found==token:sub(1,#found) then fail('STORE_TRUNCATED')end
   if found~=token then fail('STORE_PREFIX_STRUCTURE_INVALID')end
   at=at+#token
  end
  local value=blank()
  literal('T5:S6:orders');value.orders=read(2)
  literal('S7:patrols');value.patrols=read(2)
  -- Both payment containers must be complete. The later roster contains
  -- observations and may be recovered only through its last complete row.
  local complete,why=pcall(function()
   literal('S6:rosterT')
   local seen={}
   local n=length(MAX_ENTRIES);entries=entries+n
   if entries>MAX_ENTRIES then fail('STORE_ENTRIES_LIMIT')end
   for _=1,n do
    local key=read(3)
    if type(key)~='string' or seen[key] then fail('STORE_ROSTER_KEY_INVALID')end
    seen[key]=true;value.roster[key]=read(3)
   end
   literal('S3:seq');value.seq=read(2)
   literal('S7:versionN1:1')
  end)
  if complete then fail('STORE_PREFIX_NOT_TRUNCATED')end
  if why~='STORE_TRUNCATED' then fail(why)end
  value.partialRoster=true
  return value
 end
 local value=read(1)
 if at~=#source+1 then fail('STORE_TRAILING_DATA')end
 return value
end
local function text(value)return type(value)=='string' and value~=''end
local function decodeClippedEnvelope(source,prefix)
 if source:sub(1,#prefix)~=prefix then return nil end
 local size,digest,hex=source:sub(#prefix+1):match('^(%d+):(%d+):([0-9a-f]*)$')
 if not size or #size>8 or #digest>10 then return nil end
 size,digest=tonumber(size),tonumber(digest)
 if size>MAX_BYTES or #hex>=size*2 or digest>4294967295 then return nil end
 hex=hex:sub(1,#hex-#hex%2)
 return (hex:gsub('..',function(pair)return string.char(tonumber(pair,16))end))
end
local statuses={pending_payment=true,pending=true,refund_pending=true,refunded=true,cancelled=true,complete=true}
local prices={hire=20000,replace=10000}
local function clippedSource(saved)
 if type(saved)~='string' or #saved~=4095 then fail('STORE_NOT_NATIVE_CLIP')end
 local raw=saved
 -- Pre-chunk releases could re-wrap already-clipped fields each time the
 -- save was opened and written again. Each decode discards the header and
 -- at least halves the byte count, so even repeated clipping is bounded.
 while raw:sub(1,#RECOVERY)==RECOVERY do
  raw=decodeClippedEnvelope(raw,RECOVERY)
  if raw==nil then fail('STORE_PREFIX_RECOVERY_INVALID')end
 end
 if raw:sub(1,#ENVELOPE)==ENVELOPE then
  raw=decodeClippedEnvelope(raw,ENVELOPE)
  if raw==nil then fail('STORE_PREFIX_ENVELOPE_INVALID')end
 end
 return raw
end
local function recoverClipped(saved)
 local raw=clippedSource(saved)
 -- Old saves used sorted keys with a fixed five-field header. Verify the
 -- remaining bytes agree with that header before offering a new ledger.
 local signature=MAGIC..'T5:S6:ordersT'
 diagnostic.legacyClip=#raw>=#MAGIC and raw:sub(1,math.min(#raw,#signature))==signature:sub(1,#raw)
 local value=decode(raw,true)
 schema(value)
 local largest,n=0,0
 for key,row in pairs(value.orders)do
  local index=type(key)=='string' and tonumber(key)
  local meta=type(row)=='table' and row.metadata
  if not index or index<1 or index%1~=0 or tostring(index)~=key
   or type(meta)~='table' or row.id~=key or not prices[row.kind] or prices[row.kind]~=row.cost or not statuses[row.status]
   or not text(row.subject) or not text(meta.town) or not text(meta.building)
   or (row.kind=='replace' and (not text(meta.deadID) or row.subject~='replace:'..meta.deadID)) then
   fail('STORE_PREFIX_ORDER_INVALID')
  end
  largest=math.max(largest,index);n=n+1
 end
 -- Pre-departure ledgers never removed receipts. A gap may hide an old
 -- charge, so even a syntactically complete payment map cannot be adopted.
 if largest~=n or (value.seq~=0 and value.seq~=largest) then fail('STORE_PREFIX_SEQUENCE_MISMATCH')end
 value.seq=largest
 for pid,row in pairs(value.patrols)do
  local order=type(row)=='table' and value.orders[row.order]
  if not text(pid) or not order or order.kind~='hire' or row.pid~=pid or order.pid~=pid
   or row.town~=order.metadata.town or row.building~=order.metadata.building
   or type(row.base)~='number' or row.base<0 or row.base%1~=0
   or type(row.number)~='number' or row.number<1 or row.number%1~=0 then
   fail('STORE_PREFIX_PATROL_INVALID')
  end
 end
 for _,row in pairs(value.orders)do
  if row.kind=='hire' and row.status=='complete' and not value.patrols[row.pid] then fail('STORE_PREFIX_PATROL_MISSING')end
 end
 for key,row in pairs(value.roster)do
  if type(row)~='table' or row.id~=key or not text(row.pid) or not text(row.town)
   or not text(row.building) or not text(row.squadTemplate) or type(row.dead)~='boolean'
   or (row.order and not value.orders[row.order]) then fail('STORE_PREFIX_ROSTER_INVALID')end
 end
 return value
end
local function readSaved(saved)
 if type(saved)=='string' and saved:sub(1,#ENVELOPE)==ENVELOPE then saved=unwrap(saved,ENVELOPE)end
 local value=decode(saved);schema(value);return value
end
local function writeField(gameData,key,saved)
 if not gameData or not gameData.sdata then fail('STORE_GAME_DATA_UNAVAILABLE')end
 gameData:addString(key,saved,'KenshiShop',false)
 -- Some implementations only add a field once. Verify both native routes.
 if gameData.sdata[key]~=saved then gameData.sdata[key]=saved end
 if gameData.sdata[key]~=saved then fail('STORE_SAVE_VERIFY_FAILED')end
end
local function chunkKey(key,index)
 return key..'Chunk'..index
end
local function chunkIndex(field,key)
 if type(field)~='string' then return end
 local suffix=field:match('^'..key..'Chunk([1-9]%d*)$')
 local index=suffix and tonumber(suffix)
 if index and index<=MAX_CHUNKS then return index end
end
local function manifest(value)
 if type(value)~='string' or value:sub(1,#CHUNK_MANIFEST)~=CHUNK_MANIFEST then return end
 if #value>32 then fail('STORE_CHUNK_MANIFEST_INVALID')end
 local size,digest=value:sub(#CHUNK_MANIFEST+1):match('^(%d+):(%d+)$')
 size,digest=tonumber(size),tonumber(digest)
 if not size or size<=CHUNK_BYTES or size>MAX_TRANSPORT or not digest or digest>4294967295 then
  fail('STORE_CHUNK_MANIFEST_INVALID')
 end
 return math.ceil(size/CHUNK_BYTES),size,digest
end
local function readTransport(fields,key,header)
 local count,size,digest=manifest(header)
 if not count then return header end
 local parts={}
 for i=1,count do
  local part=fields[chunkKey(key,i)]
  if part==nil then fail('STORE_CHUNK_MISSING '..i)end
  if type(part)~='string' or #part~=math.min(CHUNK_BYTES,size-(i-1)*CHUNK_BYTES)
   or part:find('[^\32-\126]') then fail('STORE_CHUNK_INVALID '..i)end
  parts[i]=part
 end
 local payload=table.concat(parts)
 if checksum(payload)~=digest then fail('STORE_CHUNK_CHECKSUM_INVALID')end
 return payload
end
local function clearChunks(fields,key,count,clearRecovery)
 local stale={}
 -- A failed rewrite can leave numbered fields outside the old manifest or
 -- gaps between fields. Snapshot only the keys in our reserved namespace.
 for partKey in pairs(fields)do
  local index=chunkIndex(partKey,key)
  if (index and index>count) or (clearRecovery and chunkIndex(partKey,RECOVERY_KEY)) then
   stale[#stale+1]=partKey
  end
 end
 for _,partKey in ipairs(stale)do
  fields[partKey]=nil
  if fields[partKey]~=nil then fail('STORE_CHUNK_CLEAR_FAILED')end
 end
end
local function writeTransport(gameData,key,payload,clearRecovery)
 local fields=gameData and gameData.sdata
 if not fields then fail('STORE_GAME_DATA_UNAVAILABLE')end
 if #payload>MAX_TRANSPORT then fail('STORE_BYTES_LIMIT')end
 local count=0
 if #payload<=CHUNK_BYTES then
  writeField(gameData,key,payload)
 else
  count=math.ceil(#payload/CHUNK_BYTES)
  for i=1,count do
   writeField(gameData,chunkKey(key,i),payload:sub((i-1)*CHUNK_BYTES+1,i*CHUNK_BYTES))
  end
  local header=CHUNK_MANIFEST..#payload..':'..string.format('%.0f',checksum(payload))
  writeField(gameData,key,header)
 end
 if readTransport(fields,key,fields[key])~=payload then fail('STORE_SAVE_VERIFY_FAILED')end
 clearChunks(fields,key,count,clearRecovery)
end
local function identitySet(values)
 if type(values)~='table' then fail('STORE_DEPARTURE_IDS_INVALID')end
 for key,value in pairs(values)do
  if not text(key) or value~=true then fail('STORE_DEPARTURE_ID_INVALID')end
 end
end
local function departurePlan(town,plan)
 if not text(town) or type(plan)~='table' or not text(plan.anchor) then fail('STORE_DEPARTURE_SCOPE_INVALID')end
 identitySet(plan.buildings)
 if plan.property~=nil then identitySet(plan.property)end
 if plan.departed~=nil and type(plan.departed)~='boolean' then fail('STORE_DEPARTURE_STATUS_INVALID')end
 if plan.buildings[plan.anchor]~=true or type(plan.squads)~='table' then fail('STORE_DEPARTURE_ANCHOR_INVALID')end
 for pid,row in pairs(plan.squads)do
  if not text(pid) or type(row)~='table' or not text(row.template) or not text(row.building)
   or (row.handle~=nil and not text(row.handle))
   or plan.buildings[row.building]~=true then fail('STORE_DEPARTURE_SQUAD_INVALID')end
 end
end
local function departureSchema(value)
 if type(value)~='table' or type(value.evacuations)~='table' then fail('STORE_DEPARTURE_INVALID')end
 identitySet(value.buildings);identitySet(value.squads)
 local claimedBuilding,claimedSquad={},{}
 for town,plan in pairs(value.evacuations)do
  departurePlan(town,plan)
  for key in pairs(plan.buildings)do
   if value.buildings[key]~=true or claimedBuilding[key] then fail('STORE_DEPARTURE_BUILDING_CONFLICT')end
   claimedBuilding[key]=true
  end
  for pid in pairs(plan.squads)do
   if value.squads[pid]~=true or claimedSquad[pid] then fail('STORE_DEPARTURE_SQUAD_CONFLICT')end
   claimedSquad[pid]=true
  end
 end
end
function M.evacuationReady()return departureReady end
function M.evacuationCorrupt()return diagnostic.departureError~=nil end
function M.evacuation(town)return departure.evacuations[town]end
function M.retiredBuilding(key)return departure.buildings[key]==true end
function M.retiredPlatoon(pid)return departure.squads[pid]==true end
function M.beginEvacuation(town,plan)
 if not departureReady then return false,'STORE_DEPARTURE_NOT_READY'end
 if departure.evacuations[town] then return false,'STORE_DEPARTURE_ALREADY_STARTED'end
 local ok,copied=pcall(function()
  -- Snapshot plain persisted data before awarding any retirement marker.
  local copy=decode(encode(plan));departurePlan(town,copy)
  for key in pairs(copy.buildings)do
   if M.retiredBuilding(key) then fail('STORE_DEPARTURE_BUILDING_CONFLICT')end
  end
  for pid in pairs(copy.squads)do
   if M.retiredPlatoon(pid) then fail('STORE_DEPARTURE_SQUAD_CONFLICT')end
  end
  return copy
 end)
 if not ok then return false,tostring(copied)end
 for key in pairs(copied.buildings)do departure.buildings[key]=true end
 for pid in pairs(copied.squads)do departure.squads[pid]=true end
 departure.evacuations[town]=copied
 return true,copied
end
function M.finishEvacuation(town)
 if not departureReady then return false,'STORE_DEPARTURE_NOT_READY'end
 local plan=departure.evacuations[town]
 if not plan then return false,'STORE_DEPARTURE_NOT_FOUND'end
 local function belongs(rowTown,building,pid)
  if text(rowTown) then return rowTown==town end
  return plan.buildings[building]==true or plan.squads[pid]~=nil
 end
 for key,row in pairs(state.roster)do
  if type(row)=='table' and belongs(row.town,row.building,row.pid) then state.roster[key]=nil end
 end
 for key,row in pairs(state.patrols)do
  if type(row)=='table' and belongs(row.town,row.building,row.pid) then state.patrols[key]=nil end
 end
 for key,row in pairs(state.orders)do
  if type(row)=='table' then
   local meta=type(row.metadata)=='table' and row.metadata or {}
   if belongs(meta.town,meta.building,row.pid) then state.orders[key]=nil end
  end
 end
 departure.evacuations[town]=nil
 return true
end
local function loadDepartures(gameData)
 local ok,result=pcall(function()
  local fields=gameData and gameData.sdata
  if not fields then fail('STORE_GAME_DATA_UNAVAILABLE')end
  local header=fields[EVACUATION_KEY]
  if header==nil then
   for key in pairs(fields)do
    if chunkIndex(key,EVACUATION_KEY) then fail('STORE_DEPARTURE_MANIFEST_MISSING')end
   end
   return departure
  end
  local saved=readTransport(fields,EVACUATION_KEY,header)
  if type(saved)=='string' then departureHeld=saved end
  local value=decode(unwrap(saved,ENVELOPE));departureSchema(value)
  return value
 end)
 if ok then departure=result;departureReady=true;departureHeld=nil
 else diagnostic.departureError=tostring(result)end
 state.evacuations=departure.evacuations
end
local function saveDepartures(gameData)
 if not departureReady then
  -- Save GameData may be reconstructed by the engine. Preserve a readable
  -- damaged payload or a bounded marker if its original chunks are missing.
  local saved=departureHeld or envelope(UNRESOLVED..tostring(diagnostic.departureError):sub(1,512),ENVELOPE)
  writeTransport(gameData,EVACUATION_KEY,saved)
  return
 end
 if next(departure.buildings)==nil then return end
 departureSchema(departure)
 writeTransport(gameData,EVACUATION_KEY,envelope(encode(departure),ENVELOPE))
end
local function failureMarker(gameData,why,key)
 -- A failed encode/write must not make the next native save look like a new
 -- campaign. The bounded marker preserves uncertainty, not the missing data.
 local saved=envelope(UNRESOLVED..tostring(why):sub(1,512),RECOVERY)
 writeTransport(gameData,key or RECOVERY_KEY,saved)
end
local function loaded(value)
 state=value;state.evacuations=departure.evacuations;ready=true
 if diagnostic.departureError then return false,'STORE_DEPARTURE_HELD '..diagnostic.departureError end
 return true
end
local function loadLegacy(gameData)
 local saved
 local ok,result=pcall(function()
  if not gameData or not gameData.sdata then fail('STORE_GAME_DATA_UNAVAILABLE')end
  local fields=gameData.sdata
  local recoveryHeader,primaryHeader=fields[RECOVERY_KEY],fields[KEY]
  local orphanRecovery,orphanPrimary=false,false
  if recoveryHeader==nil then
   -- A missing manifest with any surviving chunk is not an empty history.
   for partKey in pairs(fields)do
    if chunkIndex(partKey,RECOVERY_KEY) then orphanRecovery=true;break end
    if primaryHeader==nil and chunkIndex(partKey,KEY) then orphanPrimary=true end
   end
  end
  local function readSlot(key,orphaned)
   saved=fields[key]
   local complete,payload=false,'STORE_CHUNK_MANIFEST_MISSING'
   if not orphaned then complete,payload=pcall(readTransport,fields,key,saved)end
   if not complete then
    -- Incomplete chunks cannot be certified as the original paid history.
    -- Retain a bounded warning rather than a manifest that cannot stand alone.
    held={raw=UNRESOLVED..tostring(payload):sub(1,512),marker=true}
    diagnostic.historyMarker=true
    fail(payload)
   end
   saved=payload
   return payload
  end
  if recoveryHeader~=nil or orphanRecovery then
   -- A recovery field records an unresolved history, not a backup authorized
   -- for automatic rollback. Even a valid primary cannot erase that warning.
   diagnostic.source='RECOVERY'
   local recovery=readSlot(RECOVERY_KEY,orphanRecovery)
   local restored,raw
   if type(recovery)=='string' and #recovery>MAX_BYTES and #recovery<=MAX_TRANSPORT
    and recovery:sub(1,#RECOVERY)~=RECOVERY and not recovery:find('[^\32-\126]') then
    -- New-format primary fields can exceed the raw codec limit after hex
    -- encoding. Their already safe ASCII bytes need no second expansion.
    restored,raw=true,recovery
   else restored,raw=pcall(unwrap,recovery,RECOVERY)end
   if not restored then fail('STORE_RECOVERY_INVALID '..tostring(raw))end
   held={raw=raw,envelope=recovery};saved=raw
   if raw:sub(1,#UNRESOLVED)==UNRESOLVED then
    held.marker=true;diagnostic.historyMarker=true
    fail('STORE_HISTORY_UNRESOLVED '..raw:sub(#UNRESOLVED+1))
   end
   local decoded,why=pcall(readSaved,raw)
   fail(decoded and 'STORE_RECOVERY_HELD' or tostring(why))
  end
  diagnostic.source='PRIMARY';saved=readSlot(KEY,orphanPrimary)
  if saved==nil then diagnostic.source='NONE';return blank()end
  return readSaved(saved)
 end)
 diagnostic.format=format(saved);diagnostic.bytes=type(saved)=='string' and #saved or 0
 if not ok then
  local candidate=held and held.raw or saved
  if type(candidate)=='string' and #candidate==4095 then
   local recovered,partial=pcall(recoverClipped,candidate)
   if recovered then
    held=nil
    diagnostic.source='NATIVE_CLIP_RECOVERED'
    return loaded(partial)
   end
   diagnostic.prefixError=type(partial)=='string' and partial:match('^STORE_[A-Z_]+') or 'STORE_PREFIX_ERROR'
  end
  diagnostic.error=tostring(result)
  if not held and type(saved)=='string' then held={raw=saved}end
  return false,diagnostic.error
 end
 return loaded(result)
end

function M.load(gameData)
 M.reset()
 loadDepartures(gameData)
 local legacyOK,legacyError=loadLegacy(gameData)
 local fields=gameData and gameData.sdata
 if not fields then return legacyOK,legacyError end
 local header=fields[ORDERS_KEY]
 local marker=fields[ORDERS_FAILURE_KEY]
 if header==nil and marker==nil then
  local seen=false
  for key in pairs(fields)do
   if chunkIndex(key,ORDERS_KEY) then seen=true;break end
  end
  if not seen then return legacyOK,legacyError end
 end

 newOrders=true;ready=false
 state=blank();state.evacuations=departure.evacuations;state.partialRoster=true
 diagnostic.legacyError=legacyError;diagnostic.source='NEW_ORDERS'
 local ok,result=pcall(function()
  if header==nil then fail('STORE_CHUNK_MANIFEST_MISSING')end
  local saved=readTransport(fields,ORDERS_KEY,header)
  if type(saved)=='string' then newOrdersHeld=saved end
  if marker~=nil then fail('STORE_NEW_ORDERS_HISTORY_UNRESOLVED')end
  if format(saved)~='ASCII_HEX' then fail('STORE_NEW_ORDERS_FORMAT_INVALID')end
  local value=readSaved(saved)
  if value.partialRoster~=true then fail('STORE_NEW_ORDERS_SCOPE_INVALID')end
  return value
 end)
 diagnostic.error=not ok and ('STORE_NEW_ORDERS_HELD '..tostring(result)) or nil
 diagnostic.historyMarker=marker~=nil
 if not ok then return false,diagnostic.error end
 newOrdersHeld=nil
 return loaded(result)
end

local function saveHeld(gameData)
 diagnostic.preserved=false
 local ok,why=pcall(function()
  local saved=held.envelope
  if not saved then
   -- Preserve an oversized ASCII source verbatim to keep it bounded.
   local raw=held.raw
   if #raw>MAX_BYTES and #raw<=MAX_TRANSPORT
    and not raw:find('[^\32-\126]') then saved=raw
   else saved=envelope(raw,RECOVERY)end
  end
  writeTransport(gameData,RECOVERY_KEY,saved)
  held.envelope=saved;diagnostic.preserved=not held.marker
 end)
 diagnostic.saveError=not ok and tostring(why) or nil
 if ok then
  if not newOrders then diagnostic.historyMarker=held.marker==true end
  return true
 end
 if newOrders then return false,'STORE_ARCHIVE_SAVE_FAILED '..tostring(why)end
 local marked,problem=pcall(failureMarker,gameData,diagnostic.error..' preservation='..tostring(why))
 diagnostic.historyMarker=marked or diagnostic.historyMarker
 if marked then return false,'STORE_HELD_MARKER_ONLY '..tostring(why)end
 return false,'STORE_HELD_UNPRESERVED '..tostring(why)..' recovery='..tostring(problem)
end

local function markFailedNewOrders(gameData,why)
 if not newOrders then return end
 local marked=pcall(failureMarker,gameData,why,ORDERS_FAILURE_KEY)
 diagnostic.historyMarker=marked or diagnostic.historyMarker
end

function M.save(gameData)
 if ready or held or newOrders then
  local departureSaved,why=pcall(saveDepartures,gameData)
  if not departureSaved then
   diagnostic.saveError=tostring(why)
   markFailedNewOrders(gameData,why)
   return false,'STORE_DEPARTURE_SAVE_FAILED '..tostring(why)
  end
 end
 if held then
  local ok,why=saveHeld(gameData)
  if not ok then markFailedNewOrders(gameData,why);return false,why end
 end
 if not ready then
  if not newOrders then return false,held and 'STORE_HELD' or 'STORE_NOT_READY' end
  local ok,why=pcall(function()
   if newOrdersHeld then writeTransport(gameData,ORDERS_KEY,newOrdersHeld)end
   failureMarker(gameData,diagnostic.error,ORDERS_FAILURE_KEY)
  end)
  diagnostic.saveError=not ok and tostring(why) or nil
  return false,not ok and ('STORE_NEW_ORDERS_SAVE_FAILED '..tostring(why)) or 'STORE_NEW_ORDERS_HELD'
 end
 local key=newOrders and ORDERS_KEY or KEY
 local failureKey=newOrders and ORDERS_FAILURE_KEY or RECOVERY_KEY
 local ok,result=pcall(function()
  schema(state)
  -- KenshiLua string writers consume C strings. An ASCII envelope preserves
  -- arbitrary original bytes, including Unicode and embedded NUL characters.
  -- Departure state also persists when payment history is held. Keep it in
  -- its own native field and never snapshot it as part of a payment receipt.
  local saved={version=state.version,seq=state.seq,roster=state.roster,orders=state.orders,
   patrols=state.patrols,partialRoster=state.partialRoster}
  writeTransport(gameData,key,envelope(encode(saved),ENVELOPE),not newOrders)
  -- Only this still-ready session owns the complete current state. After its
  -- verified write it may remove an earlier transient failure marker; a load
  -- of an uncertain recovery field never reaches this branch.
  local fields=gameData.sdata
  if fields[failureKey]~=nil then
   fields[failureKey]=nil
   if fields[failureKey]~=nil then fail('STORE_RECOVERY_CLEAR_FAILED')end
  end
  return true
 end)
 diagnostic.saveError=not ok and tostring(result) or nil
 if not ok then
  local marked,problem=pcall(failureMarker,gameData,result,failureKey)
  diagnostic.historyMarker=marked or diagnostic.historyMarker
  if marked then return false,tostring(result)end
  return false,'STORE_SAVE_FAILED_UNPRESERVED '..tostring(result)..' recovery='..tostring(problem)
 end
 diagnostic.historyMarker=false
 if diagnostic.departureError then return false,'STORE_DEPARTURE_HELD '..diagnostic.departureError end
 return result
end
return M
