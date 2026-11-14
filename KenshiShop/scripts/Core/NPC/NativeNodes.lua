-- Actual engine LocationNodes, created by the dedicated node factory. These
-- are not furniture/Building objects and have no physical model or collision.
local Live=require('Core.NPC.LiveState')
local Transform=require('Transform')
local Posts=require('Core.NPC.PostData')
local Log=require('Diagnostics')
local M={}
local buildings={}
function M.resetSession()buildings={}end
function M.ensure(s,b)
 if s.cfg.role=='patrol'then return true end
 local world=getGameWorld();local gm=world and world.gamedata
 if not gm or not world.theFactory then return false,'NODE_FACTORY_UNAVAILABLE'end
 if Live.call(b,'isPhysical')~=true then return false,'BUILDING_NOT_PHYSICAL'end
 local r=buildings[s.key]
 if not r or r.gm~=gm then r={gm=gm,created={},attached={},tries=0};buildings[s.key]=r end
 if r.done then return true end
 if r.tries>=3 then return false,'NODE_SETUP_FAILED'end
 local entries=Posts[s.cfg.shop] or {};local pending={}
 for i,p in ipairs(entries)do
  local id=p.role=='trader' and '1180-gamedata.base' or '1186-gamedata.base'
  local data=Live.call(gm,'getData',id,0)
  if not data then return false,'NODE_TEMPLATE_MISSING '..id end
  pending[#pending+1]={index=i,entry=p,data=data,id='KS84_NODE:'..s.key..':'..i}
 end
 if #pending==0 then return false,'NODE_COORDINATES_MISSING'end
 local ok,err=pcall(function()
  for _,p in ipairs(pending)do
   if not r.created[p.index]then
    local pos,rot=Transform.world(b:getPosition(),b:getOrientation(),b:getScale(),p.entry)
    local node=world.theFactory:createLocationNode(true,p.data,pos,b,b:getFaction(),rot,nil,p.id)
    assert(node and not tostring(node):find('(nil)',1,true),'LOCATION_NODE_CREATE_FAILED')
    -- Do not dereference lightuserdata; use the documented building node ID API.
    r.created[p.index]=true
   end
   if not r.attached[p.index]then b:addUsageNode(p.id);r.attached[p.index]=true end
  end
  b:updateUsageNodes();b:forceValidUsageNodesValidation()
 end)
 if not ok then r.tries=r.tries+1;return false,'NATIVE_NODE_SETUP '..tostring(err)end
 r.done=true
 Log.console('NPC_NATIVE_NODES84 shop='..s.cfg.shop..' building='..s.key..' count='..#pending..' factory=createLocationNode furniture_changes=0')
 return true
end
return M
