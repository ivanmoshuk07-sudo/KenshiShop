-- Native work observation plus infrequent native job/shift handoffs.
local Live=require('Core.NPC.LiveState')
local Audit=require('Core.NPC.PostAudit')
local PostDuty=require('Core.NPC.PostDuty')
local Care=require('Core.NPC.NativeCare')
local M={}
function M.tick(s,ms)
 Care.tick(s,ms)
 PostDuty.tick(s,ms)
 local d={members={}};s.duty=d
 for _,m in ipairs(ms)do
  local o=Live.call(m.char,'getOrdersReciever')
  local g=Live.call(o,'getCurrentGoal');local key=Live.call(g,'key')
  d.members[m.key]={state=key and ('NATIVE_TASK_'..key) or 'NATIVE_TASK_UNKNOWN'}
 end
 Audit.observe(s,ms)
 return true
end
function M.status(s)
 if not s.duty then return 'NATIVE_PENDING'end
 local counts={}
 for _,r in pairs(s.duty.members)do counts[r.state]=(counts[r.state] or 0)+1 end
 local rows={};for state,n in pairs(counts)do rows[#rows+1]=state..':'..n end;table.sort(rows)
 return table.concat(rows,',')
end
return M
