-- Register actual MedicalSystem instances of the 14 custom NoSever races.
-- Native hooks prevent amputation; health, prosthetics and AI are never edited.
local Live=require('Core.NPC.LiveState')
local Native=require('Core.NPC.NativeBridge')
local Log=require('Diagnostics')
local M={}
local allowed={}
for n=7101,7117 do if n<=7106 or n>=7110 then allowed[n..'-KenshiShop.mod']=true end end
local function field(o,k)local ok,v=pcall(function()return o[k]end);if ok then return v end end
function M.isProtectedRace(id)return allowed[id]==true end
local function emit(s,r,event,detail)
 Log.console('NPC_NOSEVER91_'..event..' shop='..s.cfg.shop..' role='..s.cfg.role
  ..' member='..r.member..' race='..tostring(r.race)..' '..tostring(detail or ''))
end
function M.tick(s,ms)
 s.noSever=s.noSever or {}
 for _,mate in ipairs(ms)do
  local c=mate.char;local race=field(field(Live.call(c,'getRace'),'data'),'stringID')
  if type(race)=='string' then
   local r=s.noSever[mate.key] or {member=mate.key,tries=0,amputations=0,crushes=0};s.noSever[mate.key]=r
   local med=Live.call(c,'getMedical')
   if med then
    if not M.isProtectedRace(race) then
     if r.active then Native.unprotectLimbs(med);r.active=false;emit(s,r,'REMOVED','current_race='..race)end
     r.race=race
    else
     if r.race~=race then r.race=race;r.tries=0;r.active=false end
     if r.tries<3 then
      local callOK,ok,a,cr=pcall(Native.protectLimbs,med,race)
      if not callOK or ok~=true then
       r.tries=r.tries+1
       emit(s,r,'FAILED','attempt='..r.tries..'/3 reason='..tostring(callOK and a or ok))
      else
       if not r.active then
        r.active=true
        local missing={};local names={'left_arm','right_arm','left_leg','right_leg'}
        for part=0,3 do
         local value=Live.call(med,'getLimbState',part)
         if value==1 or value==3 then missing[#missing+1]=names[part+1]end
        end
        emit(s,r,'READY','native_guard=ACTIVE existing_missing='..(#missing==0 and 'NONE' or table.concat(missing,','))..' health_writes=0 restore_existing=false')
       end
       a=tonumber(a) or 0;cr=tonumber(cr) or 0
       local now=type(s.now)=='number' and s.now or 0
       if (a>r.amputations or cr>r.crushes) and now>=(r.nextReport or 0) then
        emit(s,r,'BLOCKED','amputations='..a..' crushes='..cr)
        r.nextReport=now+10
       end
       r.amputations=a;r.crushes=cr
      end
     end
    end
   end
  end
 end
end
return M
