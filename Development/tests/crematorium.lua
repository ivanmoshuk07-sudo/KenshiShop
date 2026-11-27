-- Native entry points and scope, with fake game objects. The game executes cremation.
package.path=arg[1]..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local Config=require('Core.Police.Services.Config')
local clock,hookID=0,0
local hooks,spawns,resumes={},{},{}
local buildings={}
Events={
 on=function(event,callback)
  assert(event=='MyGUI::Gui::eventFrameStart')
  hookID=hookID+1;hooks[hookID]=callback;return hookID
 end,
 off=function(id)hooks[id]=nil end,
}
function getGameWorld()
 return {getTimeStamp_inGameHours=function()
  return {getTotalHours=function()return clock end}
 end}
end
local function advance(minutes)
 clock=clock+minutes/60
 for _=1,20 do for _,callback in pairs(hooks)do callback() end end
end
package.loaded.Diagnostics={console=function()end,error=function(message)error(message)end}
for _,name in ipairs({'Bar','Engineering','Armour','Weapons','Robotics','Police'})do
 package.loaded['Core.'..name..'.init']={}
end
package.loaded['Core.NPC.Controller']={new=function(cfg)
 assert(cfg.template==Config.undertaker and cfg.shop=='crematorium' and cfg.role=='undertaker' and cfg.count==1)
 assert(cfg.faction==Config.faction and not cfg.serviceHired)
 return {
  start=function(b)
   assert(not spawns[b.key]);spawns[b.key]=1;return true
  end,
  resume=function(b)resumes[b.key]=true;return true,'EXISTING_LOOKUP'end,
  status=function()return 'TEST'end,check=function()return 'TEST'end,
  resetSession=function()end,
 }
end}

local function building(key,player,complete,id)
 local state={isComplete=complete,needMats=function(self)return not self.isComplete end,
  getTotalMats=function()return 8 end,getTotalMatsPresent=function(self)return self.isComplete and 8 or 4 end}
 local b={key=key,buildState=state,isValid=function()return true end,isDestroyed=function()return false end,
  isCreated=function(self)return self.buildState==nil or self.buildState.isComplete end,
  getBuildState=function(self)return self.buildState end,
  getGameData=function()return {stringID=id or Config.crematorium}end,
  getTown=function()return {getFaction=function()return {isThePlayer=function()return player end}end}end}
 function b:getHandle()
  return {toString=function()return key end,getBuilding=function()return buildings[key]end}
 end
 buildings[key]=b;return b
end
local registry=require('Core.Registry')
local a=building('a',true,false)
local shop=assert(registry.byBuilding(a))
assert(shop.name=='crematorium' and Config.templates[Config.undertaker].driver=='Core.Crematorium.NPC')
assert(not registry.byBuilding(building('vanilla',true,true,'3962-gamedata.base')))
shop.npcResume(a);assert(not resumes.a and not next(hooks))
shop.enqueue(a);shop.enqueue(a);advance(1);assert(not spawns.a)
a.buildState.isComplete=true
advance(1);shop.enqueue(a);advance(1)
assert(spawns.a==1 and not next(hooks))
local b=building('b',true,true)
shop.enqueue(b);advance(1);assert(spawns.b==1 and not next(hooks))
shop.resetSession()
a.buildState=nil
shop.npcResume(a);advance(10)
assert(resumes.a and spawns.a==1 and not next(hooks))
local driver=require('Core.Crematorium.NPC')
assert(not driver.start(building('foreign',false,true)) and not spawns.foreign)

package.loaded['Core.NPC.NativeCare']={tick=function()error('corpse is not a rescue patient')end}
package.loaded['Core.NPC.PostDuty']={tick=function()error('undertaker does not occupy a scripted post')end}
local Duty=require('Core.NPC.Duty')
local c={getOrdersReciever=function()
 return {getCurrentGoal=function()return {key=function()return 137 end,priority=2}end}
end}
local s={cfg=Config.copy(Config.undertaker),work={done=true},now=1,key='a'}
assert(Duty.tick(s,{{key='joe',char=c}}))
assert(s.duty.members.joe.state=='NATIVE_TASK_137')
assert(s.work.postAudit.rows.joe.result=='CORPSE_DISPOSAL_ACTIVE')
print('PASS crematorium spawns one undertaker after construction, resumes without spawning, and leaves corpse disposal to the native task')
