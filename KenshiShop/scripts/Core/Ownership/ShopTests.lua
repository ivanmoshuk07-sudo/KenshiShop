-- KenshiShop alpha.33: manual one-shot, read-only two-shop field tests.
-- No hook, spawn, build, faction mutation, or persistent background task.
local Log=require('Diagnostics')
local Registry=require('Core.Ownership.Registry')
local M={}
local SIDS={['104-KenshiShop.mod']='robotics',['100-KenshiShop.mod']='bar'}
local EXPECT='400-KenshiShop.mod'
local test=nil
local function try(fn)
 local ok,v=pcall(fn)
 if ok then return v end
 return nil
end
local function prop(o,name)
 return try(function()return o and o[name] end)
end
local function call(o,name)
 return try(function()return o and o[name] and o[name](o) end)
end
local function textid(b)
 return try(function()return b:getHandle():toString()end) or 'UNAVAILABLE'
end
local function faction(b)
 local f=call(b,'getFaction')
 local d=call(f,'getData')
 return tostring(prop(d,'stringID') or 'UNAVAILABLE')
end
local function town(b)
 local h=call(b,'getTownHandle')
 return tostring(call(h,'toString') or 'TOWN_ID_UNAVAILABLE')
end
local function lines(s)
 Log.console(s)
 return s
end
local function discover(state,scan)
 if scan then pcall(scan) end
 local out={}
 for _,key in ipairs(state.order)do
  local ent=state.tracked[key]
  if ent and SIDS[ent.id] then
   local b=call(ent.handle,'getBuilding')
   if b and call(b,'isValid')==true and SIDS[prop(call(b,'getGameData'),'stringID')] then
    out[#out+1]={key=key,kind=SIDS[ent.id],b=b}
   end
  end
 end
 return out
end
local function recentTiming(kind,key)
 local history=Registry.logs(400)
 for i=#history,1,-1 do
  local v=history[i]
  if v:find('OWN_TRANSFER_TIMING ',1,true)
   and v:find(' shop='..kind..' ',1,true)
   and v:find(' building='..key..' ',1,true) then
    return v
  end
 end
 return 'OWN_TRANSFER_TIMING_NOT_RECORDED'
end
local function report(kind,state,scan,onlyNew,filterKeys)
 local seen,okCount,summary={},0,{}
 local items=discover(state,scan)
 for _,it in ipairs(items)do
  if (not onlyNew or not test or not test.base[it.key])
     and (not filterKeys or filterKeys[it.key]) then
   local owner=faction(it.b)
   local player=call(it.b,'isThePlayer')
   local pass=owner==EXPECT and player==false
   local rec={key=it.key,kind=it.kind,pass=pass}
   summary[#summary+1]=rec
   if pass then okCount=okCount+1 end
   seen[it.kind]=(seen[it.kind] or 0)+1
   lines('OWN_TEST_'..kind..'_ITEM shop='..it.kind..' building='..it.key
     ..' owner='..owner..' playerOwned='..tostring(player)
     ..' townHandle='..town(it.b)..' result='..(pass and 'PASS' or 'FAIL'))
   lines('OWN_TEST_'..kind..'_TIMING shop='..it.kind..' building='..it.key..' '..recentTiming(it.kind,it.key))
  end
 end
 local both=(seen.robotics==1 and seen.bar==1)
 local barEarly='NOT_ESTABLISHED'
 for _,rec in ipairs(summary)do
  if rec.kind=='bar' then
   local event=recentTiming('bar',rec.key)
   if event:find('mode=ANCHOR_APPLIED',1,true) and event:find('origin=CONSTRUCTION',1,true) then
    barEarly='ANCHOR_BEFORE_STORE_NPC'
   elseif event:find('mode=APPLIED',1,true) then
    barEarly='OWN_STORE_SQUAD'
   elseif event:find('mode=ALREADY_OWNED',1,true) then
    barEarly='ALREADY_OWNED'
   end
  end
 end
 local result=(both and #summary==2 and okCount==2) and 'PASS' or 'INCOMPLETE_OR_FAILED'
 local fin='OWN_TEST_'..kind..'_RESULT status='..result..' stores='..#summary
   ..' owned='..okCount..' robotics='..tostring(seen.robotics or 0)
   ..' bar='..tostring(seen.bar or 0)
   ..' bar_transfer_mode='..barEarly
   ..' scoped_to_new='..tostring(onlyNew==true)
   ..' no_mutations=true'
 lines(fin)
 return fin
end
function M.start(state,scan)
 local base={}
 for _,it in ipairs(discover(state,scan))do base[it.key]=true end
 test={base=base}
 local n=0 for _ in pairs(base)do n=n+1 end
 return lines('OWN_TEST_1_START baseline_shops='..n
  ..' action=build_robotics_then_bar; after_both_run_KS.ownerTest1Report()')
end
function M.report1(state,scan)
 if not test then return lines('OWN_TEST_1_NOT_STARTED run_KS.ownerTest1Start_before_construction') end
 return report('1',state,scan,true)
end
function M.before(state,scan)
 return report('2_BEFORE',state,scan,test~=nil)
end
function M.after(state,scan,roboticsKey,barKey)
 if roboticsKey~=nil or barKey~=nil then
  if type(roboticsKey)~='string' or type(barKey)~='string' or
     #roboticsKey>160 or #barKey>160 then
   return lines('OWN_TEST_2_AFTER_ERROR expected_two_building_handle_strings')
  end
  return report('2_AFTER',state,scan,false,{[roboticsKey]=true,[barKey]=true})
 end
 return report('2_AFTER',state,scan,false)
end
return M
