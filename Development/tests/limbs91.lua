-- Registration and failure/readback tests. No damage or healing is simulated.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local logs={};package.loaded.Diagnostics={console=function(line)logs[#logs+1]=line end}
local calls,fail,amputations,crushes
package.loaded['Core.NPC.NativeBridge']={
 protectLimbs=function(med,race)
  calls.protect=calls.protect+1;assert(med.id=='medical')
  if fail then return false,'NOSEVER_NATIVE_API_MISSING'end
  return true,amputations,crushes
 end,
 unprotectLimbs=function()calls.remove=calls.remove+1;return true end}
local Protect=require('Core.NPC.NoSever')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local s,ms,c,med,race,missing
local function fixture()
 calls={protect=0,remove=0};fail=false;amputations=0;crushes=0;logs={};race='7117-KenshiShop.mod';missing=false
 med={id='medical',health=-216,getLimbState=function(_,part)return missing and part==2 and 1 or 0 end,
  _setHealth=function()error('health writes forbidden')end,setRobotLimbItem=function()error('limb restoration forbidden')end}
 c={getRace=function()return {data={stringID=race}}end,getMedical=function()return med end,
  isUnconcious=function()return true end,isBeingCarried=function()return true end,
  setRace=function()error('race changes forbidden')end,setDestination=function()error('orders forbidden')end}
 s={cfg={role='guard',shop='armour'},now=720};ms={{key='guard',char=c}}
end
test('whitelist contains exactly the 14 custom races, excluding vanilla and other mods',function()
 local found=0
 for n=7100,7120 do if Protect.isProtectedRace(n..'-KenshiShop.mod')then found=found+1;assert(n>=7101 and n<=7106 or n>=7110 and n<=7117)end end
 assert(found==14 and not Protect.isProtectedRace('17946-stick_people.mod') and not Protect.isProtectedRace('7117-other.mod'))
end)
test('actual medical instance registers while unconscious/carried, with zero health/race/order writes',function()
 fixture();Protect.tick(s,ms);assert(calls.protect==1 and s.noSever.guard.active and med.health==-216)
end)
test('all protected races register; matching names alone never register a vanilla race',function()
 for n=7101,7117 do if n<=7106 or n>=7110 then
  fixture();race=n..'-KenshiShop.mod';Protect.tick(s,ms);assert(calls.protect==1 and s.noSever.guard.active)
 end end
 fixture();race='17946-stick_people.mod';c.getName=function()return 'KS NoSever: Skeleton'end
 Protect.tick(s,ms);assert(calls.protect==0)
end)
test('existing limb loss is reported and never silently repaired',function()
 fixture();missing=true;Protect.tick(s,ms)
 assert(logs[1]:find('existing_missing=left_leg',1,true) and logs[1]:find('restore_existing=false',1,true) and med.health==-216)
end)
test('missing or failed native bridge never reports READY and stops after three failures',function()
 fixture();fail=true;for i=1,20 do Protect.tick(s,ms)end
 assert(calls.protect==3 and #logs==3 and not s.noSever.guard.active)
 for _,line in ipairs(logs)do assert(line:find('_FAILED',1,true) and not line:find('_READY',1,true))end
end)
test('medical data still loading defers without using the failure budget',function()
 fixture();local get=c.getMedical;c.getMedical=function()return nil end
 for i=1,20 do Protect.tick(s,ms)end;assert(calls.protect==0 and s.noSever.guard.tries==0)
 c.getMedical=get;Protect.tick(s,ms);assert(calls.protect==1)
end)
test('a race change to vanilla removes a previous registration and does not change the race back',function()
 fixture();Protect.tick(s,ms);race='17946-stick_people.mod';Protect.tick(s,ms)
 assert(calls.remove==1 and not s.noSever.guard.active and race=='17946-stick_people.mod')
 Protect.tick(s,ms);assert(calls.remove==1)
end)
test('native blocked counters are observed with bounded log frequency',function()
 fixture();Protect.tick(s,ms);amputations=1;Protect.tick(s,ms)
 assert(logs[#logs]:find('_BLOCKED',1,true));local written=#logs
 amputations=2;s.now=721;Protect.tick(s,ms);assert(#logs==written)
 amputations=3;crushes=1;s.now=731;Protect.tick(s,ms);assert(#logs==written+1 and med.health==-216)
end)
print('NoSever registration/readback tests passed: '..count)
