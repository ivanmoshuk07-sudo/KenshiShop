-- Save-scoped police service ledger. Only plain Lua data is serialized; no
-- file I/O, executable deserialization, engine objects or event hooks here.
local M={}
local KEY='KenshiShopChiefStateV1'
local MAGIC='KSCS1:'
local MAX_BYTES=2*1024*1024
local MAX_DEPTH=12
local MAX_ENTRIES=20000
local state,ready
local function blank()return {version=1,seq=0,roster={},orders={},patrols={}}end
function M.reset()state=blank();ready=false end
M.reset()
function M.get()return state end
function M.ready()return ready end
local function fail(message)error(message,0)end
local function finite(n)return n==n and n~=math.huge and n~=-math.huge end
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
function M.load(gameData)
 M.reset()
 local ok,result=pcall(function()
  if not gameData or not gameData.sdata then fail('STORE_GAME_DATA_UNAVAILABLE')end
  local saved=gameData.sdata[KEY]
  if saved==nil then return blank()end
  local value=decode(saved);schema(value);return value
 end)
 if not ok then return false,tostring(result)end
 state=result;ready=true;return true
end
function M.save(gameData)
 if not ready then return false,'STORE_NOT_READY'end
 local ok,result=pcall(function()
  schema(state);local saved=encode(state)
  if not gameData or not gameData.sdata then fail('STORE_GAME_DATA_UNAVAILABLE')end
  gameData:addString(KEY,saved,'KenshiShop',false)
  -- Some GameData implementations only add a field the first time. The
  -- exposed string map permits updating that same field on repeated saves.
  if gameData.sdata[KEY]~=saved then gameData.sdata[KEY]=saved end
  if gameData.sdata[KEY]~=saved then fail('STORE_SAVE_VERIFY_FAILED')end
  return true
 end)
 if not ok then return false,tostring(result)end
 return result
end
return M
