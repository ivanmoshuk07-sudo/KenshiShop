-- Real native dialogue choices, with a save-independent selection session.
-- Native DialogLineData text is shared, so only one active conversation owns
-- this dynamic pool. The paid backend receives the frozen death ID, never an
-- index or a request to choose some other vacancy.
local Log=require('Diagnostics')
local M={}
local PACKAGE='11100-KenshiShop.mod'
local ROOT='11101-KenshiShop.mod'
local GREETING='11102-KenshiShop.mod'
local CHECK='11103-KenshiShop.mod'
local HIRE='11105-KenshiShop.mod'
local LEAVE='11106-KenshiShop.mod'
local LIST='11200-KenshiShop.mod'
local PREV='11220-KenshiShop.mod'
local NEXT='11221-KenshiShop.mod'
local EXIT='11222-KenshiShop.mod'
local SIZE=6
local attached={}
local started=false
local active,queued
local serial=0
local function sid(number)return number..'-KenshiShop.mod'end
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function call(o,k,...)
 local fn=field(o,k);if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,o,...);if ok then return v end
end
local function invoke(o,k,...)
 local fn=field(o,k);assert(type(fn)=='function','CHIEF_SELECTION_API_MISSING '..k)
 return fn(o,...)
end
local function transitionError(message)
 Log.error(message)
 local ok,w=pcall(getGameWorld)
 if ok and w and type(field(w,'showPlayerAMessage_withLog'))=='function' then
  pcall(w.showPlayerAMessage_withLog,w,'Не удалось обновить диалог. Повторите разговор с начальником охраны.',true)
 end
end
local function handle(c)return call(call(c,'getHandle'),'toString')end
local function chiefValid(c)
 return field(call(c,'getGameData'),'stringID')=='7310-KenshiShop.mod'
  and field(call(call(c,'getFaction'),'getData'),'stringID')=='400-KenshiShop.mod'
end
local function playerValid(c)
 return call(c,'isPlayerCharacter')==true and call(call(c,'getFaction'),'isThePlayer')==true
end
local function containsRoot(dialogue)
 local choices=field(call(dialogue,'getConversationList',1),'conversationChoices')
 if choices then for i=1,#choices do if call(choices[i],'getStringID')==ROOT then return true end end end
 return false
end
function M.attach(chief)
 if not chiefValid(chief) then return false,'CHIEF_IDENTITY_MISMATCH'end
 local key=handle(chief);local dialogue=field(chief,'dialogue')
 if not key or not dialogue then return false,'CHIEF_DIALOGUE_UNAVAILABLE'end
 if containsRoot(dialogue) then attached[key]={chief=chief,dialogue=dialogue};return true end
 local previous=attached[key]
 if previous and previous.chief==chief and previous.dialogue==dialogue then return false,'CHIEF_DIALOGUE_READBACK_PENDING'end
 local world=getGameWorld();local data=world and call(world.gamedata,'getData',PACKAGE,73)
 if not data then return false,'CHIEF_DIALOGUE_PACKAGE_MISSING'end
 local fn=field(dialogue,'addDialoguePackage')
 if type(fn)~='function' then return false,'CHIEF_DIALOGUE_API_MISSING'end
 local ok,err=pcall(fn,dialogue,data)
 if not ok then return false,'CHIEF_DIALOGUE_ATTACH_FAILED '..tostring(err)end
 attached[key]={chief=chief,dialogue=dialogue}
 if not containsRoot(dialogue) then return false,'CHIEF_DIALOGUE_READBACK_PENDING'end
 Log.console('NPC_CHIEF_DIALOGUE_ATTACHED chief='..key..' package='..PACKAGE)
 return true
end
local function invalidate()
 serial=serial+1;active=nil;queued=nil
end
function M.resetSession()attached={};invalidate()end
local function context(dialogue)
 local chief=call(dialogue,'getCharacter')
 local player=call(call(dialogue,'getConversationTarget'),'getCharacter')
 if not chiefValid(chief) or not playerValid(player) then return nil end
 local chiefKey,playerKey=handle(chief),handle(player)
 if not chiefKey or not playerKey then return nil end
 return chief,player,chiefKey,playerKey
end
local function matches(s,dialogue,chiefKey,playerKey)
 return s and s.dialogue==dialogue and s.chiefKey==chiefKey and s.playerKey==playerKey
end
local function close(s)
 s.internalClose=true
 local ok,err=pcall(invoke,s.dialogue,'endDialogue',true)
 s.internalClose=false
 if not ok then error('CHIEF_DIALOGUE_END_FAILED '..tostring(err),0)end
end
local function collect(dialogue)
 local choices=field(invoke(dialogue,'getConversationList',1),'conversationChoices')
 assert(choices,'CHIEF_SELECTION_ROOT_UNAVAILABLE')
 local root
 for i=1,#choices do if call(choices[i],'getStringID')==ROOT then root=choices[i];break end end
 assert(root,'CHIEF_SELECTION_ROOT_UNAVAILABLE')
 local nodes,seen,todo={}, {},{root}
 local scanned=0
 while #todo>0 do
  local node=table.remove(todo)
  if not seen[node] then
   seen[node]=true;scanned=scanned+1;assert(scanned<=256,'CHIEF_SELECTION_TREE_LIMIT')
   local key=invoke(node,'getStringID');nodes[key]=node
   local children=field(node,'children')
   if not children then
    invoke(node,'setupChildren');children=field(node,'children')
   end
   local list=field(children,'conversationChoices')
   if list then for i=1,#list do todo[#todo+1]=list[i]end end
  end
 end
 for _,key in ipairs({LIST,PREV,NEXT,EXIT})do assert(nodes[key],'CHIEF_SELECTION_NODE_MISSING '..key)end
 for n=0,SIZE-1 do
  for _,base in ipairs({11210,11230,11240,11250})do
   assert(nodes[sid(base+n)],'CHIEF_SELECTION_NODE_MISSING '..sid(base+n))
  end
 end
 return nodes
end
local function text(node,value)
 node.texts=value
 local read=field(node,'texts')
 assert(type(read)=='table' and read[1]==value,'CHIEF_SELECTION_TEXT_VERIFY_FAILED')
end
local function locked(s,node,on)
 invoke(s.dialogue,'setLineLocked',node,on)
 assert(invoke(s.dialogue,'isLocked',node)==on,'CHIEF_SELECTION_LOCK_VERIFY_FAILED')
end
local function rows(s,api)
 local result,why=api.listLosses(s.chief,s.player)
 assert(type(result)=='table',tostring(why or 'CHIEF_SELECTION_LIST_UNAVAILABLE'))
 assert(#result<=4096,'CHIEF_SELECTION_ROWS_LIMIT')
 local copy,seen={},{}
 for _,row in ipairs(result)do
  assert(type(row)=='table' and type(row.id)=='string' and row.id~='' and not seen[row.id],'CHIEF_SELECTION_ID_INVALID')
  local label=row.label or row.name
  assert(type(label)=='string' and label~='','CHIEF_SELECTION_LABEL_INVALID')
  copy[#copy+1]={id=row.id,label=label};seen[row.id]=true
 end
 s.rows=copy
end
local function prepareList(s)
 local total=#s.rows;local pages=math.max(1,math.ceil(total/SIZE))
 s.page=math.max(1,math.min(s.page or 1,pages));s.slots={};s.selected=nil
 local title=total==0 and 'Подтверждённых погибших без оплаченной замены нет.'
  or 'Кого нанять заново? '..total..' погибших. Страница '..s.page..' из '..pages..'. Замена одного — 10 000 кат.'
 text(s.nodes[LIST],title)
 for n=0,SIZE-1 do
  local row=s.rows[(s.page-1)*SIZE+n+1]
  s.slots[n+1]=row
  text(s.nodes[sid(11210+n)],row and row.label or 'Нет подтверждённой вакансии')
  locked(s,s.nodes[sid(11210+n)],not row)
  locked(s,s.nodes[sid(11240+n)],true)
  locked(s,s.nodes[sid(11250+n)],true)
 end
 locked(s,s.nodes[PREV],s.page<=1)
 locked(s,s.nodes[NEXT],s.page>=pages)
 locked(s,s.nodes[EXIT],false)
end
local function reopen(s,node,phase)
 assert(active==s,'CHIEF_SELECTION_SUPERSEDED')
 s.phase='queued';close(s)
 queued={session=s,token=s.token,node=node,phase=phase}
end
local function band(key,base)
 for n=0,SIZE-1 do if key==sid(base+n) then return n+1 end end
end
local function selectedLine(key)
 return key==LIST or key==PREV or key==NEXT or key==EXIT
  or band(key,11210) or band(key,11230) or band(key,11240) or band(key,11250)
end
local function dispatch(api,dialogue,line)
 local key=call(line,'getStringID')
 if key~=GREETING and key~=CHECK and key~=HIRE and key~=LEAVE and not selectedLine(key) then return end
 local chief,player,chiefKey,playerKey=context(dialogue)
 if not chief then return end
 if key==GREETING then
  invalidate()
  active={dialogue=dialogue,chief=chief,player=player,chiefHand=chief:getHandle(),playerHand=player:getHandle(),
   chiefKey=chiefKey,playerKey=playerKey,token=serial,phase='menu'}
  return
 end
 local s=active
 if not matches(s,dialogue,chiefKey,playerKey) then return end
 if key==HIRE or key==LEAVE then
  if s.phase~='menu' then return end
  invalidate();close(s)
  if key==HIRE then
   local ok,why=api.request('hire',chief,player)
   if ok==false then error('CHIEF_DIALOGUE_REQUEST_FAILED '..tostring(why),0)end
  end
  return
 end
 if key==CHECK then
  if s.phase~='menu' then return end
  s.nodes=collect(dialogue);rows(s,api);s.page=1;prepareList(s)
  reopen(s,s.nodes[LIST],'list');return
 end
 if not s.nodes or s.nodes[key]~=line then return end
 if key==LIST or band(key,11230) then return end
 if key==EXIT then
  if s.phase~='list' then return end
  invalidate();close(s);return
 end
 if key==PREV or key==NEXT then
  if s.phase~='list' or invoke(dialogue,'isLocked',line) then return end
  s.page=s.page+(key==NEXT and 1 or -1);rows(s,api);prepareList(s)
  reopen(s,s.nodes[LIST],'list');return
 end
 local slot=band(key,11210)
 if slot then
  if s.phase~='list' or invoke(dialogue,'isLocked',line) then return end
  local row=s.slots[slot];if not row then return end
  -- Copy strings, rather than retaining a mutable roster row or page index.
  s.selected={id=row.id,label=row.label,slot=slot}
  text(s.nodes[sid(11230+slot-1)],'Нанять замену для «'..row.label..'» за 10 000 кат?')
  text(s.nodes[sid(11240+slot-1)],'Да, нанять «'..row.label..'» за 10 000 кат.')
  locked(s,s.nodes[sid(11240+slot-1)],false)
  locked(s,s.nodes[sid(11250+slot-1)],false)
  reopen(s,s.nodes[sid(11230+slot-1)],'confirm');return
 end
 local pay,cancel=band(key,11240),band(key,11250)
 if not pay and not cancel then return end
 local selected=s.selected;local chosen=pay or cancel
 if s.phase~='confirm' or not selected or chosen~=selected.slot or invoke(dialogue,'isLocked',line) then return end
 local frozen=s.slots[chosen]
 if not frozen or frozen.id~=selected.id then return end
 if cancel then
  rows(s,api);prepareList(s);reopen(s,s.nodes[LIST],'list');return
 end
 local deathID=selected.id
 invalidate();close(s)
 local ok,why=api.request('replace',chief,player,deathID)
 if ok==false then error('CHIEF_DIALOGUE_REQUEST_FAILED '..tostring(why),0)end
end
local function openQueued()
 local job=queued;if not job then return end
 queued=nil
 local s=job.session
 if active~=s or s.token~=job.token or s.phase~='queued' then return end
 local chief=call(s.chiefHand,'getCharacter');local player=call(s.playerHand,'getCharacter')
 if not chiefValid(chief) or not playerValid(player) or handle(chief)~=s.chiefKey or handle(player)~=s.playerKey
  or field(chief,'dialogue')~=s.dialogue then invalidate();return end
 local ended=call(s.dialogue,'conversationHasEnded')
 if ended==false then
  -- Native GUI close messages may take more than one frame. Wait briefly
  -- for this conversation to end, without restarting it or issuing NPC jobs.
  local target=handle(call(call(s.dialogue,'getConversationTarget'),'getCharacter'))
  if target and target~=s.playerKey then invalidate();return end
  -- The outer native line may already have advanced to the prepared child
  -- after its action callback. Adopt that real view rather than opening it
  -- twice or waiting for a conversation that has legitimately continued.
  if target==s.playerKey and field(s.dialogue,'currentLine')==job.node then
   s.chief=chief;s.player=player;s.phase=job.phase;return
  end
  job.waits=(job.waits or 0)+1
  if job.waits>=5 then invalidate();error('CHIEF_SELECTION_CLOSE_TIMEOUT',0)end
  queued=job;return
 elseif ended~=true then
  invalidate();error('CHIEF_SELECTION_CLOSE_STATE_UNAVAILABLE',0)
 end
 s.chief=chief;s.player=player;s.phase=job.phase;s.reopening=true
 local ok,opened=pcall(invoke,s.dialogue,'startPlayerConversation',player,job.node)
 s.reopening=false
 if not ok or opened~=true or active~=s
  or handle(call(call(s.dialogue,'getConversationTarget'),'getCharacter'))~=s.playerKey then
  invalidate();pcall(close,s)
  error('CHIEF_SELECTION_OPEN_FAILED '..tostring(ok and opened or opened),0)
 end
end
function M.start(api)
 assert(type(api)=='table' and type(api.request)=='function' and type(api.listLosses)=='function','CHIEF_SERVICE_API_REQUIRED')
 if started then return true end
 local actionHook=Events.on('Dialogue::_doActions',function(dialogue,line)
  local ok,why=pcall(dispatch,api,dialogue,line)
  if not ok then
   local s=active;invalidate();if s and s.dialogue==dialogue then pcall(close,s)end
   transitionError('NPC_CHIEF_SELECTION_ERROR '..tostring(why))
  end
 end)
 assert(actionHook,'CHIEF_DIALOGUE_HOOK_UNAVAILABLE')
 assert(Events.on('MyGUI::Gui::eventFrameStart',function()
  local ok,why=pcall(openQueued)
  if not ok then invalidate();transitionError('NPC_CHIEF_SELECTION_OPEN_ERROR '..tostring(why))end
 end),'CHIEF_SELECTION_FRAME_HOOK_UNAVAILABLE')
 assert(Events.on('Dialogue::endDialogue',function(dialogue)
  if active and active.dialogue==dialogue and not active.internalClose and active.phase~='queued' and not active.reopening then invalidate()end
 end),'CHIEF_SELECTION_END_HOOK_UNAVAILABLE')
 assert(Events.on('Dialogue::startPlayerConversation',function(dialogue,_,line,default)
  if active and not active.reopening then
   local key=call(line,'getStringID')
   -- A newly opened ordinary greeting can establish its session inside the
   -- original call. Every other external start supersedes any old selection.
   if active.dialogue~=dialogue or active.phase~='menu' or (key~=ROOT and key~=GREETING) then invalidate()end
  end
  return default
 end),'CHIEF_SELECTION_START_HOOK_UNAVAILABLE')
 assert(Events.on('GameWorld::resetGame',M.resetSession),'CHIEF_DIALOGUE_RESET_HOOK_UNAVAILABLE')
 started=true
 return true
end
return M
