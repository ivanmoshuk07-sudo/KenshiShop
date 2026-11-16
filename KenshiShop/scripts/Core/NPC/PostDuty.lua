-- Shift/rotation changes only. A job is not reissued while travelling or
-- standing. Emergency care, combat and player/native orders defer changes.
local Jobs=require('Core.NPC.PostJobs')
local Nodes=require('Core.NPC.NativeNodes')
local Posts=require('Core.NPC.PostData')
local Live=require('Core.NPC.LiveState')
local Log=require('Diagnostics')
local Transform=require('Transform')
local M={}
function M.day(now)local h=now/60%24;return h>=6 and h<23 end
function M.candidates(shop,role,floor)
 local out={}
 for i,p in ipairs(Posts[shop] or {})do
  local kind=role=='trader' and 1 or 2
  if p.kind==kind and p.floor==floor then out[#out+1]=i end
 end
 if #out==0 and role=='trader' then
  for i,p in ipairs(Posts[shop] or {})do if p.kind==2 and p.floor==floor then out[#out+1]=i end end
 end
 return out
end
local function report(s,r,status,why)
 local text=status..':'..tostring(why)
 if r.message==text then return end;r.message=text
 Log.console('NPC_POST_DUTY90 shop='..s.cfg.shop..' role='..s.cfg.role..' building='..s.key
  ..' member='..tostring(r.member)..' hour='..string.format('%.3f',s.now/60%24)
  ..' status='..status..' detail='..tostring(why))
end
local function observe(s,r,c)
 if not r.node or not r.observeAt or s.now<r.observeAt then return end
 r.observeAt=nil
 local o=Live.call(c,'getOrdersReciever');local g=Live.call(o,'getCurrentGoal')
 local ok,subject=pcall(function()return g.subject:toString()end)
 local pos=Live.call(c,'getPosition');local target=Live.call(Live.call(r.node.handle,'getRootObjectBase'),'getPosition')
 local distance=pos and target and Transform.error(pos,target)
 local task=Live.call(g,'key');local floor=Live.call(c,'getFloor')
 local arrived=task==51 and ok and subject==r.node.handle:toString()
  and floor==r.node.floor and distance and distance<=1.5
 Log.console('NPC_POST_OBSERVE90 shop='..s.cfg.shop..' role='..s.cfg.role..' member='..r.member
  ..' hour='..string.format('%.3f',s.now/60%24)..' active='..tostring(task)
  ..' subject_match='..tostring(ok and subject==r.node.handle:toString())
  ..' npc_floor='..tostring(floor)..' target_floor='..r.node.floor
  ..' distance='..tostring(distance)..' arrived='..tostring(arrived==true))
end
function M.tick(s,ms)
 if not s.work or not s.work.done or not s.building or type(s.now)~='number' then return end
 local role=s.cfg.role
 -- Patrols retain the native route in the day; only the night shift gets
 -- personal post subjects. The leader/follower FCS goals are time-gated too.
 if role=='patrol' and s.cfg.shop~='police' then return end
 if Live.call(s.building,'isPhysical')~=true then return end
 local day=M.day(s.now)
 local patrolActive=role=='patrol' and ((s.cfg.patrolNight and not day) or (not s.cfg.patrolNight and day))
 if role=='trader' and (s.cfg.shop=='bar' or s.cfg.shop=='robotics') then return end
 local state=s.postDuty or {members={},floorByMember={},patrolSlots={}};s.postDuty=state
 state.patrolSlots=state.patrolSlots or {}
 local physical=tostring(Live.call(s.building,'getRootNode'))
 if state.physical~=physical then
  for _,r in pairs(state.members)do r.mode=nil;r.prepared=nil;r.node=nil;r.observeAt=nil;r.tries=0 end
  state.open=nil;state.physical=physical
 end
 if state.lastNow and s.now<state.lastNow then
  for _,r in pairs(state.members)do r.nextAt=s.now end
 end
 state.lastNow=s.now
 if role=='patrol' then
  local present={};for _,m in ipairs(ms)do present[m.key]=true end
  for key in pairs(state.patrolSlots)do
   if not present[key]then
    state.patrolSlots[key]=nil
    Nodes.claim(s,nil,false,{key=key})
   end
  end
 end
 if role=='trader' and state.open~=day then
  -- This is the native flag read by Building.isPublic/isAShop, not a lock
  -- order on the player's door. Stock and furniture are never modified.
  local ok,err=pcall(function()
   s.building.publicDaytime=day
   assert(s.building.publicDaytime==day,'SHOP_PUBLIC_VERIFY_FAILED')
  end)
  if ok then
   state.open=day
   report(s,state,'SHOP_SHIFT',(day and 'OPEN_06_23' or 'CLOSED_23_06')
    ..' native_public='..tostring(Live.call(s.building,'isPublic'))
    ..' native_shop='..tostring(Live.call(s.building,'isAShop')))
  else report(s,state,'SHOP_SHIFT_FAILED',err)end
 end
 local ordered={};for _,m in ipairs(ms)do ordered[#ordered+1]=m end
 table.sort(ordered,function(a,b)return a.key<b.key end)
 for rank,m in ipairs(ordered)do
  local r=state.members[m.key] or {member=m.key,index=0,tries=0};state.members[m.key]=r
  if role=='patrol' and state.patrolSlots[m.key]==nil then
   local used={};for _,slot in pairs(state.patrolSlots)do used[slot]=true end
   for slot=1,3 do if not used[slot] then state.patrolSlots[m.key]=slot;break end end
  end
  observe(s,r,m.char)
  if role=='guard' and state.floorByMember[m.key]==nil then
   -- Native names persist in the save, so a surviving second-floor guard
   -- keeps that role after reloading even when the first guard has died.
   local name=Live.call(m.char,'getName') or ''
   local saved=tonumber(name:match('^KS: Охрана %((%d+) этаж%)$'))
   state.floorByMember[m.key]=(saved==1 or saved==2) and saved-1 or (rank-1)%2
  end
  local floor=role=='guard' and state.floorByMember[m.key] or 0
  local mode=role=='guard' and ('FLOOR_'..floor) or (day and 'DAY' or 'NIGHT')
  local due=r.mode~=mode or (role=='guard' and s.now>=(r.nextAt or 0))
  if due and r.tries<3 then
   local safe,why=Jobs.safe(m.char)
   if not safe then report(s,r,'DEFER',why)
   elseif (role=='trader' and day) or patrolActive then
    local ok,err=Jobs.clear(m.char)
    if ok then
     if r.node then Nodes.claim(s,nil,false,m)end
     r.node=nil;r.mode=mode;r.tries=0
     report(s,r,role=='patrol' and (s.cfg.patrolNight and 'NATIVE_PATROL_NIGHT' or 'NATIVE_PATROL_DAY') or 'NATIVE_SHOPKEEPER',
      role=='patrol' and ('leader=36 followers=141 hours='..(s.cfg.patrolNight and '23_06' or '06_23')) or 'task=20')
    else report(s,r,'DEFER',err)end
   else
    local list=M.candidates(s.cfg.shop,role,floor)
    local nextIndex=r.index%math.max(1,#list)+1
    local outside=role=='chief' and day
    if role=='patrol' then outside=(s.cfg.streetSlotBase or 0)+(state.patrolSlots[m.key] or 0) end
    local index
    for offset=0,#list-1 do
     local candidate=(nextIndex+offset-1)%#list+1
     if Nodes.available(s,list[candidate],outside,m.key)then index=list[candidate];nextIndex=candidate;break end
    end
    if not index then report(s,r,'NO_POST','floor='..floor)
    else
     local node,err
     node,err=Nodes.target(s,s.building,ms,index,outside)
     if not node then
      if err~='WAIT_NATIVE_INTERIOR' then r.tries=r.tries+1 end
      report(s,r,'WAIT_NODE',err)
     else
      local ok,detail=Jobs.assign(m.char,node)
      if ok then
       r.mode=mode;r.index=nextIndex;r.nextAt=s.now+30;r.tries=0;r.node=node
       r.observeAt=s.now+2;Nodes.claim(s,index,outside,m)
       if role=='guard' and not r.labelled then
        local name='KS: Охрана ('..(floor+1)..' этаж)'
        local fn;pcall(function()fn=m.char.setName end)
        if type(fn)=='function' then
         local named=pcall(fn,m.char,name)
         r.labelled=named and Live.call(m.char,'getName')==name
        end
       end
       report(s,r,'JOB_ASSIGNED','task=51 priority=1 floor='..node.floor..' outside='..tostring(outside)
        ..' post='..node.handle:toString()..' next_game_minute='..r.nextAt)
      else r.tries=r.tries+1;report(s,r,'ASSIGN_FAILED',detail)end
     end
    end
   end
  end
 end
end
return M
