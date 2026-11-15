-- Native NPC origin, separate from the player outpost where the squad serves.
-- No dependency on Transport/LiveState: Transport uses this before spawning.
local M={}
function M.field(o,k)
 local ok,v=pcall(function()return o[k]end)
 if ok then return v end
end
function M.call(o,k,...)
 local fn=M.field(o,k)
 if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,o,...)
 if ok then return v end
end
function M.handleID(h)
 if not h or M.call(h,'isNull')==true then return nil end
 return M.call(h,'toString')
end
function M.id(o)return M.handleID(M.call(o,'getHandle'))end
function M.npc(t)
 if not M.id(t) or M.call(t,'isValid')~=true then return false end
 local f=M.call(t,'getFaction')
 local kind=M.field(t,'townType')
 return M.call(f,'isThePlayer')==false and (kind==1 or kind==2 or kind==3)
end
function M.select(faction,position,existing)
 if M.npc(existing) then return existing,'SAVED_ORIGIN' end
 local ok,king=pcall(function()return getSharedKing()end)
 local towns=ok and M.call(M.field(king,'townList'),'getAllTowns')
 if not towns then return nil,'ORIGIN_TOWN_LIST_UNAVAILABLE' end
 local best,bestRank,bestDistance,bestID
 local success,err=pcall(function()
  assert(position and type(position.x)=='number' and type(position.z)=='number','ORIGIN_POSITION_INVALID')
  assert(#towns<=12000,'ORIGIN_SCAN_LIMIT')
  for i=1,#towns do
   -- getAllTowns returns RootObject*, so recover the TownBase Lua binding.
   local h=M.call(towns[i],'getHandle')
   local t=M.handleID(h) and M.call(h,'getTown')
   if M.npc(t) then
    local f=M.call(t,'getFaction')
    local enemy=M.call(M.field(faction,'relations'),'isEnemy',f)
    local reverse=M.call(M.field(f,'relations'),'isEnemy',faction)
    local pos=M.call(t,'getPosition')
    if M.call(f,'isNotARealFaction')==false and enemy==false and reverse==false
      and pos and type(pos.x)=='number' and type(pos.z)=='number' then
     local own=M.field(M.call(f,'getData'),'stringID')==M.field(M.call(faction,'getData'),'stringID')
     local rank=own and 0 or 1
     local d=(pos.x-position.x)^2+(pos.z-position.z)^2
     local id=M.id(t)
     if d==d and d<math.huge and (not best or rank<bestRank
       or (rank==bestRank and (d<bestDistance or (d==bestDistance and id<bestID)))) then
      best,bestRank,bestDistance,bestID=t,rank,d,id
     end
    end
   end
  end
 end)
 if not success then return nil,tostring(err) end
 return best,best and 'REAL_NPC_TOWN' or 'NO_NONHOSTILE_NPC_ORIGIN'
end
function M.assign(owns,preferred,kind)
 local current=M.field(owns,'_homeTown')
 local origin=M.npc(current) and current or preferred
 assert(M.npc(origin),'NPC_ORIGIN_INVALID')
 local id=M.id(origin)
 if M.id(current)~=id then owns:setHomeTown(origin,kind)end
 assert(M.id(M.field(owns,'_homeTown'))==id,'NPC_ORIGIN_NOT_APPLIED expected='..id)
 return origin
end
return M
