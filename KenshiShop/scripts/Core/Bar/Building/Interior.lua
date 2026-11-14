local Layouts = {['100-KenshiShop.mod']=require('Core.Bar.Building.FurnitureData')}
local FloorPlan = require('FloorPlan')
local FloorAssignment = require('FloorAssignment')
local Settings = require('Settings')
local Transform = require('Transform')
local Correction = require('Core.Bar.Building.Calibration')
local OwnerPolicy=require('Core.Bar.Building.OwnerPolicy')
local LiveFurniture=require('Core.Bar.Building.LiveFurniture')
local Log = require('Diagnostics')
local M = {}
-- Rooftop furniture remains interior-linked but is flagged as outside furniture.

local attempted = {}
function M.expectedInternalCount()
 local count=0
 for _,x in ipairs(Layouts[next(Layouts)].objects) do if not x.outside then count=count+1 end end
 return count
end
function M.resetSession() attempted={} end
local function keyOf(parent) return parent:getHandle():toString() end
function M.getAttempt(parent)
    local a=attempted[keyOf(parent)]
    if not a then return nil end
    return {status=a.status,placed=a.placed,failed=a.failed,
        corrected=a.corrected or 0,unresolved=a.unresolved or 0,
        floorRemapped=a.floorRemapped or 0,floorClamped=a.floorClamped or 0,
        floorFixed=a.floorFixed or 0,floorUnresolved=a.floorUnresolved or 0,
        roofFlagged=a.roofFlagged or 0,roofUnresolved=a.roofUnresolved or 0}
end
function M.clearEmptyAttempt(parent)
    local key=keyOf(parent)
    local a=attempted[key]
    if not a then return true end
    if a.placed~=0 then return false,'Previous attempt created objects' end
    local ok,count=pcall(function() return parent:getNumInternalBuildings() end)
    if not ok or count~=0 then return false,'Cannot verify zero interior children' end
    attempted[key]=nil
    Log.info('MANUAL_EMPTY_RETRY_ALLOWED handle='..key)
    return true
end

local function selection(shop,count,explicitIndices)
    if explicitIndices then
        local chosen={}
        assert(#explicitIndices>0 and #explicitIndices<=3,'Manual probe allows 1..3 items')
        for _,i in ipairs(explicitIndices) do
            assert(type(i)=='number' and i==math.floor(i) and i>=1 and i<=count,'Bad probe index')
            chosen[#chosen+1]=i
        end
        return chosen
    end
    local mode=Settings.mode
    local chosen={}
    if mode=='disabled' then return chosen end
    if mode=='full' then
        for i=1,count do chosen[#chosen+1]=i end
    elseif mode=='probe' then
        local indices=assert(Settings.probes[shop],'Missing probe '..shop)
        assert(#indices>0 and #indices<=3,'Probe must contain 1..3 indices')
        for _,i in ipairs(indices) do
            assert(type(i)=='number' and i==math.floor(i) and i>=1 and i<=count,'Invalid probe index')
            chosen[#chosen+1]=i
        end
    else error('Unknown Settings.mode '..tostring(mode)) end
    return chosen
end
local function safeInfo(label,callback)
    local ok,result=pcall(callback)
    if not ok then Log.error(label..' '..tostring(result));return nil end
    return result
end

function M.complete(parent,explicitIndices)
    local data=parent:getGameData()
    local shop=data and data.stringID
    local layout=shop and Layouts[shop]
    if not layout then return end
    local key=keyOf(parent)
    if attempted[key] then
        Log.info('INTERIOR_SKIPPED_ALREADY_ATTEMPTED shop='..layout.name..' handle='..key)
        return
    end
    attempted[key]={status='starting',placed=0,failed=0,corrected=0,unresolved=0,
        floorRemapped=0,floorClamped=0,floorFixed=0,floorUnresolved=0,
        roofFlagged=0,roofUnresolved=0}
    local chosen=selection(shop,#layout.objects,explicitIndices)
    if #chosen==0 then
        attempted[key].status='disabled'
        Log.info('INTERIOR_DISABLED shop='..layout.name)
        return {status='disabled',placed=0,failed=0}
    end
    local placed,failed,corrected,unresolved,currentIndex,calls=0,0,0,0,0,0
    local floorRemapped,floorClamped,floorFixed,floorUnresolved=0,0,0,0
    local roofFlagged,roofUnresolved=0,0
    local ownerMismatch,ownerPlayer,ownerNPC,ownerUnknown=0,0,0,0
    local floorGroupsLogged={}
    attempted[key].status='running'
    local ok,err=pcall(function()
        assert(parent:isValid(),'Parent building invalid')
        assert(not parent:isDestroyed(),'Parent building destroyed')
        if not parent:isThePlayer() then
            Log.info('OWNER_NOT_PLAYER_YET shop='..layout.name..' continuing for custom shop ID')
        end
        local existing=safeInfo('EXISTING_CHILD_COUNT',function() return parent:getNumInternalBuildings() end)
        -- Crucial: do not add a second furniture set to an already furnished shop.
        assert(type(existing)=='number' and existing==0,
            'Existing interior furniture '..tostring(existing)..': blocked to prevent duplicates')
        local world=getGameWorld()
        assert(world and world.theFactory and world.gamedata,'World factory unavailable')
        local town=safeInfo('TOWN_QUERY',function() return parent:getTown() end)
        local ui=getPlayerInterface()
        local playerFaction=ui and safeInfo('PLAYER_FACTION_QUERY',function() return ui:getFaction() end)
        local ownerFaction=world.factionMgr and safeInfo('BAR_NPC_FACTION_QUERY',function()
            return world.factionMgr:getFactionByStringID('400-KenshiShop.mod') end)
        assert(playerFaction and ownerFaction,'BAR_OWNER_FACTIONS_UNAVAILABLE; furniture creation not started')
        local function factionID(f)
            local d=f and f:getData()
            return d and tostring(d.stringID) or 'UNKNOWN'
        end
        local playerID=factionID(playerFaction)
        local npcID=factionID(ownerFaction)
        assert(npcID=='400-KenshiShop.mod' and playerID~=npcID,'BAR_OWNER_FACTION_MISMATCH')
        local ownerPlan,planError=OwnerPolicy.plan(layout,world.gamedata)
        assert(ownerPlan,'BAR_FURN_OWNER_PLAN_FAIL '..tostring(planError))
        Log.console('BAR_FURN_PLAN building='..key..' shared='..ownerPlan.sharedTotal
          ..' shared_player='..ownerPlan.sharedPlayer..' shared_npc='..ownerPlan.sharedNPC
          ..' other_npc='..(ownerPlan.npc-ownerPlan.sharedNPC)
          ..' player_total='..ownerPlan.player..' npc_total='..ownerPlan.npc)
        local floors=safeInfo('FLOORS_QUERY',function() return parent:getNumFloors() end)
        local origin,rotation,scale=parent:getPosition(),parent:getOrientation(),parent:getScale()
        assert(type(scale)=='number' and scale>0,'Invalid building scale')
        local floorPlan=assert(FloorPlan.forShop(shop),'Missing floor plan')
        Log.info(string.format('INTERIOR_PREPARE shop=%s handle=%s mode=%s floors=%s selected=%d parentY=%.3f',
            layout.name,key,Settings.mode,tostring(floors),#chosen,origin.y))
        safeInfo('LOAD_PHYSICAL',function() parent:loadInteriorPhysical(true) end)
        safeInfo('LOAD_GRAPHICS',function() parent:loadInteriorGraphics(true) end)
        local insideCache={}
        for _,i in ipairs(chosen) do
            currentIndex=i
            local item=layout.objects[i]
            local classification=floorPlan[i]
            local oneOk,oneErr=pcall(function()
                assert(item and classification,'Missing item or floor plan')
                local record=world.gamedata:getData(item.id,0)
                assert(record,'Missing BUILDING record '..item.id)
                local category,ownerSource,recordName=OwnerPolicy.classify(item,record)
                local owner=assert(ownerPlan.owners[i],'BAR_OWNER_PLAN_MISSING_INDEX '..i)
                local desiredFaction=owner=='PLAYER' and playerFaction or ownerFaction
                local desiredID=owner=='PLAYER' and playerID or npcID
                if ownerSource=='UNCLASSIFIED_DEFAULT_NPC' then
                    ownerUnknown=ownerUnknown+1
                    Log.console('BAR_FURNITURE_UNCLASSIFIED index='..i..' id='..item.id
                        ..' name='..tostring(recordName)..' default=NPC; verify_with_FCS')
                end
                local target,q=Transform.world(origin,rotation,scale,item)
                local assignment=FloorAssignment.resolve(shop,classification,floors)
                local floor=assignment.native
                if assignment.remapped then
                    floorRemapped=floorRemapped+1
                    attempted[key].floorRemapped=floorRemapped
                end
                if assignment.clamped then
                    floorClamped=floorClamped+1
                    attempted[key].floorClamped=floorClamped
                end
                local group=tostring(assignment.outside)..'/'..assignment.source..'/'..floor
                if not floorGroupsLogged[group] then
                    floorGroupsLogged[group]=true
                    Log.info(string.format('FLOOR_MAP shop=%s source=%d native=%d gameFloors=%s outside=%s clamped=%s',
                        layout.name,assignment.source,floor,tostring(floors),
                        tostring(assignment.outside),tostring(assignment.clamped)))
                end
                local inside=parent
                if classification.outside then inside=nil end
                local child,report=Correction.create({world=world,record=record,target=target,
                    town=town,faction=desiredFaction,rotation=q,inside=inside,floor=floor,
                    outside=classification.outside,cache=insideCache,shop=layout.name,index=i})
                calls=calls+(report and report.calls or 0)
                if not child then error('Factory did not leave a live item '..i) end
                placed=placed+1
                attempted[key].placed=placed
                if owner=='PLAYER' then ownerPlayer=ownerPlayer+1 else ownerNPC=ownerNPC+1 end
                local added,addWhy=LiveFurniture.register(parent,child,i,owner,item.id,classification.outside)
                if not added then Log.error('BAR_FURN_HANDLE_REGISTER_FAILED index='..i..' '..tostring(addWhy)) end
                local actualFaction=safeInfo('BAR_FURN_GET_FACTION',function() return child:getFaction() end)
                local actualID=actualFaction and factionID(actualFaction) or 'UNAVAILABLE'
                local actualPlayer=safeInfo('BAR_FURN_IS_PLAYER',function() return child:isThePlayer() end)
                if actualID~=desiredID or actualPlayer~=(owner=='PLAYER') then
                    ownerMismatch=ownerMismatch+1
                    Log.error('BAR_FURN_OWNER_MISMATCH index='..i..' id='..item.id..' name='..tostring(recordName)
                        ..' expected='..desiredID..' actual='..actualID
                        ..' playerOwned='..tostring(actualPlayer)..' pending_safe_transfer')
                else
                    Log.info('BAR_FURN_OWNER_OK index='..i..' id='..item.id..' owner='..owner
                        ..' faction='..desiredID..' source='..ownerSource)
                end
                if report and report.corrected then
                    corrected=corrected+1;attempted[key].corrected=corrected
                end
                if report and report.unresolved then
                    unresolved=unresolved+1;attempted[key].unresolved=unresolved
                end
                -- Verify the native floor *after* the final create/correction.
                -- createBuilding's floor argument alone does not prove that
                -- Kenshi assigned the resulting object to that floor.
                local nativeOK,nativeFloor=pcall(function() return child:getFloor() end)
                if nativeOK and nativeFloor==floor then
                    -- Already correct. Do not force a visibility refresh.
                else
                    local setOK,setErr=pcall(function() child:setFloor(floor) end)
                    local checkOK,checkFloor=pcall(function() return child:getFloor() end)
                    if setOK and checkOK and checkFloor==floor then
                        floorFixed=floorFixed+1
                        attempted[key].floorFixed=floorFixed
                        Log.info(string.format('FLOOR_FIXED shop=%s index=%d before=%s after=%d',
                            layout.name,i,tostring(nativeFloor),floor))
                    else
                        floorUnresolved=floorUnresolved+1
                        attempted[key].floorUnresolved=floorUnresolved
                        Log.error(string.format('FLOOR_UNRESOLVED shop=%s index=%d wanted=%d got=%s setError=%s',
                            layout.name,i,floor,tostring(checkFloor),tostring(setErr)))
                    end
                end
                -- Mark open-air rooftop objects independently from native floor.
                -- Keep parent link (inside=parent) so Kenshi can switch floors.
                if assignment.roof then
                    local flagOK,flagErr=pcall(function()
                        child:setIsOutsideFurniture(true)
                        assert(child:getIsOutsideFurniture()==true,'Outside flag not set')
                        local roofParent=assert(child:furnitureParentBuilding(),'Roof parent link lost')
                        assert(roofParent:getHandle():toString()==key,'Roof parent changed')
                    end)
                    if flagOK then
                        roofFlagged=roofFlagged+1
                        attempted[key].roofFlagged=roofFlagged
                        Log.info(string.format('ROOF_FLAG_APPLIED shop=%s index=%d nativeFloor=%d',
                            layout.name,i,floor))
                    else
                        -- Revert immediately; never knowingly leave a detached roof item.
                        pcall(function() child:setIsOutsideFurniture(false) end)
                        roofUnresolved=roofUnresolved+1
                        attempted[key].roofUnresolved=roofUnresolved
                        Log.error(string.format('ROOF_FLAG_UNRESOLVED shop=%s index=%d nativeFloor=%d error=%s',
                            layout.name,i,floor,tostring(flagErr)))
                    end
                end
                local linked=safeInfo('PARENT_CHECK',function() return child:furnitureParentBuilding() end)
                if not classification.outside and linked then
                    local linkedKey=safeInfo('PARENT_HANDLE',function() return linked:getHandle():toString() end)
                    if linkedKey and linkedKey~=key then Log.error('PARENT_MISMATCH shop='..layout.name..' index='..i) end
                end
                local outside=safeInfo('OUTSIDE_CHECK',function() return child:getIsOutsideFurniture() end)
                local expectedOutside=classification.outside or assignment.roof
                if outside~=nil and outside~=expectedOutside then
                    Log.error('OUTSIDE_MISMATCH shop='..layout.name..' index='..i)
                end
                safeInfo('CHILD_NOTIFY index='..i,function() child:notifyChange() end)
                if i%10==0 or i==#layout.objects then
                    Log.info(string.format('CREATE_PROGRESS shop=%s index=%d placed=%d failed=%d corrected=%d unresolved=%d',
                        layout.name,i,placed,failed,corrected,unresolved))
                end
            end)
            if not oneOk then
                failed=failed+1
                attempted[key].failed=failed
                Log.error('CREATE_FAILED shop='..layout.name..' index='..i..' '..tostring(oneErr))
            end
        end
        safeInfo('UPDATE_USAGE_NODES',function() parent:updateUsageNodes() end)
        safeInfo('PARENT_NOTIFY',function() parent:notifyChange() end)
    end)
    if not ok then
        attempted[key].status='stopped'
        Log.error(string.format('INTERIOR_STOP shop=%s handle=%s index=%d placed=%d failed=%d corrected=%d unresolved=%d %s',
            layout.name,key,currentIndex,placed,failed,corrected,unresolved,tostring(err)))
        return {status='stopped',placed=placed,failed=failed,corrected=corrected,unresolved=unresolved}
    end
    local placedOK=(failed==0 and unresolved==0 and floorUnresolved==0 and roofUnresolved==0 and placed==#chosen)
    local status=placedOK and (ownerMismatch==0 and 'INTERIOR_DONE' or 'INTERIOR_OWNER_PARTIAL') or 'INTERIOR_PARTIAL' 
    Log.console('BAR_FURN_OWNER_SUMMARY building='..key..' PLAYER='..ownerPlayer..' NPC='..ownerNPC..' mismatches='..ownerMismatch..' unclassified='..ownerUnknown..' current_session_transfer_pending')
    attempted[key].status=status
    Log.info(string.format('%s shop=%s handle=%s expected=%d placed=%d failed=%d corrected=%d unresolved=%d nativeCalls=%d floorRemapped=%d floorClamped=%d floorFixed=%d floorUnresolved=%d roofFlagged=%d roofUnresolved=%d',
        status,layout.name,key,#chosen,placed,failed,corrected,unresolved,calls,
        floorRemapped,floorClamped,floorFixed,floorUnresolved,roofFlagged,roofUnresolved))
    return {status=status,placed=placed,failed=failed,corrected=corrected,unresolved=unresolved}
end
return M
