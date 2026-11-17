-- Native save-field boundary checks; no game files or engine code are loaded.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local Store=require('Core.Police.Services.Store')
local KEY='KenshiShopChiefStateV1'
local RECOVERY_KEY=KEY..'Recovery'
local LEGACY_BLANK='KSCS1:T5:S6:ordersT0:S7:patrolsT0:S6:rosterT0:S3:seqN1:0S7:versionN1:1'
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function data(saved)
 return {sdata=saved and {[KEY]=saved} or {},writes=0,
  addString=function(self,key,value,category,visible)
   assert((key==KEY or key==RECOVERY_KEY) and category=='KenshiShop' and visible==false)
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
 gd.sdata=setmetatable({},{__index=function(_,key)return storage[key]end,
  __newindex=function(_,key,value)if value==nil then storage[key]=nil else storage[key]=cstring(value)end end})
 function gd:addString(key,value,category,visible)
  assert((key==KEY or key==RECOVERY_KEY) and category=='KenshiShop' and visible==false)
  self.writes=self.writes+1;storage[key]=cstring(value)
 end
 return gd,storage
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
 assert(Store.save(gd));local encoded=gd.sdata[KEY]
 assert(#encoded>2*1024*1024 and #encoded<4*1024*1024)
 local last=encoded:sub(-1);local damaged=encoded:sub(1,-2)..(last=='0' and '1' or '0')
 local ok,why=Store.load(data(damaged));assert(not ok and why=='STORE_CHECKSUM_INVALID')
 local heldGD,storage=nativeData();assert(select(2,Store.save(heldGD))=='STORE_HELD')
 assert(storage[RECOVERY_KEY]==damaged)
 ok,why=Store.load(heldGD);assert(not ok and why=='STORE_CHECKSUM_INVALID' and not Store.ready())
 local nextGD,nextStorage=nativeData();assert(select(2,Store.save(nextGD))=='STORE_HELD')
 assert(nextStorage[RECOVERY_KEY]==damaged)
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
print('Police save ledger tests passed: '..count)
