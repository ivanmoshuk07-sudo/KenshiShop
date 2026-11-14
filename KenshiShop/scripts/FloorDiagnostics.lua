-- KenshiShop 0.3.0-alpha.11
-- Manual-only, bounded floor inspection/repair for ALREADY BUILT shops.
-- Only furniture linked to the exact chosen parent is eligible.
-- Repair changes ONLY floor numbers, never coordinates, ownership or objects.
local Layouts=require('Layouts')
-- Read-only IDs for ignoring foreign/legacy markers during furniture diagnostics.
local LEGACY_MARKERS={['1180-gamedata.base']=true,['1184-gamedata.base']=true,['1186-gamedata.base']=true,['6700-KenshiShop.mod']=true,['6701-KenshiShop.mod']=true}
local FloorPlan=require('FloorPlan')
local FloorAssignment=require('FloorAssignment')
local Transform=require('Transform')
local M={}
local MAX_SCAN=2500
local MAX_DISTANCE=5.0
local function safe(f)
    local ok,value=pcall(f)
    if ok then return value end
    return nil
end
local function key(b) return b:getHandle():toString() end
local function distance(a,b) return Transform.error(a,b) end
local function sortByDistance(a,b)
    if a.d==b.d then
        if a.source==b.source then return a.candidate<b.candidate end
        return a.source<b.source
    end
    return a.d<b.d
end

function M.collect(parent)
    assert(parent and parent:isValid(),'Parent building invalid')
    local data=assert(parent:getGameData(),'Parent GameData unavailable')
    local sid=tostring(data.stringID)
    local layout=assert(Layouts[sid],'Not a KenshiShop building')
    local plan=assert(FloorPlan.forShop(sid),'Missing floor plan')
    local floors=parent:getNumFloors()
    local origin,rot,scale=parent:getPosition(),parent:getOrientation(),parent:getScale()
    local expected={}
    local roofExpected=0
    for i,item in ipairs(layout.objects) do
        if not item.outside then
            local pos=Transform.world(origin,rot,scale,item)
            local assigned=FloorAssignment.resolve(sid,plan[i],floors)
            expected[#expected+1]={index=i,id=item.id,pos=pos,floor=assigned.native,source=assigned.source,roof=assigned.roof}
            if assigned.roof then roofExpected=roofExpected+1 end
        end
    end
    local player=assert(getPlayerInterface(),'Player interface unavailable')
    local faction=assert(player:getFaction(),'Player faction unavailable')
    local owned=assert(faction.factionOwnerships,'Faction ownerships unavailable')
    local ptrs=lektor.new('Building*')
    owned:getOwnedBuildingPtrs(ptrs,nil)
    assert(#ptrs<=MAX_SCAN,'Owned building scan exceeds safety limit '..MAX_SCAN)
    local parentKey=key(parent)
    local candidates={}
    local nodeCandidates=0
    for i=1,#ptrs do
        local b=ptrs[i]
        if b then
            local linked=safe(function() return b:furnitureParentBuilding() end)
            if linked and safe(function() return key(linked) end)==parentKey then
                local gd=safe(function() return b:getGameData() end)
                local pos=safe(function() return b:getPosition() end)
                if gd and pos and LEGACY_MARKERS[tostring(gd.stringID)] then
                    nodeCandidates=nodeCandidates+1
                elseif gd and pos then
                    candidates[#candidates+1]={building=b,id=tostring(gd.stringID),pos=pos,
                        floor=safe(function() return b:getFloor() end),
                        outside=safe(function() return b:getIsOutsideFurniture() end)}
                end
            end
        end
    end
    local pairsByDistance={}
    for i,x in ipairs(expected) do
        for j,y in ipairs(candidates) do
            if x.id==y.id then
                local d=distance(x.pos,y.pos)
                if d<=MAX_DISTANCE then
                    pairsByDistance[#pairsByDistance+1]={source=i,candidate=j,d=d}
                end
            end
        end
    end
    table.sort(pairsByDistance,sortByDistance)
    local usedSource,usedCandidate,matches={}, {}, {}
    for _,pair in ipairs(pairsByDistance) do
        if not usedSource[pair.source] and not usedCandidate[pair.candidate] then
            usedSource[pair.source]=true
            usedCandidate[pair.candidate]=true
            local x,y=expected[pair.source],candidates[pair.candidate]
            matches[#matches+1]={source=x,candidate=y,distance=pair.d,
                mismatch=y.floor~=x.floor}
        end
    end
    table.sort(matches,function(a,b) return a.source.index<b.source.index end)
    local mismatch=0
    local byFloor={}
    local examples={}
    for _,m in ipairs(matches) do
        if m.mismatch then
            mismatch=mismatch+1
            if #examples<10 then
                examples[#examples+1]=string.format('index=%d id=%s native=%s wanted=%d posDelta=%.2f',
                    m.source.index,m.source.id,tostring(m.candidate.floor),m.source.floor,m.distance)
            end
        end
        local f=tostring(m.candidate.floor)
        byFloor[f]=(byFloor[f] or 0)+1
    end
    return {
        sid=sid,name=layout.name,floors=floors,expected=#expected,roofExpected=roofExpected,
        children=parent:getNumInternalBuildings(),candidates=#candidates,nodeCandidates=nodeCandidates,
        matched=#matches,mismatches=mismatch,matches=matches,
        byFloor=byFloor,examples=examples,checked=#ptrs,
    }
end

function M.audit(parent)
    local a=M.collect(parent)
    local lines={string.format('FLOOR_AUDIT READ-ONLY shop=%s gameFloors=%s',a.name,tostring(a.floors)),
        string.format('ownedScanned=%d expectedInterior=%d parentChildren=%d foundLinked=%d ignoredLegacyMarkers=%d matched=%d',
            a.checked,a.expected,a.children,a.candidates,a.nodeCandidates,a.matched),
        string.format('nativeFloorMismatches=%d matchTolerance=%.1f',a.mismatches,MAX_DISTANCE)}
    local keys={}
    for k in pairs(a.byFloor) do keys[#keys+1]=k end
    table.sort(keys)
    local counts={}
    for _,k in ipairs(keys) do counts[#counts+1]=k..':'..a.byFloor[k] end
    lines[#lines+1]='nativeFloor:count='..table.concat(counts,' | ')
    for _,s in ipairs(a.examples) do lines[#lines+1]='MISMATCH '..s end
    if a.matched~=a.expected or a.candidates~=a.expected then
        lines[#lines+1]='WARNING: incomplete matching; read-only report.'
    elseif a.mismatches==0 then
        lines[#lines+1]='All matched native floor numbers are correct. If visuals still overlap, the issue is floor visibility/geometry, not floorNum.'
    else
        lines[#lines+1]='Floor mismatch detected; this version has no save-repair command.'
    end
    return table.concat(lines,'\n')
end

return M
