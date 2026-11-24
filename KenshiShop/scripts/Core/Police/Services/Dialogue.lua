-- Real native dialogue choices, with a save-independent selection session.
-- Native DialogLineData text is shared, so only one active conversation owns
-- this dynamic pool. The paid backend receives the frozen death ID, never an
-- index or a request to choose some other vacancy.
local Log=require('Diagnostics')
local Live=require('Core.NPC.LiveState')
local M={}
local PACKAGE='11100-KenshiShop.mod'
local ROOT='11101-KenshiShop.mod'
local GREETING='11102-KenshiShop.mod'
local CHECK='11103-KenshiShop.mod'
local HIRE='11105-KenshiShop.mod'
local LEAVE='11106-KenshiShop.mod'
local EVACUATE='11107-KenshiShop.mod'
local LIST='11200-KenshiShop.mod'
local PREV='11220-KenshiShop.mod'
local NEXT='11221-KenshiShop.mod'
local EXIT='11222-KenshiShop.mod'
local EVACUATION_PROMPT='11300-KenshiShop.mod'
local CONFIRM_EVACUATION='11301-KenshiShop.mod'
local CANCEL_EVACUATION='11302-KenshiShop.mod'
local HIRE_PROMPT='11400-KenshiShop.mod'
local CONFIRM_HIRE='11401-KenshiShop.mod'
local CANCEL_HIRE='11402-KenshiShop.mod'
local LEGACY_ORDER=' Старые записи об оплате повреждены. Этот заказ будет записан отдельно.'
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
 for _,key in ipairs({LIST,PREV,NEXT,EXIT,EVACUATION_PROMPT,CONFIRM_EVACUATION,CANCEL_EVACUATION,HIRE_PROMPT,CONFIRM_HIRE,CANCEL_HIRE})do
  assert(nodes[key],'CHIEF_SELECTION_NODE_MISSING '..key)
 end
 for n=0,SIZE-1 do
  for _,base in ipairs({11210,11230,11240,11250})do
   assert(nodes[sid(base+n)],'CHIEF_SELECTION_NODE_MISSING '..sid(base+n))
  end
 end
 return nodes
end
local function text(node,value)
 -- Native text setters consume C strings. Keep the original roster/identity
 -- bytes intact, but make presentation safe for that boundary as well.
 value=value:gsub('%z',' ')
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
 s.notice=nil
 if why=='SERVICE_STORE_NOT_READY' then
  s.notice='Реестр найма недоступен.'
 elseif why=='ROSTER_HISTORY_INCOMPLETE' then
  s.notice='Состав ещё проверяется. Часть старых сведений о потерях недоступна.'
 elseif result==nil or why then
  s.notice='Состав города проверен не полностью. Список уточняется.'
 end
 if result==nil then
  Log.console('NPC_CHIEF_ROSTER_UNAVAILABLE reason='..tostring(why))
  s.rows={}
  return
 end
 assert(type(result)=='table',tostring(why or 'CHIEF_SELECTION_LIST_UNAVAILABLE'))
 assert(#result<=4096,'CHIEF_SELECTION_ROWS_LIMIT')
 local copy,seen={},{}
 for _,row in ipairs(result)do
  assert(type(row)=='table' and type(row.id)=='string' and row.id~='' and not seen[row.id],'CHIEF_SELECTION_ID_INVALID')
  local label=row.label or row.name
  assert(type(label)=='string' and label~='','CHIEF_SELECTION_LABEL_INVALID')
  copy[#copy+1]={id=row.id,label=label,replaceable=row.replaceable~=false and why~='SERVICE_STORE_NOT_READY'}
  seen[row.id]=true
 end
 s.rows=copy
end
local function prepareList(s)
 local total=#s.rows;local pages=math.max(1,math.ceil(total/SIZE))
 s.page=math.max(1,math.min(s.page or 1,pages));s.slots={};s.selected=nil
 local title=s.notice or 'Все на месте.'
 if total>0 then
  title='Пропавшие сотрудники: '..total..'.'
  if pages>1 then title=title..' Страница '..s.page..' из '..pages..'.' end
  if s.notice then title=title..' '..s.notice end
 end
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
local function advance(s,node,phase,nativeChild)
 assert(active==s,'CHIEF_SELECTION_SUPERSEDED')
 s.phase=nativeChild and phase or 'queued'
 -- A linked child usually advances inside the native reply handler. The
 -- fallback runs after the handler returns and only reopens a missing view.
 queued={session=s,token=s.token,node=node,phase=phase,nativeChild=nativeChild}
end
local function band(key,base)
 for n=0,SIZE-1 do if key==sid(base+n) then return n+1 end end
end
local function selectedLine(key)
 return key==LIST or key==PREV or key==NEXT or key==EXIT
  or key==EVACUATION_PROMPT or key==CONFIRM_EVACUATION or key==CANCEL_EVACUATION
  or key==HIRE_PROMPT or key==CONFIRM_HIRE or key==CANCEL_HIRE
  or band(key,11210) or band(key,11230) or band(key,11240) or band(key,11250)
end
local function inView(dialogue,line,parentKey)
 local current=field(dialogue,'currentLine')
 return current==line or call(current,'getStringID')==parentKey
end
local function request(api,action,chief,player,key,selected,newLedger)
 local ok,why=api.request(action,chief,player,selected,newLedger)
 Log.console('NPC_CHIEF_DIALOGUE_REQUEST line='..key..' action='..action..' queued='..tostring(ok==true)
  ..' reason='..tostring(why or 'NONE'))
 if ok~=true then error('CHIEF_DIALOGUE_REQUEST_FAILED '..tostring(why),0)end
end
local function dispatch(api,dialogue,line)
 local key=call(line,'getStringID')
 local menuReply=key==CHECK or key==HIRE or key==LEAVE or key==EVACUATE
 if key~=GREETING and not menuReply and not selectedLine(key) then return end
 local chief,player,chiefKey,playerKey=context(dialogue)
 if not chief then
  if menuReply or key==CONFIRM_EVACUATION or key==CONFIRM_HIRE or band(key,11240) then
   Log.console('NPC_CHIEF_DIALOGUE_CONTEXT_MISSING line='..key)
  end
  return
 end
 if menuReply and not inView(dialogue,line,GREETING) then return end
 if key==GREETING or (menuReply and not active) then
  invalidate()
  active={dialogue=dialogue,chief=chief,player=player,chiefHand=chief:getHandle(),playerHand=player:getHandle(),
   chiefKey=chiefKey,playerKey=playerKey,token=serial,phase='menu'}
  if key==GREETING then return end
 end
 local s=active
 if not matches(s,dialogue,chiefKey,playerKey) then return end
 if menuReply and s.phase~='menu' then return end
 if key==LEAVE then s.phase='finished';return end
 if key==HIRE then
  s.nodes=collect(dialogue)
  s.newLedger=api.newLedgerOffered()
  local quote='Три патрульных за 20 000 кат. Днём они стоят у башни, ночью патрулируют.'
  text(s.nodes[HIRE_PROMPT],quote..(s.newLedger and LEGACY_ORDER or '')..' Подтверждаешь?')
  advance(s,s.nodes[HIRE_PROMPT],'hire',true)
  return
 end
 if key==EVACUATE then
  s.nodes=collect(dialogue)
  Log.console('NPC_CHIEF_DIALOGUE_EVACUATION_PROMPT line='..key)
  advance(s,s.nodes[EVACUATION_PROMPT],'evacuation',true)
  return
 end
 if key==CHECK then
  s.nodes=collect(dialogue);rows(s,api);s.page=1;prepareList(s)
  Log.console('NPC_CHIEF_DIALOGUE_ROSTER line='..key..' rows='..#s.rows..' complete='..tostring(not s.notice))
  advance(s,s.nodes[LIST],'list',true);return
 end
 if not s.nodes or s.nodes[key]~=line then return end
 if key==LIST or key==EVACUATION_PROMPT or key==HIRE_PROMPT or band(key,11230) then return end
 if key==CONFIRM_HIRE or key==CANCEL_HIRE then
  if s.phase~='hire' or not inView(dialogue,line,HIRE_PROMPT) then return end
  s.phase='finished';queued=nil
  if key==CONFIRM_HIRE then request(api,'hire',chief,player,key,nil,s.newLedger) end
  return
 end
 if key==CONFIRM_EVACUATION or key==CANCEL_EVACUATION then
  if s.phase~='evacuation' or not inView(dialogue,line,EVACUATION_PROMPT) then return end
  s.phase='finished';queued=nil
  if key==CONFIRM_EVACUATION then
   request(api,'evacuate',chief,player,key)
  end
  return
 end
 if key==EXIT then
  if s.phase~='list' then return end
  s.phase='finished';queued=nil;return
 end
 if key==PREV or key==NEXT then
  if s.phase~='list' or invoke(dialogue,'isLocked',line) then return end
  s.page=s.page+(key==NEXT and 1 or -1);rows(s,api);prepareList(s)
  advance(s,s.nodes[LIST],'list');return
 end
 local slot=band(key,11210)
 if slot then
  if s.phase~='list' or invoke(dialogue,'isLocked',line) then return end
  local row=s.slots[slot];if not row then return end
  -- Copy strings, rather than retaining a mutable roster row or page index.
  s.selected={id=row.id,label=row.label,slot=slot,replaceable=row.replaceable,newLedger=row.replaceable and api.newLedgerOffered()}
  local question=row.replaceable and 'Нанять замену для «'..row.label..'» за 10 000 кат?'
   or '«'..row.label..'». Замена пока недоступна.'
  text(s.nodes[sid(11230+slot-1)],question..(s.selected.newLedger and LEGACY_ORDER or ''))
  text(s.nodes[sid(11240+slot-1)],'Да, нанять «'..row.label..'» за 10 000 кат.')
  locked(s,s.nodes[sid(11240+slot-1)],not row.replaceable)
  locked(s,s.nodes[sid(11250+slot-1)],false)
  advance(s,s.nodes[sid(11230+slot-1)],'confirm',true);return
 end
 local pay,cancel=band(key,11240),band(key,11250)
 if not pay and not cancel then return end
 local selected=s.selected;local chosen=pay or cancel
 if s.phase~='confirm' or not selected or chosen~=selected.slot or invoke(dialogue,'isLocked',line) then return end
 if not inView(dialogue,line,sid(11230+chosen-1)) then return end
 local frozen=s.slots[chosen]
 if not frozen or frozen.id~=selected.id then return end
 if cancel then
  rows(s,api);prepareList(s);advance(s,s.nodes[LIST],'list');return
 end
 if not selected.replaceable then return end
 local deathID=selected.id
 s.phase='finished';queued=nil
 request(api,'replace',chief,player,key,deathID,selected.newLedger)
end
local function openQueued()
 local job=queued;if not job or not Live.readyWorld() then return end
 queued=nil
 local s=job.session
 if active~=s or s.token~=job.token then return end
 local chief=call(s.chiefHand,'getCharacter');local player=call(s.playerHand,'getCharacter')
 if not chiefValid(chief) or not playerValid(player) or handle(chief)~=s.chiefKey or handle(player)~=s.playerKey
  or field(chief,'dialogue')~=s.dialogue then invalidate();return end
 local ended=call(s.dialogue,'conversationHasEnded')
 if ended==false then
  local target=handle(call(call(s.dialogue,'getConversationTarget'),'getCharacter'))
  if target and target~=s.playerKey then invalidate();return end
  if not job.closing then
   if job.nativeChild and target==s.playerKey and field(s.dialogue,'currentLine')==job.node then
    s.chief=chief;s.player=player;s.phase=job.phase;return
   end
   job.closing=true;s.phase='queued';close(s)
   ended=call(s.dialogue,'conversationHasEnded')
  end
  if ended==false then
   job.waits=(job.waits or 0)+1
   if job.waits>=5 then invalidate();error('CHIEF_SELECTION_CLOSE_TIMEOUT',0)end
   queued=job;return
  end
 end
 if ended~=true then
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
 assert(type(api)=='table' and type(api.request)=='function' and type(api.listLosses)=='function'
  and type(api.newLedgerOffered)=='function','CHIEF_SERVICE_API_REQUIRED')
 if started then return true end
 local actionHook=Events.on('Dialogue::_doActions',function(dialogue,line)
  local ok,why=pcall(dispatch,api,dialogue,line)
  if not ok then
   invalidate()
   transitionError('NPC_CHIEF_SELECTION_ERROR '..tostring(why))
  end
 end)
 assert(actionHook,'CHIEF_DIALOGUE_HOOK_UNAVAILABLE')
 assert(Events.on('MyGUI::Gui::eventFrameStart',function()
  local ok,why=pcall(openQueued)
  if not ok then invalidate();transitionError('NPC_CHIEF_SELECTION_OPEN_ERROR '..tostring(why))end
 end),'CHIEF_SELECTION_FRAME_HOOK_UNAVAILABLE')
 assert(Events.on('Dialogue::endDialogue',function(dialogue)
  if active and active.dialogue==dialogue and not active.internalClose and not active.reopening then
   local pending=queued and queued.session==active
   -- Terminal replies used to change pages can naturally finish this
   -- conversation before the requested view is opened on the next frame.
   if not pending or queued.nativeChild then invalidate()end
  end
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
