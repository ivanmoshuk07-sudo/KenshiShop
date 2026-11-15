-- Bounded observations of native work. Never issue a movement/job order here.
local Live=require('Core.NPC.LiveState')
local O=require('Core.NPC.OriginTown')
local Log=require('Diagnostics')
local Nodes=require('Core.NPC.NativeNodes')
local M={}
local function task(c)
 local g=Live.call(Live.call(c,'getOrdersReciever'),'getCurrentGoal')
 return Live.call(g,'key'),O.field(g,'priority')
end
function M.probe(s,c,key)
 local active,priority=task(c)
 local row={active=active,priority=priority,home=O.handleID(O.field(Live.call(c,'getStateBroadcast'),'homeBuilding'))}
 if s.cfg.role=='patrol' then
  local hour=type(s.now)=='number' and s.now/60%24
  row.expected=hour and (hour<6 or hour>=23) and 51 or (key==s.work.leader and 36 or 141)
  row.result=row.expected==51 and 'PATROL_NIGHT_POST' or 'NATIVE_PATROL_OR_FOLLOW';return row
 end
 row.expected=({trader=20,guard=268,chief=38})[s.cfg.role]
 local held,why=Live.halted(c)
 if held then row.result='DEFER_'..tostring(why);return row end
 if ({[25]=true,[57]=true,[58]=true,[60]=true,[70]=true,[99]=true,[100]=true,[105]=true,[106]=true,[142]=true,[148]=true})[active] then
  row.result='NATIVE_CARE';return row
 end
 local hour=type(s.now)=='number' and s.now/60%24
 if s.cfg.role=='trader' and s.cfg.shop~='bar' and s.cfg.shop~='robotics'
   and hour and (hour<6 or hour>=23)then row.result='OFF_SHIFT';return row end
 if row.home~=s.key then row.result='BROADCAST_HOME_MISMATCH';return row end
 local duty=s.postDuty and s.postDuty.members and s.postDuty.members[key]
 if active==51 and duty and duty.node then
  row.expected=51
  local goal=Live.call(Live.call(c,'getOrdersReciever'),'getCurrentGoal')
  row.post=O.handleID(O.field(goal,'subject'))
  row.result=row.post==O.handleID(duty.node.handle) and 'ASSIGNED_POST_ACTIVE' or 'ASSIGNED_POST_SUBJECT_MISMATCH'
  local root=Live.call(O.field(goal,'subject'),'getRootObjectBase')
  row.floor=Live.call(root,'getFloor');row.layoutFloor=duty.node.floor;row.floorMatch=row.floor==row.layoutFloor
  row.geometry=duty.node.outside and 'NATIVE_DOOR_POST' or 'EXPLICIT_NATIVE_POST'
  return row
 end
 local method=({trader='findShopkeeperNode',guard='findGuardNodeForBuilding_indoorOnly',chief='findGuardNodeForBuilding_inOrOut'})[s.cfg.role]
 local ai=Live.call(c,'getAI');local fn=O.field(ai,method)
 if type(fn)~='function' then row.result='FINDER_API_UNAVAILABLE';return row end
 -- The binding returns BOTH score and an output hand. In the supplied native
 -- code Shopkeeper can return score=1 even when the node hand is null.
 local ok,score,h=pcall(fn,ai,c:getHandle(),true)
 row.finder=method
 if not ok then row.result='FINDER_ERROR';row.error=tostring(score);return row end
 row.score=score;row.post=O.handleID(h)
 row.result=row.post and 'POST_FOUND' or 'NO_SELECTABLE_POST'
 if row.post then
  local root=Live.call(h,'getRootObjectBase')
  local pos=Live.call(root,'getPosition')
  if not pos or type(pos.x)~='number' or type(pos.y)~='number' or type(pos.z)~='number' then
   row.geometry='POSITION_UNAVAILABLE'
  elseif not s.building or type(Nodes.nearest)~='function' then row.geometry='LAYOUT_UNAVAILABLE'
  else
   local yes,entry,error=pcall(Nodes.nearest,s,s.building,pos)
   row.distance=yes and error or nil
   row.geometry=yes and entry and (error<=0.75 and 'MATCH' or 'OUTSIDE_LAYOUT') or 'CHECK_UNAVAILABLE'
   row.floor=Live.call(root,'getFloor');row.layoutFloor=yes and entry and entry.floor or nil
   if row.floor~=nil and row.layoutFloor~=nil then row.floorMatch=row.floor==row.layoutFloor end
   row.position=string.format('%.2f,%.2f,%.2f',pos.x,pos.y,pos.z)
  end
 end
 return row
end
function M.observe(s,ms)
 if not s.work or not s.work.done then return end
 local a=s.work.postAudit or {count=0,nextAt=0};s.work.postAudit=a
 local now=type(s.now)=='number' and s.now or 0
 if a.count>=3 or now<a.nextAt then return end
 a.count=a.count+1;a.nextAt=now+2;a.rows={}
 for _,m in ipairs(ms)do
  local ok,row=pcall(M.probe,s,m.char,m.key)
  if not ok then row={result='AUDIT_ERROR',error=tostring(row)} end
  a.rows[m.key]=row
  Log.console('NPC_WORK_AUDIT90 shop='..s.cfg.shop..' role='..s.cfg.role..' member='..m.key
   ..' observation='..a.count..'/3 expected='..tostring(row.expected)..' active='..tostring(row.active)..' priority='..tostring(row.priority)
   ..' result='..row.result..' finder='..tostring(row.finder)..' score='..tostring(row.score)
   ..' post='..tostring(row.post)..' home='..tostring(row.home)
   ..' geometry='..tostring(row.geometry)..' error_distance='..tostring(row.distance)
   ..' position='..tostring(row.position)..' floor='..tostring(row.floor)..' layout_floor='..tostring(row.layoutFloor)
   ..' floor_match='..tostring(row.floorMatch)..' error='..tostring(row.error or 'NONE'))
 end
end
return M
