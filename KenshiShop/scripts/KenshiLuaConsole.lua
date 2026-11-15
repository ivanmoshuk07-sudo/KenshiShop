-- KenshiShop 0.3.0-alpha.13: diagnostics for KenshiLua's EXISTING Lua console.
-- No window, no MyGUI widgets, no key binding, no command parser or polling.
-- KenshiLua's console evaluates Lua in _G; export functions explicitly to _G.
local Log = require('Diagnostics')
local layoutsOK, Layouts = pcall(require, 'Layouts')
if not layoutsOK then Layouts = {} end
local API = {version = '0.3.0-alpha.86-origin-service'}
local state = {
    started = false, core = 'not started', coreError = nil,
    tracked = {}, order = {},
    events = {construction=0, loaded=0, matched=0, scans=0},
    hooks = {},
}
local MAX_SCAN = 2500
local EXPECTED = {
    ['100-KenshiShop.mod']=101,
    ['101-KenshiShop.mod']=44,
    ['102-KenshiShop.mod']=61,
    ['103-KenshiShop.mod']=68,
    ['104-KenshiShop.mod']=17,
    ['105-KenshiShop.mod']=61,
}
local function join(lines) return table.concat(lines, '\n') end
local function safe(fn)
    local ok, value = pcall(fn)
    if ok then return value, nil end
    return nil, tostring(value)
end
local function call(name, fn)
    return function(...)
        local ok, result = pcall(fn, ...)
        if ok then return result end
        Log.error('CONSOLE_'..name..' '..tostring(result))
        return 'KS.'..name..' ERROR: '..tostring(result)..'\nSee KenshiLua Log Viewer.'
    end
end
local function shopID(b)
    local d = b:getGameData()
    return d and tostring(d.stringID) or nil
end
local function handleKey(b)
    return b:getHandle():toString()
end
local function track(b, source)
    if not b then return false end
    local id = shopID(b)
    if not id or not EXPECTED[id] then return false end
    local h = b:getHandle()
    local key = h:toString()
    if not state.tracked[key] then
        state.tracked[key] = {id=id, handle=h, source=source}
        state.order[#state.order+1] = key
    end
    return true
end
local function observe(b, event)
    state.events[event] = (state.events[event] or 0) + 1
    local ok, found = pcall(track, b, event)
    if ok and found then
        state.events.matched = state.events.matched + 1
        Log.info('CONSOLE_EVENT '..event..' shop='..shopID(b))
    elseif not ok then
        Log.error('CONSOLE_EVENT_'..event..' '..tostring(found))
    end
end
local function resolve(index)
    local n = tonumber(index)
    if not n or n ~= math.floor(n) or n < 1 or n > #state.order then
        return nil, 'Invalid shop index; run KS.scan() then KS.list().'
    end
    local entry = state.tracked[state.order[n]]
    if not entry then return nil, 'Shop index is stale; run KS.scan().' end
    local b, err = safe(function()
        if not entry.handle or entry.handle:isNull() then return nil end
        return entry.handle:getBuilding()
    end)
    if not b then return nil, 'Building not loaded: '..tostring(err or 'nil') end
    local valid, verr = safe(function() return b:isValid() end)
    if not valid then return nil, 'Invalid building: '..tostring(verr or 'isValid=false') end
    local current, sidErr = safe(function() return shopID(b) end)
    if current ~= entry.id then return nil, 'Building ID changed: '..tostring(current or sidErr)..'; run KS.scan().' end
    return b, entry
end
local function details(b)
    local lines = {}
    local fields = {
        {'sid', function() return shopID(b) end},
        {'playerOwned', function() return b:isThePlayer() end},
        {'destroyed', function() return b:isDestroyed() end},
        {'floors', function() return b:getNumFloors() end},
        {'interiorChildren', function() return b:getNumInternalBuildings() end},
        {'townPresent', function() return b:getTown() ~= nil end},
        {'factionPresent', function() return b:getFaction() ~= nil end},
        {'interiorPresent', function() return b.myInterior ~= nil end},
        {'scale', function() return b:getScale() end},
        {'position', function()
            local p = b:getPosition()
            return string.format('%.2f, %.2f, %.2f', p.x, p.y, p.z)
        end},
    }
    for _, field in ipairs(fields) do
        local value, err = safe(field[2])
        lines[#lines+1] = field[1]..'='..(err and 'ERROR: '..err or tostring(value))
    end
    return lines
end
local function recordsFor(b)
    local id = shopID(b)
    local layout = Layouts[id]
    if not layout then return {'Missing layout for '..tostring(id)} end
    local w = getGameWorld()
    if not w or not w.gamedata then return {'GameData unavailable'} end
    local found, missing = 0, {}
    local errors = {}
    for i, item in ipairs(layout.objects) do
        local record, err = safe(function() return w.gamedata:getData(item.id, 0) end)
        if record then found=found+1 else
            if #missing<12 then missing[#missing+1] = i..':'..tostring(item.id) end
            if err and #errors<3 then errors[#errors+1] = err end
        end
    end
    local lines = {string.format('RECORDS %s found=%d/%d missing=%d',
        tostring(layout.name), found, #layout.objects, #layout.objects-found)}
    if #missing>0 then lines[#lines+1]='Missing samples: '..table.concat(missing, ', ') end
    for _, e in ipairs(errors) do lines[#lines+1]='Lookup error: '..e end
    return lines
end
local function floorInfo(b)
    local id = shopID(b)
    local ok, FloorPlan = pcall(require, 'FloorPlan')
    if not ok then return {'FloorPlan ERROR: '..tostring(FloorPlan)} end
    local summary = FloorPlan.summary(id)
    if not summary then return {'No floor summary for '..tostring(id)} end
    local gameFloors, err = safe(function() return b:getNumFloors() end)
    local lines = {string.format('FLOORS %s game=%s sourceObjects=%d',
        tostring(Layouts[id] and Layouts[id].name or id), tostring(gameFloors or err), summary.count)}
    for _, group in ipairs({'inside','outside'}) do
        local levels = {}
        for level, count in pairs(summary[group]) do levels[#levels+1]={level=level,count=count} end
        table.sort(levels, function(a,c) return a.level<c.level end)
        local parts = {}
        for _, x in ipairs(levels) do parts[#parts+1] = x.level..':'..x.count end
        lines[#lines+1] = group..' sourceFloor:count='..table.concat(parts, ' | ')
    end
    lines[#lines+1]='Roof is a separate flag: see KS.roofAudit(index).'
    local okAssign,assign=pcall(require,'FloorAssignment')
    if okAssign then
        local mapped={}
        for i,c in ipairs(FloorPlan.forShop(id)) do
            local f=assign.resolve(id,c,gameFloors)
            local k=(c.outside and 'outside ' or 'inside ')..tostring(f.native)
            mapped[k]=(mapped[k] or 0)+1
        end
        local parts={}
        for k,n in pairs(mapped) do parts[#parts+1]=k..':'..n end
        table.sort(parts)
        lines[#lines+1]='Native floor plan: '..table.concat(parts,' | ')
    else lines[#lines+1]='FloorAssignment unavailable: '..tostring(assign) end
    return lines
end

API.help = call('help',function()
 return join({
  'KenshiShop '..API.version..' | construction + intact interiors + isolated NPC stage1',
  'KS.npcCheck(1) - READ-ONLY NPC template/faction/outside-city check',
  'KS.npcStart(1) - schedule NPC: first squad +1 game minute; next +5',
  'KS.npcStatus(1) - independent trader/guard role statuses',
  'KS.npcReport() - ALL tracked shops and roles, read-only',
  'KS.npcLogs(120) - ONLY automatic NPC event messages',
  'KS.ownerScan() - READ-ONLY discover PLAYER and KenshiShop merchant-owned buildings',
  'KS.ownerAudit(1), KS.ownerReport(), KS.ownerLogs(200) - READ-ONLY ownership/timing checks',
  'KS.shopFurnitureAudit(1) - READ-ONLY furniture ownership check for ANY shop',
  'KS.shopFurnitureRepair(1) - ONE-SHOT ownership repair for NON-BAR shop (TEST SAVE)',
  'KS.barFurnitureLive(1), KS.barSplitRepair(1) - bar-only split check/repair',
  'KS.ownerTest1Start() BEFORE construction; KS.ownerTest1Report() AFTER robotics and bar',
  'KS.ownerTest2Before() BEFORE saving; KS.ownerTest2After() AFTER game reload',
  'KS.recoveryCheck() - engineering split check: trader 1/1 + guard 2/2; NO teleport',
  'KS.npcReport(), KS.npcLogs(120) - spawn and delivery diagnostics only',
  'KS.npcSplitCheck(1) - READ-ONLY saved/live trader 1/1 and guard 2/2',
  'KS.npcSplitReport() - READ-ONLY audit of four split shops',
  'KS.npcResume(1) - attach saved squads; resume delivery if idle (never respawns)',
  'NPC delivery: 3 tries (1 game minute each), 2-minute wait, one gate rescue, final try',
  'NPC work AI disabled: spawn outside town and delivery only',
  'KS.status()    - module/core status',
  'KS.scan()      - one-shot read-only scan of PLAYER-owned shops',
  'KS.list()      - detected shops',
  'KS.inspect(1)  - building and furniture status',
  'KS.records(1)  - furniture FCS references',
  'KS.floors(1)   - floor classification',
  'KS.floorAudit(1), KS.roofAudit(1) - read-only floor/roof diagnostics',
  'KS.preflight(1), KS.mounted(1) - read-only interior diagnostics',
  'KS.lookup("100-KenshiShop.mod"), KS.selftest(), KS.logs(30)',
  'Automatic NPC schedule: first squad T+1 game minute; second T+6 game minutes.',
  'Existing finished shops: KS.scan(); KS.list(); KS.npcStart(1) once.',
  'No load-event NPC respawn. Existing saved NPCs require in-game verification.',
 })
end)
API.status = call('status', function()
    local w, we = safe(function() return getGameWorld() end)
    local ok, settings = pcall(require, 'Settings')
    local correctionOK = pcall(require, 'PositionCorrection')
    local s = Log.stats()
    return join({
        'KenshiShop '..API.version..' | KenshiLua built-in console',
        'core='..state.core..(state.coreError and (' error='..state.coreError) or ''),
        'world='..tostring(w~=nil)..' factory='..tostring(w and w.theFactory~=nil)..' gamedata='..tostring(w and w.gamedata~=nil),
        'Layouts='..tostring(layoutsOK)..(layoutsOK and '' or (' ERROR='..tostring(Layouts))),
        'PositionCorrection='..tostring(correctionOK)..' (bounded 2-pass)',
        'FloorAssignment='..tostring(pcall(require,'FloorAssignment')),
        'RoofDiagnostics='..tostring(pcall(require,'RoofDiagnostics')),
        'Settings='..tostring(ok)..' mode='..(ok and tostring(settings.mode) or 'unavailable'),
        'events: construction='..state.events.construction..' loaded='..state.events.loaded..' matches='..state.events.matched,
        'tracked='..#state.order..' errors='..s.errors..' logEntries='..s.retained,
        'worldQueryError='..tostring(we or 'none'),
    })
end)
API.events = call('events', function()
    return string.format('EVENTS construction=%d loaded=%d matched=%d manualScans=%d',
        state.events.construction,state.events.loaded,state.events.matched,state.events.scans)
end)
API.scan = call('scan', function()
 state.events.scans=state.events.scans+1
 local ui=assert(getPlayerInterface(),'Load a game first')
 local player=assert(ui:getFaction(),'Player faction missing')
 -- Keep already observed shops after ownership changes; they no longer appear under PLAYER-owned buildings.
 -- Deliberately do not clear event-tracked handles here.
 local checked,found,issues=0,0,{}
 local own=assert(player.factionOwnerships,'Player ownerships missing')
 local arr,err=safe(function()
  local z=lektor.new('Building*')
  own:getOwnedBuildingPtrs(z,nil)
  return z
 end)
 if arr then
  for i=1,math.min(#arr,MAX_SCAN) do
   checked=checked+1
   local ok,matched=pcall(track,arr[i],'player:pointer')
   if ok and matched then found=found+1
   elseif not ok and #issues<5 then issues[#issues+1]=tostring(matched) end
  end
  if #arr>MAX_SCAN then issues[#issues+1]='pointer safety cap reached' end
 else issues[#issues+1]=tostring(err) end
 local hs,herr=safe(function()
  local z=lektor.new('hand')
  own:getOwnedBuildingsH(z)
  return z
 end)
 if hs then
  for i=1,math.min(#hs,MAX_SCAN) do
   local b=safe(function()return hs[i]:getBuilding()end)
   if b then
    checked=checked+1
    local ok,matched=pcall(track,b,'player:handle')
    if ok and matched then found=found+1
    elseif not ok and #issues<5 then issues[#issues+1]=tostring(matched) end
   end
  end
  if #hs>MAX_SCAN then issues[#issues+1]='handle safety cap reached' end
 else issues[#issues+1]='handles: '..tostring(herr) end
 table.sort(state.order,function(a,b)
  local x,y=state.tracked[a],state.tracked[b]
  if x.id==y.id then return a<b end
  return x.id<y.id
 end)
 local lines={string.format('SCAN checked=%d matched=%d unique=%d (PLAYER only)',checked,found,#state.order)}
 for _,v in ipairs(issues) do lines[#lines+1]='SCAN_WARNING '..v end
 lines[#lines+1]='Next: KS.list()'
 return join(lines)
end)
API.ownerScan = call('ownerScan',function()
 local world=assert(getGameWorld(),'World not ready')
 local ui=assert(getPlayerInterface(),'Player interface missing')
 local player=assert(ui:getFaction(),'Player faction missing')
 local manager=assert(world.factionMgr,'Faction manager missing')
 local sources={{label='player',faction=player}}
 for _,id in ipairs({'400-KenshiShop.mod','401-KenshiShop.mod'})do
  local fac=safe(function()return manager:getFactionByStringID(id)end)
  if fac then sources[#sources+1]={label=id,faction=fac} end
 end
 local count,warnings=0,{}
 for _,source in ipairs(sources)do
  local own=safe(function()return source.faction.factionOwnerships end)
  if own then
   local list,err=safe(function()
    local dest=lektor.new('Building*')
    own:getOwnedBuildingPtrs(dest,nil)
    return dest
   end)
   if list then
    for i=1,math.min(#list,MAX_SCAN)do
     local ok,matched=pcall(track,list[i],'owner-scan:'..source.label)
     if ok and matched then count=count+1 end
    end
   elseif #warnings<5 then warnings[#warnings+1]=source.label..': '..tostring(err) end
   local hands,herr=safe(function()
    local dest=lektor.new('hand')
    own:getOwnedBuildingsH(dest)
    return dest
   end)
   if hands then
    for i=1,math.min(#hands,MAX_SCAN)do
     local b=safe(function()return hands[i]:getBuilding()end)
     if b then
      local ok,matched=pcall(track,b,'owner-handle:'..source.label)
      if ok and matched then count=count+1 end
     end
    end
   elseif #warnings<5 then warnings[#warnings+1]=source.label..': '..tostring(herr) end
  end
 end
 table.sort(state.order,function(a,b)
  local x,y=state.tracked[a],state.tracked[b]
  if x.id==y.id then return a<b end
  return x.id<y.id
 end)
 local out={'OWN_SCAN matched='..count..' unique_tracked='..#state.order..' read_only=true; no_spawn'}
 for _,v in ipairs(warnings)do out[#out+1]='OWN_SCAN_WARNING '..v end
 return join(out)
end)
API.list = call('list', function()
    local lines = {'Tracked KenshiShop buildings: '..#state.order}
    for i, key in ipairs(state.order) do
        if i>40 then lines[#lines+1]='...remaining entries hidden';break end
        local x=state.tracked[key]
        local b = safe(function() return x.handle:getBuilding() end)
        lines[#lines+1]=string.format('%d) %s [%s] SID=%s',
            i, tostring(Layouts[x.id] and Layouts[x.id].name or x.id), b and 'loaded' or 'unloaded', x.id)
    end
    if #state.order==0 then lines[#lines+1]='Run KS.scan()' end
    return join(lines)
end)
API.inspect = call('inspect', function(n)
    local b, err = resolve(n)
    if not b then return err end
    return join(details(b))
end)
API.records = call('records', function(n)
    local b, err = resolve(n)
    if not b then return err end
    return join(recordsFor(b))
end)
API.floors = call('floors', function(n)
    local b, err = resolve(n)
    if not b then return err end
    return join(floorInfo(b))
end)
API.preflight = call('preflight', function(n)
    local b, err = resolve(n)
    if not b then return err end
    local id = shopID(b)
    local layout = Layouts[id]
    local w = getGameWorld()
    local lines = {
        'PREFLIGHT READ-ONLY',
        'shop='..tostring(layout and layout.name)..' expectedFurniture='..tostring(layout and #layout.objects),
        'factoryPresent='..tostring(w and w.theFactory~=nil)..' gamedataPresent='..tostring(w and w.gamedata~=nil),
    }
    for _, x in ipairs(details(b)) do lines[#lines+1]=x end
    local ok, Interiors = pcall(require, 'Interiors')
    if ok and Interiors.getAttempt then
        local a, e = safe(function() return Interiors.getAttempt(b) end)
        lines[#lines+1] = a and ('attempt='..tostring(a.status)..' placed='..tostring(a.placed)..' failed='..tostring(a.failed)..' corrected='..tostring(a.corrected)..' unresolved='..tostring(a.unresolved)..' floorFixed='..tostring(a.floorFixed)..' floorUnresolved='..tostring(a.floorUnresolved)) or ('attempt=none this session '..tostring(e or ''))
    else lines[#lines+1]='Interiors unavailable: '..tostring(Interiors) end
    for _, x in ipairs(recordsFor(b)) do lines[#lines+1]=x end
    for _, x in ipairs(floorInfo(b)) do lines[#lines+1]=x end
    lines[#lines+1]='No objects created. interiorChildren excludes some exterior furniture.'
    return join(lines)
end)
-- Read-only inspection of furniture already present on the parent building.
-- Does not attempt to relocate old furniture or search/destroy other objects.
API.mounted = call('mounted', function(n)
    local b,err=resolve(n)
    if not b then return err end
    local parentPos=b:getPosition()
    local list=lektor.new('Building*')
    local total=b:getMountedBuildings(list)
    local lines={string.format('MOUNTED READ-ONLY parentY=%.3f reported=%s list=%d',
        parentPos.y,tostring(total),#list)}
    for i=1,math.min(#list,8) do
        local child=list[i]
        local ok,pos=pcall(function() return child:getPosition() end)
        local id=child and child:getGameData()
        lines[#lines+1]=string.format('%d) sid=%s posY=%s deltaFromParent=%s',
            i,tostring(id and id.stringID),ok and string.format('%.3f',pos.y) or 'ERROR',
            ok and string.format('%.3f',pos.y-parentPos.y) or 'ERROR')
    end
    lines[#lines+1]='Existing objects are unchanged. For correction, load a save BEFORE construction.'
    return join(lines)
end)

-- Manual one-shot inspection and repair of already built interiors.
API.floorAudit = call('floorAudit', function(n)
    local b,err=resolve(n)
    if not b then return err end
    local FloorDiagnostics=require('FloorDiagnostics')
    return FloorDiagnostics.audit(b)
end)
API.roofAudit = call('roofAudit',function(n)
    local b,err=resolve(n)
    if not b then return err end
    return require('RoofDiagnostics').audit(b)
end)
API.lookup = call('lookup', function(id)
    if type(id)~='string' or #id<1 or #id>160 then return 'Usage: KS.lookup("100-KenshiShop.mod")' end
    local w=getGameWorld()
    if not w or not w.gamedata then return 'GameData unavailable' end
    local d,err=safe(function() return w.gamedata:getData(id,0) end)
    if not d then return 'LOOKUP MISSING '..id..' '..tostring(err or '') end
    local name=safe(function() return d.name end)
    return 'LOOKUP FOUND '..id..' name='..tostring(name)
end)
API.barFurnitureCatalog = call('barFurnitureCatalog',function()
 local layout=require('Core.Bar.Building.FurnitureData')
 local policy=require('Core.Bar.Building.OwnerPolicy')
 local w=getGameWorld()
 if not w or not w.gamedata then return 'BAR_FURN_CATALOG_GAME_DATA_UNAVAILABLE' end
 local plan,planError=policy.plan(layout,w.gamedata)
 if not plan then return 'BAR_FURN_PLAN_ERROR '..tostring(planError) end
 local byID={}
 local order={}
 for i,item in ipairs(layout.objects)do
  local entry=byID[item.id]
  if not entry then
   local data=safe(function()return w.gamedata:getData(item.id,0)end)
   local owner,source,name=policy.classify(item,data)
   entry={id=item.id,owner=owner,source=source,name=name,count=0,indices={}}
   byID[item.id]=entry;order[#order+1]=entry
  end
  entry.count=entry.count+1
  entry.indices[#entry.indices+1]=i
  entry.players=(entry.players or 0)+(plan.owners[i]=='PLAYER' and 1 or 0)
  entry.npcs=(entry.npcs or 0)+(plan.owners[i]=='NPC' and 1 or 0)
 end
 local lines={'BAR_FURN_CATALOG READ-ONLY unique='..#order..' total='..#layout.objects
  ..' shared='..plan.sharedTotal..' shared_player='..plan.sharedPlayer..' shared_npc='..plan.sharedNPC}
 for _,entry in ipairs(order)do
  lines[#lines+1]=entry.id..' count='..entry.count..' PLAYER='..entry.players..' NPC='..entry.npcs..' group='..entry.owner
   ..' source='..entry.source..' name='..tostring(entry.name)
   ..' indices='..table.concat(entry.indices,',')
 end
 return join(lines)
end)
API.barFurnitureLive = call('barFurnitureLive',function(n)
 local b,err=resolve(n)
 if not b then return err end
 if shopID(b)~='100-KenshiShop.mod' then return 'NOT_BAR' end
 local live=require('Core.Bar.Building.LiveFurniture')
 local status=live.status(b)
 local ok,report=require('Core.Ownership.Furniture').auditBar(b)
 return 'BAR_FURN_LIVE '..status..' | audit='..(ok and 'PASS' or 'INCOMPLETE')..' '..tostring(report)..' READ_ONLY'
end)
API.barSplitRepair = call('barSplitRepair',function(n)
 local b,err=resolve(n)
 if not b then return err end
 if shopID(b)~='100-KenshiShop.mod' then return 'NOT_BAR' end
 local success,detail=require('Core.Bar.Building.FurnitureRestore').apply(b,'MANUAL_ONCE')
 return 'BAR_SPLIT_MANUAL '..(success and 'PASS ' or 'FAILED ')..tostring(detail)
end)
API.shopFurnitureAudit = call('shopFurnitureAudit',function(n)
 local b,err=resolve(n)
 if not b then return err end
 if shopID(b)=='100-KenshiShop.mod' then
  local ok,report=require('Core.Ownership.Furniture').auditBar(b)
  return 'SHOP_FURN_AUDIT bar '..(ok and 'PASS ' or 'INCOMPLETE ')..tostring(report)
 end
 local ok,report=require('Core.Ownership.Furniture').auditAllNPC(b)
 return 'SHOP_FURN_AUDIT '..(ok and 'PASS ' or 'INCOMPLETE ')..tostring(report)
end)
API.shopFurnitureRepair = call('shopFurnitureRepair',function(n)
 local b,err=resolve(n)
 if not b then return err end
 if shopID(b)=='100-KenshiShop.mod' then return 'BAR_SPECIAL_POLICY: use KS.barSplitRepair(n)' end
 local ok,report=require('Core.Ownership.NPCFurnitureRestore').apply(b,'MANUAL_SINGLE')
 return 'SHOP_FURN_REPAIR '..(ok and 'PASS ' or 'FAILED ')..tostring(report)
end)
API.selftest = call('selftest', function()
    local lines={'SELFTEST READ-ONLY'}
    local ok, FloorPlan = pcall(require, 'FloorPlan')
    local assignmentOK, FloorAssignment = pcall(require,'FloorAssignment')
    local transformOK, Transform = pcall(require, 'Transform')
    local w = getGameWorld()
    local gd = w and w.gamedata
    local ids = {}
    for id in pairs(EXPECTED) do ids[#ids+1]=id end
    table.sort(ids)
    local total, failures = 0, 0
    for _,id in ipairs(ids) do
        local layout = Layouts[id]
        local count = layout and #layout.objects or 0
        total = total+count
        if count~=EXPECTED[id] then failures=failures+1 end
        local floor, ferr = nil, nil
        if ok then floor,ferr = safe(function() return FloorPlan.forShop(id) end) end
        if not floor or #floor~=count then failures=failures+1 end
        local fcs = 'WORLD_UNAVAILABLE'
        if gd then
            local record = safe(function() return gd:getData(id,0) end)
            fcs=record and 'FOUND' or 'MISSING'
            if not record then failures=failures+1 end
        end
        lines[#lines+1] = string.format('%s layout=%d/%d floors=%s FCS=%s',
            id,count,EXPECTED[id],tostring(floor~=nil),fcs)
        if ferr then lines[#lines+1]='FloorPlan error '..tostring(ferr) end
    end
    if total~=291 then failures=failures+1 end
    if not assignmentOK or FloorAssignment.validate()~=352 then failures=failures+1 end
    lines[#lines+1]='FloorAssignment='..tostring(assignmentOK)
    if transformOK and Layouts['100-KenshiShop.mod'] then
        local item = Layouts['100-KenshiShop.mod'].objects[1]
        local identityOK = pcall(function()
            local p,q = Transform.world({x=0,y=0,z=0},{w=1,x=0,y=0,z=0},1,item)
            assert(p.x==item.p[1] and p.y==item.p[2] and p.z==item.p[3])
            assert(type(q.w)=='number')
        end)
        if not identityOK then failures=failures+1 end
        lines[#lines+1]='Transform identity='..tostring(identityOK)
    else failures=failures+1; lines[#lines+1]='Transform unavailable' end
    -- Validate the NEW split FCS templates and saved/live squads independently.
    -- No spawning, AI changes, NPC movement, or automatic scanning of unrelated shops.
    local splitOK,Split=pcall(require,'Core.NPC.SplitAudit')
    if splitOK then
        local fcsOK,fcsPass=Split.templates(w)
        lines[#lines+1]=fcsOK
        if fcsPass==false then failures=failures+1 end
        local tested,passed,unverified=0,0,0
        for _,key in ipairs(state.order) do
            local entry=state.tracked[key]
            if entry then
                local b=safe(function()return entry.handle:getBuilding()end)
                if b and Split.isSplitShop(b) then
                    local report,code=Split.check(b)
                    tested=tested+1
                    if code=='PASS' then passed=passed+1
                    else unverified=unverified+1 end
                    lines[#lines+1]=report
                end
            end
        end
        lines[#lines+1]=string.format('SPLIT_LIVE tested=%d pass=%d unverified=%d',tested,passed,unverified)
        if tested==0 then lines[#lines+1]='SPLIT_LIVE NOT_TESTED: KS.ownerScan(); KS.npcSplitReport()' end
    else
        failures=failures+1
        lines[#lines+1]='SPLIT_DIAGNOSTICS_MODULE_ERROR '..tostring(Split)
    end
    lines[#lines+1] = string.format('SELFTEST_RESULT furniture=%d expectedFurniture=291 failures=%d',total,failures)
    return join(lines)
end)
-- Explicit one-shot manual trigger for EXISTING furnished shops. By default only a new
-- construction success automatically launches NPCs. Never retries a role in one game session.
API.npcCheck = call('npcCheck', function(n)
 local b,err=resolve(n)
 if not b then return err end
 local shop=require('Core.Registry').byBuilding(b)
 return shop and ('NPC_CHECK '..shop.name..': '..shop.npcCheck(b)) or 'NO_SHOP_MODULE'
end)
API.npcStart = call('npcStart', function(n)
 local b,err=resolve(n)
 if not b then return err end
 local Registry=require('Core.Registry')
 local shop=Registry.byBuilding(b)
 if not shop then return 'NO_SHOP_MODULE' end
 if b:getNumInternalBuildings()~=shop.interior.expectedInternalCount() then
  return 'NPC_START_BLOCKED: interior count differs (legacy or incomplete); no changes made'
 end
 return 'NPC_START '..shop.name..': '..shop.npcStart(b)
end)
API.npcStatus = call('npcStatus', function(n)
 local b,err=resolve(n)
 if not b then return err end
 local shop=require('Core.Registry').byBuilding(b)
 return shop and ('NPC_STATUS '..shop.name..': '..shop.npcStatus(b)) or 'NO_SHOP_MODULE'
end)
API.npcResume = call('npcResume', function(n)
 local b,err=resolve(n)
 if not b then return err end
 local shop=require('Core.Registry').byBuilding(b)
 return shop and ('NPC_RESUME '..shop.name..': '..shop.npcResume(b)) or 'NO_SHOP_MODULE'
end)
API.npcReport = call('npcReport',function()
 local Registry=require('Core.Registry')
 local lines={'NPC_REPORT '..API.version,'Read-only live buildings. Saved NPCs are re-attached without respawning.'}
 local unloaded,visible=0,0
 for i,key in ipairs(state.order) do
  local entry=state.tracked[key]
  local b=safe(function()return entry.handle:getBuilding()end)
  if b then
   local shop=Registry.byBuilding(b)
   if shop then
    visible=visible+1
    lines[#lines+1]=i..' '..shop.name..' '..shop.npcStatus(b)
   end
  else unloaded=unloaded+1 end
 end
 lines[#lines+1]='SUMMARY visible='..visible..' unloaded_skipped='..unloaded..' session_entries='..#state.order
 if visible==0 then lines[#lines+1]='NO_LOADED_SHOPS; KS.scan() refreshes player-owned buildings read-only' end
 return join(lines)
end)
API.npcSplitCheck = call('npcSplitCheck',function(n)
 local b,err=resolve(n)
 if not b then return err end
 return require('Core.NPC.SplitAudit').check(b)
end)
API.npcSplitReport = call('npcSplitReport',function()
 local split=require('Core.NPC.SplitAudit')
 local lines={'SPLIT_REPORT '..API.version..' READ_ONLY'}
 local tested,passed=0,0
 for _,key in ipairs(state.order)do
  local entry=state.tracked[key]
  if entry then
   local b=safe(function()return entry.handle:getBuilding()end)
   if b and split.isSplitShop(b) then
    tested=tested+1
    local info,code=split.check(b)
    if code=='PASS' then passed=passed+1 end
    lines[#lines+1]=info
   end
  end
 end
 lines[#lines+1]='SPLIT_SUMMARY loaded='..tested..' verified='..passed..' pending_or_unverified='..(tested-passed)
 if tested==0 then lines[#lines+1]='NO_LOADED_SPLIT_SHOPS; KS.ownerScan(); KS.list()' end
 return join(lines)
end)
API.npcLogs = call('npcLogs',function(n)
 local out=Log.historyNPC(n)
 if #out==0 then return 'NPC_LOG_EMPTY (events are emitted automatically on actual transitions)' end
 return join(out)
end)
-- Test commands are read-only, besides one-shot test start markers in the log.
-- Test 1 baseline must be captured before construction; test 2 snapshots are
-- compared using the uploaded KenshiLua logs across process restarts.
API.ownerTest1Start = call('ownerTest1Start',function()
 return require('Core.Ownership.ShopTests').start(state,API.ownerScan)
end)
API.ownerTest1Report = call('ownerTest1Report',function()
 return require('Core.Ownership.ShopTests').report1(state,API.ownerScan)
end)
API.ownerTest2Before = call('ownerTest2Before',function()
 return require('Core.Ownership.ShopTests').before(state,API.ownerScan)
end)
API.ownerTest2After = call('ownerTest2After',function(roboticsKey,barKey)
 return require('Core.Ownership.ShopTests').after(state,API.ownerScan,roboticsKey,barKey)
end)
API.ownerAudit = call('ownerAudit',function(n)
 local b,err=resolve(n)
 if not b then return err end
 local shop=require('Core.Registry').byBuilding(b)
 if not shop then return 'NO_SHOP_MODULE' end
 return require('Core.Ownership.Registry').audit(shop.name,b)
end)
API.ownerReport = call('ownerReport',function()
 local reg=require('Core.Ownership.Registry')
 local shops=require('Core.Registry')
 local out={'OWN_REPORT '..API.version..' | read-only; NO NPC respawns'}
 for i,key in ipairs(state.order)do
  local entry=state.tracked[key]
  local b=entry and safe(function()return entry.handle:getBuilding()end)
  if b then
   local shop=shops.byBuilding(b)
   out[#out+1]=i..' '..(shop and reg.audit(shop.name,b) or 'SHOP_UNKNOWN')
  else out[#out+1]=i..' BUILDING_UNLOADED key='..key end
 end
 if #state.order==0 then out[#out+1]='NO_SHOPS_TRACKED (building events or KS.scan() required)' end
 return join(out)
end)
API.ownerLogs = call('ownerLogs',function(n)
 local out=require('Core.Ownership.Registry').logs(n)
 if #out==0 then return 'OWN_LOGS_EMPTY' end
 return join(out)
end)
-- Engineering-only manual savegame recovery test. No changes to normal NPC controllers.
local function existingEngineering(n)
 if n~=nil then
  local b,err=resolve(n)
  if not b then return nil,err end
  if shopID(b)~='101-KenshiShop.mod' then return nil,'INDEX_IS_NOT_ENGINEERING' end
  return b
 end
 local matches={}
 local function collect()
  for _,key in ipairs(state.order) do
   local entry=state.tracked[key]
   if entry and entry.id=='101-KenshiShop.mod' then
    local b=safe(function()return entry.handle:getBuilding() end)
    if b and b:isValid() then matches[#matches+1]=b end
   end
  end
 end
 collect()
 if #matches==0 then
  API.ownerScan() -- read-only discovery; includes shops now owned by NPC factions
  collect()
 end
 if #matches==0 then return nil,'ENGINEERING_NOT_FOUND: KS.ownerScan(); KS.list()' end
 if #matches>1 then return nil,'MULTIPLE_ENGINEERING_BUILDINGS: specify index from KS.list()' end
 return matches[1]
end
API.recoveryCheck = call('recoveryCheck',function(n)
 local b,err=existingEngineering(n)
 if not b then return 'RECOVERY_CHECK_REFUSED '..tostring(err) end
 return require('Core.Engineering.NPC.RecoveryTest').check(b)
end)
API.recoveryStart = call('recoveryStart',function(n)
 -- The old manual controller would race the integrated delivery controller.
 -- Keep the console name for compatibility, but never run two movement controllers.
 return 'RECOVERY_START_DISABLED alpha.28 integrated recovery active; use KS.npcReport(), KS.npcLogs(120)'
end)
API.recoveryStatus = call('recoveryStatus',function()
 return require('Core.Engineering.NPC.RecoveryTest').status()
end)
API.recoveryLogs = call('recoveryLogs',function(n)
 return require('Core.Engineering.NPC.RecoveryTest').history(n)
end)
API.recoveryCancel = call('recoveryCancel',function()
 return require('Core.Engineering.NPC.RecoveryTest').cancel()
end)
API.logs = call('logs', function(n)
    local limit = tonumber(n) or 30
    limit = math.max(1,math.min(50,math.floor(limit)))
    return join(Log.history(limit))
end)
function API.setCoreStatus(value, err)
    state.core = tostring(value)
    state.coreError = err and tostring(err) or nil
end
function API.start()
    -- The only UI is KenshiLua's own Console. Explicit _G is mandatory for
    -- KenshiLua mod-script sandbox -> global console visibility.
    _G.KS = API
    _G.KenshiShopDebug = API
    if state.started then return true end
    state.started = true
    if Events and type(Events.on)=='function' then
        for _, info in ipairs({
            {'Building::_NV_notifyConstructionComplete','construction'},
            {'Building::_NV_onBuildingLoaded','loaded'},
        }) do
            local ok, token = pcall(Events.on, info[1], function(b) observe(b,info[2]) end)
            if ok then state.hooks[#state.hooks+1]=token
            else Log.error('CONSOLE_OBSERVER_REGISTRATION '..info[1]..' '..tostring(token)) end
        end
    else
        Log.error('CONSOLE_NO_EVENTS_API')
    end
    Log.info('KenshiLua console API ready: KS.help() | KS.status() | KS.scan()')
    return true
end
return API
