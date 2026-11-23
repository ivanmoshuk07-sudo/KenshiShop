-- Native squad package and member/home verification boundaries.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local function hand(id)
 return {toString=function(self)return self.id end,isNull=function(self)return self.id==nil end,
  setNull=function(self)self.id=nil end,id=id}
end
local function faction(id,player)
 return {getData=function()return {stringID=id}end,isThePlayer=function()return player end}
end
local ks=faction('400-KenshiShop.mod',false)
local player=faction('PLAYER',true)
local origin={getHandle=function()return hand('origin')end,isValid=function()return true end,
  getFaction=function()return ks end,townType=1}
local town={getHandle=function()return hand('town')end,isValid=function()return true end,
  getFaction=function()return player end,withinBordersRange=function(_,p)return p.x<100 end}
local ctx={town='town',townObject=town,key='bar'}
local function ownership(home)
 return {_homeBuilding=hand(home),_homeTown=origin,setHomeBuilding=function(self,h,k)
  assert(k==1 and h:isNull());self._homeBuilding=h
 end}
end
local applications,activations=0,0
local function squad(id,home,loaded)
 local own=ownership(home)
 local p={isDead=false,canRefresh=true,regenerates=true,position=5,
  getPosition=function(self)return {x=self.position,y=0,z=0}end,
  getFaction=function()return ks end,getPlatoonStringID=function()return id end,
  getOwnerships=function()return own end,getSquadType=function()return 1 end,
  squadTemplate={stringID='7800-KenshiShop.mod'}}
 local bb={pkg={},hasContractJob=function()return false end,
  getCurrentPackage=function(self)return self.pkg end,replaceAIPackage=function(self,data)
   applications=applications+1;self.pkg={packageData=data}
  end}
 p.getBlackboard=function()return bb end
 local ms={}
 for i=1,2 do
  local memberOwn=ownership(home)
  local broadcast={homeBuilding=hand(home)}
  local orders={hasOrders=function(self)return self.pending==true end,
   clearOrders=function(self)self.pending=false end,
   getCurrentGoal=function()return {key=function()return 51 end}end}
  local c={position=10,getPosition=p.getPosition,getOwnerships=function()return memberOwn end,
   getFaction=p.getFaction,getStateBroadcast=function()return broadcast end,
   isDead=function()return false end,isPlayerCharacter=function()return false end,
   getOrdersReciever=function()return orders end}
  ms[i]={key=id..i,char=c}
 end
 p.ms=ms
 if loaded then p.getActivePlatoon=function()return {getSquadSize=function()return #ms end}end end
 return p,ms
end
local first,firstMembers=squad('first','bar',true)
first.squadTemplate.stringID='310-KenshiShop.mod'
ctx.chief=firstMembers[1].char
ctx.chief.getPlatoon=function()return {me=first}end
local other=squad('other','different-town',true)
local unloaded=squad('unloaded','bar',false)
local groups={{first,other},{unloaded}}
local world={gamedata={getData=function(_,id,kind)
 assert(id=='11303-KenshiShop.mod' and kind==72);return {stringID=id}
end}}
function getGameWorld()return world end
package.loaded['Core.Police.Services.Roster']={platoons=function()return groups,true end}
package.loaded['Core.NPC.LiveState']={
 call=function(o,k,...)if o and o[k] then return o[k](o,...) end end,
 halted=function(c)return c.halted,'COMBAT' end}
package.loaded['Core.NPC.Transport']={
 members=function(_,p)return p.ms end,valid=function(p)return p and type(p.x)=='number'end}
package.loaded['Core.NPC.NativeActivation']={ensure=function(_,ms)
 activations=activations+#ms;return true
end}
local Evacuees=require('Core.Police.Services.Evacuees')
assert(not Evacuees.plan({town='town',townObject=town,key='bar'},{bar=true}))
local plan=assert(Evacuees.plan(ctx,{bar=true}))
assert(plan.first.building=='bar' and plan.unloaded and not plan.other)
local progress={}
firstMembers[1].char.halted=true
firstMembers[1].char:getOrdersReciever().pending=true
assert(not Evacuees.step(ctx,plan,progress,0))
assert(applications==1 and first:getOwnerships()._homeBuilding:toString()=='bar'
 and firstMembers[1].char:getOrdersReciever():hasOrders())
assert(unloaded:getOwnerships()._homeBuilding:isNull() and unloaded:getOwnerships()._homeTown==origin)
firstMembers[1].char.halted=false
assert(not Evacuees.step(ctx,plan,progress,3) and applications==1)
assert(not Evacuees.step(ctx,plan,progress,5))
assert(applications==2 and activations==2 and not first.regenerates and not first.canRefresh)
assert(not firstMembers[1].char:getOrdersReciever():hasOrders())
assert(first:getOwnerships()._homeBuilding:isNull() and first:getOwnerships()._homeTown==origin)
assert(other:getOwnerships()._homeBuilding:toString()=='different-town')
for _,m in ipairs(firstMembers)do
 assert(m.char:getStateBroadcast().homeBuilding:isNull() and m.char:getOwnerships()._homeTown==origin)
end
firstMembers[1].char.position=140
unloaded.position=130
assert(not Evacuees.step(ctx,plan,progress,10))
assert(applications==2 and activations==2)
firstMembers[2].char.position=145
assert(Evacuees.step(ctx,plan,{},15)) -- reload accepts the verified native package
assert(applications==2 and activations==2)
groups={{other},{}}
local reloading={}
assert(not Evacuees.step(ctx,plan,reloading,20))
assert(not Evacuees.step(ctx,plan,reloading,25))
assert(Evacuees.step(ctx,plan,reloading,30))
print('Police evacuation native plan, safety, loaded/unloaded retreat, reload and scope OK')
