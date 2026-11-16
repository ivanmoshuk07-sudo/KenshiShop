-- Synchronous, save-scoped payment claims. Ambiguous native effects are held
-- for inspection; repeating a dialogue must never repeat a debit or spawn.
local Store=require('Core.Police.Services.Store')
local M={}
local MAX_INT=2147483647
local function integer(value)
 return type(value)=='number' and value==value and value>=0 and value<=MAX_INT and value%1==0
end
local function field(object,key)
 local ok,value=pcall(function()return object[key]end)
 if ok then return value end
end
local function balance(wallet,getMoney)
 local ok,value=pcall(getMoney,wallet)
 if ok and integer(value) then return value end
end
local function reason(value,fallback)
 if type(value)=='string' and value~='' then return value end
 return fallback
end
-- Copy metadata before touching money. An engine handle, metatable or cycle
-- must not make an otherwise successful transaction impossible to save.
local function metadataCopy(source)
 if source==nil then return {} end
 if type(source)~='table' then return nil end
 local active,entries={},0
 local function copy(value,depth)
  local kind=type(value)
  if kind=='string' or kind=='boolean' then return value end
  if kind=='number' and value==value and value~=math.huge and value~=-math.huge then return value end
  if kind~='table' or depth>8 or getmetatable(value)~=nil or active[value] then error('INVALID_METADATA',0)end
  active[value]=true
  local result={}
  for key,item in pairs(value)do
   local keyType=type(key)
   if keyType~='string' and keyType~='boolean' and keyType~='number' then error('INVALID_METADATA',0)end
   if keyType=='number' and (key~=key or key==math.huge or key==-math.huge)then error('INVALID_METADATA',0)end
   entries=entries+1;if entries>1000 then error('INVALID_METADATA',0)end
   result[key]=copy(item,depth+1)
  end
  active[value]=nil
  return result
 end
 local ok,result=pcall(copy,source,1)
 if ok then return result end
end
local function refund(order,wallet,getMoney,addMoney,why)
 order.status='refund_pending'
 -- Allocation may have changed the wallet. Verify the credit against the
 -- current balance, never against the earlier payment observation.
 local before=balance(wallet,getMoney)
 if before==nil or before>MAX_INT-order.cost then return order,nil,'REFUND_PENDING'end
 order.refundBefore=before
 order.refundAttempted=true
 local ok=pcall(addMoney,wallet,order.cost)
 local after=balance(wallet,getMoney)
 order.refundAfter=after
 if ok and after==before+order.cost then
  order.status='refunded'
  return order,nil,reason(why,'ALLOCATION_FAILED')
 end
 -- No automatic credit retry, even if addMoney threw after adding money.
 return order,nil,'REFUND_PENDING'
end
function M.pay(kind,subject,cost,wallet,metadata,allocate)
 if not Store.ready() then return nil,nil,'STORE_NOT_READY'end
 if type(kind)~='string' or kind=='' or type(subject)~='string' or subject=='' then
  return nil,nil,'INVALID_ORDER'
 end
 local state=Store.get()
 for _,existing in pairs(state.orders)do
  if type(existing)=='table' and existing.kind==kind and existing.subject==subject
   and existing.status~='cancelled' and existing.status~='refunded' then
   return existing,nil,'DUPLICATE'
  end
 end
 if not integer(cost) or cost==0 then return nil,nil,'INVALID_PRICE'end
 if type(allocate)~='function' then return nil,nil,'ALLOCATOR_REQUIRED'end
 local plain=metadataCopy(metadata)
 if not plain then return nil,nil,'INVALID_METADATA'end
 local getMoney,takeMoney,addMoney=field(wallet,'getMoney'),field(wallet,'takeMoney'),field(wallet,'addMoney')
 if type(getMoney)~='function' or type(takeMoney)~='function' or type(addMoney)~='function' then
  return nil,nil,'WALLET_API_UNAVAILABLE'
 end
 local before=balance(wallet,getMoney)
 if before==nil then return nil,nil,'BALANCE_UNAVAILABLE'end
 if before<cost then return nil,nil,'INSUFFICIENT_FUNDS'end
 state.seq=state.seq+1
 local order={id=tostring(state.seq),kind=kind,subject=subject,cost=cost,
  status='pending_payment',metadata=plain,before=before}
 state.orders[order.id]=order
 -- Claim exists before any native call, including a reentrant dialogue.
 local paid,taken=pcall(takeMoney,wallet,cost)
 local after=balance(wallet,getMoney)
 order.after=after
 if after==before then
  order.status='cancelled'
  return order,nil,'PAYMENT_NOT_TAKEN'
 end
 if not paid or taken~=true or after~=before-cost then
  return order,nil,'PAYMENT_UNCERTAIN'
 end
 order.status='pending'
 order.spawnAttempted=true
 local ok,receipt,why,uncertain=pcall(allocate,order)
 if not ok then return order,nil,'ALLOCATION_UNCERTAIN'end
 if receipt~=nil then
  -- Receipts are transient and may contain native objects. Only the caller's
  -- explicitly written plain pid/member fields belong in the saved order.
  local inspected,pending=pcall(function()return receipt.pending end)
  if not inspected or uncertain~=false or why~=nil then
   return order,receipt,'ALLOCATION_UNCERTAIN'
  end
  if pending then return order,receipt,'ALLOCATION_PENDING'end
  order.status='complete'
  return order,receipt,nil
 end
 if uncertain~=false then return order,nil,'ALLOCATION_UNCERTAIN'end
 return refund(order,wallet,getMoney,addMoney,why)
end
return M
