package.path=arg[1]..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path

local towerSID='105-KenshiShop.mod'
local crematoriumSID='106-KenshiShop.mod'
local chiefSID='310-KenshiShop.mod'
local npcID='400-KenshiShop.mod'
local objects,retired,transfers,stopped={},{},{},{}
local function hand(key)
 return {
  key=key,toString=function(h)return h.key end,
  isNull=function(h)return h.key==nil end,
  setNull=function(h)h.key=nil end,
  fromString=function(h,wanted)h.key=wanted end,
  getBuilding=function(h)return objects[h.key]end,
  getPlatoon=function(h)return objects[h.key]end,
 }
end
local function faction(id,player)
 local f={getData=function()return {stringID=id}end,isThePlayer=function()return player end}
 f.factionOwnerships={
  getOwnedBuildingPtrs=function(_,out,town)
   for _,b in pairs(objects)do
    if b.owner==f and b.town==town then out[#out+1]=b end
   end
  end,
  getOwnedBuildingsH=function(_,out)
   for key,b in pairs(objects)do
    if b.owner==f then out[#out+1]=hand(key)end
   end
  end,
 }
 return f
end
local player,npc,foreign=faction('204-gamedata.base',true),faction(npcID,false),faction('foreign',false)
local ap={getSquadSize=function()return 1 end}
player.getActivePlatoons=function()return {{getActivePlatoon=function()return ap end}}end
getGameWorld=function()
 return {factionMgr={getFactionByStringID=function(_,id)if id==npcID then return npc end end}}
end
lektor={new=function()return {}end}
package.loaded.Diagnostics={console=function()end}
package.loaded['Core.Ownership.Registry']={retire=function(_,k)stopped[k]=true end}
package.loaded.Layouts={
 [towerSID]={name='police',objects={{id='sign',outside=true,p={3,0,1},q={1,0,0,0}}}},
 [crematoriumSID]={name='crematorium',objects={}},
}
local function town(key)
 return {getFaction=function()return player end,getHandle=function()return hand(key)end}
end
local a,b=town('townA'),town('townB')
local function building(key,template,owner,town,parent,position)
 local o={owner=owner,town=town,inside=0,
  getGameData=function()return {stringID=template}end,
  getHandle=function()return hand(key)end,
  getTown=function()return town end,
  getTownHandle=function()return town and town:getHandle() or hand(nil)end,
  isValid=function()return true end,
  getFaction=function(self)return self.owner end,
  isThePlayer=function(self)return self.owner==player end,
  furnitureParentBuilding=function()return parent end,
  getPosition=function()return position or {x=0,y=0,z=0}end,
  getOrientation=function()return {w=1,x=0,y=0,z=0}end,
  getScale=function()return 1 end,
  getNumInternalBuildings=function(self)return self.inside end,
  getMountedBuildings=function()return 0 end,
  setFaction=function(self,f,targetAP)
   assert(targetAP==ap)
   if self.fail then error('native refused')end
   self.owner=f
   transfers[key]=(transfers[key] or 0)+1
  end,
 }
 objects[key]=o
 return o
end
local tower=building('tower',towerSID,npc,a)
tower.inside=2
local armchair=building('armchair','seat',npc,nil,tower)
local bed=building('bed','bed',player,a,tower)
local sign=building('sign','sign',npc,nil,nil,{x=3,y=0,z=1})
local outside=building('outside','exterior',npc,a)
local unrelated=building('unrelated','building',player,a)
local crematorium=building('crematorium',crematoriumSID,npc,a)
local neighbor=building('neighbor',towerSID,npc,b)
local oldTower=building('retired',towerSID,player,a)
retired.retired=true
objects.squad={getPlatoonStringID=function()return 'squad'end,getFaction=function()return npc end,
 squadTemplate={stringID=chiefSID}}
tower.residentSquad=hand('squad')
tower.residentSquadTemplate={stringID=chiefSID}
local ctx={building=tower,town='townA'}
local Retirement=require('Core.Ownership.Retirement')
Retirement.setPredicate(function(key)return retired[key]==true end)
local Property=require('Core.Police.Services.PropertyReturn')
local staffed=assert(Property.staffedShopKeys(ctx))
assert(staffed.tower=='police' and staffed.crematorium=='crematorium' and not staffed.neighbor and not staffed.retired)
local plan=assert(Property.prepare(ctx))
assert(plan.buildings.tower and not plan.buildings.neighbor and not plan.buildings.retired)
assert(plan.buildings.crematorium and plan.property.crematorium)
assert(plan.property.armchair and plan.property.bed and plan.property.sign and plan.property.outside)
assert(not plan.property.unrelated and not plan.property.neighbor and not next(transfers))
local pending,reason=Property.prepare(ctx,{missing=true})
assert(not pending and reason:find('EXPECTED_SHOP_UNAVAILABLE',1,true) and not next(transfers))
tower.inside=3
pending,reason=Property.prepare(ctx)
assert(not pending and reason:find('INTERIOR_NOT_READY',1,true) and not next(transfers))
tower.inside=2
pending,reason=Property.apply(ctx,plan.buildings,plan.property)
assert(not pending and reason:find('PROPERTY_SCOPE_CHANGED',1,true) and not next(transfers))
retired.tower=true;retired.crematorium=true
objects.armchair=nil
pending,reason=Property.apply(ctx,plan.buildings,plan.property)
assert(not pending and reason:find('PROPERTY_UNLOADED',1,true) and not next(transfers))
objects.armchair=armchair
local squads={squad={building='tower',template=chiefSID,handle='squad'}}
outside.fail=true
pending,reason=Property.apply(ctx,plan.buildings,plan.property,squads)
assert(not pending and reason:find('PROPERTY_RETURN_UNVERIFIED',1,true))
assert(stopped.tower and tower.owner==player and armchair.owner==player)
assert(tower.residentSquad:isNull() and tower.residentSquadTemplate==nil)
outside.fail=false
assert(Property.apply(ctx,plan.buildings,plan.property,squads))
assert(outside.owner==player and sign.owner==player and bed.owner==player)
assert(crematorium.owner==player and stopped.crematorium and transfers.crematorium==1)
assert(transfers.tower==1 and transfers.armchair==1 and not transfers.bed)
assert(neighbor.owner==npc and not transfers.unrelated and not stopped.neighbor and not stopped.retired)
sign.owner=foreign
pending,reason=Property.apply(ctx,plan.buildings,plan.property,squads)
assert(not pending and reason:find('PROPERTY_OWNER_CHANGED',1,true) and sign.owner==foreign)
assert(oldTower.owner==player and unrelated.owner==player)
sign.owner=player
tower.residentSquad=hand('squad')
tower.residentSquadTemplate={stringID=chiefSID}
objects.squad=nil
assert(Property.apply(ctx,plan.buildings,plan.property,squads))
assert(tower.residentSquad:isNull() and tower.residentSquadTemplate==nil)
tower.owner=npc
tower.residentSquad=hand('visitor')
objects.visitor={getFaction=function()return foreign end}
pending,reason=Property.apply(ctx,plan.buildings,plan.property,squads)
assert(not pending and reason:find('FOREIGN_RESIDENT_PRESERVED',1,true) and tower.owner==npc)

-- A construction event can arm a shop just before the player confirms.
-- Verify that each pending closure gives way to the persisted retirement.
local armed
Events={
 on=function(_,fn)assert(not armed);armed=fn;return 1 end,
 off=function()armed=nil end,
}
for i,name in ipairs({'Bar','Engineering','Armour','Weapons','Robotics','Police'})do
 local prefix='Core.'..name
 local key='queued'..name
 package.loaded[prefix..'.Building.Interior']={
  expectedInternalCount=function()return 1 end,
  complete=function()error('retired construction must not furnish')end,
 }
 package.loaded[prefix..'.NPC.init']={
  start=function()error('retired construction must not staff')end,
 }
 package.loaded[prefix..'.Manifest']={}
 package.loaded['Core.Bar.Building.LoadAudit']={}
 local b=building(key,(99+i)..'-KenshiShop.mod',player,a)
 b.getNumInternalBuildings=function()error('retired construction must not inspect')end
 local shop=require(prefix..'.init')
 assert(shop.enqueue(b) and armed)
 retired[key]=true
 armed()
 assert(not armed)
end
print('Police property return (mock): scoped discovery, complete preflight, native fail/retry, resident release, and ownership readback passed.')
