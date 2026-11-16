-- Native save-field boundary checks; no game files or engine code are loaded.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local Store=require('Core.Police.Services.Store')
local KEY='KenshiShopChiefStateV1'
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function data(saved)
 return {sdata=saved and {[KEY]=saved} or {},writes=0,
  addString=function(self,key,value,category,visible)
   assert(key==KEY and category=='KenshiShop' and visible==false)
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
 local gd=fresh();assert(Store.save(gd));local saved=gd.sdata[KEY]
 assert(saved:find('S7:versionN1:1',1,true))
 rejected(saved:gsub('S7:versionN1:1','S7:versionN1:2'),'STORE_VERSION_UNSUPPORTED')
 rejected('KSCS1:T0:','STORE_VERSION_UNSUPPORTED')
 rejected(saved:gsub('S3:seqN1:0','S3:seqN2:-1'),'STORE_SEQUENCE_INVALID')
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
 local ok,reason=Store.save(gd);assert(not ok and reason:find('STORE_BYTES_LIMIT',1,true) and gd.writes==0)
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
  local gd,state=fresh();state.orders.bad=value;assert(not Store.save(gd) and gd.writes==0)
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
print('Police save ledger tests passed: '..count)
