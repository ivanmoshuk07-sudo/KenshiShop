-- KenshiShop 0.3.0-alpha.11
-- Bounded placement correction from original CITY BUILDER: at most two
-- createBuilding calls and ONE destroy per item. No scanning or background loops.
-- The position supplied to the native factory may be shifted by the engine,
-- including a full building-origin Y offset (observed in the user's bar logs).
local Transform = require('Transform')
local Log = require('Diagnostics')
local M = {}
local MAX_ERROR = 5.0
local MAX_CORRECTION = 20000.0 -- Guard against nonsensical/corrupt coordinates.

local function vec(v)
    return string.format('%.3f,%.3f,%.3f',v.x,v.y,v.z)
end
local function difference(a,b)
    return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z}
end
local function subtract(a,b)
    return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z}
end
local function magnitude(v)
    return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
end
local function isFinite(v)
    return v and v.x==v.x and v.y==v.y and v.z==v.z
      and math.abs(v.x)<100000000 and math.abs(v.y)<100000000 and math.abs(v.z)<100000000
end

-- opts: {world, record, target, town, faction, rotation, inside, floor,
--        outside, cache, shop, index}; cache is a per-building INSIDE offset.
-- Returns (live child or nil, {calls, corrected, unresolved, destroyed}).
function M.create(opts)
    local world=opts.world
    local target=opts.target
    local cache=opts.cache
    local outside=opts.outside
    local context=string.format('shop=%s index=%d',tostring(opts.shop),opts.index)
    assert(isFinite(target),'Invalid target position '..context)
    local input=target
    if not outside and cache and cache.offset then
        input=subtract(target,cache.offset)
    end
    local calls=0
    local function spawn(position,attempt)
        calls=calls+1
        Log.info(string.format('CREATE_BEFORE %s attempt=%d input=%s target=%s floor=%d outside=%s',
            context,attempt,vec(position),vec(target),opts.floor,tostring(outside)))
        -- The 8th argument is Layout* furnitureOf. It MUST be nil.
        local child=world.theFactory:createBuilding(opts.record,position,opts.town,
            opts.faction,opts.rotation,nil,nil,nil,nil,opts.inside,false,true,false,
            opts.floor,outside)
        if child then Log.info(string.format('CREATE_AFTER %s attempt=%d',context,attempt)) end
        return child
    end
    local child=spawn(input,1)
    if not child then
        Log.error('CREATE_NIL '..context)
        return nil,{calls=calls,corrected=false,unresolved=false,destroyed=false}
    end
    local ok,actual=pcall(function() return child:getPosition() end)
    if not ok or not isFinite(actual) then
        Log.error('POSITION_UNAVAILABLE '..context..' '..tostring(actual))
        return child,{calls=calls,corrected=false,unresolved=true,destroyed=false}
    end
    local delta=Transform.error(actual,target)
    if delta<=MAX_ERROR then
        if not outside and cache then cache.offset=difference(actual,input) end
        return child,{calls=calls,corrected=false,unresolved=false,destroyed=false,delta=delta}
    end
    local errorVec=difference(actual,target)
    Log.info(string.format('POSITION_SHIFT %s firstDelta=%.3f shift=%s target=%s actual=%s',
        context,delta,vec(errorVec),vec(target),vec(actual)))
    if not isFinite(errorVec) or magnitude(errorVec)>MAX_CORRECTION then
        Log.error(string.format('POSITION_UNRESOLVED %s correction out of bounds delta=%.3f',context,delta))
        return child,{calls=calls,corrected=false,unresolved=true,destroyed=false,delta=delta}
    end
    -- Never destroy a pre-existing item: only the exact object returned by spawn().
    -- Mirrors CITY BUILDER: destroy once, then re-create with measured correction.
    local destroyedOK,destroyed=pcall(function()
        return world:destroy(child,false,'KenshiShop position correction')
    end)
    if not destroyedOK or destroyed~=true then
        Log.error('POSITION_DESTROY_REFUSED '..context..' '..tostring(destroyed))
        return child,{calls=calls,corrected=false,unresolved=true,destroyed=false,delta=delta}
    end
    child=nil -- Do not access native pointer after destroy.
    local correctedInput=subtract(input,errorVec)
    Log.info(string.format('POSITION_RETRY %s correctedInput=%s',context,vec(correctedInput)))
    local retry=spawn(correctedInput,2)
    if not retry then
        Log.error('POSITION_RETRY_FAILED '..context..' no live object')
        return nil,{calls=calls,corrected=false,unresolved=true,destroyed=true,delta=delta}
    end
    local posOK,final=pcall(function() return retry:getPosition() end)
    if not posOK or not isFinite(final) then
        Log.error('POSITION_RETRY_UNVERIFIED '..context..' '..tostring(final))
        return retry,{calls=calls,corrected=false,unresolved=true,destroyed=true,delta=delta}
    end
    local finalDelta=Transform.error(final,target)
    if finalDelta>MAX_ERROR then
        Log.error(string.format('POSITION_UNRESOLVED %s afterRetry=%.3f final=%s target=%s',
            context,finalDelta,vec(final),vec(target)))
        return retry,{calls=calls,corrected=false,unresolved=true,destroyed=true,delta=finalDelta}
    end
    if not outside and cache then cache.offset=difference(final,correctedInput) end
    Log.info(string.format('POSITION_CORRECTED %s firstDelta=%.3f finalDelta=%.3f',
        context,delta,finalDelta))
    return retry,{calls=calls,corrected=true,unresolved=false,destroyed=true,delta=finalDelta}
end
return M
