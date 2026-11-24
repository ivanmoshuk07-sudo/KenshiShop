-- Save-scoped police service ledger. Only plain Lua data is serialized; no
-- file I/O, executable deserialization, engine objects or event hooks here.
local M={}
local KEY='KenshiShopChiefStateV1'
local RECOVERY_KEY=KEY..'Recovery'
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
local function blank()return {version=1,seq=0,roster={},orders={},patrols={}}end
function M.reset()
 state=blank();ready=false;held=nil
 diagnostic={error=nil,source='NONE',format='NONE',bytes=0,preserved=false,historyMarker=false}
end
M.reset()
function M.get()return state end
function M.ready()return ready end
function M.status()
 return {ready=ready,error=diagnostic.error,source=diagnostic.source,format=diagnostic.format,
  bytes=diagnostic.bytes,held=held~=nil,preserved=diagnostic.preserved,saveError=diagnostic.saveError,
  historyMarker=diagnostic.historyMarker}
end
function M.diagnostics()
 local d=M.status()
 return 'ready='..tostring(d.ready)..' error='..tostring(d.error or 'NONE')..' source='..d.source
  ..' format='..d.format..' bytes='..d.bytes..' held='..tostring(d.held)..' preserved='..tostring(d.preserved)
  ..' history_marker='..tostring(d.historyMarker)
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
local function decode(source)
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
  if at==first or source:sub(at,at)~=':' then fail('STORE_LENGTH_INVALID')end
  local value=tonumber(source:sub(first,at-1));at=at+1
  if not value or value>limit then fail('STORE_LENGTH_LIMIT')end
  return value
 end
 local read
 read=function(depth)
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
 local value=read(1)
 if at~=#source+1 then fail('STORE_TRAILING_DATA')end
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
local function failureMarker(gameData,why)
 -- A failed encode/write must not make the next native save look like a new
 -- campaign. The bounded marker preserves uncertainty, not the missing data.
 local saved=envelope(UNRESOLVED..tostring(why):sub(1,512),RECOVERY)
 writeTransport(gameData,RECOVERY_KEY,saved)
end
function M.load(gameData)
 M.reset()
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
  diagnostic.error=tostring(result)
  if not held and type(saved)=='string' then held={raw=saved}end
  return false,diagnostic.error
 end
 state=result;ready=true;return true
end
function M.save(gameData)
 if not ready then
  if not held then return false,'STORE_NOT_READY'end
  diagnostic.preserved=false
  local ok,why=pcall(function()
   local saved=held.envelope
   if not saved then
    -- Preserve an oversized but already ASCII source verbatim;
    -- wrapping it again would expand it on every failed load/save cycle.
    local raw=held.raw
    if #raw>MAX_BYTES and #raw<=MAX_TRANSPORT
     and not raw:find('[^\32-\126]') then saved=raw
    else saved=envelope(raw,RECOVERY)end
   end
   writeTransport(gameData,RECOVERY_KEY,saved)
   held.envelope=saved;diagnostic.preserved=not held.marker
   diagnostic.historyMarker=held.marker==true
  end)
  diagnostic.saveError=not ok and tostring(why) or nil
  if not ok then
   local marked,problem=pcall(failureMarker,gameData,diagnostic.error..' preservation='..tostring(why))
   diagnostic.historyMarker=marked or diagnostic.historyMarker
   if marked then return false,'STORE_HELD_MARKER_ONLY '..tostring(why)end
   return false,'STORE_HELD_UNPRESERVED '..tostring(why)..' recovery='..tostring(problem)
  end
  return false,'STORE_HELD'
 end
 local ok,result=pcall(function()
  schema(state)
  -- KenshiLua string writers consume C strings. An ASCII envelope preserves
  -- arbitrary original bytes, including Unicode and embedded NUL characters.
  writeTransport(gameData,KEY,envelope(encode(state),ENVELOPE),true)
  -- Only this still-ready session owns the complete current state. After its
  -- verified write it may remove an earlier transient failure marker; a load
  -- of an uncertain recovery field never reaches this branch.
  local fields=gameData.sdata
  if fields[RECOVERY_KEY]~=nil then
   fields[RECOVERY_KEY]=nil
   if fields[RECOVERY_KEY]~=nil then fail('STORE_RECOVERY_CLEAR_FAILED')end
  end
  return true
 end)
 diagnostic.saveError=not ok and tostring(result) or nil
 if not ok then
  local marked,problem=pcall(failureMarker,gameData,result)
  diagnostic.historyMarker=marked or diagnostic.historyMarker
  if marked then return false,tostring(result)end
  return false,'STORE_SAVE_FAILED_UNPRESERVED '..tostring(result)..' recovery='..tostring(problem)
 end
 diagnostic.historyMarker=false
 return result
end
return M
