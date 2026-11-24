-- Native chief services. All paid allocations occur once on the owner thread;
-- save data contains identities and receipts, never live engine pointers.
local Config=require('Core.Police.Services.Config')
local Store=require('Core.Police.Services.Store')
local Roster=require('Core.Police.Services.Roster')
local Orders=require('Core.Police.Services.Orders')
local Dialogue=require('Core.Police.Services.Dialogue')
local Recruit=require('Core.Police.Services.Recruit')
local Evacuation=require('Core.Police.Services.Evacuation')
local PropertyReturn=require('Core.Police.Services.PropertyReturn')
local Controller=require('Core.NPC.Controller')
local Transport=require('Core.NPC.Transport')
local Nodes=require('Core.NPC.NativeNodes')
local Posts=require('Core.NPC.PostDuty')
local Work=require('Core.NPC.RoleAI')
local Existing=require('Core.NPC.ExistingSquads')
local Residence=require('Core.NPC.Residence')
local Retirement=require('Core.Ownership.Retirement')
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local M={}
local queue,drivers,attached,dialogueStatus={},{},{},{}
local hireWait={}
local started,hooksReady,hooksInstalled,loadedSeen=false,false,false,false
local frames,nextScan,epoch,sequence=0,0,0,0
local indexed,recoverOrders,recoverPatrols,recoveryQueue=false,{},{},{}
local pausedRecovery={}
local RECOVER_MINUTES=10
local RECOVERY_CHECKS=6
local MAX_HIRES=2
local HIRE_PRICE=20000
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
 local key,townID=id(building),id(town)
 if type(key)~='string' or key=='' or type(townID)~='string' or townID=='' then return nil,'CHIEF_TOWN_UNAVAILABLE'end
 return {chief=chief,player=player,building=building,key=key,town=townID,townObject=town}
end
local function playerWallet(player)
 local wallet=field(Live.call(player,'getFaction'),'factionOwnerships')
 local balance=Live.call(wallet,'getMoney')
 if type(balance)=='number' and balance==Live.call(player,'getMoney') then return wallet end
end
function M.newLedgerOffered()
 return hooksInstalled and Store.canStartNewOrders()
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
 local hired=cfg.serviceHired and Store.get().patrols[record.pid]
 if hired then cfg=Config.forHire(hired.number or 1,cfg.template) end
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
 if Store.evacuation(ctx.town) then return nil,'TOWN_EVACUATING' end
 if not Store.evacuationReady() then return nil,'SERVICE_STORE_NOT_READY' end
 local rosterIncomplete=not Store.ready() or Store.get().partialRoster
 local expectedShops,coverageWhy
 if rosterIncomplete then expectedShops,coverageWhy=PropertyReturn.staffedShopKeys(ctx) end
 local scanned,scanWhy=Roster.scan(true,ctx.town,expectedShops)
 if coverageWhy then scanned=false;scanWhy=coverageWhy end
 local rows=lossSnapshots(ctx)
 if not scanned then
  report('SCAN_UNAVAILABLE',scanWhy)
  if #rows==0 then
   return nil,rosterIncomplete and 'ROSTER_HISTORY_INCOMPLETE' or (scanWhy or 'SCAN_UNAVAILABLE')
  end
 end
 if #rows>0 and (not Store.ready() or not hooksReady) and not M.newLedgerOffered() then
  return rows,'SERVICE_STORE_NOT_READY'
 end
 return rows,not scanned and (scanWhy or 'SCAN_UNAVAILABLE') or nil
end
local function hiredConfig(pid,row)
 local cfg=Config.forHire(row.number or 1,row.template or Config.hired)
 if not cfg then return nil end
 cfg.existingID=pid
 if not cfg.towerPosts then cfg.streetSlotBase=row.base or cfg.streetSlotBase end
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
  if not cfg then return false,'HIRED_TEMPLATE_MISMATCH' end
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
local function resident(building)
 return Live.call(field(building,'residentSquad'),'getPlatoon')
end
local function nativeTemplate(p)return field(field(p,'squadTemplate'),'stringID')end
local function nativeFaction(p)return field(Live.call(Live.call(p,'getFaction'),'getData'),'stringID')end
local function isHired(p)
 local template=nativeTemplate(p)
 return template==Config.hired or template==Config.hiredGuard
end
local function regularResident(building,p)
 local template=nativeTemplate(p)
 if template~='310-KenshiShop.mod' and template~='311-KenshiShop.mod' then return false end
 if nativeFaction(p)~=Config.faction then return false end
 local home=field(Live.call(p,'getOwnerships'),'_homeBuilding')
 return Live.call(home,'toString')==id(building)
end
local function findResident(building,preferred)
 if preferred then
  local p=Roster.findPlatoon(preferred)
  if regularResident(building,p) then return p end
 end
 -- Newer beta.11 receipts may point at the preceding hired patrol. Resolve
 -- the original squads by town building and their exact templates.
 for _,template in ipairs({'311-KenshiShop.mod','310-KenshiShop.mod'})do
  local p=Existing.find(building,Config.templates[template])
  if regularResident(building,p) then return p end
 end
end
local function restoreTowerResident(building,preferred,paid,discovered)
 local current=resident(building)
 if regularResident(building,current) then return current end
 if current then
  local currentID=Live.call(current,'getPlatoonStringID')
  local row=currentID and Store.get().patrols[currentID]
  if not row then
   for _,candidate in ipairs(discovered or {})do if candidate.pid==currentID then row=candidate;break end end
  end
  if not isHired(current) or nativeFaction(current)~=Config.faction
   or not row or row.building~=id(building) or row.town~=id(Live.call(building,'getTown')) then
   return nil,'FOREIGN_TOWER_RESIDENT_PRESERVED'
  end
 elseif not paid or Live.call(field(building,'residentSquad'),'isNull')~=true then
  return nil,'TOWER_RESIDENT_LOADING'
 end
 local restore=findResident(building,preferred)
 if not restore then return nil,'TOWER_ORIGINAL_RESIDENT_LOADING' end
 local ok,why=Residence.bind(building,restore,current)
 if not ok or not regularResident(building,resident(building)) then
  return nil,why or 'TOWER_RESIDENT_RESTORE_PENDING'
 end
 report('TOWER_RESIDENT_RESTORED','building='..id(building)..' pid='..Live.call(restore,'getPlatoonStringID'))
 return restore
end
local function hireHome(p,building)
 local owns=Live.call(p,'getOwnerships')
 local handle=field(owns,'_homeBuilding')
 if Live.call(handle,'toString')==id(building) then return true end
 if Live.call(handle,'isNull')~=true or nativeFaction(p)~=Config.faction then return false end
 local ok=pcall(function()
  owns:setHomeBuilding(building:getHandle(),(SquadType and SquadType.SQ_RESIDENT) or 1)
 end)
 return ok and Live.call(field(owns,'_homeBuilding'),'toString')==id(building)
end
local function finishHired(order,p,building,fresh)
 local pid=Live.call(p,'getPlatoonStringID')
 local row=pid and Store.get().patrols[pid]
 if not row then return false,'HIRED_RECEIPT_MISSING'end
 if row.order~=order.id or syncHireReceipt(pid,row)~=order then return false,'HIRED_RECEIPT_MISMATCH'end
 if id(building)~=row.building or id(Live.call(building,'getTown'))~=row.town then
  return false,'HIRED_SERVICE_BUILDING_CHANGED'
 end
 if attached[pid] then return true end
 local template=nativeTemplate(p)
 if not isHired(p) or nativeFaction(p)~=Config.faction or (row.template and row.template~=template) then
  return false,'HIRED_PLATOON_UNVERIFIED'
 end
 row.template=template
 if not hireHome(p,building) then return false,'HIRED_HOME_UNAVAILABLE' end
 -- Paid extras used to replace this single building slot. Only repair it
 -- when a matching paid squad occupies it, or a pending order left it empty.
 local current=resident(building)
 if isHired(current) or (order.status~='complete' and not regularResident(building,current)) then
  local restored,why=restoreTowerResident(building,order.metadata.residentPID,true)
  if not restored then return false,why end
 end
 local cfg=hiredConfig(pid,row)
 if not cfg then return false,'HIRED_TEMPLATE_MISMATCH' end
 local ok,why=driverFor(p,cfg).adopt(building,p,{fresh=fresh==true})
 if not ok then return false,why end
 attached[pid]=true;row.adopted=true;hireWait[pid]=nil
 recoverPatrols[pid]=nil
 report('HIRED_MONITOR_READY','order='..order.id..' pid='..pid..' base='..row.base)
 return true
end
local function reportHireWait(pid,why)
 if hireWait[pid]==why then return end
 hireWait[pid]=why
 report('HIRED_WAIT','pid='..pid..' reason='..tostring(why))
end
function M.hiredDuty(s,ms)
 if not Store.ready() or not attached[s.pid] or not s.postDuty or not s.work or not s.work.done then return end
 local row=Store.get().patrols[s.pid]
 if not row or row.building~=s.key then return end
 local order=Store.get().orders[row.order]
 if not order or order.status~='pending' then return end
 local mode=s.cfg.towerPosts and 'FLOOR_0' or (Posts.day(s.now) and 'DAY' or 'NIGHT')
 local count=0
 for _,m in ipairs(ms)do
  if Live.call(m.char,'isDead')~=true then
   local member=s.postDuty.members[m.key]
   if not member or member.mode~=mode then return end
   if s.cfg.towerPosts and (not member.node or member.node.outside~=false or member.node.floor~=0) then return end
   count=count+1
  end
 end
 if count==0 then return end
 order.status='complete'
 report('HIRED_DUTY_READY','order='..order.id..' pid='..s.pid..' members='..count..' shift='..mode)
 if s.cfg.towerPosts then notify('Второй отряд получил посты внутри башни.')
 else notify('Патруль получил задачи. Днём — посты у башни, ночью — обход города.') end
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
  recoverOrders[order.id]=order.status=='pending' and order.pid and order.member and true or nil
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
local function prepareNativePatrols(ctx)
 local state=Store.get()
 local count,highest,seen=0,0,{}
 for _,order in pairs(state.orders)do
  local meta=order.metadata
  if order.kind=='hire' and meta and meta.town==ctx.town
   and order.status~='cancelled' and order.status~='refunded' then
   count=count+1
   highest=math.max(highest,tonumber(meta.number) or 0)
   if order.pid then seen[order.pid]=true end
  end
 end
 for pid,row in pairs(state.patrols)do
  if row.town==ctx.town then
   highest=math.max(highest,tonumber(row.number) or 0)
   if not seen[pid] then count=count+1;seen[pid]=true end
  end
 end
 ctx.nativePatrols={}
 highest=math.max(count,highest)
 if ctx.openNewLedger or Store.legacyOrdersArchived() then
  local existing,why=Roster.hiredInTown(ctx.town)
  if not existing then return false,why end
  for _,row in ipairs(existing)do
   local prior=state.patrols[row.pid]
   if prior then
    if prior.building~=row.building or prior.town~=row.town then return false,'HIRED_NATIVE_HOME_CHANGED' end
   elseif not seen[row.pid] then
    highest=highest+1
    row.number=highest;row.base=highest*3
    ctx.nativePatrols[#ctx.nativePatrols+1]=row
   end
  end
 end
 ctx.nextPatrolNumber=highest+1
 return true
end
function M.hireOffer(chief,player)
 local ctx,why=context(chief,player)
 if not ctx then return nil,why end
 if Store.evacuation(ctx.town) then return nil,'TOWN_EVACUATING' end
 M.buildingLoaded(ctx.key)
 ctx.openNewLedger=M.newLedgerOffered()
 if not (hooksReady and Store.ready()) and not ctx.openNewLedger then return nil,'SERVICE_STORE_NOT_READY' end
 if pendingUnknown(ctx.town) then return nil,'PAYMENT_PENDING' end
 local ok,reason=prepareNativePatrols(ctx)
 if not ok then return nil,reason end
 if ctx.nextPatrolNumber>MAX_HIRES then return nil,'HIRE_LIMIT' end
 return ctx.nextPatrolNumber,nil,ctx.openNewLedger
end
local function openOrderLedger(ctx)
 if ctx.openNewLedger then
  local ok,why=Store.startNewOrders()
  if not ok then
   report('NEW_ORDERS_UNAVAILABLE',why)
   notify('Открыть реестр новых заказов пока не удалось. Деньги не списаны.')
   return false
  end
  hooksReady=hooksInstalled
  report('NEW_ORDERS_STARTED','town='..ctx.town)
 end
 for _,row in ipairs(ctx.nativePatrols or {})do
  Store.get().patrols[row.pid]=row
  recoverPatrols[row.pid]=true
 end
 return true
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
 if plan.cfg.serviceHired and not Store.get().patrols[record.pid] then
  local found=false
  for _,row in ipairs(ctx.nativePatrols or {})do if row.pid==record.pid then found=true;break end end
  if not found then
   report('REPLACEMENT_PREFLIGHT','HIRED_IDENTITY_MISSING')
   notify('Привязку прежнего патруля пока не удалось подтвердить. Деньги не списаны.')
   return
  end
 end
 if not openOrderLedger(ctx) then return end
 local order,receipt,reason=Orders.pay('replace','replace:'..record.id,10000,ctx.wallet,
  {building=record.building,town=ctx.town,deadID=record.id},function(tx)
   record.order=tx.id
   local result,err,uncertain=Recruit.spawn(plan)
   if result then
    tx.pid=result.pid;tx.member=result.member or id(result.root);tx.metadata.recruitStages=result.stages or {}
    if not err and finishReplacement(tx,plan,result) then return result,nil,false end
    result.pending=true;return result,err or 'REPLACEMENT_INITIALIZING',true
   end
   return nil,err,uncertain
  end)
 track(order)
 if order and (order.status=='refunded' or order.status=='cancelled') then record.order=nil end
 if order and order.status=='complete' then
  notify('Замена нанята за 10 000 кат. Новый NPC направляется на службу.')
 elseif order and order.status=='pending' then notify('Заказ замены оплачен. Ожидается завершение нативного создания и назначения; повторной оплаты не будет.')
 else failed('replace',reason,order)end
end
local function hire(ctx,nonce)
 local number=ctx.nextPatrolNumber
 local base=number*3
 local cfg=Config.forHire(number)
 local ok,pre=pcall(Transport.preflight,ctx.building,cfg)
 if not ok then report('HIRED_PREFLIGHT',pre);notify('Отряд пока нельзя направить к башне. Деньги не списаны.');return end
 local state={cfg=cfg,key=ctx.key,building=ctx.building}
 local indices=Posts.candidates('police',cfg.role,0,cfg.towerPosts)
 local verified=0
 if cfg.towerPosts then
  for _,index in ipairs(indices)do
   if Nodes.available(state,index,false) and Nodes.target(state,ctx.building,{},index,false) then verified=verified+1 end
   if verified==cfg.count then break end
  end
 elseif indices[1] then
  for slot=1,cfg.count do
   if Nodes.target(state,ctx.building,{},indices[1],base+slot) then verified=verified+1 end
  end
 end
 if verified~=cfg.count then
  report('HIRED_POST_PREFLIGHT','slot='..number..' verified='..verified)
  notify(cfg.towerPosts and 'Внутри башни пока нет трёх доступных постов. Деньги не списаны.'
   or 'У башни пока нет трёх доступных дневных постов. Деньги не списаны.')
  return
 end
 local regular,reason=restoreTowerResident(ctx.building,nil,false,ctx.nativePatrols)
 local residentPID=Live.call(regular,'getPlatoonStringID')
 if not residentPID then
  report('HIRED_TOWER_CHECK',reason)
  notify('Штатный отряд башни пока не подтверждён. Деньги не списаны.');return
 end
 if not openOrderLedger(ctx) then return end
 -- The durable sequence prevents a fresh Lua session reusing an earlier
 -- dialogue nonce after loading the same campaign.
 local subject='hire:'..tostring(Store.get().seq+1)..':'..nonce
 local order,receipt,reason=Orders.pay('hire',subject,HIRE_PRICE,ctx.wallet,
  {building=ctx.key,town=ctx.town,base=base,number=number,template=cfg.template,residentPID=residentPID},function(tx)
   local p=Transport.spawn(pre,ctx.building,cfg)
   if not p then return nil,'HIRED_FACTORY_RESULT_UNCERTAIN',true end
   local pid=Live.call(p,'getPlatoonStringID')
   if not pid then return nil,'HIRED_IDENTITY_LOADING',true end
   tx.pid=pid
   Store.get().patrols[pid]={pid=pid,building=ctx.key,town=ctx.town,base=base,number=number,template=cfg.template,order=tx.id}
   local result={pid=pid,pending=true}
   local attachedNow,why=finishHired(tx,p,ctx.building,true)
   if not attachedNow then reportHireWait(pid,why) end
   return result,nil,false
  end)
 track(order)
 if order and order.status=='pending' then notify('Отряд оплачен. Ожидается назначение задач.')
 else failed('hire',reason,order)end
end
local function process(request)
 local chief=Live.call(request.chiefHand,'getCharacter')
 local player=Live.call(request.playerHand,'getCharacter')
 if id(chief)~=request.chiefKey or id(player)~=request.playerKey then return end
 local ctx,why=context(chief,player)
 if not ctx then report('CONTEXT_UNAVAILABLE',why);notify('Начальник, игрок или башня сейчас недоступны для оформления заказа.');return end
 if request.action=='evacuate' then
  if not hooksInstalled then notify('Уход недоступен до подключения сохранения услуг.');return end
  local begun,reason=Evacuation.begin(ctx)
  if begun then report('EVACUATION_STARTED','town='..ctx.town);notify('Начинаем уход из города.')
  else report('EVACUATION_NOT_STARTED',reason);notify('Уход пока недоступен. Проверьте, что город загружен и отряды на месте.')end
  return
 end
 if Store.evacuation(ctx.town) then notify('Город покидают. Найм закрыт.');return end
 ctx.openNewLedger=request.newLedger and M.newLedgerOffered()
 if not (hooksReady and Store.ready()) and not ctx.openNewLedger then
  notify('Данные найма сейчас недоступны. Деньги не списаны.');return
 end
 ctx.wallet=playerWallet(player)
 if not ctx.wallet then report('PLAYER_WALLET_UNVERIFIED');notify('Кошелёк игрока недоступен. Деньги не списаны.');return end
 local price=request.action=='hire' and HIRE_PRICE or 10000
 if Live.call(ctx.wallet,'getMoney')<price then failed(request.action,'INSUFFICIENT_FUNDS');return end
 if pendingUnknown(ctx.town) then notify('Сначала требуется завершить проверку предыдущего оплаченного заказа. Повторной оплаты не будет.');return end
 if request.action=='hire' or ctx.openNewLedger or Store.legacyOrdersArchived() then
  local ok,reason=prepareNativePatrols(ctx)
  if not ok then
   report('HIRED_NATIVE_SCAN_UNAVAILABLE',reason)
   notify('Проверка существующих патрулей ещё не завершена. Деньги не списаны.');return
  end
 end
 if request.action=='replace' then
  replace(ctx,request.selectedID)
 elseif request.action=='hire' then
  if ctx.nextPatrolNumber>MAX_HIRES then notify('Оба дополнительных отряда уже наняты.');return end
  if ctx.nextPatrolNumber~=request.hireSlot then notify('Предложение изменилось. Спроси начальника о найме ещё раз.');return end
  hire(ctx,request.nonce)
 end
end
function M.observe(s,ms)
 if Store.retiredBuilding(s.key) then return end
 -- The chief can report current native observations while past payments are
 -- quarantined. Confirmed current deaths may be visible as read-only rows.
 if s.cfg.role=='chief' then
  for _,m in ipairs(ms)do if Live.call(m.char,'isDead')==false then
   local ready,reason=Dialogue.attach(m.char)
   local status=ready and 'READY' or tostring(reason)
   if dialogueStatus[m.key]~=status then report('DIALOGUE_STATUS','member='..m.key..' status='..status);dialogueStatus[m.key]=status end
  end end
 end
 if not Store.evacuationReady() then return end
 local ok,why=pcall(Roster.observe,s,ms)
 if not ok then report('ROSTER_ERROR',why)end
end
local function recover(task)
 if task.kind=='patrol' then
  local pid=task.key
  local row=Store.get().patrols[pid]
  if not row or attached[pid] or Store.retiredPlatoon(pid) or Store.retiredBuilding(row.building) then recoverPatrols[pid]=nil;return end
  local b=Roster.building(row.building)
  if not b then reportHireWait(pid,'TOWER_NOT_LOADED');return end
  local p=Roster.findPlatoon(pid)
  if not p then reportHireWait(pid,'PLATOON_NOT_REGISTERED');return end
  local order=Store.get().orders[row.order]
  if order then
   local ok,why=finishHired(order,p,b)
   if not ok then reportHireWait(pid,why) end
  else
   if not isHired(p) or not hireHome(p,b) then return end
   local regular,why=restoreTowerResident(b,nil,true)
   if not regular then reportHireWait(pid,why);return end
   local cfg=hiredConfig(pid,row)
   if cfg and driverFor(p,cfg).adopt(b,p) then attached[pid]=true;recoverPatrols[pid]=nil end
  end
 elseif task.kind=='replace' then
  local key=task.key;local order=Store.get().orders[key]
  if not order or order.kind~='replace' or order.status~='pending' or Store.evacuation(order.metadata.town) then
   recoverOrders[key]=nil;return
  end
  -- Resolve the saved actor and platoon again on this frame. A native
  -- replacement receipt is borrowed only for the original allocation call.
  if not order.pid or not order.member then return end
  local record=Store.get().roster[order.metadata.deadID]
  local b=Roster.building(order.metadata.building)
  if not record or not b then return end
  local p=Roster.findPlatoon(order.pid)
  if not p then return end
  local plan,receipt=Recruit.restore(record,b,p,order.member,order.metadata.recruitStages)
  if plan and receipt and finishReplacement(order,plan,receipt) then notify('Оплаченная замена готова к службе.')end
 end
end
local function scheduleRecovery(now)
 if #recoveryQueue>0 then return end
 nextScan=now+RECOVER_MINUTES
 -- Only pending receipts and not-yet-attached paid squads enter this queue.
 -- One task is consumed per frame; completed history is never walked here.
 local function add(kind,keys)
  local sorted={};for key in pairs(keys)do sorted[#sorted+1]=key end;table.sort(sorted)
  for _,key in ipairs(sorted)do recoveryQueue[#recoveryQueue+1]={kind=kind,key=key}end
 end
 add('patrol',recoverPatrols);add('replace',recoverOrders)
end
function M.request(action,chief,player,selectedID,newLedger,hireSlot)
 if action~='replace' and action~='hire' and action~='evacuate' then return false,'UNKNOWN_SERVICE'end
 if action=='replace' and (type(selectedID)~='string' or selectedID=='') then return false,'LOSS_SELECTION_REQUIRED'end
 if action=='hire' and hireSlot~=1 and hireSlot~=2 then return false,'HIRE_QUOTE_REQUIRED'end
 if #queue>=8 then return false,'SERVICE_QUEUE_FULL'end
 local chiefHand,playerHand=Live.call(chief,'getHandle'),Live.call(player,'getHandle')
 local chiefKey,playerKey=Live.call(chiefHand,'toString'),Live.call(playerHand,'toString')
 if not chiefKey or not playerKey then return false,'SERVICE_PARTICIPANT_UNAVAILABLE' end
 sequence=sequence+1
 queue[#queue+1]={action=action,chiefHand=chiefHand,playerHand=playerHand,chiefKey=chiefKey,playerKey=playerKey,
  selectedID=selectedID,newLedger=newLedger==true,hireSlot=hireSlot,nonce=tostring(epoch)..':'..sequence}
 return true
end
local function stopTownServices(town,plan)
 for pid,row in pairs(plan.squads)do
  local driver=drivers[pid]
  if driver then driver.resetSession();drivers[pid]=nil end
  local cfg=Config.templates[row.template]
  if cfg and cfg.driver then
   local base=require(cfg.driver)
   if base.stopBuilding then base.stopBuilding(row.building) end
  end
  pausedRecovery[row.building]=nil
  attached[pid]=nil;recoverPatrols[pid]=nil
 end
 for key,order in pairs(Store.get().orders)do
  if order.metadata and order.metadata.town==town then recoverOrders[key]=nil end
 end
end
local function recoveryStep(task)
 local isPatrol=task.kind=='patrol'
 local pending=isPatrol and recoverPatrols or recoverOrders
 local saved=isPatrol and Store.get().patrols or Store.get().orders
 local checks=pending[task.key]
 if not checks then return end
 local ok,err=pcall(recover,task)
 if not ok then report('RECOVER_ERROR',err) end
 if not pending[task.key] then return end
 checks=(type(checks)=='number' and checks or 0)+1
 if checks<RECOVERY_CHECKS then pending[task.key]=checks;return end
 pending[task.key]=nil
 local row=saved[task.key]
 local data=row and (isPatrol and row or row.metadata)
 if data and data.building then
  local paused=pausedRecovery[data.building] or {}
  paused[#paused+1]=task;pausedRecovery[data.building]=paused
  report('RECOVER_PAUSED','kind='..task.kind..' key='..task.key..' building='..data.building)
 end
end
function M.tick()
 local restoring=Store.ready() and (not indexed or next(recoverOrders) or next(recoverPatrols))
 local leaving=hooksInstalled and next(Store.get().evacuations)
 if #queue==0 and not restoring and not leaving then return end
 if not Live.readyWorld() then return end
 frames=frames+1
 indexWork()
 local processed=false
 if #queue>0 then
  processed=true
  local request=table.remove(queue,1);local ok,err=pcall(process,request)
  if not ok then report('REQUEST_ERROR',err);notify('Заказ требует проверки. Повторный призыв автоматически не выполняется.')end
 end
 if leaving and (frames==1 or frames%60==0) then
  Evacuation.tick(Live.clock(),report,notify,stopTownServices)
 end
 if not Store.ready() or (not next(recoverOrders) and not next(recoverPatrols)) then return end
 if frames==1 or frames%60==0 then
  local now=Live.clock()
  if now<nextScan-RECOVER_MINUTES then nextScan=now;recoveryQueue={}end
  if now>=nextScan then scheduleRecovery(now)end
 end
 if not processed and #recoveryQueue>0 then
  recoveryStep(table.remove(recoveryQueue,1))
 end
end
function M.resetSession()
 for _,driver in pairs(drivers)do pcall(driver.resetSession)end
 queue={};drivers={};attached={};dialogueStatus={};hireWait={};frames=0;nextScan=0;epoch=epoch+1;sequence=0;loadedSeen=false
 indexed=false;recoverOrders={};recoverPatrols={};recoveryQueue={};pausedRecovery={}
 Evacuation.reset();Roster.reset();Dialogue.resetSession();Store.reset()
end
function M.buildingLoaded(key)
 -- An unloaded or still-settling district gets a fresh bounded retry budget
 -- at the next native load, or when the player asks about hiring at its tower.
 local paused=pausedRecovery[key]
 if not paused then return end
 pausedRecovery[key]=nil
 for _,task in ipairs(paused)do
  local pending=task.kind=='patrol' and recoverPatrols or recoverOrders
  pending[task.key]=true
 end
 nextScan=0
end
function M.start()
 if started then return true end
 _G.KenshiShopPoliceServices=M
 Retirement.setPredicate(Store.retiredBuilding)
 local required={
  {'PlayerInterface::serialise',function(_,data)
   -- A brand-new campaign has no load callback. Its first ordinary save is
   -- the native save-scope handshake; corrupt loaded state is never replaced.
   if not loadedSeen and not Store.ready() then
    loadedSeen=true;local ok,why=Store.load(data);hooksReady=hooksInstalled and ok
    report(ok and 'STATE_INITIALIZED' or 'LOAD_ERROR',(why or 'save_scoped=true')..' '..Store.diagnostics())
   end
   local ok,why=Store.save(data)
   if ok then hooksReady=hooksInstalled
   elseif why=='STORE_HELD' then hooksReady=false;report('STATE_HELD',Store.diagnostics())
   elseif why~='STORE_NOT_READY' then hooksReady=false;report('SAVE_ERROR',why..' '..Store.diagnostics())end
  end},
  {'PlayerInterface::loadFromSerialise',function(_,data)
   M.resetSession();loadedSeen=true;local ok,why=Store.load(data);hooksReady=hooksInstalled and ok
   report(ok and 'STATE_LOADED' or 'LOAD_ERROR',(why or 'save_scoped=true')..' '..Store.diagnostics())
  end},
  {'Character::declareDead',function(c)if Store.evacuationReady() then local ok,why=pcall(Roster.death,c);if not ok then report('DEATH_ERROR',why)end end end},
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
 report('STARTED','native_dialogue=true replacement=10000 hire_three=20000 hire_limit=2 save_hooks='..tostring(hooksReady))
 return hooksReady
end
return M
