-- KenshiShop alpha.29: ownership of EXISTING shop furniture only.
-- Never creates, deletes, moves or re-furnishes objects. Bounded one-shot audit.
local Layouts=require('Layouts')
local Transform=require('Transform')
local M={}
local MAX_FACTION_BUILDINGS=2500
local MAX_CANDIDATES=4000
local MATCH_RADIUS=4.0 -- position + exact template, plus parent link for inside furniture
local function call(obj,method,...)
 if not obj then return nil end
 local ok,fn=pcall(function() return obj[method] end)
 if not ok or type(fn)~='function' then return nil end
 local good,val=pcall(fn,obj,...)
 if good then return val end
 return nil
end
local function id(b)
 local d=call(b,'getGameData')
 local ok,v=pcall(function()return d and d.stringID end)
 return ok and v and tostring(v) or nil
end
local function key(b)
 local h=call(b,'getHandle')
 return h and call(h,'toString') or nil
end
local function factionID(b)
 local f=call(b,'getFaction')
 local d=f and call(f,'getData')
 local ok,v=pcall(function()return d and d.stringID end)
 return ok and v and tostring(v) or nil
end
local function collect(faction,list,seen)
 if not faction then return false,'FACTION_UNAVAILABLE' end
 local owned=faction.factionOwnerships
 if not owned then return false,'OWNERSHIP_COLLECTION_UNAVAILABLE' end
 if not lektor or type(lektor.new)~='function' then return false,'LEKTOR_UNAVAILABLE' end
 local arr=lektor.new('Building*')
 local ok,err=pcall(owned.getOwnedBuildingPtrs,owned,arr,nil)
 if not ok then return false,'OWNED_BUILDINGS_ERROR '..tostring(err) end
 if #arr>MAX_FACTION_BUILDINGS then return false,'FACTION_BUILDING_CAP '..#arr end
 for i=1,#arr do
  local b=arr[i]
  if b then
   local k=key(b)
   if k and not seen[k] then
    seen[k]=true;list[#list+1]=b
    if #list>MAX_CANDIDATES then return false,'TOTAL_BUILDING_CAP' end
   end
  end
 end
 -- Some KenshiLua builds expose saved interiors only through ownership handles.
 -- Read handles as a SECOND source, resolve only valid native buildings.
 local fn=owned.getOwnedBuildingsH
 if type(fn)=='function' then
  local hs=lektor.new('hand')
  local good=pcall(fn,owned,hs)
  if good and #hs<=MAX_FACTION_BUILDINGS then
   for i=1,#hs do
    local b=call(hs[i],'getBuilding')
    local k=b and key(b)
    if k and not seen[k] then
     seen[k]=true;list[#list+1]=b
     if #list>MAX_CANDIDATES then return false,'TOTAL_BUILDING_CAP' end
    end
   end
  end
 end
 return true
end
-- Parent-scoped, read-only native enumeration. factionOwnerships alone may exclude
-- interior furniture even when getNumInternalBuildings() reports >0.
-- getMountedBuildings is documented in KenshiLib, but its Lua binding can vary.
local function collectMounted(parent,list,seen,mounted)
 local fn=nil
 local ok=pcall(function() fn=parent.getMountedBuildings end)
 if not ok or type(fn)~='function' then return 0,'LUA_BINDING_UNAVAILABLE' end
 if not lektor or type(lektor.new)~='function' then return 0,'LEKTOR_UNAVAILABLE' end
 local arr=lektor.new('Building*')
 local success,result=pcall(fn,parent,arr)
 if not success then return 0,'MOUNTED_CALL_ERROR '..tostring(result) end
 local count=#arr
 if count>MAX_CANDIDATES then return 0,'MOUNTED_CAP '..tostring(count) end
 for i=1,count do
  local b=arr[i]
  if b then
   local k=key(b)
   if k then
    mounted[k]=true
    if not seen[k] then
     seen[k]=true;list[#list+1]=b
     if #list>MAX_CANDIDATES then return 0,'TOTAL_BUILDING_CAP' end
    end
   end
  end
 end
 return count,'OK'
end
local function geometry(parent,layout)
 local pos=call(parent,'getPosition')
 local rot=call(parent,'getOrientation')
 local scale=call(parent,'getScale')
 if not pos or not rot or not scale then return nil,'PARENT_GEOMETRY_MISSING' end
 local wanted={}
 for i,item in ipairs(layout.objects) do
  local ok,p=pcall(Transform.world,pos,rot,scale,item)
  if not ok or not p then return nil,'FURNITURE_WORLD_POSITION_FAIL index='..i end
  wanted[#wanted+1]={index=i,id=tostring(item.id),outside=item.outside==true,pos=p}
 end
 return wanted
end
function M.run(parent,ownerFaction,ownerID,ownerPlatoon)
 local parentKey=key(parent)
 local layout=Layouts[id(parent)]
 if not layout or not parentKey then return false,'UNKNOWN_SHOP_LAYOUT' end
 if not ownerFaction or not ownerPlatoon then return false,'OWNER_NOT_READY' end
 local w=getGameWorld()
 local ui=getPlayerInterface()
 local player=ui and call(ui,'getFaction')
 if not w or not player then return false,'PLAYER_OR_WORLD_UNAVAILABLE' end
 local wanted,geoErr=geometry(parent,layout)
 if not wanted then return false,geoErr end
 local candidates,seen={},{}
 local ok,err=collect(player,candidates,seen)
 if not ok then return false,'PLAYER_'..err end
 if player~=ownerFaction then
  ok,err=collect(ownerFaction,candidates,seen)
  if not ok then return false,'NPC_'..err end
 end
 local available={}
 for _,b in ipairs(candidates)do
  if key(b)~=parentKey and call(b,'isValid')==true then
   local typ=id(b)
   if typ then
    local pos=call(b,'getPosition')
    if pos then
     local parentB=call(b,'furnitureParentBuilding')
     local linked=parentB and key(parentB) or nil
     available[#available+1]={b=b,id=typ,pos=pos,linked=linked,key=key(b)}
    end
   end
  end
 end
 -- Unique exact-layout matches, nearest first; never mutate unrelated objects.
 local possible={}
 for wi,want in ipairs(wanted)do
  for ci,c in ipairs(available)do
   if c.id==want.id and ((not want.outside and c.linked==parentKey) or (want.outside and (c.linked==parentKey or c.linked==nil))) then
    local dx,dz,dy=c.pos.x-want.pos.x,c.pos.z-want.pos.z,c.pos.y-want.pos.y
    local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
    if distance<=MATCH_RADIUS then possible[#possible+1]={wi=wi,ci=ci,dist=distance} end
   end
  end
 end
 table.sort(possible,function(a,b)return a.dist<b.dist end)
 local matched,usedW,usedC={},{},{}
 for _,m in ipairs(possible)do
  if not usedW[m.wi] and not usedC[m.ci] then
   matched[#matched+1]=m;usedW[m.wi]=true;usedC[m.ci]=true
  end
 end
 local fixed,already,failed,unmatched=0,0,0,#wanted-#matched
 local samples={}
 for _,m in ipairs(matched)do
  local b=available[m.ci].b
  local before=factionID(b)
  if before==ownerID and call(b,'isThePlayer')==false then
   already=already+1
  else
   local success,e=pcall(b.setFaction,b,ownerFaction,ownerPlatoon)
   local after=factionID(b)
   if success and after==ownerID and call(b,'isThePlayer')~=true then
    fixed=fixed+1
   else
    failed=failed+1
    if #samples<5 then samples[#samples+1]='index='..wanted[m.wi].index..' before='..tostring(before)..' after='..tostring(after)..' error='..tostring(e) end
   end
  end
 end
 local details='expected='..#wanted..' matched='..#matched..' already='..already..' transferred='..fixed..' failed='..failed..' unmatched='..unmatched
 if #samples>0 then details=details..' examples='..table.concat(samples,';') end
 return failed==0 and unmatched==0,details
end
-- Read-only bar-only load inspection. All data from native game owner lists;
-- never reassigns or creates furniture and cannot affect other shop interiors.
function M.auditBar(parent)
 if id(parent)~='100-KenshiShop.mod' then return false,'NOT_BAR' end
 local layout=Layouts[id(parent)]
 local w=getGameWorld()
 local ui=getPlayerInterface()
 local player=ui and call(ui,'getFaction')
 local npc=w and w.factionMgr and call(w.factionMgr,'getFactionByStringID','400-KenshiShop.mod')
 if not player or not npc or not w.gamedata then return false,'FACTION_OR_DATA_NOT_READY' end
 local parentKey=key(parent)
 local candidates,seen={},{}
 local ok,err=collect(player,candidates,seen)
 if not ok then return false,'PLAYER_'..err end
 if player~=npc then
  ok,err=collect(npc,candidates,seen)
  if not ok then return false,'NPC_'..err end
 end
 local countOwned=#candidates
 local mounted={}
 local countMounted,mountedStatus=collectMounted(parent,candidates,seen,mounted)
 -- Direct, exact handles of items returned by OUR factory in this session.
 -- They are not available after a full game reset; do not fake coverage then.
 local fresh,freshExpected=require('Core.Bar.Building.LiveFurniture').candidates(parent)
 for _,b in ipairs(fresh) do
  local h=key(b)
  if h and not seen[h] then seen[h]=true;candidates[#candidates+1]=b end
 end
 local parentChildCount=call(parent,'getNumInternalBuildings')
 local available={}
 for _,b in ipairs(candidates)do
  if key(b)~=parentKey and call(b,'isValid')==true then
   local typ=id(b)
   local pos=call(b,'getPosition')
   if typ and pos then
    local pb=call(b,'furnitureParentBuilding')
    available[#available+1]={b=b,id=typ,pos=pos,linked=pb and key(pb) or nil,mounted=mounted[key(b)]==true}
   end
  end
 end
 local expected,geoErr=geometry(parent,layout)
 if not expected then return false,geoErr end
 local policy=require('Core.Bar.Building.OwnerPolicy')
 local ownerPlan,planErr=policy.plan(layout,w.gamedata)
 if not ownerPlan then return false,'OWNER_PLAN '..tostring(planErr) end
 local matches={}
 local modelMatches,positionMatches,eligibleMatches=0,0,0
 -- Candidate pool comes from two independent sources: faction lists and
 -- mounted children. Never assign a foreign object solely by a loose radius.
 for wi,want in ipairs(expected)do
  local nearest,dist
  for ci,c in ipairs(available)do
   if not matches[ci] and c.id==want.id then
    modelMatches=modelMatches+1
    local dx,dy,dz=c.pos.x-want.pos.x,c.pos.y-want.pos.y,c.pos.z-want.pos.z
    local d=math.sqrt(dx*dx+dy*dy+dz*dz)
    if d<=MATCH_RADIUS then
     positionMatches=positionMatches+1
     local parentVerified=c.linked==parentKey or c.mounted
     -- When the native furniture-parent link is not exposed in Lua, only
     -- permit an exact-position fallback, never a general proximity scan.
     local exactUnlinked=c.linked==nil and d<=0.10
     if parentVerified or exactUnlinked then
      eligibleMatches=eligibleMatches+1
      if not dist or d<dist then nearest=ci;dist=d end
     end
    end
   end
  end
  if nearest then matches[nearest]=wi end
 end
 local passed,wrong,unmatched,unknown,playerItems,npcItems=0,0,0,0,0,0
 local samples={}
 local byWanted={}
 for ci,wi in pairs(matches)do byWanted[wi]=available[ci].b end
 -- Use player faction data directly; factionID() expects a Building, not Faction.
 local playerD=call(player,'getData')
 local playerStr=playerD and tostring(playerD.stringID) or nil
 for wi,want in ipairs(expected)do
  local intended=assert(ownerPlan.owners[wi])
  local record=call(w.gamedata,'getData',want.id,0)
  local _,source=policy.classify(layout.objects[wi],record)
  if source=='UNCLASSIFIED_DEFAULT_NPC' then unknown=unknown+1 end
  if intended=='PLAYER' then playerItems=playerItems+1 else npcItems=npcItems+1 end
  local b=byWanted[wi]
  if not b then
   unmatched=unmatched+1
   if #samples<6 then samples[#samples+1]='unmatched:'..wi end
  else
   local expectedID=intended=='PLAYER' and playerStr or '400-KenshiShop.mod'
   local actual=factionID(b)
   local actualPlayer=call(b,'isThePlayer')
   if actual==expectedID and actualPlayer==(intended=='PLAYER') then
    passed=passed+1
   else
    wrong=wrong+1
    if #samples<6 then samples[#samples+1]='wrong:'..wi..':'..tostring(actual)..' expected='..tostring(expectedID) end
   end
  end
 end
 local msg='expected='..#expected..' matched='..(#expected-unmatched)..' pass='..passed
  ..' wrong='..wrong..' unmatched='..unmatched
  ..' native_internal='..tostring(parentChildCount)..' owned_pool='..countOwned
  ..' mounted_pool='..tostring(countMounted)..' mounted_status='..tostring(mountedStatus)
  ..' session_handles='..tostring(freshExpected)..' session_live='..#fresh
  ..' candidates='..#available..' models='..modelMatches
  ..' in_radius='..positionMatches..' eligible='..eligibleMatches
  ..' player_items='..playerItems
  ..' npc_items='..npcItems..' shared='..ownerPlan.sharedTotal
  ..' shared_player='..ownerPlan.sharedPlayer..' shared_npc='..ownerPlan.sharedNPC..' unclassified='..unknown
 if #samples>0 then msg=msg..' samples='..table.concat(samples,',') end
 -- Expose native objects only to the bar-specific, fail-closed restoration module.
 -- No setter runs here; a repair MUST require a complete unambiguous 101-item match.
 return wrong==0 and unmatched==0,msg,byWanted,ownerPlan
end
-- Alpha.38: same exact-model/position/parent audit for all NON-BAR shops.
-- No 50/50 policy here. Every matching item should be NPC owned.
-- No changes are permitted unless the ENTIRE layout is uniquely matched.
function M.auditAllNPC(parent)
 local buildingID=id(parent)
 if buildingID=='100-KenshiShop.mod' then return false,'BAR_HAS_SPECIAL_POLICY' end
 local layout=Layouts[buildingID]
 local parentKey=key(parent)
 if not layout or not parentKey then return false,'UNKNOWN_NON_BAR_SHOP' end
 local w=getGameWorld()
 local ui=getPlayerInterface()
 local player=ui and call(ui,'getFaction')
 local npc=w and w.factionMgr and call(w.factionMgr,'getFactionByStringID','400-KenshiShop.mod')
 if not player or not npc or not w or not w.gamedata then return false,'FACTIONS_NOT_READY' end
 local wanted,err=geometry(parent,layout)
 if not wanted then return false,err end
 if #wanted>160 then return false,'LAYOUT_LIMIT' end
 local candidates,seen={},{}
 local ok,why=collect(player,candidates,seen)
 if not ok then return false,'PLAYER_'..tostring(why) end
 if player~=npc then
  ok,why=collect(npc,candidates,seen)
  if not ok then return false,'NPC_'..tostring(why) end
 end
 local ownedCount=#candidates
 local mounted={}
 local mountedCount,mountedStatus=collectMounted(parent,candidates,seen,mounted)
 local fresh,freshCount=require('Core.Ownership.NPCFurnitureHandles').candidates(parent)
 for _,b in ipairs(fresh)do
  local h=key(b)
  if h and not seen[h] then seen[h]=true;candidates[#candidates+1]=b end
 end
 if #candidates>MAX_CANDIDATES then return false,'CANDIDATE_LIMIT' end
 local available={}
 for _,b in ipairs(candidates)do
  local k=key(b)
  if k and k~=parentKey and call(b,'isValid')==true then
   local model=id(b)
   local pos=call(b,'getPosition')
   local pb=call(b,'furnitureParentBuilding')
   if model and pos then
    available[#available+1]={b=b,model=model,pos=pos,
     parent=pb and key(pb) or nil,mounted=mounted[k]==true}
   end
  end
 end
 local possible={}
 for i,want in ipairs(wanted)do
  for j,c in ipairs(available)do
   if want.id==c.model then
    local dx,dy,dz=want.pos.x-c.pos.x,want.pos.y-c.pos.y,want.pos.z-c.pos.z
    local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
    local linked=(c.parent==parentKey or c.mounted)
    -- Parentless outside objects qualify ONLY at exact predicted location.
    -- An indoor item must have a verified parent or native mounted relation.
    -- Parentless outside furniture is permitted only at exact expected location.
    if (linked and dist<=0.20) or (want.outside and c.parent==nil and dist<=0.10) then
     possible[#possible+1]={index=i,candidate=j,dist=dist}
    end
   end
  end
 end
 table.sort(possible,function(a,b)return a.dist<b.dist end)
 local objects,used={},{}
 for _,pair in ipairs(possible)do
  if not objects[pair.index] and not used[pair.candidate] then
   objects[pair.index]=available[pair.candidate].b
   used[pair.candidate]=true
  end
 end
 local matched,correct,wrong=0,0,0
 for i=1,#wanted do
  local b=objects[i]
  if b then
   matched=matched+1
   if factionID(b)=='400-KenshiShop.mod' and call(b,'isThePlayer')==false then
    correct=correct+1
   else wrong=wrong+1 end
  end
 end
 local report='shop='..tostring(buildingID)..' expected='..#wanted
  ..' matched='..matched..' correct='..correct..' wrong='..wrong
  ..' owned_pool='..ownedCount..' mounted_pool='..tostring(mountedCount)
  ..' mounted_status='..tostring(mountedStatus)
  ..' session_handles='..tostring(freshCount)..' session_live='..#fresh
  ..' candidates='..#available..' read_only=true'
 return matched==#wanted and wrong==0,report,objects,{expected=#wanted,matched=matched,wrong=wrong}
end
return M
