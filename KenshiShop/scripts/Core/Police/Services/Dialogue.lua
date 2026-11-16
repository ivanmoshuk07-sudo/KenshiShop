-- Native FCS conversation on the chief. Services run through a deferred API;
-- this module neither charges cats nor creates/moves characters.
local Log=require('Diagnostics')
local M={}
local PACKAGE='11100-KenshiShop.mod'
local ROOT='11101-KenshiShop.mod'
local GREETING='11102-KenshiShop.mod'
local LEAVE='11106-KenshiShop.mod'
local actions={['11103-KenshiShop.mod']='check',['11104-KenshiShop.mod']='replace',
 ['11105-KenshiShop.mod']='hire'}
local attached,handled={},{}
local started=false
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function call(o,k,...)
 local fn=field(o,k);if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,o,...);if ok then return v end
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
 if previous and previous.chief==chief and previous.dialogue==dialogue then
  return false,'CHIEF_DIALOGUE_READBACK_PENDING'
 end
 local world=getGameWorld();local data=world and call(world.gamedata,'getData',PACKAGE,73)
 if not data then return false,'CHIEF_DIALOGUE_PACKAGE_MISSING'end
 local fn=field(dialogue,'addDialoguePackage')
 if type(fn)~='function' then return false,'CHIEF_DIALOGUE_API_MISSING'end
 local ok,err=pcall(fn,dialogue,data)
 if not ok then return false,'CHIEF_DIALOGUE_ATTACH_FAILED '..tostring(err)end
 -- Never add twice after a successful native call, even if native readback
 -- is temporarily not ready. The next observation only checks the list.
 attached[key]={chief=chief,dialogue=dialogue}
 if not containsRoot(dialogue) then return false,'CHIEF_DIALOGUE_READBACK_PENDING'end
 Log.console('NPC_CHIEF_DIALOGUE_ATTACHED chief='..key..' package='..PACKAGE)
 return true
end
function M.resetSession()attached={};handled={}end
function M.start(api)
 assert(type(api)=='table' and type(api.request)=='function','CHIEF_SERVICE_API_REQUIRED')
 if started then return true end
 local actionHook=Events.on('Dialogue::_doActions',function(dialogue,line)
  local sid=call(line,'getStringID')
  if sid~=GREETING and sid~=LEAVE and not actions[sid] then return end
  local chief=call(dialogue,'getCharacter')
  local player=call(call(dialogue,'getConversationTarget'),'getCharacter')
  if not chiefValid(chief) or not playerValid(player) then return end
  local chiefKey,playerKey=handle(chief),handle(player)
  if not chiefKey or not playerKey then return end
  local key=chiefKey..'|'..playerKey
  if sid==GREETING then handled[key]=nil;return end
  if handled[key] then return end
  handled[key]=true
  -- Close the native choice before enqueueing a purchase. The service owns
  -- preflight/payment, durable death claims and duplicate-request protection.
  local close=field(dialogue,'endDialogue')
  if type(close)~='function' then
   Log.error('NPC_CHIEF_DIALOGUE_END_API_MISSING chief='..chiefKey);return
  end
  local ended,err=pcall(close,dialogue,true)
  if not ended then Log.error('NPC_CHIEF_DIALOGUE_END_FAILED '..tostring(err));return end
  if sid==LEAVE then return end
  local ok,result,why=pcall(api.request,actions[sid],chief,player)
  if not ok or result==false then
   Log.error('NPC_CHIEF_DIALOGUE_REQUEST_FAILED action='..actions[sid]..' reason='..tostring(ok and why or result))
  end
 end)
 assert(actionHook,'CHIEF_DIALOGUE_HOOK_UNAVAILABLE')
 assert(Events.on('GameWorld::resetGame',M.resetSession),'CHIEF_DIALOGUE_RESET_HOOK_UNAVAILABLE')
 started=true
 return true
end
return M
