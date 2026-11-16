-- Native conversation dispatch only; no UI, spawning or payments are simulated.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local events={};local logs={};local requests={};local calls={}
Events={on=function(name,fn)events[name]=events[name] or {};table.insert(events[name],fn);return #events[name]end}
package.loaded.Diagnostics={console=function(s)logs[#logs+1]=s end,error=function(s)logs[#logs+1]=s end}
local Dialogue=require('Core.Police.Services.Dialogue')
local function fire(name,...)
 for _,fn in ipairs(events[name] or {})do fn(...)end
end
local function handle(key,character)return {toString=function()return key end,getCharacter=function()return character end}end
local function character(key,data,faction,player)
 return {getHandle=function()return handle(key)end,getGameData=function()return {stringID=data}end,
 getFaction=function()return {getData=function()return {stringID=faction}end,isThePlayer=function()return player end}end,
 isPlayerCharacter=function()return player end,
 takeMoney=function()error('dialogue must not charge')end,setDestination=function()error('dialogue must not move')end}
end
local chief,player,dialogue,choices,ready
local function fixture()
 requests={};logs={};calls={add=0,close=0};ready=true;Dialogue.resetSession()
 chief=character('chief','7310-KenshiShop.mod','400-KenshiShop.mod',false)
 player=character('player','player-template','204-gamedata.base',true)
 choices={}
 dialogue={getCharacter=function()return chief end,getConversationTarget=function()return handle('player',player)end,
  getConversationList=function()return {conversationChoices=choices}end,
  addDialoguePackage=function(_,data)
   assert(data.stringID=='11100-KenshiShop.mod');calls.add=calls.add+1
   if ready then choices[1]={getStringID=function()return '11101-KenshiShop.mod'end}end
  end,
  endDialogue=function(_,ended)assert(ended);calls.close=calls.close+1 end}
 chief.dialogue=dialogue
 function getGameWorld()return {gamedata={getData=function(_,sid,kind)
  assert(sid=='11100-KenshiShop.mod' and kind==73);return {stringID=sid}
 end}}end
end
local function line(number)return {getStringID=function()return number..'-KenshiShop.mod'end}end
Dialogue.start({request=function(action,c,p)
 assert(calls.close>0,'native conversation must close before enqueue')
 requests[#requests+1]={action=action,chief=c,player=p};return true
end})
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('native chief menu attaches once and preserves the existing dialogue object',function()
 fixture();local original=chief.dialogue
 assert(Dialogue.attach(chief) and Dialogue.attach(chief) and calls.add==1 and chief.dialogue==original)
end)
test('an existing FCS-loaded menu is read back without adding a duplicate package',function()
 fixture();choices[1]={getStringID=function()return '11101-KenshiShop.mod'end}
 assert(Dialogue.attach(chief) and calls.add==0)
end)
test('delayed native readback never causes repeated successful package insertion',function()
 fixture();ready=false
 assert(not Dialogue.attach(chief) and calls.add==1)
 for i=1,10 do assert(not Dialogue.attach(chief))end;assert(calls.add==1)
 choices[1]={getStringID=function()return '11101-KenshiShop.mod'end}
 assert(Dialogue.attach(chief) and calls.add==1)
end)
test('a reloaded chief dialogue under the same handle can attach its missing package',function()
 fixture();assert(Dialogue.attach(chief));local old=dialogue
 local newChoices={};chief.dialogue={getConversationList=function()return {conversationChoices=newChoices}end,
  addDialoguePackage=function()calls.add=calls.add+1;newChoices[1]={getStringID=function()return '11101-KenshiShop.mod'end}end}
 assert(Dialogue.attach(chief) and calls.add==2 and chief.dialogue~=old)
end)
test('only the exact chief record and merchant faction can receive the menu',function()
 fixture();local stranger=character('stranger','7310-KenshiShop.mod','other-faction',false);stranger.dialogue=dialogue
 assert(not Dialogue.attach(stranger) and calls.add==0)
 stranger=character('stranger','312-KenshiShop.mod','400-KenshiShop.mod',false);stranger.dialogue=dialogue
 assert(not Dialogue.attach(stranger) and calls.add==0)
end)
test('all three real player choices dispatch their exact chief and player context',function()
 for id,action in pairs({[11103]='check',[11104]='replace',[11105]='hire'})do
  fixture();fire('Dialogue::_doActions',dialogue,line(11102));fire('Dialogue::_doActions',dialogue,line(id))
  assert(#requests==1 and requests[1].action==action and requests[1].chief==chief and requests[1].player==player)
  assert(calls.close==1 and calls.add==0)
 end
end)
test('duplicate native action callbacks do not enqueue duplicate purchases',function()
 fixture();fire('Dialogue::_doActions',dialogue,line(11102))
 for i=1,15 do fire('Dialogue::_doActions',dialogue,line(11105))end
 assert(#requests==1 and calls.close==1)
 fire('Dialogue::_doActions',dialogue,line(11102));fire('Dialogue::_doActions',dialogue,line(11105))
 assert(#requests==2 and calls.close==2)
end)
test('foreign dialogue lines, nonchief speakers and nonplayer targets never dispatch',function()
 fixture();fire('Dialogue::_doActions',dialogue,line(42));assert(#requests==0 and calls.close==0)
 chief=character('stranger','312-KenshiShop.mod','400-KenshiShop.mod',false)
 fire('Dialogue::_doActions',dialogue,line(11105));assert(#requests==0 and calls.close==0)
 fixture();player=character('npc','7310-KenshiShop.mod','400-KenshiShop.mod',false)
 fire('Dialogue::_doActions',dialogue,line(11104));assert(#requests==0 and calls.close==0)
end)
test('leaving the menu closes the native conversation without issuing a service',function()
 fixture();fire('Dialogue::_doActions',dialogue,line(11102));fire('Dialogue::_doActions',dialogue,line(11106))
 assert(#requests==0 and calls.close==1)
end)
test('starting twice keeps one event dispatcher and session reset allows a fresh conversation',function()
 fixture();Dialogue.start({request=function()error('must keep original API')end})
 assert(#events['Dialogue::_doActions']==1 and #events['GameWorld::resetGame']==1)
 fire('Dialogue::_doActions',dialogue,line(11104));assert(#requests==1)
 fire('GameWorld::resetGame');fire('Dialogue::_doActions',dialogue,line(11104));assert(#requests==2)
end)
print('Chief native dialogue tests passed: '..count)
