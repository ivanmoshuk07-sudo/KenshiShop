-- Native save-field boundary checks; no game files or engine code are loaded.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local Store=require('Core.Police.Services.Store')
local KEY='KenshiShopChiefStateV1'
local RECOVERY_KEY=KEY..'Recovery'
local EVACUATION_KEY=KEY..'Departures'
local LEGACY_BLANK='KSCS1:T5:S6:ordersT0:S7:patrolsT0:S6:rosterT0:S3:seqN1:0S7:versionN1:1'
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function ownField(key)
 return key==KEY or key==RECOVERY_KEY or key==EVACUATION_KEY or key:match('^'..KEY..'Chunk%d+$')
  or key:match('^'..RECOVERY_KEY..'Chunk%d+$')
  or key:match('^'..EVACUATION_KEY..'Chunk%d+$')
end
local function data(saved)
 return {sdata=saved and {[KEY]=saved} or {},writes=0,
  addString=function(self,key,value,category,visible)
   assert(ownField(key) and category=='KenshiShop' and visible==false)
   self.writes=self.writes+1;self.sdata[key]=value
  end}
end
local function fresh()
 Store.reset();local gd=data();assert(Store.load(gd));return gd,Store.get()
end
local function rejected(saved,fragment)
 local ok,why=Store.load(data(saved));assert(not ok and not Store.ready())
 if fragment then assert(why:find(fragment,1,true),why)end
 assert(Store.get().seq==0 and next(Store.get().roster)==nil)
end
test('a fresh save has an empty versioned ledger, not a paid transaction',function()
 Store.reset();assert(not Store.ready())
 local ok,reason=Store.save(data());assert(not ok and reason=='STORE_NOT_READY')
 local gd,state=fresh()
 assert(Store.ready() and state.version==1 and state.seq==0)
 assert(next(state.roster)==nil and next(state.orders)==nil and next(state.patrols)==nil and gd.writes==0)
end)
test('roster orders and patrols round-trip Unicode, false and delimiter bytes',function()
 local gd,state=fresh();state.seq=7
 state.roster['башня:1']={member='1-123-45-678-1',role='Охранник 2',dead=true,
  notes='x:\0\nT2:S9:test',floor=1,refund=false}
 state.orders[7]={cost=10000,status='выполнено',member='новый'}
 state.patrols['отряд']={1,2,3,day=false,night=true,rate=0.125}
 assert(Store.save(gd));local encoded=gd.sdata[KEY]
 Store.reset();assert(Store.load(data(encoded)));state=Store.get()
 assert(state.seq==7 and state.roster['башня:1'].role=='Охранник 2')
 assert(state.roster['башня:1'].notes=='x:\0\nT2:S9:test' and state.roster['башня:1'].refund==false)
 assert(state.orders[7].status=='выполнено' and state.patrols['отряд'][3]==3)
 assert(state.patrols['отряд'].day==false and state.patrols['отряд'].rate==0.125)
end)
test('encoding is deterministic for table insertion order and mixed scalar keys',function()
 local gd,state=fresh();state.roster.z=2;state.roster.a=1
 state.orders[false]='no';state.orders[true]='yes';state.orders[5]='five'
 assert(Store.save(gd));local first=gd.sdata[KEY]
 local again;gd,again=fresh();again.roster.a=1;again.roster.z=2
 again.orders[5]='five';again.orders[true]='yes';again.orders[false]='no'
 assert(Store.save(gd) and gd.sdata[KEY]==first)
end)
test('corrupt truncated duplicate-key and trailing encodings fail closed',function()
 for _,source in ipairs({'','garbage','KSCS1:','KSCS1:T1:S3:key','KSCS1:T2:S1:aB0S1:aB1',
  'KSCS1:T0:trailing','KSCS1:N3:nan','KSCS1:N3:inf','KSCS1:B2','KSCS1:T1:T0:B0'})do rejected(source)end
end)
test('unsupported versions and malformed root fields fail closed',function()
 local saved=LEGACY_BLANK
 assert(saved:find('S7:versionN1:1',1,true))
 rejected(saved:gsub('S7:versionN1:1','S7:versionN1:2'),'STORE_VERSION_UNSUPPORTED')
 rejected('KSCS1:T0:','STORE_VERSION_UNSUPPORTED')
 rejected(saved:gsub('S3:seqN1:0','S3:seqN2:-1'),'STORE_SEQUENCE_INVALID')
end)
test('valid legacy ledgers load byte-exact values and migrate without losing paid claims',function()
 local name='Охрана\0второй этаж'
 local legacy='KSCS1:T5:S6:ordersT1:S1:1T2:S4:costN5:10000S6:statusS8:complete'
  ..'S7:patrolsT0:S6:rosterT1:S3:npcT2:S4:deadB1S4:nameS'..#name..':'..name
  ..'S3:seqN1:1S7:versionN1:1'
 local gd=data(legacy);assert(Store.load(gd))
 assert(Store.get().seq==1 and Store.get().orders['1'].status=='complete')
 assert(Store.get().roster.npc.name==name and Store.status().format=='LEGACY')
 assert(Store.save(gd) and gd.sdata[KEY]:sub(1,6)=='KSCS2:')
 assert(not gd.sdata[KEY]:find('[^\32-\126]'))
 assert(Store.load(gd) and Store.get().roster.npc.name==name and Store.get().orders['1'].cost==10000)
end)
test('campaign reset and absent save field never reuse another campaign roster',function()
 local gd,state=fresh();state.seq=88;state.roster.old={dead=true};assert(Store.save(gd))
 Store.reset();assert(not Store.ready() and Store.get().seq==0)
 assert(Store.load(data()) and Store.ready() and Store.get().seq==0 and next(Store.get().roster)==nil)
 rejected('corrupt');assert(Store.load(gd) and Store.get().seq==88 and Store.get().roster.old.dead)
end)
test('repeated saves persist current transactions and update an add-only native field',function()
 local gd,state=fresh();assert(Store.save(gd));local old=gd.sdata[KEY]
 gd.addString=function(self,key,value)self.writes=self.writes+1;if self.sdata[key]==nil then self.sdata[key]=value end end
 state.seq=1;state.orders['receipt']={paid=true,fulfilled=false}
 assert(Store.save(gd) and gd.sdata[KEY]~=old and gd.writes==2)
 assert(Store.load(gd) and Store.get().orders.receipt.paid and Store.get().orders.receipt.fulfilled==false)
end)
test('size depth and entry caps reject writes and hostile encodings',function()
 local gd,state=fresh();state.roster.payload=string.rep('x',2*1024*1024)
 local ok,reason=Store.save(gd);assert(not ok and reason:find('STORE_BYTES_LIMIT',1,true) and gd.writes==1 and gd.sdata[RECOVERY_KEY])
 rejected(string.rep('x',2*1024*1024+1),'STORE_BYTES_LIMIT')
 rejected('KSCS1:T20001:','STORE_LENGTH_LIMIT')
 rejected('KSCS1:S999999999999:','STORE_LENGTH_INVALID')
 rejected('KSCS1:'..string.rep('T1:S1:a',13)..'B0','STORE_DEPTH_LIMIT')
 gd,state=fresh();local cursor=state.roster
 for _=1,12 do cursor.child={};cursor=cursor.child end
 ok,reason=Store.save(gd);assert(not ok and reason:find('STORE_DEPTH_LIMIT',1,true))
 gd,state=fresh();for i=1,20001 do state.orders[i]=false end
 ok,reason=Store.save(gd);assert(not ok and reason:find('STORE_ENTRIES_LIMIT',1,true))
end)
test('cycles objects invalid numbers and non-scalar keys cannot enter saves',function()
 for _,value in ipairs({function()end,math.huge,0/0})do
  local gd,state=fresh();state.orders.bad=value;assert(not Store.save(gd) and gd.sdata[RECOVERY_KEY])
 end
 local gd,state=fresh();state.roster.self=state.roster;assert(not Store.save(gd))
 gd,state=fresh();state.orders[{}]='invalid';assert(not Store.save(gd))
 gd,state=fresh();state.orders.bad=setmetatable({},{__index=function()error('not plain')end});assert(not Store.save(gd))
end)
test('unavailable or rejected native fields report failure without claiming success',function()
 local gd=fresh();gd.addString=function()error('native field unavailable')end
 local ok,reason=Store.save(gd);assert(not ok and reason:find('native field unavailable',1,true))
 assert(not Store.load({}) and not Store.ready())
 local proxy=setmetatable({},{__index=function()return nil end,__newindex=function()end})
 assert(Store.load({sdata=proxy}))
 ok,reason=Store.save({sdata=proxy,addString=function()end})
 assert(not ok and reason:find('STORE_SAVE_VERIFY_FAILED',1,true))
end)
local function nativeData(fields)
 local storage=fields or {}
 local gd={writes=0}
 local function cstring(s)return s:match('^[^%z]*')end
 gd.sdata=setmetatable({},{__index=function(_,key)return storage[key]end,__pairs=function()return pairs(storage)end,
  __newindex=function(_,key,value)if value==nil then storage[key]=nil else storage[key]=cstring(value)end end})
 function gd:addString(key,value,category,visible)
  assert(ownField(key) and category=='KenshiShop' and visible==false)
  self.writes=self.writes+1;storage[key]=cstring(value)
 end
 return gd,storage
end
local function wirePayload(storage,key)
 local header=storage[key]
 local size=header and tonumber(header:match('^KSCH3:(%d+):'))
 if not size then return header end
 local chunks={}
 for i=1,math.ceil(size/3000)do chunks[i]=assert(storage[key..'Chunk'..i])end
 return table.concat(chunks)
end
local function reloadFromNativeDisk(storage)
 -- The C++ map itself accepts oversize strings. The serialization boundary
 -- clips them on disk, so a simple in-memory round trip missed the bug.
 local persisted={}
 for key,value in pairs(storage)do persisted[key]=value:sub(1,4095)end
 return nativeData(persisted)
end
local function wrapRecovery(payload)
 local a,b=1,0
 local hex=payload:gsub('.',function(byte)
  a=(a+byte:byte())%65521;b=(b+a)%65521
  return string.format('%02x',byte:byte())
 end)
 return 'KSHOLD2:'..#payload..':'..b*65536+a..':'..hex
end
test('ASCII envelopes round-trip arbitrary bytes through the real C-string writer contract',function()
 local gd,storage=nativeData();assert(Store.load(gd))
 local bytes={};for byte=0,255 do bytes[#bytes+1]=string.char(byte)end
 bytes=table.concat(bytes)
 Store.get().seq=3;Store.get().roster.npc={name='Начальник\0Охрана',payload=bytes}
 Store.get().orders['paid']={cost=20000,status='complete'}
 assert(Store.save(gd) and storage[KEY]:sub(1,6)=='KSCS2:' and not storage[KEY]:find('[^\32-\126]'))
 assert(Store.load(gd) and Store.get().seq==3 and Store.get().roster.npc.payload==bytes)
 assert(Store.get().roster.npc.name=='Начальник\0Охрана' and Store.get().orders.paid.status=='complete')
end)
test('envelope truncation corruption and impossible sizes fail before accepting ledger contents',function()
 local gd=fresh();assert(Store.save(gd));local encoded=gd.sdata[KEY]
 rejected(encoded:sub(1,-2),'STORE_ENVELOPE_LENGTH')
 local last=encoded:sub(-1);local changed=encoded:sub(1,-2)..(last=='0' and '1' or '0')
 rejected(changed,'STORE_CHECKSUM_INVALID')
 rejected('KSCS2:2097153:1:','STORE_BYTES_LIMIT')
 rejected('KSCS2:999999999:1:','STORE_ENVELOPE_INVALID')
 rejected(encoded..'z','STORE_ENVELOPE_INVALID')
end)
test('a corrupt loaded ledger is preserved in quarantine across fresh native save objects',function()
 local damaged='KSCS1:T1:S20:part\0missing'
 local loaded,why=Store.load(data(damaged))
 assert(not loaded and why=='STORE_TRUNCATED' and Store.status().held)
 local gd,storage=nativeData()
 local saved,reason=Store.save(gd)
 assert(not saved and reason=='STORE_HELD' and not storage[KEY] and Store.status().preserved)
 local quarantine=storage[RECOVERY_KEY]
 assert(quarantine:sub(1,8)=='KSHOLD2:' and not quarantine:find('[^\32-\126]'))
 loaded,why=Store.load(gd)
 assert(not loaded and why=='STORE_TRUNCATED' and Store.status().source=='RECOVERY')
 local nextGD,nextStorage=nativeData();saved,reason=Store.save(nextGD)
 assert(not saved and reason=='STORE_HELD' and nextStorage[RECOVERY_KEY]==quarantine)
 assert(not Store.ready() and Store.get().seq==0 and next(Store.get().orders)==nil)
end)
test('recovery markers never authorize rollback to a seemingly valid primary ledger',function()
 assert(not Store.load(data('KSCS1:T1:S40:truncated')))
 local held=data();assert(select(2,Store.save(held))=='STORE_HELD')
 held.sdata[KEY]=LEGACY_BLANK
 assert(not Store.load(held) and Store.status().held and not Store.ready())
 -- A syntactically valid but explicitly held history is still not permission
 -- to invent a new campaign or repeat any earlier debit.
 local valid=fresh();assert(Store.save(valid))
 valid.sdata[RECOVERY_KEY]=valid.sdata[KEY]:gsub('^KSCS2:','KSHOLD2:')
 local ok,why=Store.load(valid)
 assert(not ok and why=='STORE_RECOVERY_HELD' and not Store.ready())
end)
test('large ASCII envelopes are quarantined without another hex expansion or byte loss',function()
 local gd=fresh();Store.get().roster.payload=string.rep('x',1024*1024+100)
 assert(Store.save(gd));local encoded=wirePayload(gd.sdata,KEY)
 assert(#encoded>2*1024*1024 and #encoded<4*1024*1024)
 local last=encoded:sub(-1);local damaged=encoded:sub(1,-2)..(last=='0' and '1' or '0')
 local ok,why=Store.load(data(damaged));assert(not ok and why=='STORE_CHECKSUM_INVALID')
 local heldGD,storage=nativeData();assert(select(2,Store.save(heldGD))=='STORE_HELD')
 assert(wirePayload(storage,RECOVERY_KEY)==damaged)
 ok,why=Store.load(heldGD);assert(not ok and why=='STORE_CHECKSUM_INVALID' and not Store.ready())
 local nextGD,nextStorage=nativeData();assert(select(2,Store.save(nextGD))=='STORE_HELD')
 assert(wirePayload(nextStorage,RECOVERY_KEY)==damaged)
end)
test('large paid history survives the native 4095-byte field limit without losing values',function()
 local gd,storage=nativeData();assert(Store.load(gd))
 local large=string.rep('Имя\0охранника\n',900)
 Store.get().seq=8;Store.get().roster.npc={name=large,dead=true}
 Store.get().orders.paid={kind='replace',status='complete',cost=10000}
 assert(Store.save(gd) and storage[KEY]:find('^KSCH3:') and storage[KEY..'Chunk2'])
 local oldFile=reloadFromNativeDisk({[KEY]=wirePayload(storage,KEY)})
 local ok,why=Store.load(oldFile)
 assert(not ok and why=='STORE_ENVELOPE_LENGTH' and Store.status().bytes==4095)
 for key,value in pairs(storage)do assert(#value<=3000 and not value:find('[^\32-\126]'),key)end
 assert(Store.load(reloadFromNativeDisk(storage)))
 assert(Store.get().seq==8 and Store.get().roster.npc.name==large and Store.get().orders.paid.cost==10000)
end)
test('a 4095-byte recovery field clipped during the paid orders stays quarantined byte-for-byte',function()
 local gd,storage=nativeData();assert(Store.load(gd))
 Store.get().orders.payload=string.rep('x',3000)
 assert(Store.save(gd))
 local oldRecovery=wirePayload(storage,KEY):gsub('^KSCS2:','KSHOLD2:')
 assert(#oldRecovery>4095)
 local oldFile=reloadFromNativeDisk({[RECOVERY_KEY]=oldRecovery})
 local ok,why=Store.load(oldFile)
 assert(not ok and why=='STORE_RECOVERY_INVALID STORE_ENVELOPE_LENGTH' and Store.status().bytes==4095)
 local heldGD,heldStorage=nativeData();assert(select(2,Store.save(heldGD))=='STORE_HELD')
 assert(heldStorage[RECOVERY_KEY]:find('^KSCH3:') and Store.status().preserved)
 ok,why=Store.load(reloadFromNativeDisk(heldStorage))
 assert(not ok and Store.status().bytes==4095 and Store.status().source=='RECOVERY')
 local again,saved=nativeData();assert(select(2,Store.save(again))=='STORE_HELD')
 assert(wirePayload(saved,RECOVERY_KEY)==wirePayload(heldStorage,RECOVERY_KEY))
end)
test('native 4095-byte clipping recovers complete paid receipts and the intact roster prefix',function()
 local gd,storage=nativeData();assert(Store.load(gd))
 local state=Store.get();state.seq=1
 state.orders['1']={id='1',kind='hire',subject='hire:1:1:2',cost=20000,status='complete',pid='hires',
  metadata={town='town',building='tower'}}
 state.patrols.hires={pid='hires',town='town',building='tower',order='1',base=3,number=1}
 state.roster.a={id='a',pid='hires',town='town',building='tower',squadTemplate='hired',dead=true}
 state.roster.z={id='z',pid='guards',town='town',building='house',squadTemplate='guard',dead=false,
  name=string.rep('охрана',600)}
 assert(Store.save(gd))
 local primary=wirePayload(storage,KEY)
 local recovery=primary:gsub('^KSCS2:', 'KSHOLD2:')
 for index,old in ipairs({primary,recovery,wrapRecovery(recovery:sub(1,4095))})do
  local source=index==1 and KEY or RECOVERY_KEY
  local cropped,saved=reloadFromNativeDisk({[source]=old})
  assert(Store.load(cropped),Store.diagnostics())
  local recovered=Store.get()
  assert(Store.ready() and Store.status().source=='NATIVE_CLIP_RECOVERED' and Store.status().partialRoster)
  assert(recovered.orders['1'].status=='complete' and recovered.seq==1)
  assert(recovered.patrols.hires.order=='1' and recovered.roster.a.dead and not recovered.roster.z)
  assert(Store.save(cropped) and not saved[RECOVERY_KEY])
  assert(Store.load(reloadFromNativeDisk(saved)) and Store.get().partialRoster and Store.get().seq==1)
 end
end)
test('repeated beta.7 clipping can preserve the payment header through six recovery wrappers',function()
 -- Beta.6 wrote plain KSCS1. Older recovery writes then wrapped the same
 -- nested, clipped field on every newly loaded session.
 local legacy='KSCS1:T5:S6:ordersT0:S7:patrolsT0:S6:rosterT1:S4:tailS6000:'
  ..string.rep('x',6000)..'S3:seqN1:0S7:versionN1:1'
 local clipped=legacy:sub(1,4095)
 for depth=1,7 do
  clipped=wrapRecovery(clipped):sub(1,4095)
  if depth>=5 then
   -- Beta.8 preserved this clipped history with an intact outer envelope
   -- and a checksum-verified chunk transport.
   local envelope=wrapRecovery(clipped)
   local size,digest=wrapRecovery(envelope):match('^KSHOLD2:(%d+):(%d+):')
   local storage={[RECOVERY_KEY]='KSCH3:'..size..':'..digest}
   for offset=1,#envelope,3000 do
    storage[RECOVERY_KEY..'Chunk'..(1+(offset-1)//3000)]=envelope:sub(offset,offset+2999)
   end
   local gd,persisted=reloadFromNativeDisk(storage)
   local ok,why=Store.load(gd)
   if depth<=6 then
    assert(ok and Store.ready() and Store.get().partialRoster,Store.diagnostics())
    assert(Store.get().seq==0 and next(Store.get().orders)==nil and next(Store.get().patrols)==nil)
    assert(Store.save(gd) and not persisted[RECOVERY_KEY])
    assert(Store.load(reloadFromNativeDisk(persisted)) and Store.get().partialRoster)
   else
    assert(not ok and why=='STORE_ENCODING_INVALID' and not Store.ready())
    assert(Store.status().prefixError=='STORE_TRUNCATED',Store.diagnostics())
    assert(Store.diagnostics():find('prefix_error=STORE_TRUNCATED',1,true))
   end
  end
 end
end)
test('clipped receipts with a hole or missing hire identity cannot activate payment',function()
 local gd,storage=nativeData();assert(Store.load(gd))
 local state=Store.get();state.seq=2
 state.orders['2']={id='2',kind='hire',subject='hire:2:1:2',cost=20000,status='complete',pid='hires',
  metadata={town='town',building='tower'}}
 state.patrols.hires={pid='hires',town='town',building='tower',order='2',base=3,number=1}
 state.roster.tail=string.rep('x',4000)
 assert(Store.save(gd))
 local oldFile=reloadFromNativeDisk({[KEY]=wirePayload(storage,KEY)})
 assert(not Store.load(oldFile) and not Store.ready())
 assert(Store.load(gd));state=Store.get();state.seq=1
 local paid=state.orders['2'];state.orders['2']=nil;paid.id='1';state.orders['1']=paid
 state.patrols.hires=nil;assert(Store.save(gd))
 oldFile=reloadFromNativeDisk({[KEY]=wirePayload(storage,KEY)})
 assert(not Store.load(oldFile) and not Store.ready())
end)
test('invalid, missing and mutated parts prevent an incomplete paid history from opening',function()
 local gd,storage=nativeData();assert(Store.load(gd))
 Store.get().roster.payload=string.rep('x',4000)
 Store.get().orders.paid={status='pending',cost=10000}
 assert(Store.save(gd) and storage[KEY..'Chunk2'])
 local partKey=KEY..'Chunk2'
 local originalPart=storage[partKey]
 for i,reason in ipairs({'STORE_CHUNK_MISSING 2','STORE_CHUNK_INVALID 2','STORE_CHUNK_CHECKSUM_INVALID'})do
  if i==1 then storage[partKey]=nil
  elseif i==2 then storage[partKey]=originalPart:sub(1,-2)
  else storage[partKey]='0'..originalPart:sub(2)end
  local ok,why=Store.load(gd);assert(not ok and why==reason and not Store.ready(),why)
  assert(Store.status().historyMarker and next(Store.get().orders)==nil)
  local heldGD,heldStorage=nativeData();assert(select(2,Store.save(heldGD))=='STORE_HELD')
  assert(not Store.status().preserved and heldStorage[RECOVERY_KEY] and not heldStorage[KEY])
  ok,why=Store.load(heldGD)
  assert(not ok and why:find('STORE_HISTORY_UNRESOLVED',1,true) and not Store.ready())
 end
end)
test('parts without a manifest cannot activate a fresh or stale primary ledger',function()
 local gd=data();gd.sdata[KEY..'Chunk2']='partial'
 local ok,why=Store.load(gd)
 assert(not ok and why=='STORE_CHUNK_MANIFEST_MISSING' and Store.status().source=='PRIMARY')
 gd.sdata[KEY]=LEGACY_BLANK;gd.sdata[RECOVERY_KEY..'Chunk3']='partial recovery'
 ok,why=Store.load(gd)
 assert(not ok and why=='STORE_CHUNK_MANIFEST_MISSING' and Store.status().source=='RECOVERY')
end)
test('verified rewrites remove only stale ledger parts and preserve new paid claims',function()
 local gd,storage=nativeData();assert(Store.load(gd))
 storage.OtherMod='leave this alone'
 Store.get().roster.payload=string.rep('x',9000)
 Store.get().orders.paid={status='complete',cost=10000}
 assert(Store.save(gd) and storage[KEY..'Chunk7'])
 storage[KEY..'Chunk9']='orphaned by earlier write'
 storage[RECOVERY_KEY..'Chunk6']='orphaned recovery part'
 Store.get().roster.payload=string.rep('y',2000)
 assert(Store.save(gd) and storage[KEY..'Chunk2'] and not storage[KEY..'Chunk3'] and not storage[KEY..'Chunk7'])
 assert(not storage[KEY..'Chunk9'] and not storage[RECOVERY_KEY..'Chunk6'])
 Store.get().roster.payload=nil
 assert(Store.save(gd) and storage[KEY]:find('^KSCS2:') and not storage[KEY..'Chunk1'])
 assert(not storage[KEY..'Chunk2'] and storage.OtherMod=='leave this alone')
 assert(Store.load(reloadFromNativeDisk(storage)) and Store.get().orders.paid.status=='complete')
end)
test('malformed recovery fields remain held and reset never carries them into another campaign',function()
 local gd=data();gd.sdata[RECOVERY_KEY]='invalid\0recovery'
 assert(not Store.load(gd) and Store.status().error:find('STORE_RECOVERY_INVALID',1,true))
 local saved=nativeData();assert(select(2,Store.save(saved))=='STORE_HELD')
 assert(not Store.load(saved) and not Store.ready())
 assert(Store.load(data()) and Store.ready() and not Store.status().held and Store.get().seq==0)
 assert(Store.status().error==nil and Store.status().source=='NONE')
end)
test('failed quarantine persistence is reported without enabling service or discarding held bytes',function()
 assert(not Store.load(data('KSCS1:T1:S30:short')))
 local bad={sdata={},addString=function()error('no native write')end}
 local ok,why=Store.save(bad)
 assert(not ok and why:find('no native write',1,true) and not Store.ready() and Store.status().held)
 assert(not Store.status().preserved and Store.status().saveError)
 local gd=nativeData();assert(select(2,Store.save(gd))=='STORE_HELD' and Store.status().preserved)
 assert(not Store.load(gd))
end)
test('diagnostics expose scalar state without original saved payload or engine objects',function()
 assert(not Store.load(data('KSCS1:T1:S200:private-ledger-name')))
 local d=Store.status();assert(d.error=='STORE_TRUNCATED' and d.bytes>0 and d.held and not d.ready)
 for _,value in pairs(d)do assert(type(value)=='string' or type(value)=='boolean' or type(value)=='number')end
 d.error='mutated';assert(Store.status().error=='STORE_TRUNCATED')
 assert(not Store.diagnostics():find('private-ledger-name',1,true))
 assert(Store.diagnostics():find('STORE_TRUNCATED',1,true))
end)
test('a ready ledger encode failure leaves a bounded unresolved-history marker without mutating paid state',function()
 local gd,state=fresh();state.seq=7;state.orders.paid={cost=20000,status='complete'}
 state.roster.oversized=string.rep('x',2*1024*1024)
 local ok,why=Store.save(gd)
 assert(not ok and why:find('STORE_BYTES_LIMIT',1,true) and Store.ready() and Store.get()==state)
 assert(state.seq==7 and state.orders.paid.status=='complete' and not gd.sdata[KEY])
 assert(gd.sdata[RECOVERY_KEY] and #gd.sdata[RECOVERY_KEY]<2048)
 assert(Store.status().historyMarker and not Store.status().preserved)
 ok,why=Store.load(gd)
 assert(not ok and why:find('STORE_HISTORY_UNRESOLVED',1,true) and not Store.ready())
 assert(Store.status().held and Store.status().historyMarker)
end)
test('a failed primary write uses a writable recovery key and a later verified save clears its marker',function()
 local gd,storage=nativeData();assert(Store.load(gd))
 Store.get().seq=3;Store.get().orders.paid={status='complete',cost=10000}
 local add=gd.addString;local reject=true
 gd.addString=function(self,key,...)
  if reject and key==KEY then error('PRIMARY_WRITE_UNAVAILABLE')end
  return add(self,key,...)
 end
 local ok,why=Store.save(gd)
 assert(not ok and why:find('PRIMARY_WRITE_UNAVAILABLE',1,true))
 assert(Store.ready() and Store.get().orders.paid.cost==10000 and storage[RECOVERY_KEY])
 reject=false
 assert(Store.save(gd) and storage[KEY] and not storage[RECOVERY_KEY] and not Store.status().historyMarker)
 assert(Store.load(gd) and Store.get().seq==3 and Store.get().orders.paid.status=='complete')
end)
test('save failure never permits a stale valid primary to reactivate older paid history',function()
 local gd,state=fresh();assert(Store.save(gd))
 local old=gd.sdata[KEY]
 state.seq=1;state.orders.newPayment={cost=10000,status='pending'}
 state.roster.oversized=string.rep('x',2*1024*1024)
 assert(not Store.save(gd) and gd.sdata[KEY]==old and gd.sdata[RECOVERY_KEY])
 local ok,why=Store.load(gd)
 assert(not ok and why:find('STORE_HISTORY_UNRESOLVED',1,true) and not Store.ready())
end)
test('a failed marker cleanup remains blocked even after the primary payload was written correctly',function()
 local gd,storage=nativeData();assert(Store.load(gd));Store.get().orders.paid={status='complete'}
 storage[RECOVERY_KEY]='old failure marker'
 local mt=getmetatable(gd.sdata);local write=mt.__newindex
 mt.__newindex=function(self,key,value)
  if key~=RECOVERY_KEY or value~=nil then write(self,key,value)end
 end
 local ok,why=Store.save(gd)
 assert(not ok and why=='STORE_RECOVERY_CLEAR_FAILED' and storage[KEY] and storage[RECOVERY_KEY])
 assert(Store.ready() and Store.get().orders.paid.status=='complete')
 ok,why=Store.load(gd)
 assert(not ok and why:find('STORE_HISTORY_UNRESOLVED',1,true) and not Store.ready())
end)
test('oversized binary held bytes keep an explicit warning when bounded preservation cannot retain the body',function()
 local bad='\0'..string.rep('x',2*1024*1024)
 assert(not Store.load(data(bad)) and Store.status().held)
 local gd,storage=nativeData();local ok,why=Store.save(gd)
 assert(not ok and why:find('STORE_HELD_MARKER_ONLY',1,true))
 assert(not Store.status().preserved and Store.status().historyMarker and storage[RECOVERY_KEY])
 assert(#storage[RECOVERY_KEY]<2048)
 ok,why=Store.load(gd)
 assert(not ok and why:find('STORE_HISTORY_UNRESOLVED',1,true) and not Store.ready())
 local again=nativeData();assert(select(2,Store.save(again))=='STORE_HELD')
 assert(not Store.status().preserved and Store.status().historyMarker)
end)
test('failure of both native fields reports unpreserved history and retains in-memory paid claims',function()
 local gd,state=fresh();state.orders.paid={cost=10000,status='pending'}
 gd.addString=function()error('ALL_NATIVE_WRITES_FAILED')end
 local ok,why=Store.save(gd)
 assert(not ok and why:find('STORE_SAVE_FAILED_UNPRESERVED',1,true) and why:find('ALL_NATIVE_WRITES_FAILED',1,true))
 assert(Store.ready() and Store.get()==state and state.orders.paid.status=='pending')
 assert(not Store.status().preserved and not Store.status().historyMarker and Store.status().saveError)
end)
local function evacuationPlan()
 return {anchor='tower',buildings={tower=true,house=true},property={tower=true,house=true,bed=true},
  squads={guard={template='security',building='house'}}}
end
test('a confirmed departure snapshots its plan and restores only its identity markers',function()
 local gd,storage=nativeData();assert(Store.load(gd) and Store.evacuationReady())
 local input=evacuationPlan();local begun,plan=Store.beginEvacuation('town',input)
 assert(begun and plan~=input and not Store.beginEvacuation('town',input))
 assert(Store.get().evacuations.town==plan and Store.evacuation('town')==plan)
 input.buildings.house=nil
 assert(Store.retiredBuilding('tower') and Store.retiredBuilding('house') and not Store.retiredBuilding('bed'))
 assert(Store.retiredPlatoon('guard') and not Store.retiredPlatoon('another'))
 plan.departed=true;plan.squads.guard.progress='moving'
 assert(Store.save(gd));assert(Store.load(reloadFromNativeDisk(storage)))
 plan=Store.evacuation('town')
 assert(plan.departed and plan.property.bed and plan.squads.guard.progress=='moving')
 assert(Store.retiredBuilding('house') and Store.retiredPlatoon('guard'))
end)
test('finishing a departure clears just its staffing records and leaves no pending plan in native saves',function()
 local gd,storage=nativeData();assert(Store.load(gd))
 local state=Store.get();state.seq=12
 state.roster.a={town='town',pid='guard',building='house'}
 state.roster.b={town='another',pid='different',building='another tower'}
 state.roster.c={town='another',pid='guard',building='house'}
 state.roster.d={pid='guard',building='house'}
 state.orders['10']={metadata={town='town'},status='complete'}
 state.orders['11']={metadata={town='another'},status='pending'}
 state.patrols.guard={pid='guard',town='town',building='tower'}
 assert(Store.beginEvacuation('town',evacuationPlan()))
 assert(not Store.finishEvacuation('another') and state.roster.a and state.orders['10'])
 assert(Store.finishEvacuation('town'))
 assert(not Store.evacuation('town') and not state.roster.a and not state.orders['10'] and not state.patrols.guard)
 assert(state.roster.b and state.roster.c and not state.roster.d and state.orders['11'] and state.seq==12)
 assert(Store.save(gd));assert(Store.load(reloadFromNativeDisk(storage)))
 assert(next(Store.get().evacuations)==nil and Store.retiredBuilding('tower') and Store.retiredPlatoon('guard'))
 assert(Store.get().roster.b and Store.get().roster.c and Store.get().orders['11'] and Store.get().seq==12)
 assert(Store.load(data()) and not Store.retiredBuilding('tower') and not Store.retiredPlatoon('guard'))
end)
test('invalid and conflicting departure plans leave no partial markers',function()
 assert(Store.load(data()))
 local plan=evacuationPlan();plan.squads.guard.building='elsewhere'
 assert(not Store.beginEvacuation('first',plan) and not Store.retiredBuilding('tower'))
 plan=evacuationPlan();plan.departed='yes'
 assert(not Store.beginEvacuation('first',plan) and not Store.retiredBuilding('tower'))
 plan=evacuationPlan();plan.invalid=function()end
 assert(not Store.beginEvacuation('first',plan) and not Store.retiredPlatoon('guard'))
 assert(Store.beginEvacuation('first',evacuationPlan()))
 assert(not Store.beginEvacuation('second',evacuationPlan()) and not Store.evacuation('second'))
end)
test('evacuation progress persists while unresolved payment history remains in quarantine',function()
 local gd,storage=nativeData({[KEY]='unsafe-to-interpret'})
 assert(not Store.load(gd) and not Store.ready() and Store.evacuationReady())
 assert(Store.beginEvacuation('town',evacuationPlan()))
 assert(select(2,Store.save(gd))=='STORE_HELD' and storage[EVACUATION_KEY] and storage[RECOVERY_KEY])
 assert(not Store.load(reloadFromNativeDisk(storage)) and Store.status().held and Store.evacuationReady())
 assert(Store.evacuation('town').squads.guard.building=='house' and Store.retiredBuilding('house'))
 assert(Store.finishEvacuation('town') and not Store.ready())
 assert(select(2,Store.save(gd))=='STORE_HELD')
 assert(not Store.load(reloadFromNativeDisk(storage)) and not Store.evacuation('town') and Store.retiredBuilding('house'))
end)
test('a damaged departure field holds paid work without discarding previously verified payments',function()
 local original,storage=nativeData();assert(Store.load(original))
 Store.get().orders.paid={status='complete',cost=20000}
 assert(Store.save(original));storage[EVACUATION_KEY]='damaged'
 local loaded,reason=Store.load(original)
 assert(not loaded and reason:find('STORE_DEPARTURE_HELD',1,true))
 assert(not Store.ready() and not Store.evacuationReady() and Store.evacuationCorrupt())
 assert(Store.get().orders.paid.cost==20000 and not Store.beginEvacuation('t',evacuationPlan()))
 local again,fields=nativeData()
 assert(not Store.save(again) and fields[KEY] and fields[EVACUATION_KEY]=='damaged')
 assert(not Store.load(again) and Store.get().orders.paid.cost==20000)
end)
print('Police save ledger tests passed: '..count)
