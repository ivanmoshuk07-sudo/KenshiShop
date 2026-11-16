-- Payment/spawn boundary checks with plain Lua wallets; no game engine used.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local Store=require('Core.Police.Services.Store')
local Orders=require('Core.Police.Services.Orders')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local function data()
 return {sdata={},addString=function(self,key,value)self.sdata[key]=value end}
end
local function fresh()
 local gd=data();assert(Store.load(gd));return gd,Store.get()
end
local function wallet(amount)
 return {money=amount,debits=0,credits=0,
  getMoney=function(self)if self.readFailed then error('read failed')end;return self.money end,
  takeMoney=function(self,cost)self.debits=self.debits+1;self.money=self.money-cost;return true end,
  addMoney=function(self,cost)self.credits=self.credits+1;self.money=self.money+cost end}
end
local function purchase(w,allocate,subject,metadata,cost)
 return Orders.pay('replace',subject or 'replace:dead-1',cost or 10000,w,metadata,allocate)
end
local function success(order)
 order.pid='platoon-1';order.members={'member-1'}
 return {pid='platoon-1'},nil,false
end
local function reload(gd)
 assert(Store.save(gd));Store.reset();assert(Store.load(gd))
end
test('confirmed payment allocates once and duplicates survive reload',function()
 local gd,state=fresh();local w=wallet(50000);local calls=0
 local function allocate(order)calls=calls+1;return success(order)end
 local order,receipt,why=purchase(w,allocate)
 assert(order.id=='1' and state.seq==1 and order.status=='complete' and order.spawnAttempted)
 assert(receipt.pid=='platoon-1' and why==nil and order.before==50000 and order.after==40000)
 assert(w.money==40000 and w.debits==1 and calls==1)
 local same,again,duplicate=purchase(w,allocate)
 assert(same==order and again==nil and duplicate=='DUPLICATE' and w.debits==1 and calls==1)
 reload(gd)
 -- A changed caller price or unavailable current wallet cannot reopen a claim.
 same,again,duplicate=Orders.pay('replace','replace:dead-1',0,nil,nil,nil)
 assert(same.id=='1' and same.status=='complete' and again==nil and duplicate=='DUPLICATE')
 assert(w.debits==1 and calls==1)
end)
test('readiness funds price allocator and refund APIs fail before debit',function()
 Store.reset();local w=wallet(50000)
 local order,_,why=purchase(w,success);assert(not order and why=='STORE_NOT_READY')
 fresh();w=wallet(9999)
 order,_,why=purchase(w,success);assert(not order and why=='INSUFFICIENT_FUNDS' and w.debits==0)
 w=wallet(50000)
 for _,cost in ipairs({0,-1,0.5,math.huge,0/0,2147483648})do
  order,_,why=Orders.pay('replace','replace:dead-1',cost,w,{},success)
  assert(not order and why=='INVALID_PRICE' and w.debits==0)
 end
 order,_,why=purchase(w,nil);assert(not order and why=='ALLOCATOR_REQUIRED')
 w.addMoney=nil;order,_,why=purchase(w,success)
 assert(not order and why=='WALLET_API_UNAVAILABLE' and w.debits==0 and Store.get().seq==0)
end)
test('verified no debit cancels without allocation and permits a new request',function()
 fresh();local w=wallet(50000);local calls=0
 w.takeMoney=function(self)self.debits=self.debits+1;return true end
 local order,_,why=purchase(w,function()calls=calls+1 end)
 assert(order.status=='cancelled' and why=='PAYMENT_NOT_TAKEN' and calls==0 and w.money==50000)
 w.takeMoney=function(self,cost)self.debits=self.debits+1;self.money=self.money-cost;return true end
 local nextOrder=purchase(w,success)
 assert(nextOrder.id=='2' and nextOrder.status=='complete' and w.debits==2)
end)
test('partial contradictory thrown and unreadable debits remain claimed',function()
 local cases={
  function(self,cost)self.money=self.money-cost+1;return true end,
  function(self,cost)self.money=self.money-cost;return false end,
  function(self,cost)self.money=self.money-cost;error('native debit failed')end,
  function(self,cost)self.money=self.money-cost;self.readFailed=true;return true end,
 }
 for _,debit in ipairs(cases)do
  local gd=fresh();local w=wallet(50000);local calls=0
  w.takeMoney=function(self,cost)self.debits=self.debits+1;return debit(self,cost)end
  local order,_,why=purchase(w,function()calls=calls+1 end)
  assert(order.status=='pending_payment' and why=='PAYMENT_UNCERTAIN' and not order.spawnAttempted)
  reload(gd);local same,_,duplicate=purchase(w,success)
  assert(same.id==order.id and duplicate=='DUPLICATE' and w.debits==1 and calls==0 and w.credits==0)
 end
end)
test('known allocation failure refunds the current balance exactly once',function()
 fresh();local w=wallet(50000);local calls=0
 local order,_,why=purchase(w,function()
  calls=calls+1;w.money=w.money+7;return nil,'SPAWN_UNAVAILABLE',false
 end)
 assert(order.status=='refunded' and order.spawnAttempted and why=='SPAWN_UNAVAILABLE')
 assert(order.refundAttempted and order.refundBefore==40007 and order.refundAfter==50007)
 assert(w.money==50007 and w.debits==1 and w.credits==1 and calls==1)
 local retry=purchase(w,success)
 assert(retry.id=='2' and retry.status=='complete' and w.debits==2 and w.credits==1)
end)
test('failed or uncertain refunds never retry credit after reload',function()
 local cases={
  function()end,
  function(self,cost)self.money=self.money+cost-1 end,
  function(self,cost)self.money=self.money+cost;error('credit result unknown')end,
 }
 for _,credit in ipairs(cases)do
  local gd=fresh();local w=wallet(50000)
  w.addMoney=function(self,cost)self.credits=self.credits+1;return credit(self,cost)end
  local order,_,why=purchase(w,function()return nil,'FAILED',false end)
  assert(order.status=='refund_pending' and order.refundAttempted and why=='REFUND_PENDING')
  reload(gd);local same,_,duplicate=purchase(w,success)
  assert(same.status=='refund_pending' and duplicate=='DUPLICATE' and w.credits==1 and w.debits==1)
 end
end)
test('allocation exceptions uncertainty and pending receipts never spawn twice',function()
 local cases={
  function()error('allocation threw after creating a platoon')end,
  function()return nil,'READBACK_PENDING',true end,
  function()return {pending=true},nil,false end,
  function()return {pid='not-verified'},nil,nil end,
 }
 for _,allocate in ipairs(cases)do
  local gd=fresh();local w=wallet(50000);local calls=0
  local order=purchase(w,function(o)calls=calls+1;return allocate(o)end)
  assert(order.status=='pending' and order.spawnAttempted and w.money==40000 and w.credits==0)
  reload(gd);local same,_,duplicate=purchase(w,success)
  assert(same.id==order.id and duplicate=='DUPLICATE' and w.debits==1 and calls==1)
 end
end)
test('claims precede reentrant native calls and allocator callbacks',function()
 fresh();local w=wallet(50000);local nested=0
 local native=w.takeMoney
 w.takeMoney=function(self,cost)
  local order,receipt,why=purchase(self,success)
  assert(order.status=='pending_payment' and receipt==nil and why=='DUPLICATE');nested=nested+1
  return native(self,cost)
 end
 local order=purchase(w,function(o)
  assert(o.spawnAttempted)
  local again,receipt,why=purchase(w,success)
  assert(again==o and receipt==nil and why=='DUPLICATE');nested=nested+1
  return success(o)
 end)
 assert(order.status=='complete' and nested==2 and w.debits==1)
end)
test('metadata is copied and engine receipts stay outside the plain ledger',function()
 local gd=fresh();local w=wallet(50000)
 local metadata={role='Охранник',count=3,nested={false,42}}
 local engine=setmetatable({native=function()end},{})
 local order,receipt=purchase(w,function(o)o.members={'native-handle-string'};return {native=engine},nil,false end,nil,metadata)
 metadata.nested[2]=99
 assert(order.metadata.nested[2]==42 and receipt.native==engine and order.receipt==nil)
 reload(gd);assert(Store.get().orders[order.id].members[1]=='native-handle-string')
end)
test('unsafe metadata is rejected before payment',function()
 local cycle={};cycle.self=cycle
 for _,metadata in ipairs({{f=function()end},cycle,setmetatable({},{}),{number=math.huge},{[{}]='key'}})do
  fresh();local w=wallet(50000);local order,_,why=purchase(w,success,nil,metadata)
  assert(not order and why=='INVALID_METADATA' and w.debits==0 and Store.get().seq==0)
 end
end)
test('kind and subject distinguish replacement deaths and hired patrol requests',function()
 fresh();local w=wallet(70000)
 local first=Orders.pay('replace','replace:dead-1',10000,w,{},success)
 local second=Orders.pay('replace','replace:dead-2',10000,w,{},success)
 local hire=Orders.pay('hire','hire:request-1',20000,w,{count=3},success)
 local duplicate,_,why=Orders.pay('hire','hire:request-1',20000,w,{},success)
 assert(first.id=='1' and second.id=='2' and hire.id=='3' and duplicate==hire and why=='DUPLICATE')
 assert(w.money==30000 and w.debits==3)
end)
print('Police order tests passed: '..count)
