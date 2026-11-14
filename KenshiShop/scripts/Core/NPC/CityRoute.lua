-- Read-only city geometry. Native gate area codes keep destinations on the home side.
local Live=require('Core.NPC.LiveState')
local T=require('Core.NPC.Transport')
local M={}
function M.inside(town,home,p)
 if not T.valid(p) or Live.call(town,'withinBordersRange',p,0.90)~=true then return false end
 local gates=Live.call(town,'hasGates')
 if gates==false then return true end
 if gates~=true then return false end
 local gate=Live.call(town,'getNearestGate',p)
 if not gate then return false end
 local outside=Live.call(gate,'getOutsideGateCode')
 local a=Live.call(gate,'getGateCodeAt',home)
 local b=Live.call(gate,'getGateCodeAt',p)
 return a~=nil and b~=nil and outside~=nil and a~=outside and b==a
end
function M.build(b,leader,world)
 local town=Live.call(b,'getTown');local home=Live.call(b,'getPosition')
 if not town or not T.valid(home) then return nil,'HOME_UNAVAILABLE' end
 local mgr=Live.call(town,'getBuildingsManager')
 local ok,map=pcall(function()return mgr.buildingEntities end)
 if not ok or not map then return nil,'CITY_BUILDINGS_UNAVAILABLE' end
 local points={}
 local valid,err=pcall(function()
  local scanned=0
  for house in pairs(map) do
   scanned=scanned+1;if scanned>4000 then error('BUILDING_SCAN_CAP')end
   if house and Live.call(house,'isValid')==true and Live.call(house,'isFurniture')==false
    and not Live.call(house,'isAWall') and not Live.call(house,'isGate') then
    local door=Live.call(house,'getDoor')
    local pos=door and Live.call(door,'getPositionForWaypoint',home)
    if T.valid(pos) and M.inside(town,home,pos)
     and Live.call(world.navmesh,'getPositionValid',pos)==true
     and Live.call(leader,'pathExists',pos)==true then
     local distinct=true
     for _,p in ipairs(points)do if T.distance2D(p,pos)<25 then distinct=false;break end end
     if distinct then points[#points+1]=Live.copy(pos) end
    end
   end
  end
 end)
 if not valid then return nil,tostring(err) end
 if #points<2 then return nil,'NOT_ENOUGH_VERIFIED_CITY_POINTS' end
 local center=Live.call(town,'getPosition') or home
 local function angle(p)return math.atan2 and math.atan2(p.z-center.z,p.x-center.x) or math.atan(p.z-center.z,p.x-center.x)end
 table.sort(points,function(a,c)return angle(a)<angle(c)end)
 -- Keep a compact loop, spread around actual streets/doors, with no random outside rings.
 if #points>12 then
  local chosen={};for i=0,11 do chosen[#chosen+1]=points[math.floor(i*#points/12)+1]end;points=chosen
 end
 return points
end
return M
