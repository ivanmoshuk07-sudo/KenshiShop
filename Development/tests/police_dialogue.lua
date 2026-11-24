-- Native text/lock/selection API boundaries. The real game GUI is not simulated.
package.path=assert(arg[1])..'/?.lua;'..arg[1]..'/?/init.lua;'..package.path
local events,logs,requests={}, {},{}
Events={on=function(name,fn)events[name]=events[name] or {};table.insert(events[name],fn);return #events[name]end}
package.loaded.Diagnostics={console=function(s)logs[#logs+1]=s end,error=function(s)logs[#logs+1]=s end}
local Dialogue=require('Core.Police.Services.Dialogue')
local function fire(name,...)
 for _,fn in ipairs(events[name] or {})do fn(...)end
end
local function sid(n)return n..'-KenshiShop.mod'end
local function hand(key,c)return {toString=function()return key end,getCharacter=function()return c end}end
local function character(key,data,faction,player)
 local c={getGameData=function()return {stringID=data}end,
 getFaction=function()return {getData=function()return {stringID=faction}end,isThePlayer=function()return player end}end,
 isPlayerCharacter=function()return player end,
 takeMoney=function()error('dialogue must not charge')end,setDestination=function()error('dialogue must not move')end}
 c.getHandle=function()return hand(key,c)end
 return c
end
local calls,chief,player,dialogue,nodes,choices,ready,losses
local failText,failLock,failOpen,failList,storeUnavailable,cstringText
local function node(number)
 local texts={'placeholder'}
 local n={getStringID=function()return sid(number)end,setupChildren=function()end}
 setmetatable(n,{__index=function(_,k)if k=='texts'then return texts end end,
  __newindex=function(t,k,v)
   if k=='texts' then
    if failText then error('setter unavailable')end
    if cstringText and type(v)=='string' then v=v:match('^[^%z]*')end
    texts=type(v)=='table' and v or {v}
   else rawset(t,k,v)end
  end})
 nodes[number]=n;return n
end
local function children(number,ids)
 local list={}
 for _,n in ipairs(ids)do list[#list+1]=nodes[n] or node(n)end
 nodes[number].children={conversationChoices=list}
end
local function tree()
 nodes={};for _,n in ipairs({11101,11102,11103,11105,11106,11200,11220,11221,11222})do node(n)end
 children(11101,{11102});children(11102,{11103,11105,11106});children(11103,{11200})
 local list={}
 for i=0,5 do
  for _,base in ipairs({11210,11230,11240,11250})do node(base+i)end
  children(11210+i,{11230+i});children(11230+i,{11240+i,11250+i});list[#list+1]=11210+i
 end
 for _,n in ipairs({11220,11221,11222})do list[#list+1]=n end
 children(11200,list)
end
local function nativeDialogue(c)
 local d={ended=true,locked={},target=nil}
 function d:getCharacter()return c end
 function d:getConversationTarget()return hand(self.target and 'player',self.target)end
 function d:getConversationList()return {conversationChoices=choices}end
 function d:addDialoguePackage(data)
  assert(data.stringID=='11100-KenshiShop.mod');calls.add=calls.add+1
  if ready then choices[1]=nodes[11101]end
 end
 function d:endDialogue(ended)
  assert(ended);calls.close=calls.close+1;self.ended=true;self.target=nil
  fire('Dialogue::endDialogue',self,true)
 end
 function d:conversationHasEnded()return self.ended end
 function d:setLineLocked(line,on)
  if not failLock then self.locked[line]=on end
 end
 function d:isLocked(line)return self.locked[line]==true end
 function d:startPlayerConversation(target,line)
  calls.open=calls.open+1;if failOpen then return false end
  self.target=target;self.ended=false;self.currentLine=line
  fire('Dialogue::_doActions',self,line)
  fire('Dialogue::startPlayerConversation',self,target,line,true)
  return true
 end
 c.dialogue=d;return d
end
local function fixture()
 Dialogue.resetSession();logs={};requests={};calls={add=0,close=0,open=0};ready=true
 failText=false;failLock=false;failOpen=false;failList=false;storeUnavailable=false;cstringText=false
 losses={{id='dead-a',label='Первый: охрана бара'},{id='dead-b',label='Второй: продавец оружия'},
  {id='dead-c',label='Третий: патрульный'}}
 tree();choices={}
 chief=character('chief','7310-KenshiShop.mod','400-KenshiShop.mod',false)
 player=character('player','player-template','204-gamedata.base',true)
 dialogue=nativeDialogue(chief)
 function getGameWorld()return {gamedata={getData=function(_,key,kind)
  assert(key=='11100-KenshiShop.mod' and kind==73);return {stringID=key}
 end}}end
end
Dialogue.start({listLosses=function(c,p)
 assert(c:getGameData().stringID=='7310-KenshiShop.mod' and p==player)
 if storeUnavailable then return nil,'SERVICE_STORE_NOT_READY'end
 if failList then return nil,'STORE_NOT_READY'end
 return losses
end,request=function(action,c,p,selected)
 assert(calls.close>0,'native conversation must close before enqueue')
 requests[#requests+1]={action=action,chief=c,player=p,id=selected};return true
end})
local function action(n,d)
 d=d or dialogue
 fire('Dialogue::_doActions',d,nodes[n] or {getStringID=function()return sid(n)end})
end
local function frame()fire('MyGUI::Gui::eventFrameStart')end
local function greet(d)
 d=d or dialogue;d.target=player;d.ended=false;action(11102,d)
end
local function list()
 assert(Dialogue.attach(chief));greet();action(11103);frame()
end
local function selected(n)
 action(11210+n-1);frame()
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end

test('native menu attaches once and existing loaded menus are preserved',function()
 fixture();local original=chief.dialogue
 assert(Dialogue.attach(chief) and Dialogue.attach(chief) and calls.add==1 and chief.dialogue==original)
 fixture();choices[1]=nodes[11101];assert(Dialogue.attach(chief) and calls.add==0)
end)
test('delayed native readback never repeats a successful package insertion',function()
 fixture();ready=false;assert(not Dialogue.attach(chief))
 for i=1,10 do assert(not Dialogue.attach(chief))end
 assert(calls.add==1);choices[1]=nodes[11101];assert(Dialogue.attach(chief))
end)
test('a replaced native dialogue under the same chief handle can attach',function()
 fixture();assert(Dialogue.attach(chief));choices={};dialogue=nativeDialogue(chief)
 assert(Dialogue.attach(chief) and calls.add==2)
end)
test('only the exact chief record and faction can receive the menu',function()
 fixture();local c=character('stranger','312-KenshiShop.mod','400-KenshiShop.mod',false);c.dialogue=dialogue
 assert(not Dialogue.attach(c) and calls.add==0)
 c=character('stranger','7310-KenshiShop.mod','other',false);c.dialogue=dialogue
 assert(not Dialogue.attach(c) and calls.add==0)
end)
test('asking about losses opens real named choices on the following frame without payment',function()
 fixture();assert(Dialogue.attach(chief));greet();action(11103)
 assert(calls.open==0 and #requests==0)
 frame();assert(dialogue.currentLine==nodes[11200] and calls.open==1)
 assert(nodes[11210].texts[1]==losses[1].label and nodes[11211].texts[1]==losses[2].label)
 assert(not dialogue:isLocked(nodes[11211]) and dialogue:isLocked(nodes[11213]))
end)
test('choosing the second NPC then confirming sends that exact ID once',function()
 fixture();list();selected(2)
 assert(#requests==0 and dialogue.currentLine==nodes[11231])
 assert(nodes[11231].texts[1]:find(losses[2].label,1,true))
 assert(nodes[11241].texts[1]:find('10 000',1,true))
 action(11241);action(11241);frame()
 assert(#requests==1 and requests[1].action=='replace' and requests[1].id=='dead-b')
 assert(requests[1].chief==chief and requests[1].player==player)
end)
test('the frozen selection cannot change when the roster is reordered',function()
 fixture();list();selected(2)
 losses={losses[3],losses[1],losses[2]};action(11241)
 assert(#requests==1 and requests[1].id=='dead-b')
end)
test('next and previous pages cover every casualty without a hidden six-NPC cap',function()
 fixture();losses={};for i=1,15 do losses[i]={id='casualty-'..i,label='NPC '..i}end
 list();assert(dialogue:isLocked(nodes[11220]) and not dialogue:isLocked(nodes[11221]))
 action(11221);frame();assert(nodes[11210].texts[1]=='NPC 7')
 action(11221);frame();assert(nodes[11210].texts[1]=='NPC 13' and dialogue:isLocked(nodes[11221]))
 action(11220);frame();assert(nodes[11210].texts[1]=='NPC 7')
 selected(3);action(11242);assert(#requests==1 and requests[1].id=='casualty-9')
end)
test('cancel returns to the current list page and never pays',function()
 fixture();list();selected(2);action(11251);frame()
 assert(#requests==0 and dialogue.currentLine==nodes[11200])
 action(11241);assert(#requests==0,'old confirmation must not stay valid')
 selected(1);action(11240);assert(#requests==1 and requests[1].id=='dead-a')
end)
test('empty lists and hidden slots cannot reach a paid action',function()
 fixture();losses={};list()
 for n=11210,11215 do assert(dialogue:isLocked(nodes[n]));action(n)end
 assert(dialogue:isLocked(nodes[11220]) and dialogue:isLocked(nodes[11221]))
 action(11240);action(11104);assert(#requests==0)
 action(11222);frame();assert(#requests==0 and dialogue:conversationHasEnded())
end)
test('a stale page, mismatching slot and old automatic replacement entry cannot pay',function()
 fixture();list();action(11240);action(11104);assert(#requests==0)
 selected(2);action(11240);assert(#requests==0)
 action(11241);assert(#requests==1 and requests[1].id=='dead-b')
end)
test('a new greeting or a different chief invalidates the old confirmation',function()
 fixture();list();selected(2);greet();action(11241);assert(#requests==0)
 list();selected(2)
 local c=character('chief2','7310-KenshiShop.mod','400-KenshiShop.mod',false)
 local d=nativeDialogue(c);greet(d)
 dialogue.target=player;dialogue.ended=false;action(11241,dialogue)
 assert(#requests==0)
end)
test('foreign conversations and Escape cancel queued or visible selections',function()
 fixture();list();selected(2);dialogue:endDialogue(true)
 dialogue.target=player;dialogue.ended=false;action(11241);assert(#requests==0)
 fixture();assert(Dialogue.attach(chief));greet();action(11103)
 local c=character('other','other-template','other-faction',false);local other=nativeDialogue(c)
 fire('Dialogue::startPlayerConversation',other,player,{getStringID=function()return 'foreign'end},true)
 frame();assert(calls.open==0 and #requests==0)
end)
test('campaign reset clears queued reopens and selected identities',function()
 fixture();assert(Dialogue.attach(chief));greet();action(11103);fire('GameWorld::resetGame');frame()
 assert(calls.open==0 and #requests==0)
 fixture();list();selected(2);fire('GameWorld::resetGame');action(11241)
 assert(#requests==0)
end)
test('text, lock, list and native opening failures never reach payment',function()
 for _,failure in ipairs({'text','lock','list','open'})do
  fixture();assert(Dialogue.attach(chief));greet()
  if failure=='text'then failText=true elseif failure=='lock'then failLock=true
  elseif failure=='list'then failList=true else failOpen=true end
  action(11103);frame();action(11210);frame();action(11240)
  assert(#requests==0 and #logs>0,failure)
 end
end)
test('duplicate native list and slot callbacks do not queue multiple reopens',function()
 fixture();assert(Dialogue.attach(chief));greet()
 for i=1,10 do action(11103)end;frame();assert(calls.open==1)
 for i=1,10 do action(11211)end;frame();assert(calls.open==2 and #requests==0)
 action(11241);assert(#requests==1)
end)
test('native close can finish after several frames without losing the chosen view',function()
 fixture();assert(Dialogue.attach(chief));greet();action(11103)
 dialogue.ended=false
 frame();frame();assert(calls.open==0 and #requests==0)
 dialogue.ended=true;frame();assert(calls.open==1 and dialogue.currentLine==nodes[11200])
 action(11211);frame();action(11241)
 assert(#requests==1 and requests[1].id=='dead-b')
end)
test('a stuck native close and a new ordinary conversation cancel pending reopens',function()
 fixture();assert(Dialogue.attach(chief));greet();action(11103);dialogue.ended=false
 for i=1,8 do frame()end
 assert(calls.open==0 and #requests==0 and #logs>0)
 fixture();assert(Dialogue.attach(chief));greet();action(11103)
 fire('Dialogue::startPlayerConversation',dialogue,player,nodes[11101],true)
 frame();assert(calls.open==0 and #requests==0)
end)
test('native automatic child progression is accepted without reopening the same view',function()
 fixture();assert(Dialogue.attach(chief));greet();action(11103)
 dialogue.ended=false;dialogue.target=player;dialogue.currentLine=nodes[11200]
 frame();assert(calls.open==0 and #requests==0)
 action(11211)
 dialogue.ended=false;dialogue.target=player;dialogue.currentLine=nodes[11231]
 frame();assert(calls.open==0 and #requests==0)
 action(11241);assert(#requests==1 and requests[1].id=='dead-b')
end)
test('hire and leave retain their original native actions without selection',function()
 fixture();greet();for i=1,10 do action(11105)end
 assert(#requests==1 and requests[1].action=='hire' and requests[1].id==nil)
 greet();action(11105);assert(#requests==2)
 greet();action(11106);assert(#requests==2)
end)
test('nonchief speakers and nonplayer targets cannot select or hire',function()
 fixture();greet();player=character('npc','npc-template','400-KenshiShop.mod',false)
 action(11103);frame();action(11105);assert(#requests==0 and calls.open==0)
 fixture();chief=character('guard','312-KenshiShop.mod','400-KenshiShop.mod',false)
 dialogue=nativeDialogue(chief);greet();action(11105);assert(#requests==0)
end)
test('an unavailable save ledger opens a native explanation with every purchase slot locked',function()
 fixture();storeUnavailable=true;list()
 assert(dialogue.currentLine==nodes[11200] and nodes[11200].texts[1]:find('недоступны',1,true))
 assert(not nodes[11200].texts[1]:find('погибших без оплаченной замены нет',1,true))
 for i=0,5 do
  assert(dialogue:isLocked(nodes[11210+i]) and dialogue:isLocked(nodes[11240+i]))
  action(11210+i);frame();action(11240+i)
 end
 assert(dialogue:isLocked(nodes[11220]) and dialogue:isLocked(nodes[11221]) and #requests==0 and #logs==1)
 action(11222);assert(dialogue.ended and #requests==0)
end)
test('a recovered ledger restores actual named choices on the next conversation',function()
 fixture();storeUnavailable=true;list();action(11222)
 storeUnavailable=false;greet();action(11103);frame()
 assert(nodes[11200].texts[1]:find('Кого нанять заново?',1,true) and not dialogue:isLocked(nodes[11211]))
 selected(2);action(11241);assert(#requests==1 and requests[1].id=='dead-b')
end)
test('binary-safe saved names remain selectable through native C-string text setters',function()
 fixture();cstringText=true;losses[2].label='Имя\0охранника'
 list();assert(nodes[11211].texts[1]=='Имя охранника')
 selected(2);assert(nodes[11231].texts[1]:find('Имя охранника',1,true))
 action(11241);assert(#requests==1 and requests[1].id=='dead-b' and losses[2].label=='Имя\0охранника')
end)
test('starting twice keeps the original dispatcher and API',function()
 fixture();Dialogue.start({request=function()error('must keep original API')end,listLosses=function()error('must keep API')end})
 assert(#events['Dialogue::_doActions']==1 and #events['MyGUI::Gui::eventFrameStart']==1)
 greet();action(11105);assert(#requests==1)
end)
print('Chief native selection dialogue tests passed: '..count)
