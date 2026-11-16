-- Native chief services. All paid allocations occur once on the owner thread;
-- save data contains identities and receipts, never live engine pointers.
local Config=require('Core.Police.Services.Config')
local Store=require('Core.Police.Services.Store')
local Roster=require('Core.Police.Services.Roster')
local Orders=require('Core.Police.Services.Orders')
local Dialogue=require('Core.Police.Services.Dialogue')
local Recruit=require('Core.Police.Services.Recruit')
local Controller=require('Core.NPC.Controller')
local Transport=require('Core.NPC.Transport')
local Nodes=require('Core.NPC.NativeNodes')
local Posts=require('Core.NPC.PostDuty')
local Work=require('Core.NPC.RoleAI')
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local M={}
local queue,drivers,pending,attached,dialogueStatus={},{},{},{},{}
local started,hooksReady,hooksInstalled,loadedSeen=false,false,false,false
local frames,nextScan,nextReconcile,epoch,sequence=0,0,0,0,0
local indexed,recoverOrders,recoverPatrols,recoveryQueue=false,{},{},{}
local RECOVER_MINUTES,RECONCILE_MINUTES=10,120
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
local function sid(o)return field(Live.call(o,'getGameData'),'stringID')end
local function id(o)return Live.call(Live.call(o,'getHandle'),'toString')end
local function report(event,detail)Log.console('NPC_CHIEF_'..event..' '..tostring(detail or ''))end
local function notify(text)
 report('MESSAGE',text)
 local w=getGameWorld()
 if w and type(field(w,'showPlayerAMessage_withLog'))=='function' then
  pcall(w.showPlayerAMessage_withLog,w,'Начальник охраны: '..text,true)
 end
end
local function failed(kind,why,order)
 report('ORDER_FAILED','kind='..kind..' status='..tostring(order and order.status)..' reason='..tostring(why))
 if why=='INSUFFICIENT_FUNDS' then
  notify('Недостаточно кат. Требуется '..(kind=='hire' and '20 000' or '10 000')..'.')
 elseif order and order.status=='refunded' then notify('Заказ не выполнен. Оплата полностью возвращена.')
 elseif order and (order.status=='pending_payment' or order.status=='refund_pending') then
  notify('Результат расчёта требует проверки. Повторное списание по этому заказу отключено.')
 else notify('Заказ пока недоступен. Деньги не списаны.')end
end
local function context(chief,player)
 if sid(chief)~='7310-KenshiShop.mod' or Live.call(chief,'isDead')~=false then return nil,'CHIEF_UNAVAILABLE'end
 local faction=Live.call(chief,'getFaction')
 if field(Live.call(faction,'getData'),'stringID')~=Config.faction then return nil,'CHIEF_FACTION_MISMATCH'end
 if Live.call(player,'isPlayerCharacter')~=true or Live.call(Live.call(player,'getFaction'),'isThePlayer')~=true then return nil,'PLAYER_UNAVAILABLE'end
 local own=Live.call(chief,'getOwnerships')
 local building=Live.call(field(own,'_homeBuilding'),'getBuilding')
 local town=Live.call(building,'getTown')
 if not building or Live.call(building,'isValid')~=true or sid(building)~=Config.tower
  or Live.call(Live.call(town,'getFaction'),'isThePlayer')~=true then return nil,'CHIEF_TOWER_UNAVAILABLE'end
 local wallet=field(Live.call(player,'getFaction'),'factionOwnerships')
 if not wallet or Live.call(wallet,'getMoney')~=Live.call(player,'getMoney') then return nil,'PLAYER_WALLET_UNVERIFIED'end
 local key,townID=id(building),id(town)
 if type(key)~='string' or key=='' or type(townID)~='string' or townID=='' then return nil,'CHIEF_TOWN_UNAVAILABLE'end
 return {chief=chief,player=player,building=building,key=key,town=townID,wallet=wallet}
end
local roleNames={trader='Торговец',guard='Охранник',chief='Начальник охраны',patrol='Патрульный'}
local businessNames={bar='Бар',engineering='Мастерская',armour='Магазин брони',weapons='Оружейная',robotics='Магазин робототехники',police='Охрана города'}
local function replacementClaimed(selectedID)
 for _,order in pairs(Store.get().orders)do
  if type(order)=='table' and order.kind=='replace' and order.subject=='replace:'..selectedID
   and order.status~='cancelled' and order.status~='refunded' then return true end
 end
 return false
end
local function selectedLoss(ctx,selectedID)
 if type(selectedID)~='string' or selectedID=='' then return nil,'LOSS_SELECTION_REQUIRED'end
 local record=Store.get().roster[selectedID]
 if type(record)~='table' or record.id~=selectedID then return nil,'LOSS_UNAVAILABLE'end
 if record.town~=ctx.town then return nil,'LOSS_TOWN_MISMATCH'end
 if record.dead~=true or record.order or record.replacedBy or replacementClaimed(selectedID) then return nil,'LOSS_ALREADY_CLAIMED_OR_UNCONFIRMED'end
 local cfg=Config.copy(record.squadTemplate)
 if not cfg then return nil,'LOSS_TEMPLATE_UNKNOWN'end
 return record,cfg
end
local function lossSnapshots(ctx)
 local ids={}
 for key in pairs(Store.get().roster)do
  if type(key)=='string' and selectedLoss(ctx,key) then ids[#ids+1]=key end
 end
 table.sort(ids)
 local rows={}
 for number,key in ipairs(ids)do
  local record,cfg=selectedLoss(ctx,key)
  local role=roleNames[cfg.role] or 'Сотрудник'
  local name=type(record.name)=='string' and record.name~='' and record.name~=key and record.name or role
  local business=businessNames[cfg.shop] or 'Место службы'
  local floor
  if cfg.role=='guard' then
   if type(record.floor)=='number' and record.floor>=0 and record.floor%1==0 then floor=record.floor+1
   elseif type(record.slot)=='number' and record.slot>=1 and record.slot%1==0 then floor=record.slot
   else floor=tonumber(name:match('%((%d+) этаж%)'))end
  end
  local label=tostring(number)..'. '..name..' — '..business..', '..role
  if floor then label=label..', '..floor..' этаж'end
  -- Every value is a scalar snapshot. The numbered label is presentation;
  -- only the persistent string ID is used to claim a later replacement.
  rows[#rows+1]={id=key,name=name,label=label,role=cfg.role,shop=cfg.shop,business=business,floor=floor}
 end
 return rows
end
function M.listLosses(chief,player)
 local ctx,why=context(chief,player)
 if not ctx then return nil,why end
 if not hooksReady or not Store.ready() then return nil,'SERVICE_STORE_NOT_READY'end
 local scanned,scanWhy=Roster.scan(true)
 if not scanned then report('SCAN_UNAVAILABLE',scanWhy);return nil,scanWhy or 'SCAN_UNAVAILABLE'end
 return lossSnapshots(ctx)
end
local function hiredConfig(pid,row)
 local cfg=Config.copy(Config.hired);cfg.existingID=pid;cfg.streetSlotBase=row.base
 return cfg
end
local function syncHireReceipt(pid,row)
 -- The patrol registry follows the current native platoon. An extinct squad
 -- can be replaced with a new PID while its original paid receipt survives.
 local order=Store.get().orders[row.order]
 if not order or order.kind~='hire' or type(order.metadata)~='table'
  or order.metadata.building~=row.building or order.metadata.town~=row.town then return nil end
 local oldPID=order.pid
 order.pid=pid;row.pid=pid
 if oldPID and oldPID~=pid then recoverPatrols[oldPID]=nil end
 return order
end
local function driverFor(p,cfg)
 if cfg.serviceHired then
  local pid=Live.call(p,'getPlatoonStringID')
  local existing=drivers[pid]
  if existing then return existing end
  local driver=Controller.new(cfg);drivers[pid]=driver;return driver
 end
 return require(cfg.driver)
end
local function actorCount(p,cfg)
 -- Paid allocation/readback must see the newly created actor immediately.
 local ms=Transport.members(getGameWorld(),p,cfg.count,true)
 if not ms then return nil end
 local alive={}
 for _,mate in ipairs(ms)do if Live.call(mate.char,'isDead')==false then alive[#alive+1]=mate end end
 return alive
end
local function finishReplacement(order,plan,receipt)
 local ok,why=Recruit.finish(plan,receipt)
 order.metadata.recruitStages=receipt.stages or {}
 -- Readback may discover the allocated actor before a later setup stage is
 -- ready. Persist that identity even on a deferred finish so reload can resume.
 order.pid=receipt.pid or order.pid;order.member=receipt.member or order.member
 if not ok then return false,why end
 local cfg=Config.copy(plan.record.squadTemplate)
 if cfg.serviceHired then
  local row=Store.get().patrols[receipt.pid] or Store.get().patrols[plan.record.pid]
  if not row then return false,'HIRED_IDENTITY_MISSING'end
  if receipt.pid~=plan.record.pid then
   -- Cancel the extinct owner's Lua monitor before discarding its ID; no
   -- operation is performed on its old native Platoon pointer.
   local oldDriver=drivers[plan.record.pid]
   if oldDriver then
    local stopped=pcall(oldDriver.resetSession)
    if not stopped then return false,'OLD_HIRED_MONITOR_STOP_PENDING'end
    drivers[plan.record.pid]=nil
   end
   attached[plan.record.pid]=nil;recoverPatrols[plan.record.pid]=nil
   Store.get().patrols[plan.record.pid]=nil;Store.get().patrols[receipt.pid]=row;row.pid=receipt.pid
  end
  syncHireReceipt(receipt.pid,row)
  cfg=hiredConfig(receipt.pid,row)
 end
 local ms=actorCount(receipt.platoon,cfg)
 if not ms or #ms<1 then return false,'REPLACEMENT_MEMBERS_LOADING'end
 -- A recreated one-member merchant/guard squad has no surviving AI to reuse.
 -- Install its role before saved delivery recovery; no survivor is reset.
 if #ms==1 then
  if cfg.role=='trader' then
   local resident=Live.call(field(plan.building,'residentSquad'),'getPlatoon')
   if resident and Live.call(resident,'getPlatoonStringID')~=receipt.pid then
    local oldID=Live.call(resident,'getPlatoonStringID')
    if oldID~=plan.record.pid then return false,'FOREIGN_RESIDENT_PRESERVED'end
   end
   plan.building:setResidentSquad(receipt.platoon)
  end
  local state=receipt.state or {cfg=cfg,key=id(plan.building),building=plan.building,platoon=receipt.platoon}
  state.cfg=cfg;state.now=Live.clock();receipt.state=state
  if not Work.ensure(state,ms) then return false,'REPLACEMENT_ROLE_WAIT_SAFE'end
 end
 local driver=driverFor(receipt.platoon,cfg)
 local adopted,reason=driver.adopt(plan.building,receipt.platoon,{work=receipt.state and receipt.state.work,initializedMember=receipt.member})
 if not adopted then return false,reason end
 if cfg.serviceHired then attached[receipt.pid]=true end
 local old=Store.get().roster[plan.record.id]
 if old then old.replacedBy=receipt.member;old.order=nil end
 -- If the old persistent platoon is extinct, its remaining confirmed vacancies
 -- now belong to the new native platoon; no survivor is transferred.
 if receipt.pid~=plan.record.pid then
  for _,record in pairs(Store.get().roster)do
   if record.pid==plan.record.pid and record.dead and not record.replacedBy then record.pid=receipt.pid end
  end
 end
 Roster.observe({cfg=cfg,platoon=receipt.platoon,building=plan.building,key=id(plan.building),now=Live.clock()},ms)
 order.status='complete';receipt.pending=false
 recoverOrders[order.id]=nil
 report('REPLACEMENT_READY','order='..order.id..' old='..plan.record.id..' new='..receipt.member..' pid='..receipt.pid)
 return true
end
local function finishHired(order,p,building)
 local pid=Live.call(p,'getPlatoonStringID')
 local row=pid and Store.get().patrols[pid]
 if not row then return false,'HIRED_RECEIPT_MISSING'end
 if row.order~=order.id or syncHireReceipt(pid,row)~=order then return false,'HIRED_RECEIPT_MISMATCH'end
 local complete=order.status=='complete'
 -- Once adopted, the ordinary controller owns its roster and duty. Historical
 -- receipts are retained for payment idempotency, not polled as active work.
 if attached[pid] and complete then return true end
 local residentPID=order.metadata.residentPID
 -- This rollback compensates only for a factory allocation overwriting the
 -- tower resident. A completed hire must preserve the tower's current owner,
 -- including a replacement chief created long after this paid receipt.
 if not complete and not row.adopted and residentPID then
  local actual=Live.call(Live.call(field(building,'residentSquad'),'getPlatoon'),'getPlatoonStringID')
  if actual~=residentPID then
   if actual and actual~=order.pid then return false,'FOREIGN_TOWER_RESIDENT_PRESERVED'end
   local original=Roster.findPlatoon(residentPID)
   if not original then return false,'TOWER_RESIDENT_LOADING'end
   building:setResidentSquad(original)
   if Live.call(Live.call(field(building,'residentSquad'),'getPlatoon'),'getPlatoonStringID')~=residentPID then return false,'TOWER_RESIDENT_RESTORE_PENDING'end
  end
 end
 local cfg=hiredConfig(order.pid,row)
 local ms=actorCount(p,cfg)
 if not complete and (not ms or #ms~=3) then return false,'HIRED_MEMBERS_LOADING'end
 local driver=driverFor(p,cfg)
 if not attached[order.pid] then
  local ok,why=driver.adopt(building,p,{fresh=not row.adopted})
  if not ok then return false,why end
  attached[order.pid]=true
 end
 row.adopted=true;order.status='complete'
 recoverPatrols[order.pid]=nil
 if ms then Roster.observe({cfg=cfg,platoon=p,building=building,key=id(building),now=Live.clock()},ms)end
 report(complete and 'HIRED_RESUMED' or 'HIRED_READY','order='..order.id..' pid='..order.pid..' count='..tostring(ms and #ms)..' day=posts night=patrol base='..row.base)
 return true
end
local function pendingUnknown(town)
 for _,order in pairs(Store.get().orders)do
  if order.metadata and order.metadata.town==town
   and (order.status=='pending_payment' or order.status=='refund_pending'
    or (order.status=='pending' and (not order.pid or (order.kind=='replace' and not order.member)))) then return true end
 end
 return false
end
local function track(order)
 if not order then return end
 if order.kind=='replace' then
  recoverOrders[order.id]=order.status=='pending' and true or nil
 elseif order.kind=='hire' and order.pid then
  recoverPatrols[order.pid]=not attached[order.pid] and true or nil
 end
end
local function indexWork()
 -- Rebuild transient work sets once per native load. Keep all historical
 -- receipts in Store, including uncertain payments, to prevent double debit.
 if indexed or not Store.ready() then return end
 for _,record in pairs(Store.get().roster)do
  if record.order then
   local order=Store.get().orders[record.order]
   if order and (order.status=='cancelled' or order.status=='refunded') then record.order=nil end
  end
 end
 -- Repair beta.3-.5 saves whose patrol row already migrated but whose
 -- original hire receipt still names the extinct PID, before indexing work.
 for pid,row in pairs(Store.get().patrols)do syncHireReceipt(pid,row)end
 for _,order in pairs(Store.get().orders)do track(order)end
 for pid in pairs(Store.get().patrols)do if not attached[pid] then recoverPatrols[pid]=true end end
 indexed=true
end
local function replace(ctx,selectedID)
 local record,selectionWhy=selectedLoss(ctx,selectedID)
 if not record then
  report('REPLACEMENT_SELECTION_UNAVAILABLE',selectionWhy)
  notify('Выбранный погибший больше недоступен для замены. Деньги не списаны.');return
 end
 local b=Roster.building(record.building)
 local p,lookup=Roster.findPlatoon(record.pid)
 if not p and lookup~='TRUE_NOT_FOUND' then notify('Прежний отряд пока недоступен для проверки. Оплата не списана.');return end
 local plan,why=Recruit.prepare(record,b,p)
 if not plan then report('REPLACEMENT_PREFLIGHT',why);notify('Прежний отряд или место службы пока недоступны для замены. Деньги не списаны.');return end
 local order,receipt,reason=Orders.pay('replace','replace:'..record.id,10000,ctx.wallet,
  {building=record.building,town=ctx.town,deadID=record.id},function(tx)
   record.order=tx.id
   local result,err,uncertain=Recruit.spawn(plan)
   if result then
    tx.pid=result.pid;tx.member=result.member;tx.metadata.recruitStages=result.stages or {}
    pending[tx.id]={plan=plan,receipt=result}
    if not err and finishReplacement(tx,plan,result) then return result,nil,false end
    result.pending=true;return result,err or 'REPLACEMENT_INITIALIZING',true
   end
   return nil,err,uncertain
  end)
 track(order)
 if order and (order.status=='refunded' or order.status=='cancelled') then record.order=nil end
 if order and order.status=='complete' then
  pending[order.id]=nil;notify('Замена нанята за 10 000 кат. Новый NPC направляется на службу.')
 elseif order and order.status=='pending' then notify('Заказ замены оплачен. Ожидается завершение нативного создания и назначения; повторной оплаты не будет.')
 else failed('replace',reason,order)end
end
local function hire(ctx,nonce)
 local resident=Live.call(field(ctx.building,'residentSquad'),'getPlatoon')
  or field(Live.call(ctx.chief,'getPlatoon'),'me')
 local residentPID=Live.call(resident,'getPlatoonStringID')
 if not residentPID then notify('Привязка начальника к башне пока недоступна. Деньги не списаны.');return end
 local number=1
 for _,row in pairs(Store.get().patrols)do if row.building==ctx.key then number=math.max(number,(row.number or 0)+1)end end
 local base=number*3
 local cfg=Config.copy(Config.hired);cfg.streetSlotBase=base
 local ok,pre=pcall(Transport.preflight,ctx.building,cfg)
 if not ok then report('HIRED_PREFLIGHT',pre);notify('Отряд пока нельзя направить к башне. Деньги не списаны.');return end
 local state={cfg=cfg,key=ctx.key,building=ctx.building}
 local index=Posts.candidates('police','patrol',0)[1]
 if not index then notify('Нет доступных служебных узлов башни. Оплата не списана.');return end
 for slot=1,3 do
  local node,err=Nodes.target(state,ctx.building,{},index,base+slot)
  if not node then report('HIRED_POST_PREFLIGHT',err);notify('У башни нет трёх доступных мест для дневных постов. Деньги не списаны.');return end
 end
 -- The durable sequence prevents a fresh Lua session reusing an earlier
 -- dialogue nonce after loading the same campaign.
 local subject='hire:'..tostring(Store.get().seq+1)..':'..nonce
 local order,receipt,reason=Orders.pay('hire',subject,20000,ctx.wallet,
  {building=ctx.key,town=ctx.town,base=base,number=number,residentPID=residentPID},function(tx)
   local p=Transport.spawn(pre,ctx.building,cfg)
   if not p then return nil,'HIRED_FACTORY_RESULT_UNCERTAIN',true end
   local pid=Live.call(p,'getPlatoonStringID')
   if not pid then return nil,'HIRED_IDENTITY_LOADING',true end
   tx.pid=pid
   Store.get().patrols[pid]={pid=pid,building=ctx.key,town=ctx.town,base=base,number=number,order=tx.id}
   local result={platoon=p,pid=pid}
   if finishHired(tx,p,ctx.building) then return result,nil,false end
   result.pending=true;return result,'HIRED_INITIALIZING',true
  end)
 track(order)
 if order and order.status=='complete' then notify('Нанят отряд из 3 патрульных за 20 000 кат. Днём — посты у башни, ночью — патруль.')
 elseif order and order.status=='pending' then notify('Отряд оплачен. Ожидается завершение его нативного создания; повторного найма и списания не будет.')
 else failed('hire',reason,order)end
end
local function process(request)
 local ctx,why=context(request.chief,request.player)
 if not ctx then report('CONTEXT_UNAVAILABLE',why);notify('Начальник, игрок или башня сейчас недоступны для оформления заказа.');return end
 if not hooksReady or not Store.ready() then notify('Услуга найма недоступна: реестр сохранения ещё не готов. Деньги не списаны.');return end
 local scanned,scanWhy=Roster.scan(true)
 if request.action=='check' then
  local losses=lossSnapshots(ctx)
  local parts={'Подтверждённых погибших без оплаченной замены: '..#losses..'. Замена одного — 10 000 кат.'}
  for i=1,math.min(12,#losses)do parts[#parts+1]=losses[i].label end
  if not scanned then parts[#parts+1]='Не все отряды доступны для проверки; пропавших не считаю погибшими.'end
  notify(table.concat(parts,'\n'));return
 end
 if not scanned then report('SCAN_UNAVAILABLE',scanWhy);notify('Проверка состава пока не завершена. Деньги не списаны.');return end
 if pendingUnknown(ctx.town) then notify('Сначала требуется завершить проверку предыдущего оплаченного заказа. Повторной оплаты не будет.');return end
 if request.action=='replace' then replace(ctx,request.selectedID) elseif request.action=='hire' then hire(ctx,request.nonce)end
end
function M.observe(s,ms)
 if not Store.ready() then return end
 local ok,why=pcall(Roster.observe,s,ms)
 if not ok then report('ROSTER_ERROR',why);return end
 if s.cfg.role=='chief' then
  for _,m in ipairs(ms)do if Live.call(m.char,'isDead')==false then
   local ready,reason=Dialogue.attach(m.char)
   local status=ready and 'READY' or tostring(reason)
   if dialogueStatus[m.key]~=status then report('DIALOGUE_STATUS','member='..m.key..' status='..status);dialogueStatus[m.key]=status end
  end end
 end
end
local function recover(task)
 if task.kind=='scan' then
  local ok,why=Roster.scan(true)
  if not ok then nextReconcile=math.min(nextReconcile,Live.clock()+RECOVER_MINUTES);report('SCAN_UNAVAILABLE',why)end
 elseif task.kind=='patrol' then
  local pid=task.key
  local row=Store.get().patrols[pid]
  if not row or attached[pid] then recoverPatrols[pid]=nil;return end
  local p=Roster.findPlatoon(pid);local b=Roster.building(row.building)
  if not p or not b then return end
  local order=Store.get().orders[row.order]
  if order then finishHired(order,p,b)
  else
   local cfg=hiredConfig(pid,row)
   if driverFor(p,cfg).adopt(b,p) then attached[pid]=true;recoverPatrols[pid]=nil end
  end
 elseif task.kind=='replace' then
  local key=task.key;local order=Store.get().orders[key]
  if not order or order.kind~='replace' or order.status~='pending' then recoverOrders[key]=nil;pending[key]=nil;return end
  local active=pending[key]
  if not active and order.pid and order.member then
   local record=Store.get().roster[order.metadata.deadID]
   local b=Roster.building(order.metadata.building);local p=Roster.findPlatoon(order.pid)
   if record and b and p then
    local plan,receipt=Recruit.restore(record,b,p,order.member,order.metadata.recruitStages)
    if plan and receipt then active={plan=plan,receipt=receipt};pending[key]=active end
   end
  end
  if active and finishReplacement(order,active.plan,active.receipt) then pending[key]=nil;notify('Оплаченная замена готова к службе.')end
 end
end
local function scheduleRecovery(now)
 if #recoveryQueue>0 then return end
 nextScan=now+RECOVER_MINUTES
 if now>=nextReconcile then
  nextReconcile=now+RECONCILE_MINUTES
  recoveryQueue[#recoveryQueue+1]={kind='scan'}
 end
 -- Only pending receipts and not-yet-attached paid squads enter this queue.
 -- One task is consumed per frame; completed history is never walked here.
 local function add(kind,keys)
  local sorted={};for key in pairs(keys)do sorted[#sorted+1]=key end;table.sort(sorted)
  for _,key in ipairs(sorted)do recoveryQueue[#recoveryQueue+1]={kind=kind,key=key}end
 end
 add('patrol',recoverPatrols);add('replace',recoverOrders)
end
function M.request(action,chief,player,selectedID)
 if action~='check' and action~='replace' and action~='hire' then return false,'UNKNOWN_SERVICE'end
 if action=='replace' and (type(selectedID)~='string' or selectedID=='') then return false,'LOSS_SELECTION_REQUIRED'end
 if #queue>=8 then return false,'SERVICE_QUEUE_FULL'end
 sequence=sequence+1
 queue[#queue+1]={action=action,chief=chief,player=player,selectedID=selectedID,nonce=tostring(epoch)..':'..sequence}
 return true
end
function M.tick()
 frames=frames+1
 indexWork()
 local processed=false
 if #queue>0 then
  processed=true
  local request=table.remove(queue,1);local ok,err=pcall(process,request)
  if not ok then report('REQUEST_ERROR',err);notify('Заказ требует проверки. Повторный призыв автоматически не выполняется.')end
 end
 if not Store.ready() then return end
 if frames%60==0 then
  local now=Live.clock()
  if now<nextScan-RECOVER_MINUTES then nextScan=now;nextReconcile=now;recoveryQueue={}end
  if now>=nextScan then scheduleRecovery(now)end
 end
 if not processed and #recoveryQueue>0 then
  local task=table.remove(recoveryQueue,1)
  local ok,err=pcall(recover,task);if not ok then report('RECOVER_ERROR',err)end
 end
end
function M.resetSession()
 for _,driver in pairs(drivers)do pcall(driver.resetSession)end
 queue={};drivers={};pending={};attached={};dialogueStatus={};frames=0;nextScan=0;nextReconcile=0;epoch=epoch+1;sequence=0;loadedSeen=false
 indexed=false;recoverOrders={};recoverPatrols={};recoveryQueue={}
 Roster.reset();Dialogue.resetSession();Store.reset()
end
function M.start()
 if started then return true end
 _G.KenshiShopPoliceServices=M
 local required={
  {'PlayerInterface::serialise',function(_,data)
   -- A brand-new campaign has no load callback. Its first ordinary save is
   -- the native save-scope handshake; corrupt loaded state is never replaced.
   if not loadedSeen and not Store.ready() then loadedSeen=true;Store.load(data)end
   local ok,why=Store.save(data)
   if not ok and Store.ready() then hooksReady=false;report('SAVE_ERROR',why)end
  end},
  {'PlayerInterface::loadFromSerialise',function(_,data)
   M.resetSession();loadedSeen=true;local ok,why=Store.load(data);hooksReady=hooksInstalled and ok
   report(ok and 'STATE_LOADED' or 'LOAD_ERROR',why or 'save_scoped=true')
  end},
  {'Character::declareDead',function(c)if Store.ready() then local ok,why=pcall(Roster.death,c);if not ok then report('DEATH_ERROR',why)end end end},
  {'GameWorld::resetGame',M.resetSession},
  {'MyGUI::Gui::eventFrameStart',M.tick},
 }
 hooksReady=true
 for _,entry in ipairs(required)do
  local ok,token=pcall(Events.on,entry[1],entry[2])
  if not ok or not token then hooksReady=false;report('HOOK_UNAVAILABLE',entry[1]..' '..tostring(token))end
 end
 local ok,why=pcall(Dialogue.start,M)
 if not ok or not why then hooksReady=false;report('DIALOGUE_ERROR',why)end
 hooksInstalled=hooksReady
 started=true
 report('STARTED','native_dialogue=true replacement=10000 hire_three=20000 day_posts=true night_patrol=true save_hooks='..tostring(hooksReady))
 return hooksReady
end
return M
