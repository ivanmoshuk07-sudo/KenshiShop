-- KenshiShop alpha.35: separate materials handoff from safe completed-building interior gate.
-- Never finishes building, consumes materials, modifies progress or changes ownership.
local M={}
local function field(o,k)
 if not o then return nil end
 local ok,v=pcall(function() return o[k] end)
 return ok and v or nil
end
local function call(o,k)
 local fn=field(o,k)
 if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,o)
 if ok then return v end
 return nil
end
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<1e12 end
function M.ready(b)
 if not b or call(b,'isValid')~=true or call(b,'isDestroyed')==true then
  return false,'BUILDING_NOT_VALID'
 end
 local state=call(b,'getBuildState')
 if not state then
  -- A saved building can expose no ConstructionState in a specific KenshiLua
  -- binding. Trust only the combination of a created native building and an
  -- already existing interior; this path never authorizes a new build.
  local created=call(b,'isCreated')
  local childCount=call(b,'getNumInternalBuildings')
  if created==true and type(childCount)=='number' and childCount>0 then
   return true,'SAVED_FINISHED_INTERIOR_NO_BUILD_STATE'
  end
  return false,'BUILD_STATE_UNAVAILABLE'
 end
 local complete=field(state,'isComplete')
 if complete==false then return false,'CONSTRUCTION_INCOMPLETE' end
 local missing=call(state,'needMats')
 if missing==true then return false,'MATERIALS_STILL_NEEDED' end
 local total=call(state,'getTotalMats')
 local present=call(state,'getTotalMatsPresent')
 if finite(total) and finite(present) then
  if present+0.001<total then
   return false,'MATERIALS_SHORT '..tostring(present)..'/'..tostring(total)
  end
 elseif missing==nil then
  return false,'MATERIALS_UNVERIFIED'
 end
 if complete~=true then
  -- A missing completion flag must not be mistaken for confirmation.
  return false,'COMPLETION_UNVERIFIED'
 end
 return true,'COMPLETE_MATERIALS_VERIFIED'
end

-- Ownership can change after all materials are delivered, BEFORE build progress
-- reaches 100%. This check must NEVER be used to create furniture or NPCs.
-- In particular, isComplete is construction progress, NOT a material resource.
function M.ownerReady(b)
 if not b or call(b,'isValid')~=true or call(b,'isDestroyed')==true then
  return false,'BUILDING_NOT_VALID'
 end
 local state=call(b,'getBuildState')
 if not state then
  local created=call(b,'isCreated')
  local children=call(b,'getNumInternalBuildings')
  if created==true and type(children)=='number' and children>0 then
   return true,'SAVED_FURNISHED_NO_BUILD_STATE'
  end
  return false,'MATERIAL_STATE_UNAVAILABLE'
 end
 local total=call(state,'getTotalMats')
 local present=call(state,'getTotalMatsPresent')
 local need=call(state,'needMats')
 -- Total/present are native material counters; never treat constructionProgress
 -- or isComplete as quantities. Fail closed on missing/inconsistent counters.
 if finite(total) and finite(present) and total>0 then
  if present+0.001<total then
   return false,'MATERIALS_SHORT '..tostring(present)..'/'..tostring(total)
  end
  -- During the progress phase needMats may disagree with the totals.
  -- Report it for field verification; do not mistake isComplete=false for missing mats.
  if need==true then
   return true,'MATERIAL_TOTALS_FULL_NEEDMATS_CONFLICT '..tostring(present)..'/'..tostring(total)
  end
  return true,'MATERIAL_TOTALS_VERIFIED '..tostring(present)..'/'..tostring(total)
 end
 if need==false and finite(total) and total==0 then
  return true,'ZERO_MATERIALS_VERIFIED'
 end
 return false,'MATERIAL_COUNTERS_UNVERIFIED total='..tostring(total)..' present='..tostring(present)..' needMats='..tostring(need)
end

-- Read-only numeric evidence for field logs: at most one call per field.
function M.details(b)
 local state=call(b,'getBuildState')
 if not state then return 'buildState=UNAVAILABLE' end
 return 'complete='..tostring(field(state,'isComplete'))
  ..' needMats='..tostring(call(state,'needMats'))
  ..' totalMats='..tostring(call(state,'getTotalMats'))
  ..' presentMats='..tostring(call(state,'getTotalMatsPresent'))
  ..' created='..tostring(call(b,'isCreated'))
end
return M
