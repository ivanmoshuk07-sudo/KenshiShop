-- One snapshot for all squad consumers. Only owned hand values survive a frame;
-- native Character pointers and unordered-set iterators never enter the cache.
local O=require('Core.NPC.OriginTown')
local M={}
local cache
local LIMIT=12000
local function pid(c)
 local ap=O.call(c,'getPlatoon')
 return O.call(O.field(ap,'me'),'getPlatoonStringID')
end
local function clock(w)
 local h=O.call(O.call(w,'getTimeStamp_inGameHours'),'getTotalHours')
 if type(h)=='number' and h==h then return h*60 end
end
function M.reset()cache=nil end
local function snapshot(w,now)
 cache=nil -- A failed forced read must never expose the previous snapshot.
 local set=O.field(w,'charUpdateListMain')
 if not set then return nil,'CHARACTER_SET_UNAVAILABLE' end
 local groups,unresolved={},{}
 local ok,why=pcall(function()
  local scanned=0
  for c in pairs(set)do
   scanned=scanned+1;assert(scanned<=LIMIT,'CHARACTER_SCAN_SAFETY_CAP')
   local id=pid(c)
   if id and id~='' then
    local h=O.call(c,'getHandle');local key=O.handleID(h)
    if not key or key=='' or type(O.field(h,'getCharacter'))~='function' then
     -- A bad actor must block certification of its own platoon, without
     -- stopping every unrelated loaded squad in the shared snapshot.
     unresolved[id]='CHARACTER_HANDLE_UNAVAILABLE'
    else
     local group=groups[id] or {};groups[id]=group
     group[tostring(key)]=h
    end
   end
  end
 end)
 if not ok then return nil,'SCAN_EXCEPTION '..tostring(why) end
 cache={world=w,at=now,groups=groups,unresolved=unresolved}
 return cache
end
local function resolve(index,id)
 if index.unresolved[id] then return nil,index.unresolved[id]end
 local out={}
 for key,h in pairs(index.groups[id] or {})do
  local c=O.call(h,'getCharacter')
  if not c or O.call(c,'isValid')~=true or tostring(O.id(c))~=key or pid(c)~=id then return nil,'MEMBER_CACHE_STALE' end
  out[#out+1]={key=key,char=c}
 end
 table.sort(out,function(a,b)return a.key<b.key end)
 return out
end
function M.members(w,p,expected,fresh)
 local id=O.call(p,'getPlatoonStringID')
 if not id or id=='' then return nil,'PLATOON_ID_UNAVAILABLE' end
 local now=clock(w)
 local index=cache
 local rebuild=fresh or not index or index.world~=w or not now or not index.at
  or now<index.at or now-index.at>=1
 local why
 if rebuild then index,why=snapshot(w,now)end
 if not index then return nil,why end
 local out,err=resolve(index,id)
 if not out and not rebuild then
  index,why=snapshot(w,now)
  if not index then return nil,why end
  out,err=resolve(index,id)
 end
 if not out then return nil,err end
 if type(expected)=='number' and #out>expected+2 then return nil,'MEMBER_COUNT_EXCESS '..#out end
 return out,nil
end
return M
