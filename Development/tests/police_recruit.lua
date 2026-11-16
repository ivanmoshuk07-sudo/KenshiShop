-- Portable mocks only: no Kenshi DLL, native executable or game is loaded.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local Config=require('Core.Police.Services.Config')
local Store=require('Core.Police.Services.Store')
local world,building,town,faction,platoon,ap,records,calls,events,newChar
local function handle(key,char)return {toString=function()return key end,isNull=function()return not key end,
 getCharacter=function()return char end}end
local function dataID(o)return o and o.stringID end
local function call(o,m,...)if o and type(o[m])=='function'then return o[m](o,...)end end
package.loaded.Diagnostics={console=function()end,error=function()end}
package.loaded['Core.NPC.LiveState']={call=call}
package.loaded['Core.NPC.OriginTown']={field=function(o,k)return o and o[k]end,
 id=function(o)return call(call(o,'getHandle'),'toString')end,
 select=function()return {nativeOrigin=true},'MOCK_ORIGIN'end}
package.loaded['Core.NPC.Transport']={
 valid=function(p)return p and p.x==p.x and p.y==p.y and p.z==p.z end,
 selectOutside=function()return {x=200,y=0,z=0},'gate'end,
 members=function(_,p)
  if p.scanError then return nil,p.scanError end
  return p.members
 end}
package.loaded['Core.NPC.HomeAssignment']={ensure=function(s,ms,bb)
 calls.home=calls.home+1;assert(#ms==1 and ms[1].char==newChar,'home must touch new actor only')
 assert(s.platoon==newChar.owner.me);bb.targetTown=town;events[#events+1]='home'
 return true
end}
package.loaded['Core.NPC.Appearance']={apply=function(c,_,shop)
 calls.appearance=calls.appearance+1;assert(c==newChar and c.race.data.stringID==records.dead.race)
 events[#events+1]='appearance';return true
end}
package.loaded['Core.NPC.Supplies']={sync=function(c)
 calls.supplies=calls.supplies+1;assert(c==newChar);events[#events+1]='supplies'
 if world.suppliesPending then return false,'INVENTORY_INITIALIZING'end
 return true
end}
package.loaded['Core.NPC.NativeBridge']={protectLimbs=function(_,race)
 calls.protect=calls.protect+1;assert(race==records.dead.race);events[#events+1]='protect';return true,0,0
end}
-- Exercise the real NoSever registration against the saved custom race.
local Recruit=require('Core.Police.Services.Recruit')
local function character(key,dead,owner,template)
 local c={key=key,dead=dead,owner=owner,name='Factory default',race={data={stringID='vanilla-race'}},bb={},setupCalls=0}
 function c:getHandle()return handle(self.key,self)end
 function c:getPlatoon()if self.ownerPending then error('initializing owner')end;return self.owner end
 function c:getFaction()return faction end
 function c:getGameData()return {stringID=template or 'guard-char'}end
 function c:isDead()return self.dead end
 function c:getRace()return self.race end
 function c:setRace(data)events[#events+1]='race';self.race={data=data}end
 function c:getName()return self.name end
 function c:setName(name)events[#events+1]='name';self.name=name end
 function c:setupPlatoonAI()self.setupCalls=self.setupCalls+1;events[#events+1]='setup'end
 function c:getBlackboard()return self.bb end
 function c:getMedical()return {getLimbState=function()return 0 end}end
 function c:setDestination()error('replacement must never issue movement to survivors')end
 return c
end
local function makePlatoon(key,template)
 local p={key=key,squadTemplate={stringID=template or '7800-KenshiShop.mod'},members={}}
 local a={me=p}
 function p:getPlatoonStringID()return self.key end
 function p:getFaction()return faction end
 function p:getActivePlatoon()if self.unloaded then return nil end;return a end
 function a:getSquadSize()return #p.members end
 function a:getSquadLeader()return self.lead end
 function a:setSquadLeader(c)calls.leader=calls.leader+1;self.lead=c end
 function a:removeObject(c)
  assert(c.dead==true);calls.remove=calls.remove+1
  assert(calls.actor==1 and newChar and newChar.owner==self,'allocate before retiring the last corpse')
  if world.detachFails then return false end
  for i,m in ipairs(p.members)do if m.char==c then table.remove(p.members,i);break end end
  c.owner=nil;return true
 end
 function a:addActiveObject(c)
  calls.add=calls.add+1;assert(c.owner==nil,'must not double-add factory-owned actor')
  c.owner=self;p.members[#p.members+1]={key=c.key,char=c};return true
 end
 return p,a
end
local function reset(template)
 calls={actor=0,empty=0,remove=0,add=0,leader=0,home=0,appearance=0,supplies=0,protect=0};events={}
 faction={getData=function()return {stringID=Config.faction}end}
 town={getHandle=function()return handle('town')end,getFaction=function()return {isThePlayer=function()return true end}end,
  withinBordersRange=function()return false end}
 building={getHandle=function()return handle('building')end,isValid=function()return true end,
  getFaction=function()return faction end,getTown=function()return town end,getPosition=function()return {x=0,y=0,z=0}end}
 platoon,ap=makePlatoon('old',template)
 function faction:getActivePlatoons()return self.active or {platoon}end
 function faction:getUnloadedPlatoons()return self.unloaded or {}end
 function faction:createNewEmptyActivePlatoon(data,permanent,pos)
  calls.empty=calls.empty+1;assert(permanent and pos.x==200)
  local p,a=makePlatoon('new-pid',data.stringID);self.active={p};return p
 end
 world={factionMgr={getFactionByStringID=function()return faction end},navmesh={getPositionValid=function()return true end}}
 world.gamedata={getData=function(_,key,kind)
  if world.missingData==key then return nil end
  if key=='guard-char'then assert(kind==1)end
  if key=='7111-KenshiShop.mod'then assert(kind==7)end
  return {stringID=key}
 end}
 world.theFactory={createRandomCharacter=function(_,f,pos,a,data,b,age)
  calls.actor=calls.actor+1;assert(f==faction and pos.x==200 and b==building and age==1 and dataID(data)=='guard-char')
  if world.factoryThrows then error('factory allocated then failed')end
  if world.factoryNil then return nil end
  newChar=character('new-member',false,a)
  if world.factoryNoOwner then newChar.owner=nil end
  newChar.ownerPending=world.ownerPending
  if not world.factoryNoOwner then a.me.members[#a.me.members+1]={key=newChar.key,char=newChar}end
  if world.factoryPending then return {getHandle=function()return handle('new-member',world.characterReady and newChar or nil)end}end
  return {getHandle=function()return newChar:getHandle()end}
 end}
 function getGameWorld()return world end
 Store.reset();assert(Store.load({sdata={}}))
 records={dead={id='dead',pid='old',building='building',town='town',squadTemplate=template or '7800-KenshiShop.mod',
  charTemplate='guard-char',race='7111-KenshiShop.mod',name='KS: Охрана (1 этаж)',slot=1,dead=true},
  survivor={id='survivor',pid='old',building='building',town='town',squadTemplate=template or '7800-KenshiShop.mod',dead=false}}
 Store.get().roster=records
 local corpse=character('dead',true,ap);local survivor=character('survivor',false,ap)
 survivor.name='KS: Охрана (2 этаж)';survivor.race={data={stringID='7113-KenshiShop.mod'}}
 survivor.inventory={unchanged=true};survivor.bb={nativeCare=true};ap.lead=survivor
 platoon.members={{key='dead',char=corpse},{key='survivor',char=survivor}}
 newChar=nil;return corpse,survivor
end
local function denied(fragment,p)
 local plan,why=Recruit.prepare(records.dead,building,p)
 assert(not plan and tostring(why):find(fragment,1,true),tostring(why))
 assert(calls.actor==0 and calls.empty==0 and calls.remove==0)
end
test('read-only preflight and one replacement preserve survivor, corpse, race and guard floor',function()
 local corpse,survivor=reset();local oldBB,oldInv,oldRace=survivor.bb,survivor.inventory,survivor.race
 local plan=assert(Recruit.prepare(records.dead,building,platoon));assert(calls.remove==0 and calls.actor==0)
 local receipt=assert(Recruit.spawn(plan));assert(receipt.char==newChar and receipt.member=='new-member' and not receipt.pending)
 assert(Recruit.finish(plan,receipt));assert(Recruit.finish(plan,receipt));assert(Recruit.spawn(plan)==receipt)
 assert(calls.actor==1 and calls.empty==0 and calls.add==0 and calls.remove==1 and calls.leader==0)
 assert(corpse.dead==true and corpse.owner==nil and survivor.owner==ap and ap.lead==survivor)
 assert(survivor.bb==oldBB and survivor.inventory==oldInv and survivor.race==oldRace and survivor.setupCalls==0)
 assert(survivor.name=='KS: Охрана (2 этаж)' and newChar.name=='KS: Охрана (1 этаж)')
 assert(newChar.race.data.stringID=='7111-KenshiShop.mod' and newChar.setupCalls==1)
 assert(calls.home==1 and calls.appearance==1 and calls.supplies==1 and calls.protect==1)
 assert(events[1]=='race' and events[#events]=='protect')
 assert(receipt.state.work.setup['new-member'] and receipt.state.work.leader=='survivor')
end)
test('unknown death, unloaded squad and incomplete scans refuse without allocation',function()
 reset();records.dead.dead=nil;denied('DEATH_NOT_AVAILABLE',platoon)
 reset();platoon.members[1].char.dead=nil;denied('MEMBER_DEATH_UNCONFIRMED',platoon)
 reset();platoon.unloaded=true;denied('PLATOON_UNLOADED',platoon)
 reset();platoon.scanError='UNKNOWN';denied('PLATOON_SCAN_INCOMPLETE',platoon)
 reset();records.dead.replacedBy='other';denied('DEATH_NOT_AVAILABLE',platoon)
end)
test('faction, templates, race and outside navmesh must be verified before payment',function()
 reset();building.getFaction=function()return nil end;denied('BUILDING_FACTION_MISMATCH',platoon)
 reset();world.missingData='guard-char';denied('CHARACTER_DATA_UNAVAILABLE',platoon)
 reset();world.missingData=records.dead.race;denied('RACE_DATA_UNAVAILABLE',platoon)
 reset();town.withinBordersRange=function()return nil end;denied('SPAWN_NOT_CONFIRMED_OUTSIDE',platoon)
 reset();world.navmesh.getPositionValid=function()return false end;denied('SPAWN_NAVMESH_INVALID',platoon)
end)
test('a missing platoon requires a complete all-dead ledger and both readable native rosters',function()
 reset();faction.active={};denied('PLATOON_DEATH_UNCONFIRMED',nil)
 reset();faction.active={};records.survivor=nil;denied('PLATOON_ROSTER_INCOMPLETE',nil)
 reset();records.survivor.dead=true;faction.active={};faction.unloaded={platoon};denied('EXISTING_PLATOON_REQUIRES_ACTIVE_LOOKUP',nil)
 reset();records.survivor.dead=true;faction.active={};faction.getUnloadedPlatoons=function()return nil end
 denied('FACTION_ROSTER_UNAVAILABLE',nil)
 reset();records.survivor.dead=true;faction.active={}
 local plan=assert(Recruit.prepare(records.dead,building,nil));local receipt=assert(Recruit.spawn(plan))
 assert(calls.empty==1 and calls.actor==1 and receipt.pid=='new-pid' and #receipt.platoon.members==1)
 assert(calls.leader==1 and Recruit.finish(plan,receipt));assert(Recruit.spawn(plan)==receipt and calls.actor==1)
end)
test('an entirely dead loaded platoon keeps its owner until one new actor exists',function()
 local corpse,other=reset();records.survivor.dead=true;other.dead=true;ap.lead=corpse
 local plan=assert(Recruit.prepare(records.dead,building,platoon));local receipt=assert(Recruit.spawn(plan))
 assert(receipt.platoon==platoon and receipt.pid=='old' and calls.empty==0 and calls.actor==1)
 assert(calls.remove==2 and calls.leader==1 and #platoon.members==1 and ap.lead==newChar)
 assert(corpse.dead and other.dead and not corpse.owner and not other.owner and Recruit.finish(plan,receipt))
end)
test('factory handles and owner initialization stay pending without allocating again',function()
 reset();world.factoryPending=true;local plan=assert(Recruit.prepare(records.dead,building,platoon))
 local receipt=assert(Recruit.spawn(plan));assert(receipt.pending and not receipt.char)
 assert(not Recruit.finish(plan,receipt));assert(Recruit.spawn(plan)==receipt and calls.actor==1)
 world.characterReady=true;assert(Recruit.finish(plan,receipt));assert(calls.actor==1 and newChar.setupCalls==1)
 reset();world.ownerPending=true;plan=assert(Recruit.prepare(records.dead,building,platoon));receipt=assert(Recruit.spawn(plan))
 assert(receipt.pending and calls.add==0);assert(not Recruit.finish(plan,receipt));newChar.ownerPending=nil
 assert(Recruit.finish(plan,receipt) and calls.actor==1 and calls.add==0)
end)
test('a known empty owner attaches once while an existing owner is never added twice',function()
 reset();world.factoryNoOwner=true
 local plan=assert(Recruit.prepare(records.dead,building,platoon));local receipt=assert(Recruit.spawn(plan))
 assert(calls.add==1 and newChar.owner==ap and Recruit.finish(plan,receipt))
 assert(Recruit.finish(plan,receipt) and calls.add==1 and calls.actor==1)
end)
test('post-allocation exceptions and nils are uncertain and prohibit a second factory call',function()
 for _,flag in ipairs({'factoryThrows','factoryNil'})do
  reset();world[flag]=true;local plan=assert(Recruit.prepare(records.dead,building,platoon))
  local receipt,why,uncertain=Recruit.spawn(plan);assert(not receipt and why and uncertain==true)
  receipt,why,uncertain=Recruit.spawn(plan);assert(not receipt and uncertain==true and calls.actor==1)
 end
 reset();world.detachFails=true;local plan=assert(Recruit.prepare(records.dead,building,platoon))
 local receipt=assert(Recruit.spawn(plan));assert(receipt.pending and calls.actor==1)
 assert(not Recruit.finish(plan,receipt));assert(Recruit.spawn(plan)==receipt and calls.actor==1)
 world.detachFails=nil;assert(Recruit.finish(plan,receipt))
 reset();local plan=assert(Recruit.prepare(records.dead,building,platoon));building.isValid=function()return false end
 local receipt,why,uncertain=Recruit.spawn(plan);assert(not receipt and why and uncertain==false and calls.actor==0)
end)
test('pending finishing retries only incomplete new-actor stages and restores without spawning',function()
 reset();world.suppliesPending=true;local plan=assert(Recruit.prepare(records.dead,building,platoon))
 local receipt=assert(Recruit.spawn(plan));assert(not Recruit.finish(plan,receipt))
 assert(receipt.stages.race and receipt.stages.setup and not receipt.stages.supplies)
 local resumed,restored=Recruit.restore(records.dead,building,platoon,receipt.member,receipt.stages)
 assert(resumed and restored and calls.actor==1);world.suppliesPending=nil
 assert(Recruit.finish(resumed,restored));assert(Recruit.finish(resumed,restored))
 assert(calls.actor==1 and calls.home==1 and calls.appearance==1 and newChar.setupCalls==1)
 assert(restored.state.work.setup['new-member'] and restored.setupDone)
 platoon.unloaded=true;assert(not Recruit.restore(records.dead,building,platoon,'new-member'))
 platoon.unloaded=nil;assert(not Recruit.restore(records.dead,building,platoon,'unknown-member'))
 assert(calls.actor==1 and calls.empty==0)
end)
test('restoring a finished native actor re-registers protection without repeating durable setup',function()
 reset();local plan=assert(Recruit.prepare(records.dead,building,platoon));local receipt=assert(Recruit.spawn(plan))
 assert(Recruit.finish(plan,receipt) and receipt.stages.nosever)
 local restoredPlan,restored=Recruit.restore(records.dead,building,platoon,receipt.member,receipt.stages)
 assert(restoredPlan and not restored.stages.nosever and Recruit.finish(restoredPlan,restored))
 assert(calls.protect==2 and calls.home==1 and calls.appearance==1 and newChar.setupCalls==1 and calls.actor==1)
end)
print('Chief replacement tests passed: '..count)
